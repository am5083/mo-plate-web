(** Drives the 5-step availability flow against a Session. *)

type result = {
  plate : string;
  plate_type : int;
  vehicle_type : int;
  availability : Form_parser.availability;
  checked_at : float;
}

val default_plate_type : int
(** 8 = Regular Personalized *)

val default_vehicle_type : int
(** 82 = Passenger *)

val validate_plate : string -> (string, string) Stdlib.result
(** Uppercase, strip whitespace, ensure 1-7 chars in [A-Z0-9]. *)

val check :
  ?plate_type:int ->
  ?vehicle_type:int ->
  Session.t ->
  string ->
  result

val try_check :
  ?plate_type:int ->
  ?vehicle_type:int ->
  ?max_retries:int ->
  Session.t ->
  string ->
  (result, string) Stdlib.result
(** Wraps [check] with retry-on-parse-failure. On each failure, drops session
    state (cookies + hidden fields) and retries. Returns Error after
    [max_retries] consecutive failures. *)

val full_reset :
  ?plate_type:int -> ?vehicle_type:int -> Session.t -> unit
(** Drop everything (cookies, hidden fields), GET fresh, re-do
    type+vehicle setup. Use periodically during long scans. *)
