module Vim exposing (..)

import Regex exposing (Match)


type alias SearchMatchItem =
    { id : String
    , index : Int
    , name : String
    , matches : List Match
    }


type SearchingState
    = NotSearch
    | Searching
        { match : Maybe SearchMatchItem
        , scrollTop : Int
        }
    | SearchDone (List SearchMatchItem)


type VimAction
    = ArrowUp
    | ArrowDown
    | NextPage
    | PrevPage
    | Bottom
    | Top
    | Back
    | Forward
    | ArrowLeft
    | ArrowRight
    | Search
    | StartSearch String Int
    | SearchNav Bool
    | Center
    | Esc
    | NextSearchResult Bool
    | AppendKey String
    | SetSearchModeLineBuffer String
    | Enter
    | NoAction


parseKeys : Int -> List String -> String -> Bool -> VimAction
parseKeys scrollTop pendingKeys key ctrlKey =
    case ( pendingKeys, key, ctrlKey ) of
        ( _, "ArrowUp", False ) ->
            ArrowUp

        ( _, "ArrowDown", False ) ->
            ArrowDown

        ( _, "k", False ) ->
            ArrowUp

        ( _, "j", False ) ->
            ArrowDown

        ( _, "h", False ) ->
            ArrowLeft

        ( _, "l", False ) ->
            ArrowRight

        ( _, "ArrowLeft", False ) ->
            ArrowLeft

        ( _, "ArrowRight", False ) ->
            ArrowRight

        ( _, "d", True ) ->
            NextPage

        ( _, "u", True ) ->
            PrevPage

        ( _, "G", False ) ->
            Bottom

        ( [ "g" ], "g", False ) ->
            Top

        ( _, "o", True ) ->
            Back

        ( _, "i", True ) ->
            Forward

        ( _, "/", False ) ->
            StartSearch "/" scrollTop

        ( _, "?", False ) ->
            StartSearch "?" scrollTop

        ( [], "g", False ) ->
            AppendKey "g"

        ( [], "z", False ) ->
            AppendKey "z"

        ( [ "z" ], "z", False ) ->
            Center

        ( _, "Escape", _ ) ->
            Esc

        ( _, "n", _ ) ->
            NextSearchResult True

        ( _, "N", _ ) ->
            NextSearchResult False

        ( [], "Enter", _ ) ->
            Enter

        _ ->
            NoAction
