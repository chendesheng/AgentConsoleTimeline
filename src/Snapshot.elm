module Snapshot exposing (..)

import Har exposing (EntryKind(..))
import Html exposing (..)
import Html.Attributes exposing (class, property, src, style)
import Iso8601
import Json.Encode as Encode
import Utils


agentConsoleSnapshotProps : Bool -> String -> String -> List Har.Entry -> String -> List (Html.Attribute msg)
agentConsoleSnapshotProps isSortByTime href pageName entries currentId =
    let
        stateEntryAndPrevStateEntryAllSites =
            Har.findStateEntryAndPrevStateEntryAllSites entries currentId

        stateAndActions =
            Encode.dict String.fromInt
                (\stateEntryAndPrevStateEntry ->
                    case ( stateEntryAndPrevStateEntry.stateEntry, stateEntryAndPrevStateEntry.prevStateEntry, stateEntryAndPrevStateEntry.nonStateEntries ) of
                        ( Just stateEntry, _, _ ) ->
                            Encode.object
                                [ ( "state", Encode.string <| (stateEntry |> Har.getReduxState |> Maybe.withDefault "") )
                                , ( "actions", Encode.list (\a -> a) [] )
                                , ( "time", Encode.string <| Iso8601.fromTime stateEntry.startedDateTime )
                                ]

                        ( Nothing, Just prevStateEntry, nonStateEntries ) ->
                            Encode.object
                                [ ( "state", Encode.string <| (prevStateEntry |> Har.getReduxState |> Maybe.withDefault "") )
                                , ( "actions"
                                  , if isSortByTime then
                                        nonStateEntries
                                            |> Har.filterByKind (Just ReduxAction)
                                            |> List.map (\e -> Har.getRequestBody e |> Maybe.withDefault "")
                                            |> Encode.list Encode.string

                                    else
                                        -- pass empty actions when entries are not sorted by time
                                        -- because when entries are not sorted by time, the states/actions are not in order
                                        Encode.list (\a -> a) []
                                  )
                                , ( "time"
                                  , nonStateEntries
                                        |> Utils.getLast
                                        |> Maybe.map .startedDateTime
                                        |> Maybe.withDefault Utils.epoch
                                        |> Iso8601.fromTime
                                        |> Encode.string
                                  )
                                ]

                        _ ->
                            Encode.object
                                [ ( "state", Encode.string "" )
                                , ( "actions", Encode.list (\a -> a) [] )
                                , ( "time", Encode.string "" )
                                ]
                )
                stateEntryAndPrevStateEntryAllSites

        time =
            Utils.findItem (\e -> e.id == currentId) entries
                |> Maybe.map .startedDateTime
                |> Maybe.withDefault Utils.epoch
                |> Iso8601.fromTime
                |> Encode.string
    in
    [ property "time" time
    , property "stateAndActions" stateAndActions
    , src href
    , property "pageName" <| Encode.string pageName
    ]


agentConsoleSnapshotFrame : Bool -> Bool -> String -> String -> List Har.Entry -> String -> Html msg
agentConsoleSnapshotFrame isSnapshotPopout isSortByTime href pageName entries currentId =
    Html.node "agent-console-snapshot-frame"
        ((property "isPopout" <| Encode.bool isSnapshotPopout)
            :: agentConsoleSnapshotProps isSortByTime href pageName entries currentId
        )
        []


agentConsoleSnapshotPopout : Bool -> String -> String -> List Har.Entry -> String -> Html msg
agentConsoleSnapshotPopout isSortByTime href pageName entries currentId =
    agentConsoleSnapshotFrame True isSortByTime href pageName entries currentId


type alias QuickPreview =
    { entryId : String
    , x : Int
    , y : Int
    , delayHide : Bool
    }


defaultQuickPreview : QuickPreview
defaultQuickPreview =
    { entryId = "", x = 0, y = 0, delayHide = False }


snapshotQuickPreview : Bool -> Maybe QuickPreview -> String -> String -> List Har.Entry -> Html msg
snapshotQuickPreview alignLeft quickPreview href pageName entries =
    let
        ( { entryId, x, y, delayHide }, display ) =
            case quickPreview of
                Just q ->
                    ( q, "block" )

                Nothing ->
                    ( defaultQuickPreview, "none" )
    in
    div
        [ class "quick-preview-container"
        , class <|
            if alignLeft then
                "align-left"

            else
                "align-bottom"
        , style "left" <| Utils.intPx x
        , style
            (if alignLeft then
                "top"

             else
                "bottom"
            )
          <|
            Utils.intPx y
        , class <|
            if delayHide then
                "delay-hide"

            else
                ""
        , style "display" display
        ]
        [ agentConsoleSnapshotFrame False False href pageName entries entryId ]
