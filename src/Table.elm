module Table exposing (TableModel, TableMsg(..), defaultTableModel, subTable, tableFilterView, tableView, updateTable, scrollToEntry)

import Browser.Dom as Dom
import Browser.Events exposing (onResize)
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Har exposing (EntryKind(..), SortBy, SortOrder(..))
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy6, lazy8)
import Icons
import Initial exposing (InitialMsg(..))
import Json.Decode as D
import List exposing (sortBy)
import Task
import Time
import Utils exposing (floatPx, intPx)



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
    , selected = ""
    , filter =
        { match = ""
        , kind = Nothing
        }
    , scrollTop = 0
    , waterfallMsPerPx = 10.0
    , viewportHeight = 0
    }


tableSelectNextEntry : Nav.Key -> TableModel -> Bool -> ( TableModel, Cmd TableMsg )
tableSelectNextEntry navKey table isUp =
    if table.selected /= "" then
        let
            index =
                table.entries
                    |> Utils.indexOf (\entry -> entry.id == table.selected)
                    |> Maybe.withDefault -1

            nextIndex =
                if isUp then
                    if index > 0 then
                        index - 1

                    else
                        List.length table.entries - 1

                else if index + 1 < List.length table.entries then
                    index + 1

                else
                    0

            newSelected =
                table.entries
                    |> List.drop nextIndex
                    |> List.head
                    |> Maybe.map .id
                    |> Maybe.withDefault ""
        in
        ( { table | selected = newSelected }
        , if newSelected == "" then
            Cmd.none

          else
            Cmd.batch
                [ scrollToEntry table newSelected
                , Nav.replaceUrl navKey ("#entry" ++ newSelected)
                ]
        )

    else
        ( table, Cmd.none )



-- VIEW


entryView : Float -> List TableColumn -> String -> Time.Posix -> List (Attribute TableMsg) -> Har.Entry -> Html TableMsg
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


tableCellContentView : Float -> String -> Time.Posix -> Har.Entry -> Html msg
tableCellContentView msPerPx column startTime entry =
    case column of
        "name" ->
            div
                [ style "display" "contents"
                , style "pointer-events" "none"
                ]
                [ getEntryIcon entry
                , text <|
                    let
                        slashIndexes =
                            List.reverse <| String.indexes "/" entry.request.url
                    in
                    case Har.getEntryKind entry of
                        ReduxAction ->
                            case slashIndexes of
                                _ :: j :: _ ->
                                    String.dropLeft (j + 1) entry.request.url

                                _ ->
                                    entry.request.url

                        _ ->
                            case slashIndexes of
                                i :: _ ->
                                    String.dropLeft (i + 1) entry.request.url

                                _ ->
                                    entry.request.url
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


tableCellView : Float -> TableColumn -> Time.Posix -> Har.Entry -> Html msg
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


tableHeaderCell : Float -> Time.Posix -> Time.Posix -> SortBy -> TableColumn -> Html TableMsg
tableHeaderCell waterfallMsPerPx startTime firstEntryStartTime ( sortColumn, sortOrder ) column =
    div
        [ class "table-header-cell"
        , class ("table-header-cell-" ++ column.id)
        , onClick (FlipSort column.id)
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
         , Html.node "resize-divider"
            [ Html.Events.on
                "resize"
                (D.at [ "detail", "dx" ] D.int
                    |> D.map (ResizeColumn column.id)
                )
            ]
            []
         ]
            ++ (if column.id == "waterfall" then
                    [ tableHeaderCellWaterfallScales waterfallMsPerPx startTime firstEntryStartTime ]

                else
                    []
               )
        )


tableHeaderCellWaterfallScales : Float -> Time.Posix -> Time.Posix -> Html TableMsg
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


keyDecoder : D.Decoder KeyCode
keyDecoder =
    let
        toKey key =
            case key of
                "ArrowUp" ->
                    ArrowUp

                "ArrowDown" ->
                    ArrowDown

                _ ->
                    NoKey
    in
    D.map toKey <| D.field "key" D.string


waterfallMsPerPxToScale : Float -> String
waterfallMsPerPxToScale msPerPx =
    (String.fromInt <| floor <| msPerPx / 10.0) ++ "x"


scaleToWaterfallMsPerPx : String -> Float
scaleToWaterfallMsPerPx scale =
    String.dropRight 1 scale
        |> String.toFloat
        |> Maybe.map ((*) 10.0)
        |> Maybe.withDefault 10.0


dropDownList : { value : String, onInput : String -> msg } -> List { label : String, value : String } -> Html msg
dropDownList options children =
    label [ class "select" ]
        [ div [] [ text options.value ]
        , select [ onInput options.onInput ] <|
            List.map (\item -> option [ value item.value ] [ text item.label ]) children
        ]


tableFilterOptions : List { value : String, label : String }
tableFilterOptions =
    [ { value = "", label = "All" }
    , { value = "0", label = "Redux State" }
    , { value = "1", label = "Redux Action" }
    , { value = "2", label = "Log" }
    , { value = "3", label = "Http" }
    , { value = "4", label = "Others" }
    ]


waterfallScaleOptions : List { value : String, label : String }
waterfallScaleOptions =
    [ { value = "1x", label = "1x" }
    , { value = "2x", label = "2x" }
    , { value = "3x", label = "3x" }
    , { value = "4x", label = "4x" }
    ]


tableFilterView : Float -> TableFilter -> Html TableMsg
tableFilterView waterfallMsPerPx filter =
    section [ class "table-filter" ]
        [ input
            [ class "table-filter-input"
            , value filter.match
            , onInput InputFilter
            , type_ "search"
            , autofocus True
            , placeholder "Filter"
            ]
            []
        , dropDownList
            { value = Har.entryKindLabel filter.kind
            , onInput = Har.stringToEntryKind >> SelectKind
            }
            tableFilterOptions
        , dropDownList
            { value = waterfallMsPerPxToScale waterfallMsPerPx
            , onInput = scaleToWaterfallMsPerPx >> SetWaterfallMsPerPx
            }
            waterfallScaleOptions
        ]


virtualizedList :
    { scrollTop : Int
    , viewportHeight : Int
    , itemHeight : Int
    , items : List item
    , renderItem : List (Attribute msg) -> item -> ( String, Html msg )
    }
    -> Html msg
virtualizedList { scrollTop, viewportHeight, itemHeight, items, renderItem } =
    let
        overhead = 5
        
        totalCount = List.length items

        totalHeight =
             totalCount * itemHeight

        fromIndex =
            Basics.max 0 <| floor <| toFloat scrollTop / toFloat itemHeight - overhead

        visibleItemsCount =
            Basics.min totalCount <| ceiling <| toFloat viewportHeight / toFloat itemHeight + 2 * overhead

        visibleItems =
            items |> List.drop fromIndex |> List.take visibleItemsCount
    in
    Keyed.ol
        [ style "height" <| intPx totalHeight
        , style "padding" "0"
        , style "margin" "0"
        , style "position" "relative"
        ]
        (List.indexedMap
            (\i item ->
                renderItem
                    [ style "top" <| intPx ((fromIndex + i) * itemHeight)
                    , style "position" "absolute"
                    ]
                    item
            )
            visibleItems
        )


tableBodyView : Float -> Time.Posix -> List TableColumn -> Int -> String -> Bool -> List Har.Entry -> Int -> Int -> Html TableMsg
tableBodyView msPerPx startTime columns guidelineLeft selected showDetail entries scrollTop viewportHeight =
    let
        visibleColumns =
            if showDetail then
                List.take 1 columns

            else
                columns

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
        [ class "table-body"
        , id "table-body"
        , tabindex 0
        , Utils.hijackOn "keydown" (D.map KeyDown keyDecoder)
        , on "scroll" <| D.map Scroll <| D.at [ "target", "scrollTop" ] D.int
        ]
    <|
        [ if showDetail then
            text ""

          else
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
        , virtualizedList
            { scrollTop = scrollTop
            , viewportHeight = viewportHeight
            , itemHeight = 20
            , items = entries
            , renderItem = \attrs entry -> ( entry.id, entryView msPerPx visibleColumns selected firstEntryStartTime attrs entry )
            }
        ]


tableHeadersView : Float -> Time.Posix -> Time.Posix -> SortBy -> List TableColumn -> Bool -> Html TableMsg
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


tableView : Time.Posix -> TableModel -> Bool -> Html TableMsg
tableView startTime { entries, sortBy, columns, columnWidths, selected, scrollTop, waterfallMsPerPx, viewportHeight } showDetail =
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
        [ lazy6 tableHeadersView waterfallMsPerPx startTime firstEntryStartTime sortBy columns showDetail2
        , tableBodyView waterfallMsPerPx startTime columns guidelineLeft selected2 showDetail2 entries scrollTop viewportHeight
        ]


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


type KeyCode
    = ArrowUp
    | ArrowDown
    | NoKey


type TableMsg
    = NoOp
    | FlipSort String
    | ResizeColumn String Int
      -- id, True means show detail, False means keep detail shown/hidden as is, is pushUrl
    | Select String Bool Bool Bool
    | KeyDown KeyCode
    | Scroll Int
    | ScrollToEntry String
    | InputFilter String
    | SelectKind (Maybe EntryKind)
    | SetWaterfallMsPerPx Float
    | SetViewportHeight Int


updateTable : Nav.Key -> TableMsg -> Har.Log -> TableModel -> ( TableModel, Cmd TableMsg )
updateTable navKey action log table =
    case action of
        NoOp ->
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

        KeyDown key ->
            case key of
                NoKey ->
                    ( table, Cmd.none )

                arrow ->
                    tableSelectNextEntry navKey table (arrow == ArrowUp)

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
                    , Task.attempt (\_ -> NoOp) <| Dom.focus "table-body"
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



-- SUBS


subTable : Sub TableMsg
subTable =
    onResize (\_ h -> SetViewportHeight (h - 60))
