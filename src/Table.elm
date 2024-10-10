module Table exposing
    ( TableModel
    , TableMsg(..)
    , defaultTableModel
    , getSelectedEntry
    , isSortByTime
    , scrollToEntry
    , subTable
    , tableFilterView
    , tableView
    , updateTable
    )

import Browser.Dom as Dom
import Browser.Events exposing (onResize)
import Browser.Navigation as Nav
import Dict exposing (Dict)
import File exposing (File)
import File.Select as FileSelect
import Har exposing (EntryKind(..), SortBy, SortOrder(..))
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy3, lazy5, lazy6, lazy7)
import Icons
import Initial exposing (InitialMsg(..))
import Json.Decode as D
import List exposing (sortBy)
import Task
import Time exposing (Posix)
import UndoList as UL exposing (UndoList)
import Utils exposing (floatPx, intPx)
import Vim exposing (..)



-- MODEL


tableColumnWidthVariableName : String -> String
tableColumnWidthVariableName column =
    "--table-column-" ++ column ++ "-width"


cssVar : String -> String
cssVar name =
    "var(" ++ name ++ ")"


type alias TableColumn =
    { label : String
    , id : String
    , minWidth : Int
    }


getMinWidth : List TableColumn -> String -> Int
getMinWidth columns columnId =
    case columns of
        [] ->
            80

        column :: rest ->
            if column.id == columnId then
                column.minWidth

            else
                getMinWidth rest columnId


type alias TableFilter =
    { match : String
    , kind : Maybe EntryKind
    }


type alias TableModel =
    { sortBy : SortBy
    , columnWidths : Dict String Int
    , columns : List TableColumn
    , entries : List Har.Entry
    , selected : String
    , filter : TableFilter
    , scrollTop : Int
    , waterfallMsPerPx : Float
    , viewportHeight : Int
    , pendingKeys : List String
    , search : SearchingState
    , searchHistory : UndoList String
    }


isSortByTime : TableModel -> Bool
isSortByTime table =
    case table.sortBy of
        ( "time", _ ) ->
            True

        _ ->
            False


defaultTableModel : TableModel
defaultTableModel =
    { sortBy = ( "time", Asc )
    , columnWidths =
        Dict.fromList
            [ ( "name", 250 )
            , ( "method", 50 )
            , ( "status", 50 )
            , ( "time", 80 )
            , ( "domain", 80 )
            , ( "size", 80 )
            ]
    , columns =
        [ { id = "name", label = "Name", minWidth = 80 }
        , { id = "method", label = "Method", minWidth = 50 }
        , { id = "status", label = "Status", minWidth = 50 }
        , { id = "time", label = "Time", minWidth = 80 }

        -- , { id = "domain", label = "Domain", minWidth = 80 }
        , { id = "size", label = "Size", minWidth = 80 }
        , { id = "waterfall", label = "", minWidth = 0 }
        ]
    , entries = []
    , selected = ""
    , filter =
        { match = ""
        , kind = Nothing
        }
    , scrollTop = 0
    , waterfallMsPerPx = 10.0
    , viewportHeight = 0
    , pendingKeys = []
    , search = NotSearch
    , searchHistory = { present = "", past = [], future = [] }
    }


withUpdateIndex : TableModel -> (Int -> Int) -> ( TableModel, Cmd TableMsg )
withUpdateIndex table updateIndex =
    let
        index =
            table.entries
                |> Utils.indexOf (\entry -> entry.id == table.selected)
                |> Maybe.withDefault -1

        newSelected =
            table.entries
                |> List.drop (updateIndex index)
                |> List.head
                |> Maybe.map .id
                |> Maybe.withDefault ""
    in
    ( { table | selected = newSelected, pendingKeys = [] }, scrollToEntry table newSelected )


applySearchHistory : TableModel -> TableModel
applySearchHistory table =
    let
        lastSearch =
            (UL.undo table.searchHistory).present

        matches =
            Har.searchEntry table.entries <| String.dropLeft 1 lastSearch
    in
    { table | search = SearchDone matches }


applySearchResult : Bool -> TableModel -> ( TableModel, Cmd TableMsg )
applySearchResult isNext table =
    let
        selectedIndex =
            table.entries
                |> Utils.indexOf (\entry -> entry.id == table.selected)
                |> Maybe.withDefault -1

        selected =
            case table.search of
                SearchDone result ->
                    -- FIXME: this is too much, must have better way
                    let
                        i =
                            result
                                |> Utils.indexOf (\{ index } -> index > selectedIndex)
                                |> Maybe.map
                                    (\index ->
                                        if isNext then
                                            index

                                        else
                                            index - 1
                                    )
                                |> Maybe.withDefault
                                    (if isNext then
                                        0

                                     else
                                        List.length result - 1
                                    )
                    in
                    result
                        |> List.drop i
                        |> List.head
                        |> Maybe.map
                            (\{ id } ->
                                if table.selected == id then
                                    if i == 0 then
                                        result
                                            |> List.reverse
                                            |> List.head
                                            |> Maybe.map .id
                                            |> Maybe.withDefault table.selected

                                    else
                                        result
                                            |> List.drop (i - 1)
                                            |> List.head
                                            |> Maybe.map .id
                                            |> Maybe.withDefault table.selected

                                else
                                    id
                            )
                        |> Maybe.withDefault table.selected

                _ ->
                    table.selected
    in
    ( { table | selected = selected, pendingKeys = [] }, scrollToEntry table selected )


executeVimAction : Nav.Key -> TableModel -> VimAction -> ( TableModel, Cmd TableMsg )
executeVimAction navKey table action =
    case action of
        ArrowUp ->
            withUpdateIndex table
                (\index ->
                    if index > 0 then
                        index - 1

                    else
                        List.length table.entries - 1
                )

        ArrowDown ->
            withUpdateIndex table
                (\index ->
                    if index + 1 < List.length table.entries then
                        index + 1

                    else
                        0
                )

        ArrowLeft ->
            withUpdateIndex table (Har.getPrevReduxEntryIndex table.entries)

        ArrowRight ->
            withUpdateIndex table (Har.getNextReduxEntryIndex table.entries)

        NextPage ->
            withUpdateIndex table
                (\index ->
                    Basics.min (List.length table.entries - 1) <|
                        index
                            + ceiling (toFloat table.viewportHeight / 40)
                )

        PrevPage ->
            withUpdateIndex table
                (\index ->
                    Basics.max 0 <|
                        index
                            - ceiling (toFloat table.viewportHeight / 40)
                )

        Bottom ->
            withUpdateIndex table (\_ -> List.length table.entries - 1)

        Top ->
            withUpdateIndex table (\_ -> 0)

        Back ->
            ( table, Nav.back navKey 1 )

        Forward ->
            ( table, Nav.forward navKey 1 )

        Center ->
            ( table, scrollToCenter table table.selected )

        Search ->
            { table | searchHistory = UL.new "" table.searchHistory }
                |> applySearchHistory
                |> applySearchResult True
                |> Tuple.mapSecond (\cmd -> Cmd.batch [ focus "table-body", cmd ])

        SetSearchModeLineBuffer lineBuffer ->
            let
                match =
                    lineBuffer
                        |> String.dropLeft 1
                        |> Har.findEntry table.selected table.entries

                history =
                    table.searchHistory
            in
            ( { table
                | search =
                    case table.search of
                        Searching searching ->
                            Searching { searching | match = match }

                        others ->
                            others
                , searchHistory = { history | present = lineBuffer }
              }
            , match
                |> Maybe.map (\{ id } -> scrollToEntry table id)
                |> Maybe.withDefault Cmd.none
            )

        StartSearch prefix scrollTop ->
            let
                history =
                    table.searchHistory
            in
            ( { table
                | search = Searching { match = Nothing, scrollTop = scrollTop }
                , searchHistory = { history | present = prefix }
              }
            , focus "table-search"
            )

        NextSearchResult isDown ->
            if UL.hasPast table.searchHistory then
                case table.search of
                    SearchDone _ ->
                        applySearchResult isDown table

                    NotSearch ->
                        table
                            |> applySearchHistory
                            |> applySearchResult isDown

                    _ ->
                        ( table, Cmd.none )

            else
                ( table, Cmd.none )

        Esc ->
            ( { table
                | pendingKeys = []
                , search = NotSearch
                , scrollTop =
                    case table.search of
                        Searching searching ->
                            searching.scrollTop

                        _ ->
                            table.scrollTop
              }
            , focus "table-body"
            )

        NoAction ->
            ( { table | pendingKeys = [] }, Cmd.none )

        AppendKey strKey ->
            ( { table | pendingKeys = strKey :: table.pendingKeys }, Cmd.none )

        SearchNav isUp ->
            ( { table
                | searchHistory =
                    if isUp then
                        UL.undo table.searchHistory

                    else
                        UL.redo table.searchHistory
              }
            , Cmd.none
            )


getSelectedEntry : TableModel -> Maybe Har.Entry
getSelectedEntry { selected, entries } =
    Utils.findItem (\entry -> entry.id == selected) entries



-- VIEW


entryView : Float -> List TableColumn -> String -> Posix -> List (Attribute TableMsg) -> Har.Entry -> Html TableMsg
entryView msPerPx columns selected startTime attrs entry =
    div
        (attrs
            ++ [ class
                    (if selected == entry.id then
                        "selected"

                     else
                        ""
                    )
               , id <| "entry" ++ entry.id
               , class "table-body-row"
               , on "click"
                    (D.at [ "target", "className" ] D.string
                        |> D.map
                            (\className ->
                                Select entry.id (String.contains "table-body-cell-name" className) True False
                            )
                    )
               ]
        )
        (List.map (\column -> tableCellView msPerPx column startTime entry) columns)


getEntryIcon : Har.Entry -> Html msg
getEntryIcon entry =
    case Har.getEntryKind entry of
        ReduxState ->
            Icons.snapshotDoc

        ReduxAction ->
            Icons.actionDoc

        LogMessage ->
            Icons.logDoc

        NetworkHttp ->
            Icons.httpDoc

        Others ->
            Icons.jsDoc


tableCellContentView : Float -> String -> Posix -> Har.Entry -> Html msg
tableCellContentView msPerPx column startTime entry =
    case column of
        "name" ->
            div
                [ style "display" "contents"
                , style "pointer-events" "none"
                ]
                [ getEntryIcon entry
                , text <| Har.harEntryName entry
                ]

        "status" ->
            text <| String.fromInt entry.response.status

        "time" ->
            text entry.startedDateTimeStr

        "domain" ->
            text <|
                if String.startsWith "http" entry.request.url then
                    case String.split "/" entry.request.url of
                        _ :: _ :: domain :: _ ->
                            domain

                        _ ->
                            entry.request.url

                else
                    "―"

        "size" ->
            text <| Utils.formatSize (entry.response.bodySize + entry.request.bodySize)

        "method" ->
            text entry.request.method

        "waterfall" ->
            if Utils.comparePosix startTime entry.startedDateTime == GT then
                text ""

            else
                let
                    left =
                        (toFloat <| Time.posixToMillis entry.startedDateTime - Time.posixToMillis startTime) / msPerPx

                    width =
                        entry.time / msPerPx
                in
                div
                    [ class "table-body-cell-waterfall-item"
                    , style "width" (floatPx width)
                    , style "margin-left" (floatPx left)
                    , title <|
                        (String.fromInt <| round entry.time)
                            ++ " ms; "
                            ++ "at "
                            ++ entry.startedDateTimeStr
                    ]
                    []

        _ ->
            text ""


tableCellView : Float -> TableColumn -> Posix -> Har.Entry -> Html msg
tableCellView msPerPx column startTime entry =
    div
        [ class "table-body-cell"
        , class <| "table-body-cell-" ++ column.id
        , style "width" <| cssVar <| tableColumnWidthVariableName column.id
        , title <|
            if column.id == "name" then
                entry.request.url

            else
                ""
        ]
        [ tableCellContentView msPerPx column.id startTime entry ]


tableSortIcon : SortOrder -> Html msg
tableSortIcon sortOrder =
    case sortOrder of
        Asc ->
            Icons.sortAsc

        Desc ->
            Icons.sortDesc


tableHeaderCell : Float -> Posix -> Posix -> SortBy -> TableColumn -> Html TableMsg
tableHeaderCell waterfallMsPerPx startTime firstEntryStartTime ( sortColumn, sortOrder ) column =
    div
        [ class "table-header-cell"
        , class ("table-header-cell-" ++ column.id)
        , on "click"
            (D.at [ "target", "tagName" ] D.string
                |> D.map
                    (\tagName ->
                        if tagName == "SELECT" then
                            NoOp

                        else
                            FlipSort column.id
                    )
            )
        , style "width" <| cssVar <| tableColumnWidthVariableName column.id
        , class <|
            if column.id == sortColumn then
                "sorted"

            else
                ""
        ]
        ([ text column.label
         , if column.id == sortColumn then
            tableSortIcon sortOrder

           else
            div [] []
         , Utils.resizeDivider (\dx _ -> ResizeColumn column.id dx)
         ]
            ++ (if column.id == "waterfall" then
                    [ tableHeaderCellWaterfallScales waterfallMsPerPx startTime firstEntryStartTime
                    , Utils.dropDownList
                        { value = waterfallMsPerPxToScale waterfallMsPerPx
                        , onInput = scaleToWaterfallMsPerPx >> SetWaterfallMsPerPx
                        }
                        waterfallScaleOptions
                    ]

                else
                    []
               )
        )


tableHeaderCellWaterfallScales : Float -> Posix -> Posix -> Html TableMsg
tableHeaderCellWaterfallScales msPerPx startTime firstEntryStartTime =
    let
        alignOffset =
            100
                - modBy 100
                    (floor <|
                        (toFloat <| Utils.timespanMillis startTime firstEntryStartTime)
                            / msPerPx
                    )

        toMillis : Int -> String
        toMillis i =
            let
                px =
                    toFloat <| alignOffset + i * 100
            in
            (String.fromInt <|
                floor <|
                    (((toFloat <| Utils.timespanMillis startTime firstEntryStartTime) + (px * msPerPx)) / 1000)
            )
                ++ "s"
    in
    div
        [ class "waterfall-scale-container"
        , style "margin-left" (intPx alignOffset)
        ]
        (List.range 0 20
            |> List.map
                (\i ->
                    div
                        [ class "waterfall-scale", style "left" (intPx <| i * 100) ]
                        [ div [ class "triangle-scale" ] []
                        , label [] [ text (toMillis i) ]
                        ]
                )
        )


keyDecoder : Int -> Bool -> List String -> D.Decoder ( VimAction, Bool )
keyDecoder scrollTop showDetail pendingKeys =
    D.map2
        (\key ctrlKey ->
            let
                action =
                    parseKeys scrollTop pendingKeys key ctrlKey

                action1 =
                    -- search mode is not support when showDetail is false
                    if
                        (case action of
                            StartSearch _ _ ->
                                True

                            _ ->
                                False
                        )
                            && not showDetail
                    then
                        NoAction

                    else
                        action
            in
            ( action1, action1 /= NoAction )
        )
        (D.field "key" D.string)
        (D.field "ctrlKey" D.bool)


waterfallMsPerPxToScale : Float -> String
waterfallMsPerPxToScale msPerPx =
    (String.fromInt <| floor <| msPerPx / 10.0) ++ "x"


scaleToWaterfallMsPerPx : String -> Float
scaleToWaterfallMsPerPx scale =
    String.dropRight 1 scale
        |> String.toFloat
        |> Maybe.map ((*) 10.0)
        |> Maybe.withDefault 10.0


tableFilterOptions : List { value : String, label : String }
tableFilterOptions =
    [ { value = "", label = "All" }
    , { value = "0", label = "Redux" }
    , { value = "1", label = "Log" }
    , { value = "2", label = "Http" }
    , { value = "3", label = "Others" }
    ]


onEsc : TableMsg -> Attribute TableMsg
onEsc msg =
    preventDefaultOn "keydown" <|
        D.map
            (\key ->
                if key == "Escape" then
                    ( msg, True )

                else
                    ( NoOp, False )
            )
            (D.field "key" D.string)


waterfallScaleOptions : List { value : String, label : String }
waterfallScaleOptions =
    [ { value = "1x", label = "1x" }
    , { value = "2x", label = "2x" }
    , { value = "3x", label = "3x" }
    , { value = "4x", label = "4x" }
    ]


tableFilterView : TableFilter -> Html TableMsg
tableFilterView filter =
    section [ class "table-filter" ]
        [ input
            [ class "table-filter-input"
            , id "table-filter-input"
            , value filter.match
            , onInput InputFilter
            , type_ "search"
            , autofocus True
            , placeholder "Filter"
            , onEsc SelectTable
            ]
            []
        , Utils.dropDownList
            { value = Har.entryKindValue filter.kind
            , onInput = Har.stringToEntryKind >> SelectKind
            }
            tableFilterOptions
        , div [ class "actions" ]
            [ button
                [ class "import"
                , class "text"
                , onClick Import
                ]
                [ text "⬆Import" ]
            , button
                [ class "export"
                , class "text"
                , onClick Export
                ]
                [ text "⬇Export" ]
            ]
        ]


tableBodyEntriesView : Float -> List TableColumn -> String -> Bool -> Int -> List Har.Entry -> Int -> Html TableMsg
tableBodyEntriesView msPerPx columns selected showDetail scrollTop entries viewportHeight =
    let
        visibleColumns =
            if showDetail then
                List.take 1 columns

            else
                columns

        startTime =
            Har.getFirstEntryStartTime entries (floor <| toFloat scrollTop / 20)
    in
    Utils.virtualizedList
        { scrollTop = scrollTop
        , viewportHeight = viewportHeight
        , itemHeight = 20
        , items = entries
        , renderItem = \attrs entry -> ( entry.id, entryView msPerPx visibleColumns selected startTime attrs entry )
        }


waterfallGuideline : Float -> Posix -> Int -> List Har.Entry -> Int -> Html msg
waterfallGuideline msPerPx startTime guidelineLeft entries scrollTop =
    let
        firstEntryStartTime =
            Har.getFirstEntryStartTime entries (floor <| toFloat scrollTop / 20)

        guidelineAlignOffset =
            100
                - modBy 100
                    (floor <|
                        (toFloat <| Utils.timespanMillis startTime firstEntryStartTime)
                            / msPerPx
                    )
    in
    div
        [ class "waterfall-guideline-container"
        , style "left" (intPx (guidelineLeft + guidelineAlignOffset))
        ]
        [ div
            [ class "waterfall-guideline"
            , style "left" (intPx -guidelineAlignOffset)
            ]
            []
        ]


tableBodyView : SearchingState -> List String -> Float -> Posix -> List TableColumn -> Int -> String -> Bool -> List Har.Entry -> Int -> Int -> Html TableMsg
tableBodyView search pendingKeys msPerPx startTime columns guidelineLeft selected showDetail entries scrollTop viewportHeight =
    div
        [ class "table-body"
        , id "table-body"
        , tabindex 0
        , preventDefaultOn "keydown" (D.map (Tuple.mapFirst ExecuteAction) (keyDecoder scrollTop showDetail pendingKeys))
        , on "scroll" <| D.map (round >> Scroll) <| D.at [ "target", "scrollTop" ] D.float
        ]
        [ lazy7 tableBodyEntriesView msPerPx columns selected showDetail scrollTop entries viewportHeight
        , lazy3 tableBodySearchResultView search scrollTop viewportHeight
        , if showDetail then
            text ""

          else
            lazy5 waterfallGuideline msPerPx startTime guidelineLeft entries scrollTop
        ]


tableBodySearchResultView : SearchingState -> Int -> Int -> Html msg
tableBodySearchResultView search scrollTop viewportHeight =
    let
        items =
            case search of
                SearchDone result ->
                    result

                Searching { match } ->
                    case match of
                        Just m ->
                            [ m ]

                        _ ->
                            []

                _ ->
                    []
    in
    div [ style "display" "contents" ]
        (items
            |> List.filter (\{ index } -> scrollTop <= index * 20 && index * 20 < scrollTop + viewportHeight)
            |> List.map
                (\{ name, index, matches } ->
                    let
                        ( _, spans ) =
                            List.foldl
                                (\m ( i, acc ) ->
                                    let
                                        matchIndex =
                                            m.index
                                    in
                                    if i < matchIndex then
                                        ( matchIndex + String.length m.match
                                        , span [ class "match-highlight" ] [ text m.match ]
                                            :: span [ class "match" ] [ text <| String.slice i matchIndex name ]
                                            :: acc
                                        )

                                    else
                                        ( i + String.length m.match
                                        , span [ class "match-highlight" ] [ text m.match ] :: acc
                                        )
                                )
                                ( 0, [] )
                                matches
                    in
                    div
                        [ class "table-body-search-row"
                        , style "top" (intPx (index * 20))
                        ]
                        (List.reverse spans)
                )
        )


tableHeadersView : Float -> Posix -> Posix -> SortBy -> List TableColumn -> Bool -> Html TableMsg
tableHeadersView waterfallMsPerPx startTime firstEntryStartTime sortBy columns showDetail =
    let
        visibleColumns =
            if showDetail then
                List.take 1 columns

            else
                columns
    in
    div [ class "table-header" ] <|
        List.map (tableHeaderCell waterfallMsPerPx startTime firstEntryStartTime sortBy) visibleColumns


resolveSelected : String -> List Har.Entry -> String
resolveSelected selected entries =
    if Utils.isMember (\{ id } -> selected == id) entries then
        selected

    else
        ""


tableView : Posix -> TableModel -> Bool -> Html TableMsg
tableView startTime { entries, sortBy, columns, columnWidths, selected, scrollTop, waterfallMsPerPx, viewportHeight, search, searchHistory, pendingKeys } showDetail =
    let
        selected2 =
            resolveSelected selected entries

        showDetail2 =
            selected2 /= "" && showDetail

        -- hide columns except first column when selected
        visibleColumns =
            if showDetail2 then
                List.take 1 columns

            else
                columns

        guidelineLeft =
            totalWidth columnWidths visibleColumns

        firstEntryStartTime =
            Har.getFirstEntryStartTime entries (floor <| toFloat scrollTop / 20)
    in
    section
        [ class "table"
        , class
            (if selected2 /= "" then
                "table--selected"

             else
                ""
            )
        , Utils.styles
            (List.map
                (\c ->
                    ( tableColumnWidthVariableName c.id
                    , Dict.get c.id columnWidths
                        |> Maybe.map intPx
                        |> Maybe.withDefault "auto"
                    )
                )
                visibleColumns
            )
        ]
        [ case search of
            Searching _ ->
                input
                    [ class "table-search"
                    , id "table-search"
                    , value searchHistory.present
                    , autocomplete False
                    , onInput
                        (\value ->
                            ExecuteAction <|
                                case value of
                                    "" ->
                                        Esc

                                    _ ->
                                        SetSearchModeLineBuffer value
                        )

                    -- , onBlur <| ExecuteAction Esc
                    , preventDefaultOn "keydown" <|
                        D.map
                            (\arg ->
                                case arg of
                                    ( "Escape", _ ) ->
                                        ( ExecuteAction Esc, True )

                                    ( "Enter", _ ) ->
                                        ( ExecuteAction Search, True )

                                    ( "ArrowUp", _ ) ->
                                        ( ExecuteAction <| SearchNav True, True )

                                    ( "ArrowDown", _ ) ->
                                        ( ExecuteAction <| SearchNav False, True )

                                    ( "p", True ) ->
                                        ( ExecuteAction <| SearchNav True, True )

                                    ( "n", True ) ->
                                        ( ExecuteAction <| SearchNav False, True )

                                    _ ->
                                        ( NoOp, False )
                            )
                            (D.map2 Tuple.pair (D.field "key" D.string) (D.field "ctrlKey" D.bool))
                    ]
                    []

            _ ->
                text ""
        , lazy6 tableHeadersView waterfallMsPerPx startTime firstEntryStartTime sortBy columns showDetail2
        , tableBodyView search pendingKeys waterfallMsPerPx startTime columns guidelineLeft selected2 showDetail2 entries scrollTop viewportHeight
        , detailFirstColumnResizeDivider
        ]


detailFirstColumnResizeDivider : Html TableMsg
detailFirstColumnResizeDivider =
    Utils.resizeDivider (\dx _ -> ResizeColumn "name" dx)


totalWidth : Dict String Int -> List TableColumn -> Int
totalWidth columnWidths =
    List.foldl
        (\column acc ->
            acc
                + (columnWidths
                    |> Dict.get column.id
                    |> Maybe.map (Basics.max column.minWidth)
                    |> Maybe.withDefault 0
                  )
        )
        0



-- UPDATE


type TableMsg
    = NoOp
    | FlipSort String
    | ResizeColumn String Int
      -- id, True means show detail, False means keep detail shown/hidden as is, is pushUrl
    | Select String Bool Bool Bool
    | ExecuteAction VimAction
    | Scroll Int
    | ScrollToEntry String
    | InputFilter String
    | SelectKind (Maybe EntryKind)
    | SetWaterfallMsPerPx Float
    | SetViewportHeight Int
    | SelectTable
    | Import
    | GotImportFile File
    | Export


updateTable : Nav.Key -> TableMsg -> Har.Log -> TableModel -> ( TableModel, Cmd TableMsg )
updateTable navKey action log table =
    case action of
        NoOp ->
            ( table, Cmd.none )

        Import ->
            ( table, FileSelect.file [ "*" ] GotImportFile )

        GotImportFile file ->
            ( table, Cmd.none )

        Export ->
            ( table, Cmd.none )

        FlipSort column ->
            let
                ( currentSortColumn, currentSortOrder ) =
                    table.sortBy

                newSortBy =
                    if currentSortColumn == column then
                        ( column, Har.flipSortOrder currentSortOrder )

                    else
                        ( column, Asc )

                newEntries =
                    Har.sortEntries newSortBy table.entries
            in
            ( { table | sortBy = newSortBy, entries = newEntries }, Cmd.none )

        Select id _ isPushUrl scrollTo ->
            if table.selected == id then
                ( table, Cmd.none )

            else
                ( { table | selected = id }
                , Cmd.batch
                    [ if isPushUrl then
                        Nav.pushUrl navKey ("#entry" ++ id)

                      else
                        Cmd.none
                    , if scrollTo then
                        scrollToEntry table id

                      else
                        Cmd.none
                    ]
                )

        ExecuteAction act ->
            executeVimAction navKey table act

        ResizeColumn column dx ->
            let
                columnWidths =
                    Dict.update column
                        (\width ->
                            Maybe.map
                                (\w ->
                                    let
                                        minWidth =
                                            getMinWidth table.columns column
                                    in
                                    Basics.max (dx + w) minWidth
                                )
                                width
                        )
                        table.columnWidths
            in
            ( { table | columnWidths = columnWidths }, Cmd.none )

        InputFilter match ->
            let
                newEntries =
                    Har.filterEntries match table.filter.kind log.entries

                filter =
                    table.filter
            in
            ( { table | entries = newEntries, filter = { filter | match = match } }
            , if match == "" && table.selected /= "" then
                scrollToEntry table table.selected

              else
                Cmd.none
            )

        Scroll top ->
            ( { table | scrollTop = top }, Cmd.none )

        SelectKind kind ->
            let
                newEntries =
                    Har.filterEntries table.filter.match kind log.entries

                filter =
                    table.filter
            in
            ( { table | entries = newEntries, filter = { filter | kind = kind } }
            , if table.selected /= "" then
                Cmd.batch
                    [ scrollToEntry table table.selected
                    , focus "table-body"
                    ]

              else
                Cmd.none
            )

        ScrollToEntry id ->
            ( table, scrollToEntry table id )

        SetWaterfallMsPerPx msPerPx ->
            ( { table | waterfallMsPerPx = msPerPx }, Cmd.none )

        SetViewportHeight height ->
            ( { table | viewportHeight = height }, Cmd.none )

        SelectTable ->
            ( table
            , Cmd.batch
                [ scrollToEntry table table.selected
                , focus "table-body"
                ]
            )


scrollToEntry : TableModel -> String -> Cmd TableMsg
scrollToEntry table id =
    case Utils.indexOf (\entry -> entry.id == id) table.entries of
        Just i ->
            let
                y =
                    i * 20
            in
            if table.scrollTop <= y && y < table.scrollTop + table.viewportHeight then
                Cmd.none

            else
                Task.attempt (\_ -> NoOp) <|
                    Dom.setViewportOf "table-body"
                        0
                        (if y < table.scrollTop then
                            toFloat y

                         else
                            toFloat (y - table.viewportHeight + 20)
                        )

        _ ->
            Cmd.none


scrollToCenter : TableModel -> String -> Cmd TableMsg
scrollToCenter table id =
    case Utils.indexOf (\entry -> entry.id == id) table.entries of
        Just i ->
            Task.attempt (\_ -> NoOp) <|
                Dom.setViewportOf "table-body"
                    0
                    (toFloat i * 20 - toFloat table.viewportHeight / 2 + 10)

        _ ->
            Cmd.none


focus : String -> Cmd TableMsg
focus =
    Task.attempt (\_ -> NoOp) << Dom.focus



-- SUBS


subTable : Sub TableMsg
subTable =
    onResize (\_ h -> SetViewportHeight (h - 60))
