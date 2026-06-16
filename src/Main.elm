module Main exposing (main)

import Browser
import Dict exposing (Dict)
import Html exposing (Html, button, div, h1, input, li, text, ul)
import Html.Attributes exposing (placeholder, value)
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


statusText model plate =
    case Dict.get plate model.results of
        Nothing ->
            ""

        Just r ->
            case r.available of
                Just True ->
                    "available"

                Just False ->
                    "taken"

                Nothing ->
                    r.message


candidateRow : Model -> String -> Html Msg
candidateRow model plate =
    li []
        [ text plate
        , button [ onClick (CheckRequest plate) ] [ text "check" ]
        , text (" " ++ statusText model plate)
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


init : () -> ( Model, Cmd Msg )
init _ =
    ( { seed = "Ahmed", apiBase = "http://localhost:8080", results = Dict.empty }, Cmd.none )



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
    div []
        [ h1 [] [ text "Plate Finder" ]
        , input [ placeholder "seed", value model.seed, onInput SeedChanged ] []
        , ul [] (List.map (candidateRow model) (Variations.fromSeed model.seed))
        ]



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


main : Program () Model Msg
main =
    Browser.element { init = init, update = update, view = view, subscriptions = subscriptions }
