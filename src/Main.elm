module Main exposing (main)

import Browser
import Detail exposing (DetailModel, DetailMsg(..), DetailTabName(..), detailView)
import Dict exposing (Dict)
import Har exposing (EntryKind(..), SortBy, SortOrder(..))
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy, lazy3, lazy4, lazy6, lazy8)
import Icons
import Initial exposing (InitialModel, InitialMsg(..), defaultInitialModel, initialView, updateInitial)
import Json.Decode as D
import List exposing (sortBy)
import String exposing (fromFloat, fromInt)
import Task
import Time



-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



-- MODEL


type Model
    = Initial InitialModel
    | Opened OpenedModel


type alias ClientInfo =
    { href : String
    , userAgent : String
    , version : String
    , commit : String
    }


type alias OpenedModel =
    { log : Har.Log
    , table : TableModel
    , timezone : Maybe Time.Zone
    , detail : DetailModel
    , clientInfo : ClientInfo
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Initial defaultInitialModel, Cmd.none )



-- UPDATE


type Msg
    = InitialMsg InitialMsg
    | OpenedMsg OpenedMsg


type OpenedMsg
    = TableAction TableMsg
    | GotTimezone Time.Zone
    | DetailAction DetailMsg


type KeyCode
    = ArrowUp
    | ArrowDown
    | NoKey


type TableMsg
    = FlipSort String
    | ResizeColumn String Int
    | Select Int
    | ShowDetail Int
    | KeyDown KeyCode
    | Scroll Int
    | InputFilter String
    | SelectKind (Maybe EntryKind)


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
    { match : Maybe String
    , kind : Maybe EntryKind
    }


type alias TableModel =
    { sortBy : SortBy
    , columnWidths : Dict String Int
    , columns : List TableColumn
    , entries : List Har.Entry
    , selected : Int
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
            , ( "method", 80 )
            , ( "status", 80 )
            , ( "time", 150 )
            , ( "domain", 150 )
            , ( "size", 150 )
            ]
    , columns =
        [ { id = "name", label = "Name", minWidth = 80 }
        , { id = "method", label = "Method", minWidth = 50 }
        , { id = "status", label = "Status", minWidth = 50 }
        , { id = "time", label = "Time", minWidth = 80 }
        , { id = "domain", label = "Domain", minWidth = 80 }
        , { id = "size", label = "Size", minWidth = 80 }
        , { id = "waterfall", label = "", minWidth = 0 }
        ]
    , entries = []
    , selected = -1
    , filter =
        { match = Nothing
        , kind = Nothing
        }
    , scrollTop = 0
    , waterfallMsPerPx = 10.0
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        InitialMsg initialMsg ->
            case model of
                Initial initialModel ->
                    case updateInitial initialMsg initialModel of
                        ( newModel, cmd ) ->
                            case newModel.fileContent of
                                Just log ->
                                    ( Opened
                                        { log = log
                                        , table = { defaultTableModel | entries = log.entries }
                                        , timezone = Nothing
                                        , detail = Detail.defaultDetailModel
                                        , clientInfo = Har.getClientInfo log
                                        }
                                    , Task.perform (\zone -> OpenedMsg <| GotTimezone zone) Time.here
                                    )

                                _ ->
                                    ( Initial newModel, Cmd.map InitialMsg cmd )

                _ ->
                    ( model, Cmd.none )

        OpenedMsg openedMsg ->
            case model of
                Opened openedModel ->
                    case updateOpened openedMsg openedModel of
                        newOpenedModel ->
                            ( Opened newOpenedModel, Cmd.none )

                _ ->
                    ( model, Cmd.none )


tableSelectNextEntry : TableModel -> Bool -> TableModel
tableSelectNextEntry table isUp =
    if table.selected >= 0 then
        let
            index =
                table.selected

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
        in
        { table | selected = nextIndex }

    else
        table


updateSelectNextEntry : OpenedModel -> Bool -> OpenedModel
updateSelectNextEntry model isUp =
    { model | table = tableSelectNextEntry model.table isUp }


updateOpened : OpenedMsg -> OpenedModel -> OpenedModel
updateOpened msg model =
    case msg of
        TableAction action ->
            case action of
                FlipSort column ->
                    let
                        table =
                            model.table

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
                    { model | table = { table | sortBy = newSortBy, entries = newEntries } }

                Select i ->
                    let
                        table =
                            model.table
                    in
                    { model | table = { table | selected = i } }

                ShowDetail i ->
                    let
                        table =
                            model.table

                        detail =
                            model.detail
                    in
                    { model | table = { table | selected = i }, detail = { detail | show = True } }

                KeyDown key ->
                    case key of
                        NoKey ->
                            model

                        arrow ->
                            updateSelectNextEntry model (arrow == ArrowUp)

                ResizeColumn column dx ->
                    let
                        table =
                            model.table

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
                    { model | table = { table | columnWidths = columnWidths } }

                InputFilter match ->
                    let
                        table =
                            model.table

                        newEntries =
                            Har.filterEntries (Just match) table.filter.kind model.log.entries

                        filter =
                            table.filter
                    in
                    { model | table = { table | entries = newEntries, filter = { filter | match = Just match } } }

                Scroll top ->
                    let
                        table =
                            model.table
                    in
                    { model | table = { table | scrollTop = top } }

                SelectKind kind ->
                    let
                        table =
                            model.table

                        newEntries =
                            Har.filterEntries table.filter.match kind model.log.entries

                        filter =
                            table.filter
                    in
                    { model | table = { table | entries = newEntries, filter = { filter | kind = kind } } }

        GotTimezone tz ->
            { model | timezone = Just tz }

        DetailAction detailMsg ->
            { model | detail = Detail.updateDetail model.detail detailMsg }



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


toIntPad2 : Int -> String
toIntPad2 n =
    if n < 10 then
        "0" ++ String.fromInt n

    else
        String.fromInt n


toIntPad3 : Int -> String
toIntPad3 n =
    if n < 10 then
        "00" ++ String.fromInt n

    else if n < 100 then
        "0" ++ String.fromInt n

    else
        String.fromInt n


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


formatTime : Time.Zone -> Time.Posix -> String
formatTime tz time =
    toIntPad2 (Time.toHour tz time)
        ++ ":"
        ++ toIntPad2 (Time.toMinute tz time)
        ++ ":"
        ++ toIntPad2 (Time.toSecond tz time)
        ++ ","
        ++ toIntPad3 (Time.toMillis tz time)


formatSize : Int -> String
formatSize size =
    if size < 0 then
        "―"

    else if size < 1000 then
        String.fromInt size ++ " B"

    else if size < 1000000 then
        String.fromFloat (toFixed 2 (toFloat size / 1000)) ++ " KB"

    else
        String.fromFloat (toFixed 2 (toFloat size / 1000000)) ++ " MB"


tableCellContentView : Time.Zone -> Float -> String -> Time.Posix -> Har.Entry -> Html msg
tableCellContentView tz msPerPx column startTime entry =
    case column of
        "name" ->
            div
                [ style "display" "contents"
                , style "pointer-events" "none"
                ]
                [ getEntryIcon entry
                , text <|
                    case List.head <| List.reverse <| String.indexes "/" entry.request.url of
                        Just i ->
                            String.dropLeft (i + 1) entry.request.url

                        _ ->
                            entry.request.url
                ]

        "status" ->
            text <| String.fromInt entry.response.status

        "time" ->
            text <| formatTime tz entry.startedDateTime

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
            text <| formatSize (entry.response.bodySize + entry.request.bodySize)

        "method" ->
            text entry.request.method

        "waterfall" ->
            if Har.comparePosix startTime entry.startedDateTime == GT then
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
                            ++ formatTime tz entry.startedDateTime
                    ]
                    []

        _ ->
            text ""


toFixed : Int -> Float -> Float
toFixed n f =
    let
        factor =
            toFloat (10 ^ n)
    in
    (toFloat <| round (f * factor)) / factor


floatToString : Int -> Float -> String
floatToString fixed f =
    let
        s =
            fromFloat (toFixed fixed f)

        parts =
            String.split "." s
    in
    case parts of
        [ n ] ->
            n ++ "." ++ String.repeat fixed "0"

        [ n, fraction ] ->
            n ++ "." ++ fraction ++ String.repeat (fixed - String.length fraction) "0"

        _ ->
            ""


tableCellView : Time.Zone -> Float -> TableColumn -> Time.Posix -> Har.Entry -> Html msg
tableCellView tz msPerPx column startTime entry =
    div
        [ class "table-body-cell"
        , class <| "table-body-cell-" ++ column.id
        , style "width" <| cssVar <| tableColumnWidthVariableName column.id
        ]
        [ tableCellContentView tz msPerPx column.id startTime entry ]


entryView : Time.Zone -> Float -> List TableColumn -> Int -> Time.Posix -> Int -> Har.Entry -> Html TableMsg
entryView tz msPerPx columns selected startTime index entry =
    div
        [ class
            (if selected == index then
                "selected"

             else
                ""
            )
        , class "table-body-row"
        , on "click"
            (D.at [ "target", "className" ] D.string
                |> D.map
                    (\className ->
                        if String.contains "table-body-cell-name" className then
                            ShowDetail index

                        else
                            Select index
                    )
            )
        ]
        (List.map (\column -> tableCellView tz msPerPx column startTime entry) columns)


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
            floatToString 2
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


intPx : Int -> String
intPx n =
    fromInt n ++ "px"


floatPx : Float -> String
floatPx f =
    fromFloat f ++ "px"


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


tableFilterView : TableFilter -> Html TableMsg
tableFilterView filter =
    section [ class "table-filter" ]
        [ input
            [ class "table-filter-input"
            , value (Maybe.withDefault "" filter.match)
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
        ]


styles : List ( String, String ) -> Attribute msg
styles ss =
    let
        css =
            List.foldl
                (\( prop, val ) acc ->
                    String.append acc (prop ++ ":" ++ val ++ ";\n")
                )
                ""
                ss
    in
    attribute "style" css


tableBodyView : Time.Zone -> Time.Posix -> List TableColumn -> Int -> Int -> Bool -> List Har.Entry -> Int -> Html TableMsg
tableBodyView tz startTime columns guidelineLeft selected showDetail entries scrollTop =
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
    div
        [ class "table-body"
        , tabindex 0
        , hijackOn "keydown" (D.map KeyDown keyDecoder)
        , on "scroll" (D.map Scroll (D.field "target" (D.field "scrollTop" D.int)))
        ]
    <|
        (if showDetail then
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
        )
            :: List.indexedMap (entryView tz 10.0 visibleColumns selected firstEntryStartTime) entries


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


tableView : Time.Zone -> Time.Posix -> TableModel -> Bool -> Html TableMsg
tableView tz startTime { entries, sortBy, columns, columnWidths, selected, scrollTop, waterfallMsPerPx } showDetail =
    let
        -- hide columns except first column when selected
        visibleColumns =
            if showDetail then
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
            (if selected >= 0 then
                "table--selected"

             else
                ""
            )
        , styles
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
        [ lazy6 tableHeadersView waterfallMsPerPx startTime firstEntryStartTime sortBy columns showDetail
        , lazy8 tableBodyView tz startTime columns guidelineLeft selected showDetail entries scrollTop
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


viewOpened : OpenedModel -> Html OpenedMsg
viewOpened model =
    case model.timezone of
        Just tz ->
            let
                startTime =
                    model.log.entries
                        |> List.head
                        |> Maybe.map .startedDateTime
                        |> Maybe.withDefault (Time.millisToPosix 0)
            in
            div
                [ class "app" ]
                [ Html.map TableAction (lazy tableFilterView model.table.filter)
                , Html.map TableAction (lazy4 tableView tz startTime model.table model.detail.show)
                , if model.detail.show then
                    case List.head <| List.drop model.table.selected model.table.entries of
                        Just entry ->
                            Html.map DetailAction <| lazy3 detailView model.detail model.clientInfo.href entry

                        _ ->
                            text ""

                  else
                    text ""
                ]

        _ ->
            div [] [ text "Loading..." ]


view : Model -> Html Msg
view model =
    case model of
        Initial initialModel ->
            Html.map InitialMsg (initialView initialModel)

        Opened log ->
            Html.map OpenedMsg (viewOpened log)


hijackOn : String -> D.Decoder msg -> Attribute msg
hijackOn event decoder =
    preventDefaultOn event (D.map hijack decoder)


hijack : msg -> ( msg, Bool )
hijack msg =
    ( msg, True )
