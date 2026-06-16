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
  | Stage_initial
  | Stage_type_selected
  | Stage_vehicle_selected
  | Stage_view_done
  | Stage_check_done

type availability =
  | Available
  | Not_available
  | Unknown_message of string

type form_state = {
  hidden : hidden_fields;
  plate_types : option_item list;
  vehicle_types : option_item list;
  letters : string array;
  stage : stage;
  availability : availability option;
}

let ( let* ) = Result.bind

let contains_ci haystack needle =
  let h = String.lowercase_ascii haystack in
  let n = String.lowercase_ascii needle in
  let lh = String.length h and ln = String.length n in
  if ln = 0 then true
  else if ln > lh then false
  else
    let rec loop i =
      if i > lh - ln then false
      else if String.sub h i ln = n then true
      else loop (i + 1)
    in
    loop 0

let attr_or_empty name node =
  Soup.attribute name node |> Option.value ~default:""

let hidden_value soup id =
  let sel = Printf.sprintf {|input[id="%s"]|} id in
  match Soup.(soup $? sel) with
  | None -> Error (Printf.sprintf "missing hidden input #%s" id)
  | Some node -> Ok (attr_or_empty "value" node)

let hidden_only_soup soup =
  let* viewstate = hidden_value soup "__VIEWSTATE" in
  let* viewstategenerator = hidden_value soup "__VIEWSTATEGENERATOR" in
  let* eventvalidation = hidden_value soup "__EVENTVALIDATION" in
  let lastfocus =
    match Soup.(soup $? {|input[id="__LASTFOCUS"]|}) with
    | None -> ""
    | Some n -> attr_or_empty "value" n
  in
  Ok { viewstate; viewstategenerator; eventvalidation; lastfocus }

let hidden_only html =
  hidden_only_soup (Soup.parse html)

let options_of_select soup id =
  let q = Printf.sprintf {|select[id="%s"]|} id in
  match Soup.(soup $? q) with
  | None -> []
  | Some sel ->
      Soup.(sel $$ "option")
      |> Soup.to_list
      |> List.map (fun o ->
             {
               value = attr_or_empty "value" o;
               label =
                 Soup.leaf_text o |> Option.value ~default:"" |> String.trim;
               selected = Option.is_some (Soup.attribute "selected" o);
             })

let letter_values soup =
  let rec collect i acc =
    if i > 7 then List.rev acc
    else
      let id = Printf.sprintf "MainContent_Let%d" i in
      let q = Printf.sprintf {|input[id="%s"]|} id in
      match Soup.(soup $? q) with
      | None -> List.rev acc
      | Some n -> collect (i + 1) (attr_or_empty "value" n :: acc)
  in
  Array.of_list (collect 1 [])

let lbl_text soup id =
  let q = Printf.sprintf {|span[id="%s"]|} id in
  match Soup.(soup $? q) with
  | None -> None
  | Some n ->
      Some (Soup.texts n |> String.concat " " |> String.trim)

let parse_availability soup =
  match lbl_text soup "MainContent_lblAvailability" with
  | None | Some "" -> None
  | Some text ->
      if contains_ci text "not available" then Some Not_available
      else if contains_ci text "is available" then Some Available
      else Some (Unknown_message text)

let btn_available_enabled soup =
  match Soup.(soup $? {|input[id="MainContent_btnAvailable"]|}) with
  | None -> false
  | Some n -> Option.is_none (Soup.attribute "disabled" n)

let detect_stage ~plate_selected ~vehicle_selected ~has_letters
    ~btn_avail_enabled ~availability =
  match availability with
  | Some _ -> Stage_check_done
  | None when btn_avail_enabled -> Stage_view_done
  | None when has_letters && vehicle_selected -> Stage_vehicle_selected
  | None when plate_selected -> Stage_type_selected
  | None -> Stage_initial

let parse html =
  let soup = Soup.parse html in
  let* hidden = hidden_only_soup soup in
  let plate_types = options_of_select soup "MainContent_ddlSelectPlateType" in
  let vehicle_types =
    options_of_select soup "MainContent_ddlSelectVehicleType"
  in
  let letters = letter_values soup in
  let availability = parse_availability soup in
  let plate_selected =
    List.exists (fun o -> o.selected && o.value <> "0") plate_types
  in
  let vehicle_selected =
    List.exists (fun o -> o.selected && o.value <> "0") vehicle_types
  in
  let has_letters = Array.length letters >= 7 in
  let stage =
    detect_stage ~plate_selected ~vehicle_selected ~has_letters
      ~btn_avail_enabled:(btn_available_enabled soup)
      ~availability
  in
  Ok { hidden; plate_types; vehicle_types; letters; stage; availability }
