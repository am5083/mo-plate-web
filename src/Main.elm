module Main exposing (main)

import Browser
import Html exposing (Html, div, h1, input, li, text, ul)
import Html.Attributes exposing (placeholder, value)
import Html.Events exposing (onInput)
import Variations



-- MODEL
-- TODO: a record with one field, the seed string.


type alias Model =
    { seed : String }



-- MSG


type Msg
    = SeedChanged String



-- INIT


init : Model
init =
    { seed = "Ahmed" }



-- UPDATE


update : Msg -> Model -> Model
update msg model =
    case msg of
        SeedChanged s ->
            { model | seed = s }



-- VIEW


view : Model -> Html Msg
view model =
    div []
        [ h1 [] [ text "Plate Finder" ]
        , input [ placeholder "seed", value model.seed, onInput SeedChanged ] []
        , ul [] (List.map (\c -> li [] [ text c ]) (Variations.fromSeed model.seed))
        ]


main : Program () Model Msg
main =
    Browser.sandbox { init = init, update = update, view = view }
