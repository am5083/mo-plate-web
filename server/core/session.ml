(* HTTPS plumbing for cohttp-eio: TLS via tls-eio + ca-certs. *)

let default_user_agent =
  "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"

type t = {
  client : Cohttp_eio.Client.t;
  sw : Eio.Switch.t;
  base_uri : Uri.t;
  cookies : (string, string) Hashtbl.t;
  mutable hidden : Form_parser.hidden_fields option;
  mutable last_state : Form_parser.form_state option;
  mutable last_request_at : float;
  rate_delay : float;
  jitter : float;
  user_agent : string;
  clock : float Eio.Time.clock_ty Eio.Std.r;
}

let make_https authenticator =
  let tls_config =
    match Tls.Config.client ~authenticator () with
    | Ok c -> c
    | Error (`Msg m) -> failwith ("tls config: " ^ m)
  in
  fun uri raw ->
    let host =
      Uri.host uri
      |> Option.map (fun h -> Domain_name.(host_exn (of_string_exn h)))
    in
    Tls_eio.client_of_flow ?host tls_config raw

let create ~sw ~env ?(rate_delay_ms = 750) ?(jitter_ms = 250)
    ?(user_agent = default_user_agent) ~base_uri () =
  Mirage_crypto_rng_unix.use_default ();
  Random.self_init ();
  let authenticator =
    match Ca_certs.authenticator () with
    | Ok a -> a
    | Error (`Msg m) -> failwith ("ca-certs: " ^ m)
  in
  let https = make_https authenticator in
  let client =
    Cohttp_eio.Client.make ~https:(Some https) (Eio.Stdenv.net env)
  in
  {
    client;
    sw;
    base_uri;
    cookies = Hashtbl.create 16;
    hidden = None;
    last_state = None;
    last_request_at = 0.0;
    rate_delay = float_of_int rate_delay_ms /. 1000.0;
    jitter = float_of_int (max 0 jitter_ms) /. 1000.0;
    user_agent;
    clock = Eio.Stdenv.clock env;
  }

let state t = t.last_state
let cookie_count t = Hashtbl.length t.cookies

let clear_state t =
  t.hidden <- None;
  t.last_state <- None

let cookies_clear t = Hashtbl.clear t.cookies

(* Parse a Set-Cookie value, returning (name, value). Attributes (Path, Domain,
   etc.) are dropped — we use a flat per-session jar since we only talk to one
   host. *)
let parse_set_cookie raw =
  let pair =
    match String.index_opt raw ';' with
    | None -> raw
    | Some i -> String.sub raw 0 i
  in
  match String.index_opt pair '=' with
  | None -> None
  | Some j ->
      let name = String.sub pair 0 j |> String.trim in
      let value = String.sub pair (j + 1) (String.length pair - j - 1) in
      if name = "" then None else Some (name, value)

let absorb_cookies t headers =
  Cohttp.Header.get_multi headers "set-cookie"
  |> List.iter (fun raw ->
         match parse_set_cookie raw with
         | None -> ()
         | Some (k, v) -> Hashtbl.replace t.cookies k v)

let cookie_header t =
  if Hashtbl.length t.cookies = 0 then None
  else
    let buf = Buffer.create 128 in
    let first = ref true in
    Hashtbl.iter
      (fun k v ->
        if !first then first := false else Buffer.add_string buf "; ";
        Buffer.add_string buf k;
        Buffer.add_char buf '=';
        Buffer.add_string buf v)
      t.cookies;
    Some (Buffer.contents buf)

let common_headers t =
  let h =
    Cohttp.Header.of_list
      [
        ("User-Agent", t.user_agent);
        ( "Accept",
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" );
        ("Accept-Language", "en-US,en;q=0.5");
        ("Cache-Control", "no-cache");
      ]
  in
  match cookie_header t with
  | None -> h
  | Some c -> Cohttp.Header.add h "cookie" c

let throttle t =
  let now = Eio.Time.now t.clock in
  let extra = if t.jitter > 0.0 then Random.float t.jitter else 0.0 in
  let earliest = t.last_request_at +. t.rate_delay +. extra in
  if now < earliest then Eio.Time.sleep t.clock (earliest -. now);
  t.last_request_at <- Eio.Time.now t.clock

let read_body body =
  Eio.Buf_read.(parse_exn take_all) body ~max_size:Int.max_int

let resolve_redirect base loc =
  let loc_uri = Uri.of_string loc in
  if Uri.host loc_uri <> None then loc_uri else Uri.resolve "https" base loc_uri

(* Manual redirect follower that preserves POST. *)
let rec do_request t ~meth ~uri ?body ?(redirects_left = 5) () =
  throttle t;
  let headers = common_headers t in
  let resp, resp_body =
    match meth with
    | `GET -> Cohttp_eio.Client.get ~sw:t.sw t.client ~headers uri
    | `POST ->
        let body =
          match body with
          | None -> Cohttp_eio.Body.of_string ""
          | Some s -> Cohttp_eio.Body.of_string s
        in
        let headers =
          Cohttp.Header.add headers "Content-Type"
            "application/x-www-form-urlencoded"
        in
        Cohttp_eio.Client.post ~sw:t.sw t.client ~headers ~body uri
  in
  let resp_headers = Cohttp.Response.headers resp in
  absorb_cookies t resp_headers;
  let status = Cohttp.Response.status resp in
  let code = Cohttp.Code.code_of_status status in
  if code >= 300 && code < 400 && redirects_left > 0 then begin
    (* Drain body to free the connection. *)
    let _ = read_body resp_body in
    match Cohttp.Header.get resp_headers "location" with
    | None -> failwith "redirect without Location"
    | Some loc ->
        let new_uri = resolve_redirect uri loc in
        do_request t ~meth ~uri:new_uri ?body
          ~redirects_left:(redirects_left - 1) ()
  end
  else if code >= 400 then
    failwith
      (Printf.sprintf "HTTP %d for %s %s" code
         (match meth with `GET -> "GET" | `POST -> "POST")
         (Uri.to_string uri))
  else
    let s = read_body resp_body in
    s

let update_state t body =
  match Form_parser.parse body with
  | Error e ->
      failwith
        (Printf.sprintf
           "form parse failed (likely bot-blocked or stale session): %s" e)
  | Ok st ->
      t.hidden <- Some st.hidden;
      t.last_state <- Some st;
      st

let refresh t =
  let body = do_request t ~meth:`GET ~uri:t.base_uri () in
  update_state t body

let encode_form fields =
  fields
  |> List.map (fun (k, v) ->
         Printf.sprintf "%s=%s"
           (Uri.pct_encode ~component:`Userinfo k)
           (Uri.pct_encode ~component:`Userinfo v))
  |> String.concat "&"

let hidden_pairs h =
  let open Form_parser in
  [
    ("__VIEWSTATE", h.viewstate);
    ("__VIEWSTATEGENERATOR", h.viewstategenerator);
    ("__EVENTVALIDATION", h.eventvalidation);
    ("__LASTFOCUS", h.lastfocus);
  ]

let raw_post t ~event_target ~fields () =
  let hidden =
    match t.hidden with
    | Some h -> h
    | None ->
        let _ = refresh t in
        Option.get t.hidden
  in
  let all =
    ("__EVENTTARGET", event_target) :: ("__EVENTARGUMENT", "")
    :: hidden_pairs hidden @ fields
  in
  let body = encode_form all in
  do_request t ~meth:`POST ~uri:t.base_uri ~body ()

let post t ~event_target ~fields () =
  let body = raw_post t ~event_target ~fields () in
  update_state t body
