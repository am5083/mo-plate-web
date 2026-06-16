(** Session against the MO DOR availability form.

    Holds a cookie jar plus the most recently parsed hidden fields, and
    rate-limits outgoing requests. Each post automatically injects the latest
    __VIEWSTATE / __EVENTVALIDATION / __VIEWSTATEGENERATOR / __LASTFOCUS pulled
    from the previous response, plus all stored cookies.

    Redirects are followed manually, preserving POST method (curl's default
    rewrites POST→GET on 301, which silently breaks ASP.NET state). *)

type t

val create :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  ?rate_delay_ms:int ->
  ?jitter_ms:int ->
  ?user_agent:string ->
  base_uri:Uri.t ->
  unit ->
  t
(** [rate_delay_ms] is the minimum gap between requests; [jitter_ms] is a
    uniform random extra delay added on each request. Browsers don't fire
    requests on a metronome — jitter makes the traffic pattern less
    fingerprintable as a bot, AND spreads load. *)

val clear_state : t -> unit
(** Drop hidden fields and last_state. Next post will trigger a refresh. Use
    when you want to force a fresh setup, e.g. after a long scan in case the
    server has rotated session salts. *)

val cookies_clear : t -> unit
(** Drop all cookies. Combined with clear_state, this gives a fully fresh
    session on the next request — useful when Imperva's incap_ses cookie has
    aged out. *)

val refresh : t -> Form_parser.form_state
(** GET base_uri, parse, update tokens & cookies, return state. *)

val post :
  t ->
  event_target:string ->
  fields:(string * string) list ->
  unit ->
  Form_parser.form_state
(** POST with current hidden fields + given event target + user fields. *)

val raw_post :
  t ->
  event_target:string ->
  fields:(string * string) list ->
  unit ->
  string
(** Same as post but returns the raw body (for debugging / unparseable responses). *)

val state : t -> Form_parser.form_state option

val cookie_count : t -> int
