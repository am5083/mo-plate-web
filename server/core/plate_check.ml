type result = {
  plate : string;
  plate_type : int;
  vehicle_type : int;
  availability : Form_parser.availability;
  checked_at : float;
}

let default_plate_type = 8
let default_vehicle_type = 82

let is_plate_char c =
  (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

let validate_plate raw =
  let s = String.trim raw |> String.uppercase_ascii in
  let len = String.length s in
  if len < 1 then Error "plate is empty"
  else if len > 7 then Error "plate exceeds 7 characters"
  else if not (String.for_all is_plate_char s) then
    Error "plate must contain only A-Z and 0-9"
  else Ok s

let pad_letters plate =
  let len = String.length plate in
  Array.init 7 (fun i ->
      if i < len then String.make 1 plate.[i] else "")

let letter_fields letters =
  Array.to_list letters
  |> List.mapi (fun i v ->
         (Printf.sprintf "ctl00$MainContent$Let%d" (i + 1), v))

let dropdown_fields ~plate_type ~vehicle_type =
  [
    ( "ctl00$MainContent$ddlSelectPlateType",
      string_of_int plate_type );
    ( "ctl00$MainContent$ddlSelectVehicleType",
      string_of_int vehicle_type );
  ]

let selected_int_value (opts : Form_parser.option_item list) =
  List.find_opt (fun (o : Form_parser.option_item) -> o.selected) opts
  |> Option.map (fun (o : Form_parser.option_item) -> o.value)

let need_full_setup ~plate_type ~vehicle_type (st : Form_parser.form_state) =
  let pt = selected_int_value st.plate_types in
  let vt = selected_int_value st.vehicle_types in
  pt <> Some (string_of_int plate_type)
  || vt <> Some (string_of_int vehicle_type)

let setup ~plate_type ~vehicle_type session =
  let _ = Session.refresh session in
  let _ =
    Session.post session
      ~event_target:"ctl00$MainContent$ddlSelectPlateType"
      ~fields:
        [
          ( "ctl00$MainContent$ddlSelectPlateType",
            string_of_int plate_type );
        ]
      ()
  in
  let _ =
    Session.post session
      ~event_target:"ctl00$MainContent$ddlSelectVehicleType"
      ~fields:(dropdown_fields ~plate_type ~vehicle_type)
      ()
  in
  ()

let check_once ~plate_type ~vehicle_type session plate =
  let cur =
    match Session.state session with
    | Some s -> s
    | None -> Session.refresh session
  in
  if need_full_setup ~plate_type ~vehicle_type cur then
    setup ~plate_type ~vehicle_type session;
  let letters = pad_letters plate in
  let view_fields =
    dropdown_fields ~plate_type ~vehicle_type
    @ letter_fields letters
    @ [ ("ctl00$MainContent$btnView", "View") ]
  in
  let _ = Session.post session ~event_target:"" ~fields:view_fields () in
  let avail_fields =
    dropdown_fields ~plate_type ~vehicle_type @ letter_fields letters
  in
  let st =
    Session.post session
      ~event_target:"ctl00$MainContent$btnAvailable"
      ~fields:avail_fields ()
  in
  let availability =
    match st.availability with
    | Some a -> a
    | None ->
        Form_parser.Unknown_message
          "no availability label in response (form likely reset or blocked)"
  in
  { plate; plate_type; vehicle_type; availability; checked_at = Unix.time () }

let full_reset ?(plate_type = default_plate_type)
    ?(vehicle_type = default_vehicle_type) session =
  Session.cookies_clear session;
  Session.clear_state session;
  let _ = Session.refresh session in
  setup ~plate_type ~vehicle_type session

let check ?(plate_type = default_plate_type)
    ?(vehicle_type = default_vehicle_type) session raw_plate =
  let plate =
    match validate_plate raw_plate with
    | Ok p -> p
    | Error e -> invalid_arg e
  in
  check_once ~plate_type ~vehicle_type session plate

let try_check ?(plate_type = default_plate_type)
    ?(vehicle_type = default_vehicle_type) ?(max_retries = 2) session raw_plate
    =
  match validate_plate raw_plate with
  | Error e -> Error e
  | Ok plate ->
      let rec attempt n last_err =
        if n > max_retries then Error last_err
        else
          match
            try Ok (check_once ~plate_type ~vehicle_type session plate)
            with Failure msg -> Error msg
          with
          | Ok r -> Ok r
          | Error msg ->
              (* On any HTTP/parse failure, blow away session state and try
                 again from scratch. *)
              (try full_reset ~plate_type ~vehicle_type session
               with _ -> ());
              attempt (n + 1) msg
      in
      attempt 0 "no attempt made"
