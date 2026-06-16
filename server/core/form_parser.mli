(** Pure parser for the MO DOR availability form.

    Operates on raw HTML strings (as received from the server). All functions
    return Result so parsing failures can be surfaced rather than silently
    producing empty values — a silent empty here masks bot-protection and
    session-loss bugs. *)

type hidden_fields = {
  viewstate : string;
  viewstategenerator : string;
  eventvalidation : string;
  lastfocus : string;
}

type option_item = {
  value : string;
  label : string;
  selected : bool;
}

type stage =
  | Stage_initial          (** plate type dropdown only *)
  | Stage_type_selected    (** vehicle type dropdown revealed *)
  | Stage_vehicle_selected (** Let1..Let7 inputs revealed *)
  | Stage_view_done        (** btnAvailable enabled *)
  | Stage_check_done       (** lblAvailability populated *)

type availability =
  | Available
  | Not_available
  | Unknown_message of string

type form_state = {
  hidden : hidden_fields;
  plate_types : option_item list;
  vehicle_types : option_item list;
  letters : string array;       (** length 0 if Let1-Let7 not yet present, else 7 *)
  stage : stage;
  availability : availability option;
}

val parse : string -> (form_state, string) result

val hidden_only : string -> (hidden_fields, string) result
(** Lighter-weight extraction for inner-loop posts where we only need tokens. *)
