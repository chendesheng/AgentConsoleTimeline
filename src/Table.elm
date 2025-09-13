module Table exposing
    ( TableFilter
    , TableModel
    , TableMsg(..)
    , VisitorInfo
    , defaultTableFilter
    , defaultTableModel
    , getSelectedEntry
    , isScrollbarInBottom
    , isSortByTime
    , scrollToBottom
    , subTable
    , tableFilterView
    , tableView
    , updateTable
    , visitorInfoDecoder
    )

import Browser.Dom as Dom
import Browser.Events exposing (onResize)
import Dict exposing (Dict)
import DropFile exposing (DropFileModel)
import Har exposing (EntryKind(..), SortBy, SortOrder(..))
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy3, lazy5, lazy7, lazy8)
import Icons
import Json.Decode as D
import Json.Encode as Encode
import JsonFile exposing (JsonFile, jsonFileDecoder)
import List exposing (sortBy)
import Snapshot exposing (QuickPreview)
import Task
import Time exposing (Posix)
import UndoList as UL exposing (UndoList)
import Utils exposing (GroupOption, floatPx, intPx)
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
    , highlightVisitorId : Maybe String
    , changedPaths : List String
    , page : String
    }


type alias VisitorInfo =
    { id : String, name : String }


visitorInfoDecoder : D.Decoder VisitorInfo
visitorInfoDecoder =
    D.map2 VisitorInfo
        (D.field "id" D.string)
        (D.field "name" D.string)


type alias TableModel =
    { sortBy : SortBy
    , columnWidths : Dict String Int
    , columns : List TableColumn
    , entries : List Har.Entry
    , entriesCount : Int
    , href : String
    , filter : TableFilter
    , scrollTop : Int
    , waterfallMsPerPx : Float
    , viewportHeight : Int
    , pendingKeys : List String
    , search : SearchingState
    , searchHistory : UndoList String
    , selectHistory : UndoList String
    , visitors : List VisitorInfo
    , quickPreview : Maybe QuickPreview
    }


isSortByTime : TableModel -> Bool
isSortByTime table =
    case table.sortBy of
        ( "time", _ ) ->
            True

        _ ->
            False


defaultTableFilter : TableFilter
defaultTableFilter =
    { match = ""
    , kind = Nothing
    , highlightVisitorId = Nothing
    , changedPaths = []
    , page = ""
    }


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
    , entriesCount = 0
    , filter = defaultTableFilter
    , href = ""
    , scrollTop = 0
    , waterfallMsPerPx = 10.0
    , viewportHeight = 0
    , pendingKeys = []
    , search = NotSearch
    , searchHistory = { present = "", past = [], future = [] }
    , selectHistory = { present = "", past = [], future = [] }
    , visitors = []
    , quickPreview = Nothing
    }


isScrollbarInBottom : TableModel -> Bool
isScrollbarInBottom table =
    table.scrollTop + table.viewportHeight >= table.entriesCount * 20


withUpdateIndex : TableModel -> (Int -> Int) -> ( TableModel, Cmd TableMsg )
withUpdateIndex table updateIndex =
    let
        index =
            table.entries
                |> Utils.indexOf (\entry -> entry.id == table.selectHistory.present)
                |> Maybe.withDefault -1

        newSelected =
            table.entries
                |> List.drop (updateIndex index)
                |> List.head
                |> Maybe.map .id
                |> Maybe.withDefault ""
    in
    ( { table
        | selectHistory =
            if newSelected == table.selectHistory.present then
                table.selectHistory

            else
                UL.new newSelected table.selectHistory
      }
    , scrollToEntry table newSelected
    )


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
                |> Utils.indexOf (\entry -> entry.id == table.selectHistory.present)
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
                                if table.selectHistory.present == id then
                                    if i == 0 then
                                        result
                                            |> List.reverse
                                            |> List.head
                                            |> Maybe.map .id
                                            |> Maybe.withDefault table.selectHistory.present

                                    else
                                        result
                                            |> List.drop (i - 1)
                                            |> List.head
                                            |> Maybe.map .id
                                            |> Maybe.withDefault table.selectHistory.present

                                else
                                    id
                            )
                        |> Maybe.withDefault table.selectHistory.present

                _ ->
                    table.selectHistory.present
    in
    ( { table | selectHistory = UL.new selected table.selectHistory, pendingKeys = [] }, scrollToEntry table selected )


executeVimAction : TableModel -> VimAction -> ( TableModel, Cmd TableMsg )
executeVimAction table action =
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
            let
                newSelectHistory =
                    UL.undo table.selectHistory
            in
            ( { table
                | selectHistory = newSelectHistory
              }
            , scrollToEntry table newSelectHistory.present
            )

        Forward ->
            let
                newSelectHistory =
                    UL.redo table.selectHistory
            in
            ( { table | selectHistory = newSelectHistory }, scrollToEntry table newSelectHistory.present )

        Center ->
            ( table, scrollToCenter table table.selectHistory.present )

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
                        |> Har.findEntry table.selectHistory.present table.entries

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

        Enter ->
            ( table, Cmd.none )

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
getSelectedEntry { selectHistory, entries } =
    Utils.findItem (\entry -> entry.id == selectHistory.present) entries



-- VIEW


entryView : Float -> List TableColumn -> Bool -> String -> Posix -> Har.Entry -> Bool -> Html TableMsg
entryView msPerPx columns showDetail selected startTime entry isHighlighted =
    let
        visibleColumns =
            if showDetail then
                List.take 1 columns

            else
                columns
    in
    div
        [ class
            (if selected == entry.id then
                "selected"

             else
                ""
            )
        , class
            (if isHighlighted then
                ""

             else
                "darken"
            )
        , class
            (if entry.request.method == "OPTIONS" then
                "darken"

             else
                ""
            )
        , id <| "entry" ++ entry.id
        , class "table-body-row"
        , on "click"
            (D.at [ "target", "className" ] D.string
                |> D.map
                    (\className ->
                        Select entry.id (String.contains "table-body-cell-name" className) False
                    )
            )
        ]
        (List.map (\column -> tableCellView msPerPx column startTime entry) visibleColumns)


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

            else if Har.isReduxStateEntry entry then
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
                        Utils.formatDuration (round entry.time)
                            ++ " at "
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
        , class <|
            if Har.isHttpFailedEntry entry then
                "table-body-cell-name__failed"

            else
                ""
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


tableHeaderCell : Int -> Float -> Posix -> Posix -> SortBy -> TableColumn -> Html TableMsg
tableHeaderCell entriesCount waterfallMsPerPx startTime firstEntryStartTime ( sortColumn, sortOrder ) column =
    let
        label =
            if column.id == "name" then
                column.label ++ " (" ++ String.fromInt entriesCount ++ ")"

            else
                column.label
    in
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
        ([ text label
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


keyDecoder : Int -> List String -> D.Decoder ( VimAction, Bool )
keyDecoder scrollTop pendingKeys =
    D.map2
        (\key ctrlKey ->
            let
                action =
                    parseKeys scrollTop pendingKeys key ctrlKey
            in
            ( action, action /= NoAction )
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


tableFilterOptions : List VisitorInfo -> List GroupOption
tableFilterOptions visitors =
    [ { label = "", subitems = [ { value = "", label = "All" } ] }
    , { label = "", subitems = [ { value = "1", label = "Log" } ] }
    , { label = "", subitems = [ { value = "2", label = "Http" } ] }
    , { label = "", subitems = [ { value = "3", label = "Others" } ] }
    , { label = "Redux"
      , subitems =
            { value = "0", label = "All" }
                :: List.map (\{ id, name } -> { value = "0-" ++ id, label = name }) visitors
      }
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
    , { value = "5x", label = "5x" }
    , { value = "6x", label = "6x" }
    , { value = "7x", label = "7x" }
    , { value = "8x", label = "8x" }
    , { value = "9x", label = "9x" }
    , { value = "10x", label = "10x" }
    , { value = "11x", label = "11x" }
    , { value = "12x", label = "12x" }
    , { value = "13x", label = "13x" }
    , { value = "14x", label = "14x" }
    , { value = "15x", label = "15x" }
    , { value = "16x", label = "16x" }
    , { value = "17x", label = "17x" }
    , { value = "18x", label = "18x" }
    , { value = "19x", label = "19x" }
    , { value = "20x", label = "20x" }
    ]


importButton : Maybe String -> Html TableMsg
importButton error =
    Html.node "open-file-button"
        ([ property "label" <| Encode.string "Import"
         , property "icon" <| Encode.string "import"
         , on "change" <|
            D.map (GotImportFile << Ok) <|
                D.field "detail" jsonFileDecoder
         , on "error" <|
            D.map (GotImportFile << Err) <|
                D.field "detail" D.string
         ]
            ++ (case error of
                    Just err ->
                        [ property "error" <| Encode.string err, class "error" ]

                    Nothing ->
                        []
               )
        )
        []


tableFilterView : Bool -> List VisitorInfo -> DropFileModel -> Bool -> List Har.Page -> TableFilter -> Html TableMsg
tableFilterView liveSession visitors dropFile autoFocus pages filter =
    section [ class "table-filter" ]
        [ if liveSession then
            Icons.live

          else
            text ""
        , input
            [ class "table-filter-input"
            , id "table-filter-input"
            , value filter.match
            , onInput InputFilter
            , type_ "search"
            , autofocus autoFocus
            , placeholder "Filter"

            -- , onEsc SelectTable
            ]
            []
        , Utils.dropDownListWithGroup
            { value = Har.entryKindAndHighlightVisitorIdValue filter.kind filter.highlightVisitorId
            , onInput = Har.stringToEntryKindAndHighlightVisitorId >> SelectKind
            }
          <|
            tableFilterOptions visitors
        , if List.length pages <= 1 then
            text ""

          else
            Utils.dropDownList
                { value = filter.page
                , onInput = ChangePage
                }
                (List.map (\page -> { value = page.id, label = page.id }) pages)
        , case filter.changedPaths of
            [] ->
                text ""

            changedPaths ->
                div [ class "tags" ] <| List.map tagView changedPaths
        , div [ class "actions" ]
            [ importButton dropFile.error
            , Html.node "export-button"
                [ property "label" <| Encode.string "Export"
                , property "fileName" <| Encode.string dropFile.fileName
                , property "fileContent" <| Encode.string dropFile.fileContentString
                , onClick JsonEncodeFileContent
                ]
                []
            ]
        ]


tagView : String -> Html TableMsg
tagView label =
    div [ class "tag", title label ]
        [ div [ class "tag-label" ] [ text label ]
        , button [ class "close", onClick (ToggleFilterChangedPath label) ] [ Icons.close ]
        ]


tableBodyEntriesView : Float -> List TableColumn -> String -> Bool -> Int -> List Har.Entry -> Int -> TableFilter -> Html TableMsg
tableBodyEntriesView msPerPx columns selected showDetail scrollTop entries viewportHeight filter =
    let
        startTime =
            -- startTime is not used when detail is displayed
            if showDetail then
                Utils.epoch

            else
                Har.getFirstEntryStartTime entries (floor <| toFloat scrollTop / 20)
    in
    Utils.virtualizedList
        { scrollTop = scrollTop
        , viewportHeight = viewportHeight
        , itemHeight = 20
        , items = entries
        , renderItem =
            \entry ->
                ( entry.id, lazy7 entryView msPerPx columns showDetail selected startTime entry (isHighlightEntry filter entry) )
        }


isHighlightEntry : TableFilter -> Har.Entry -> Bool
isHighlightEntry filter entry =
    if filter.highlightVisitorId == Nothing && filter.changedPaths == [] then
        True

    else
        case entry.metadata of
            Just metadata ->
                let
                    highlightByChangedPaths filterPaths paths =
                        if Har.isReduxStateEntry entry then
                            let
                                isInMetadataChangedPaths =
                                    \path -> List.any (String.contains path) paths
                            in
                            List.any isInMetadataChangedPaths filterPaths

                        else
                            False
                in
                case filter.highlightVisitorId of
                    Just visitorId ->
                        if List.any (\id -> id == visitorId) metadata.relatedVisitorIds then
                            True

                        else
                            highlightByChangedPaths filter.changedPaths metadata.changedPaths

                    Nothing ->
                        highlightByChangedPaths filter.changedPaths metadata.changedPaths

            _ ->
                False


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


getEntryByClientY : List Har.Entry -> Int -> Int -> Maybe Har.Entry
getEntryByClientY entries scrollTop clientY =
    let
        index =
            (clientY - 60 + scrollTop) // 20
    in
    entries
        |> List.drop index
        |> List.head


tableBodyView : SearchingState -> List String -> Float -> Posix -> List TableColumn -> Int -> String -> Bool -> List Har.Entry -> Int -> Int -> TableFilter -> Bool -> Html TableMsg
tableBodyView search pendingKeys msPerPx startTime columns guidelineLeft selected showDetail entries scrollTop viewportHeight filter quickPreviewEnabled =
    div
        ([ class "table-body"
         , id "table-body"
         , tabindex 0
         , preventDefaultOn "keydown" (D.map (Tuple.mapFirst ExecuteAction) (keyDecoder scrollTop pendingKeys))
         , on "scroll" <| D.map (round >> Scroll) (D.at [ "target", "scrollTop" ] D.float)
         , on "mouseleave" <| D.succeed UnhoverNameCell
         ]
            ++ (if quickPreviewEnabled then
                    let
                        handler =
                            D.map
                                (\y ->
                                    case getEntryByClientY entries scrollTop y of
                                        Just entry ->
                                            HoverNameCell entry.id y <| Har.isReduxStateEntry entry

                                        _ ->
                                            UnhoverNameCell
                                )
                            <|
                                D.field "clientY" D.int
                    in
                    [ on "mousewheel" handler
                    , on "mousemove" handler
                    ]

                else
                    []
               )
        )
        [ lazy8 tableBodyEntriesView msPerPx columns selected showDetail scrollTop entries viewportHeight filter
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


tableHeadersView : Int -> Float -> Posix -> Posix -> SortBy -> List TableColumn -> Bool -> Html TableMsg
tableHeadersView entriesCount waterfallMsPerPx startTime firstEntryStartTime sortBy columns showDetail =
    let
        visibleColumns =
            if showDetail then
                List.take 1 columns

            else
                columns
    in
    div [ class "table-header" ] <|
        List.map (tableHeaderCell entriesCount waterfallMsPerPx startTime firstEntryStartTime sortBy) visibleColumns


resolveSelected : String -> List Har.Entry -> String
resolveSelected selected entries =
    if Utils.isMember (\{ id } -> selected == id) entries then
        selected

    else
        ""


tableView : Posix -> TableModel -> Bool -> Bool -> Html TableMsg
tableView startTime { entries, filter, entriesCount, sortBy, columns, columnWidths, selectHistory, scrollTop, waterfallMsPerPx, viewportHeight, search, searchHistory, pendingKeys } showDetail quickPreviewEnabled =
    let
        selected2 =
            resolveSelected selectHistory.present entries

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
        , lazy7 tableHeadersView entriesCount waterfallMsPerPx startTime firstEntryStartTime sortBy columns showDetail2
        , tableBodyView search pendingKeys waterfallMsPerPx startTime columns guidelineLeft selected2 showDetail2 entries scrollTop viewportHeight filter quickPreviewEnabled
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
    | Select String Bool Bool
    | SetHref String
    | ExecuteAction VimAction
    | Scroll Int
    | ScrollToEntry String
    | InputFilter String
    | SelectKind ( Maybe EntryKind, Maybe String )
    | SetWaterfallMsPerPx Float
    | SetViewportHeight Int
    | SelectTable
    | ChangePage String
    | GotImportFile (Result String JsonFile)
    | HoverNameCell String Int Bool
    | UnhoverNameCell
    | JsonEncodeFileContent
    | ToggleFilterChangedPath String


updateTable : TableMsg -> Har.Log -> TableModel -> ( TableModel, Cmd TableMsg )
updateTable action log table =
    case action of
        NoOp ->
            ( table, Cmd.none )

        JsonEncodeFileContent ->
            ( table, Cmd.none )

        GotImportFile _ ->
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

        Select id _ scrollTo ->
            if table.selectHistory.present == id then
                ( table, Cmd.none )

            else
                ( { table | selectHistory = UL.new id table.selectHistory }
                , Cmd.batch
                    [ if scrollTo then
                        scrollToEntry table id

                      else
                        Cmd.none
                    ]
                )

        ExecuteAction act ->
            executeVimAction table act

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
                    Har.filterEntries table.filter.page match table.filter.kind log.entries

                filter =
                    table.filter
            in
            ( { table
                | entries = newEntries
                , entriesCount = List.length newEntries
                , filter = { filter | match = match }
              }
            , if match == "" && table.selectHistory.present /= "" then
                scrollToEntry table table.selectHistory.present

              else
                Cmd.none
            )

        Scroll top ->
            ( { table | scrollTop = top }, Cmd.none )

        SelectKind ( kind, highlightVisitorId ) ->
            let
                newEntries =
                    Har.filterEntries table.filter.page table.filter.match kind log.entries

                filter =
                    table.filter
            in
            ( { table
                | entries = newEntries
                , entriesCount = List.length newEntries
                , filter = { filter | kind = kind, highlightVisitorId = highlightVisitorId }
              }
            , if table.selectHistory.present /= "" then
                Cmd.batch
                    [ scrollToEntry table table.selectHistory.present
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
                [ scrollToEntry table table.selectHistory.present
                , focus "table-body"
                ]
            )

        ChangePage pageId ->
            let
                filter =
                    table.filter

                entries =
                    Har.filterEntries pageId table.filter.match table.filter.kind log.entries
            in
            ( { table
                | filter = { filter | page = pageId }
                , entries = entries
                , entriesCount = List.length entries
                , href =
                    log.pages
                        |> List.filter (\page -> page.id == pageId)
                        |> List.head
                        |> Maybe.map (\page -> page.title)
                        |> Maybe.withDefault ""
              }
            , Cmd.none
            )

        SetHref href ->
            ( { table | href = href }, Cmd.none )

        HoverNameCell entryId y isReduxStateEntry ->
            ( { table
                | quickPreview =
                    let
                        createQuickPreview _ =
                            { entryId = entryId
                            , x =
                                Dict.get "name" table.columnWidths
                                    |> Maybe.map ((+) 5)
                                    |> Maybe.withDefault 0
                            , y = y
                            , delayHide = not isReduxStateEntry
                            }
                    in
                    if isReduxStateEntry then
                        Just <| createQuickPreview ()

                    else
                        table.quickPreview |> Maybe.map createQuickPreview
              }
            , Cmd.none
            )

        UnhoverNameCell ->
            ( { table | quickPreview = Nothing }, Cmd.none )

        ToggleFilterChangedPath path ->
            let
                filter =
                    table.filter
            in
            ( { table
                | filter =
                    { filter
                        | changedPaths =
                            if List.any (\p -> p == path) filter.changedPaths then
                                List.filter (\p -> p /= path) filter.changedPaths

                            else
                                filter.changedPaths ++ [ path ]
                    }
              }
            , Cmd.none
            )


scrollToPx : Int -> Cmd TableMsg
scrollToPx y =
    Task.attempt (\_ -> NoOp) <|
        Dom.setViewportOf "table-body" 0 <|
            toFloat y


scrollToBottom : TableModel -> Cmd TableMsg
scrollToBottom table =
    scrollToPx (table.entriesCount * 20 - table.viewportHeight)


scrollToEntry : TableModel -> String -> Cmd TableMsg
scrollToEntry { scrollTop, viewportHeight, entries } id =
    case Utils.indexOf (\entry -> entry.id == id) entries of
        Just i ->
            let
                y =
                    i * 20
            in
            if scrollTop <= y && y + 20 <= scrollTop + viewportHeight then
                Cmd.none

            else
                scrollToPx <|
                    if y < scrollTop then
                        y

                    else
                        y + 20 - viewportHeight

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
