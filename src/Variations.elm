module Variations exposing (..)

import Set exposing (..)


normalize : String -> String
normalize seed =
    String.toUpper seed
        |> String.filter (\c -> (c <= 'Z' && c >= 'A') || (c >= '0' && c <= '9'))


reverse : String -> List String
reverse seed =
    let
        s =
            normalize seed
    in
    [ String.reverse s ]


truncate : String -> List String
truncate seed =
    let
        s =
            normalize seed

        n =
            String.length s
    in
    List.range 1 (n - 1)
        |> List.concatMap (\i -> [ String.left i s, String.right i s ])


dropAny : String -> List String
dropAny seed =
    let
        s =
            normalize seed

        n =
            String.length s
    in
    List.range 0 (n - 1)
        |> List.map (\i -> String.left i s ++ String.dropLeft (i + 1) s)


padSimple : String -> List String
padSimple seed =
    let
        s =
            normalize seed

        suffixes =
            [ "", "1", "2", "X", "Z", "MO", "STL", "KC", "01", "99" ]
    in
    suffixes
        |> List.map (\suf -> s ++ suf)
        |> List.filter (\x -> String.length x <= 7)


transformers : List (String -> List String)
transformers =
    [ reverse
    , truncate
    , dropAny
    , padSimple
    ]


fromSeed : String -> List String
fromSeed word =
    List.foldl
        (\f acc -> Set.union acc (Set.fromList (f word)))
        (Set.singleton (normalize word))
        transformers
        |> Set.toList
