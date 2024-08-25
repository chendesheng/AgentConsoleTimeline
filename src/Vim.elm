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
        { result : Maybe SearchMatchItem
        , lineBuffer : String
        , scrollTop : Int
        }
    | SearchDone
        { result : List SearchMatchItem
        , currentIndex : Int
        , lineBuffer : String
        }


type alias VimState =
    { pendingKeys : List String
    , search : SearchingState
    }


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
    | StartSearch String
    | Center
    | Esc
    | NextSearchResult
    | PrevSearchResult
    | AppendKey String
    | SetSearchModeLineBuffer String
    | NoAction


defaultVimState : VimState
defaultVimState =
    { pendingKeys = []
    , search = NotSearch
    }


updateVimState : VimState -> VimAction -> VimState
updateVimState vimState vimAction =
    case vimAction of
        NoAction ->
            { vimState | pendingKeys = [] }

        AppendKey strKey ->
            { vimState | pendingKeys = strKey :: vimState.pendingKeys }

        StartSearch prefix ->
            { vimState | search = Searching { result = Nothing, lineBuffer = prefix, scrollTop = 0 } }

        SetSearchModeLineBuffer str ->
            { vimState
                | search =
                    case vimState.search of
                        Searching searching ->
                            Searching { searching | lineBuffer = str }

                        _ ->
                            NotSearch
            }

        NextSearchResult ->
            { vimState
                | search =
                    case vimState.search of
                        SearchDone searchDone ->
                            SearchDone
                                { searchDone
                                    | currentIndex =
                                        if searchDone.currentIndex + 1 == List.length searchDone.result then
                                            0

                                        else
                                            searchDone.currentIndex + 1
                                }

                        _ ->
                            vimState.search
            }

        PrevSearchResult ->
            { vimState
                | search =
                    case vimState.search of
                        SearchDone searchDone ->
                            SearchDone
                                { searchDone
                                    | currentIndex =
                                        if searchDone.currentIndex == 0 then
                                            List.length searchDone.result - 1

                                        else
                                            searchDone.currentIndex - 1
                                }

                        _ ->
                            vimState.search
            }

        _ ->
            vimState


parseKeys : VimState -> String -> Bool -> VimAction
parseKeys { pendingKeys } key ctrlKey =
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
            StartSearch "/"

        ( _, "?", False ) ->
            StartSearch "?"

        ( [], "g", False ) ->
            AppendKey "g"

        ( [], "z", False ) ->
            AppendKey "z"

        ( [ "z" ], "z", False ) ->
            Center

        ( _, "Escape", _ ) ->
            Esc

        ( _, "n", _ ) ->
            NextSearchResult

        ( _, "N", _ ) ->
            PrevSearchResult

        _ ->
            NoAction
