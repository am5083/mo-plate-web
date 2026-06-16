(** HTTP backend for the MO plate web app.

    Exposes exactly one privileged operation a browser can't do itself: the live
    Missouri DOR availability check (CORS- and Imperva-walled). Everything else
    — candidate generation — runs client-side in Elm.

    Design for safe public exposure:
    - ONE upstream session, reused across all requests and serialised by a mutex.
      This mirrors the CLI's tuned "reuse one session, rate-limit with jitter"
      pattern that avoids tripping Imperva. Concurrent users queue; they never
      fan out into a burst against the DOR site.
    - A per-client token bucket so one caller can't monopolise that single queue.
    - Periodic full session reset so cookies don't accumulate suspicion. *)

open Mo_plate_core

let base_uri = Uri.of_string "https://sa.dor.mo.gov/mv/plates4u/available.aspx"

(* ─── config (env-overridable) ────────────────────────────────────────── *)

let getenv_int name default =
  match Sys.getenv_opt name with
  | Some s -> ( try int_of_string s with _ -> default)
  | None -> default

let getenv_str name default = Option.value ~default (Sys.getenv_opt name)

let port = getenv_int "PORT" 8080
let rate_delay_ms = getenv_int "RATE_DELAY_MS" 750
let jitter_ms = getenv_int "JITTER_MS" 250
let refresh_every = getenv_int "REFRESH_EVERY" 40
let ip_rate_capacity = getenv_int "IP_RATE_CAPACITY" 8
let ip_rate_window_sec = getenv_int "IP_RATE_WINDOW_SEC" 60
let allowed_origin = getenv_str "ALLOWED_ORIGIN" "*"

(* ─── shared upstream session, mutex-guarded ──────────────────────────── *)

type state = {
  mutex : Eio.Mutex.t;
  mutable session : Session.t option;
  mutable checks_since_reset : int;
}

let make_session ~sw ~env =
  Session.create ~sw ~env ~rate_delay_ms ~jitter_ms ~base_uri ()

(* Run a single check under the lock. Lazily creates the session, rotates it
   every [refresh_every] checks, and recreates it from scratch if a check throws
   (a thrown check usually means the session got bot-walled or went stale). *)
let checked_availability st ~sw ~env plate =
  Eio.Mutex.use_rw ~protect:true st.mutex (fun () ->
      let session =
        match st.session with
        | Some s -> s
        | None ->
            let s = make_session ~sw ~env in
            st.session <- Some s;
            s
      in
      if refresh_every > 0 && st.checks_since_reset >= refresh_every then begin
        (try Plate_check.full_reset session with _ -> ());
        st.checks_since_reset <- 0
      end;
      match Plate_check.try_check session plate with
      | Ok r ->
          st.checks_since_reset <- st.checks_since_reset + 1;
          Ok r
      | Error e -> Error e
      | exception ex ->
          (* Hard failure: drop the session so the next request rebuilds it. *)
          st.session <- None;
          st.checks_since_reset <- 0;
          Error (Printexc.to_string ex))

(* ─── JSON ────────────────────────────────────────────────────────────── *)

let avail_json = function
  | Form_parser.Available -> (`Bool true, "available")
  | Not_available -> (`Bool false, "not available")
  | Unknown_message m -> (`Null, m)

let result_json (r : Plate_check.result) : Yojson.Safe.t =
  let avail, message = avail_json r.availability in
  `Assoc
    [
      ("plate", `String r.plate);
      ("available", avail);
      ("message", `String message);
      ("checked_at", `Float r.checked_at);
    ]

let error_json ~plate ~msg : Yojson.Safe.t =
  `Assoc [ ("plate", `String plate); ("error", `String msg) ]

(* ─── HTTP plumbing ───────────────────────────────────────────────────── *)

let cors_headers extra =
  Http.Header.of_list
    (("access-control-allow-origin", allowed_origin)
    :: ("access-control-allow-methods", "GET, OPTIONS")
    :: ("access-control-allow-headers", "Content-Type")
    :: ("vary", "Origin")
    :: extra)

let respond_json ?(status = `OK) (json : Yojson.Safe.t) =
  let headers = cors_headers [ ("content-type", "application/json") ] in
  Cohttp_eio.Server.respond_string ~headers ~status
    ~body:(Yojson.Safe.to_string json)
    ()

(* Client identity for rate limiting. Behind Fly.io / a proxy the real IP is in
   a forwarded header; fall back to a constant so the limiter still applies. *)
let client_key req =
  let h = Http.Request.headers req in
  let first_hop v =
    match String.split_on_char ',' v with x :: _ -> String.trim x | [] -> v
  in
  match Http.Header.get h "fly-client-ip" with
  | Some ip -> ip
  | None -> (
      match Http.Header.get h "x-forwarded-for" with
      | Some v -> first_hop v
      | None -> (
          match Http.Header.get h "x-real-ip" with
          | Some ip -> ip
          | None -> "anonymous"))

let handle_check st ~sw ~env query =
  match List.assoc_opt "plate" query with
  | None | Some [] ->
      respond_json ~status:`Bad_request
        (error_json ~plate:"" ~msg:"missing ?plate= parameter")
  | Some (raw :: _) -> (
      match Plate_check.validate_plate raw with
      | Error e -> respond_json ~status:`Bad_request (error_json ~plate:raw ~msg:e)
      | Ok plate -> (
          match checked_availability st ~sw ~env plate with
          | Ok r -> respond_json (result_json r)
          | Error msg ->
              respond_json ~status:`Bad_gateway (error_json ~plate ~msg)))

let router st ~sw ~env limiter _conn req _body =
  let resource = Http.Request.resource req in
  let uri = Uri.of_string resource in
  let path = Uri.path uri in
  let meth = Http.Request.meth req in
  match (meth, path) with
  | `OPTIONS, _ ->
      (* CORS preflight *)
      Cohttp_eio.Server.respond_string ~headers:(cors_headers []) ~status:`No_content
        ~body:"" ()
  | `GET, "/api/health" -> respond_json (`Assoc [ ("status", `String "ok") ])
  | `GET, "/api/check" ->
      let now = Unix.gettimeofday () in
      if Ratelimit.allow limiter (client_key req) now then
        handle_check st ~sw ~env (Uri.query uri)
      else
        respond_json ~status:`Too_many_requests
          (error_json ~plate:""
             ~msg:
               (Printf.sprintf "rate limit: max %d checks per %ds"
                  ip_rate_capacity ip_rate_window_sec))
  | `GET, _ ->
      respond_json ~status:`Not_found (`Assoc [ ("error", `String "not found") ])
  | _ ->
      respond_json ~status:`Not_found
        (`Assoc [ ("error", `String "method not allowed") ])

let () =
  let st = { mutex = Eio.Mutex.create (); session = None; checks_since_reset = 0 } in
  let limiter =
    Ratelimit.create ~capacity:ip_rate_capacity
      ~window_sec:(float_of_int ip_rate_window_sec)
  in
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let handler =
    Cohttp_eio.Server.make ~callback:(router st ~sw ~env limiter) ()
  in
  let socket =
    Eio.Net.listen ~sw ~backlog:128 ~reuse_addr:true (Eio.Stdenv.net env)
      (`Tcp (Eio.Net.Ipaddr.V4.any, port))
  in
  Printf.printf
    "mo-plate-web backend on :%d  (rate ~%dms±%dms, refresh-every %d, per-IP \
     %d/%ds, origin %s)\n\
     %!"
    port rate_delay_ms jitter_ms refresh_every ip_rate_capacity
    ip_rate_window_sec allowed_origin;
  Cohttp_eio.Server.run socket handler
    ~on_error:(fun ex -> Printf.eprintf "conn error: %s\n%!" (Printexc.to_string ex))
