module Table exposing (TableModel, TableMsg(..), defaultTableModel, tableFilterView, tableView, updateTable)

import Browser.Dom as Dom
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
                    if index - 1 > 0 then
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
                [ Utils.scrollIntoView ("entry" ++ newSelected)
                , Nav.replaceUrl navKey ("#entry" ++ newSelected)
                ]
        )

    else
        ( table, Cmd.none )



-- VIEW


entryView : Float -> List TableColumn -> String -> Time.Posix -> Har.Entry -> Html TableMsg
entryView msPerPx columns selected startTime entry =
    div
        [ class
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
                        Select entry.id (String.contains "table-body-cell-name" className) True
                    )
            )
        ]
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
                    (floor
                        ((toFloat <| Time.posixToMillis firstEntryStartTime - Time.posixToMillis startTime)
                            / msPerPx
                        )
                    )

        toMillis : Int -> String
        toMillis i =
            let
                px =
                    alignOffset + i * 100
            in
            Utils.floatToString 2
                (((toFloat <| Time.posixToMillis firstEntryStartTime - Time.posixToMillis startTime) + toFloat px * msPerPx)
                    / 1000
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
        , label [ class "table-filter-select" ]
            [ div [] [ text <| Har.entryKindLabel filter.kind ]
            , select [ onInput (Har.stringToEntryKind >> SelectKind) ]
                [ option [ value "" ] [ text "All" ]
                , option [ value "0" ] [ text "Redux State" ]
                , option [ value "1" ] [ text "Redux Action" ]
                , option [ value "2" ] [ text "Log" ]
                , option [ value "3" ] [ text "Http" ]
                , option [ value "4" ] [ text "Others" ]
                ]
            ]
        , label [ class "table-filter-select" ]
            [ div [] [ text <| waterfallMsPerPxToScale waterfallMsPerPx ]
            , select [ onInput (scaleToWaterfallMsPerPx >> SetWaterfallMsPerPx) ]
                [ option [ value "1x" ] [ text "1x" ]
                , option [ value "2x" ] [ text "2x" ]
                , option [ value "3x" ] [ text "3x" ]
                , option [ value "4x" ] [ text "4x" ]
                ]
            ]
        ]


tableBodyView : Float -> Time.Posix -> List TableColumn -> Int -> String -> Bool -> List Har.Entry -> Int -> Html TableMsg
tableBodyView msPerPx startTime columns guidelineLeft selected showDetail entries scrollTop =
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
                    (floor
                        ((toFloat <| Time.posixToMillis firstEntryStartTime - Time.posixToMillis startTime)
                            / 10.0
                        )
                    )
    in
    Keyed.ol
        [ class "table-body"
        , id "table-body"
        , tabindex 0
        , Utils.hijackOn "keydown" (D.map KeyDown keyDecoder)
        , on "scroll" (D.map Scroll (D.field "target" (D.field "scrollTop" D.int)))
        ]
    <|
        (if showDetail then
            ( "waterfall", text "" )

         else
            ( "waterfall"
            , div
                [ class "waterfall-guideline-container"
                , style "left" (intPx (guidelineLeft + guidelineAlignOffset))
                ]
                [ div
                    [ class "waterfall-guideline"
                    , style "left" (intPx -guidelineAlignOffset)
                    ]
                    []
                ]
            )
        )
            :: List.map
                (\entry ->
                    ( entry.id, entryView msPerPx visibleColumns selected firstEntryStartTime entry )
                )
                entries


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
tableView startTime { entries, sortBy, columns, columnWidths, selected, scrollTop, waterfallMsPerPx } showDetail =
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
        , lazy8 tableBodyView waterfallMsPerPx startTime columns guidelineLeft selected2 showDetail2 entries scrollTop
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
    | Select String Bool Bool
    | KeyDown KeyCode
    | Scroll Int
    | InputFilter String
    | SelectKind (Maybe EntryKind)
    | SetWaterfallMsPerPx Float


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

        Select id _ isPushUrl ->
            if table.selected == id then
                ( table, Cmd.none )

            else
                ( { table | selected = id }
                , if isPushUrl then
                    Nav.pushUrl navKey ("#entry" ++ id)

                  else
                    Cmd.none
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
                Utils.scrollIntoView ("entry" ++ table.selected)

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
                    [ Utils.scrollIntoView ("entry" ++ table.selected)
                    , Task.attempt (\_ -> NoOp) <| Dom.focus "table-body"
                    ]

              else
                Cmd.none
            )

        SetWaterfallMsPerPx msPerPx ->
            ( { table | waterfallMsPerPx = msPerPx }, Cmd.none )
