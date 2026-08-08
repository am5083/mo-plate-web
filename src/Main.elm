module Main exposing (main)

import Browser
import Dict exposing (Dict)
import Html exposing (Html, a, button, div, footer, h1, header, img, input, p, span, text)
import Html.Attributes exposing (alt, class, href, maxlength, placeholder, rel, src, target, title, value)
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as Decode exposing (Decoder)
import Variations


type alias CheckResult =
    { plate : String, available : Maybe Bool, message : String }


resultDecoder : Decoder CheckResult
resultDecoder =
    Decode.map3 CheckResult
        (Decode.field "plate" Decode.string)
        (Decode.field "available" (Decode.nullable Decode.bool))
        (Decode.field "message" Decode.string)


checkPlate : String -> String -> Cmd Msg
checkPlate apiBase plate =
    let
        url =
            apiBase ++ "/api/check?plate=" ++ plate
    in
    Http.get { url = url, expect = Http.expectJson (CheckResponse plate) resultDecoder }


statusControl : Model -> String -> Html Msg
statusControl model plate =
    case Dict.get plate model.results of
        Nothing ->
            button [ class "check-btn", onClick (CheckRequest plate) ] [ text "check" ]

        Just r ->
            case r.available of
                Just True ->
                    span [ class "badge avail" ] [ text "available" ]

                Just False ->
                    span [ class "badge taken" ] [ text "taken" ]

                Nothing ->
                    span [ class "badge unknown", title r.message ] [ text "unknown" ]


candidateCard : Model -> String -> Html Msg
candidateCard model plate =
    div [ class "candidate" ]
        [ div [ class "plate plate-mini" ] [ text plate ]
        , statusControl model plate
        ]



-- MODEL


type alias Model =
    { seed : String, apiBase : String, results : Dict String CheckResult }



-- MSG


type Msg
    = SeedChanged String
    | CheckRequest String
    | CheckResponse String (Result Http.Error CheckResult)



-- INIT


type alias Flags =
    { apiBase : String }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { seed = "ahmed", apiBase = flags.apiBase, results = Dict.empty }, Cmd.none )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SeedChanged s ->
            ( { model | seed = s }, Cmd.none )

        CheckRequest plate ->
            ( model, checkPlate model.apiBase plate )

        CheckResponse plate result ->
            case result of
                Ok r ->
                    ( { model | results = Dict.insert plate r model.results }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "page" ]
        [ header [ class "hero" ]
            [ img [ class "logo-icon", src "assets/logo.svg", alt "Missouri License Plate Logo" ] []
            , h1 [ class "title" ] [ text "Missouri Plate Finder" ]
            , p [ class "subtitle" ]
                [ text "Generate look-alike & sound-alike vanity plates, then check availability with the Missouri DOR." ]
            ]
        , div [ class "plate plate-input" ]
            [ span [ class "plate-top" ] [ text "MISSOURI" ]
            , input
                [ class "seed-field"
                , value model.seed
                , maxlength 7
                , placeholder "AHMED"
                , onInput SeedChanged
                ]
                []
            , span [ class "plate-bottom" ] [ text "SHOW-ME STATE" ]
            ]
        , div [ class "grid" ] (List.map (candidateCard model) (Variations.fromSeed model.seed))
        , footer [ class "footer" ]
            [ p []
                [ text "© 2026 Ahmed Mohamed. This site is not affiliated with the Missouri Department of Revenue. View on "
                , a [ class "footer-link", href "https://github.com/am5083/mo-plate-web", target "_blank", rel "noopener noreferrer" ]
                    [ text "GitHub" ]
                , text "."
                ]
            ]
        ]



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


main : Program Flags Model Msg
main =
    Browser.element { init = init, update = update, view = view, subscriptions = subscriptions }
