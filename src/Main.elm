module Main exposing (main)

import Browser
import Dict exposing (Dict)
import File exposing (File)
import File.Select as Select
import Har
import HarDecoder exposing (harDecoder)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy, lazy3, lazy7)
import Icons
import Iso8601
import Json.Decode as D
import List exposing (sortBy)
import Task
import Time
import TokenDecoder exposing (parseToken)



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


type alias InitialModel =
    { hover : Bool
    , error : Maybe String
    , fileContent : Maybe Har.Log
    }


defaultInitialModel : InitialModel
defaultInitialModel =
    { hover = False
    , error = Nothing
    , fileContent = Nothing
    }


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


type InitialMsg
    = Pick
    | DragEnter
    | DragLeave
    | GotFile File
    | GotFileContent String


type OpenedMsg
    = TableAction TableMsg
    | GotTimezone Time.Zone
    | ChangeDetailTab DetailTabName


type SortOrder
    = Asc
    | Desc


type alias SortBy =
    ( String, SortOrder )


flipSortOrder : SortOrder -> SortOrder
flipSortOrder sortOrder =
    case sortOrder of
        Asc ->
            Desc

        Desc ->
            Asc


type KeyCode
    = ArrowUp
    | ArrowDown
    | NoKey


type TableMsg
    = FlipSort String
    | ResizeColumn String Int
    | Select Int
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
    }


type EntryKind
    = ReduxState
    | NetworkHttp
    | Log
    | ReduxAction
    | Others


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
    }


type DetailTabName
    = Preview
    | Headers
    | Request
    | Response
    | Raw


type alias DetailTab =
    { name : DetailTabName, label : String }


type alias DetailModel =
    { tab : DetailTabName
    }


getClientInfo : Har.Log -> ClientInfo
getClientInfo { entries } =
    let
        clientInfoDecoder =
            D.map4 ClientInfo
                (D.field "href" D.string)
                (D.field "userAgent" D.string)
                (D.field "version" D.string)
                (D.field "commit" D.string)

        emptyClientInfo =
            ClientInfo "" "" "" ""
    in
    case List.filter (\entry -> entry.request.url == "/log/message") entries of
        entry :: _ ->
            case entry.response.content.text of
                Just text ->
                    case D.decodeString clientInfoDecoder text of
                        Ok clientInfo ->
                            clientInfo

                        Err _ ->
                            emptyClientInfo

                _ ->
                    emptyClientInfo

        _ ->
            emptyClientInfo


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
                                        , table =
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
                                                [ { id = "name", label = "Name" }
                                                , { id = "method", label = "Method" }
                                                , { id = "status", label = "Status" }
                                                , { id = "time", label = "Time" }
                                                , { id = "domain", label = "Domain" }
                                                , { id = "size", label = "Size" }
                                                , { id = "waterfall", label = "" }
                                                ]
                                            , entries = log.entries
                                            , selected = -1
                                            , filter =
                                                { match = Nothing
                                                , kind = Nothing
                                                }
                                            , scrollTop = 0
                                            }
                                        , timezone = Nothing
                                        , detail =
                                            { tab = Preview
                                            }
                                        , clientInfo = getClientInfo log
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


compareEntry : String -> Har.Entry -> Har.Entry -> Order
compareEntry column a b =
    case column of
        "name" ->
            compareString a.request.url b.request.url

        "status" ->
            compareInt a.response.status b.response.status

        "time" ->
            comparePosix a.startedDateTime b.startedDateTime

        "domain" ->
            compareString a.request.url b.request.url

        "size" ->
            compareInt (a.response.bodySize + a.request.bodySize) (b.response.bodySize + b.request.bodySize)

        "method" ->
            compareString a.request.method b.request.method

        "waterfall" ->
            comparePosix a.startedDateTime b.startedDateTime

        _ ->
            EQ


compareInt : Int -> Int -> Order
compareInt a b =
    if a < b then
        LT

    else if a > b then
        GT

    else
        EQ


comparePosix : Time.Posix -> Time.Posix -> Order
comparePosix a b =
    compareInt (Time.posixToMillis a) (Time.posixToMillis b)


compareString : String -> String -> Order
compareString a b =
    if a < b then
        LT

    else if a > b then
        GT

    else
        EQ


sortEntries : SortBy -> List Har.Entry -> List Har.Entry
sortEntries ( column, sortOrder ) =
    List.sortWith
        (\a b ->
            let
                order =
                    compareEntry column a b
            in
            case order of
                EQ ->
                    EQ

                LT ->
                    case sortOrder of
                        Asc ->
                            LT

                        Desc ->
                            GT

                GT ->
                    case sortOrder of
                        Asc ->
                            GT

                        Desc ->
                            LT
        )


filterByKind : Maybe EntryKind -> List Har.Entry -> List Har.Entry
filterByKind kind entries =
    case kind of
        Just kd ->
            entries
                |> List.filter (\entry -> getEntryKind entry == kd)

        Nothing ->
            entries


filterByMatch : Maybe String -> List Har.Entry -> List Har.Entry
filterByMatch match entries =
    case match of
        Just filter ->
            let
                loweredFilter =
                    String.toLower filter
            in
            entries
                |> List.filter (\entry -> String.contains loweredFilter (String.toLower entry.request.url))

        Nothing ->
            entries


filterEntries : Maybe String -> Maybe EntryKind -> List Har.Entry -> List Har.Entry
filterEntries match kind entries =
    entries
        |> filterByMatch match
        |> filterByKind kind


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
                                ( column, flipSortOrder currentSortOrder )

                            else
                                ( column, Asc )

                        newEntries =
                            sortEntries newSortBy table.entries
                    in
                    { model | table = { table | sortBy = newSortBy, entries = newEntries } }

                Select i ->
                    let
                        table =
                            model.table
                    in
                    { model | table = { table | selected = i } }

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
                                (\width -> Maybe.map (\w -> Basics.max (dx + w) 0) width)
                                table.columnWidths
                    in
                    { model | table = { table | columnWidths = columnWidths } }

                InputFilter match ->
                    let
                        table =
                            model.table

                        newEntries =
                            filterEntries (Just match) table.filter.kind model.log.entries

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
                            filterEntries table.filter.match kind model.log.entries

                        filter =
                            table.filter
                    in
                    { model | table = { table | entries = newEntries, filter = { filter | kind = kind } } }

        GotTimezone tz ->
            { model | timezone = Just tz }

        ChangeDetailTab tab ->
            let
                detail =
                    model.detail
            in
            { model | detail = { detail | tab = tab } }


updateInitial : InitialMsg -> InitialModel -> ( InitialModel, Cmd InitialMsg )
updateInitial msg model =
    case msg of
        Pick ->
            ( model
            , Select.file [ "*" ] GotFile
            )

        DragEnter ->
            ( { model | hover = True }
            , Cmd.none
            )

        DragLeave ->
            ( { model | hover = False }
            , Cmd.none
            )

        GotFile file ->
            ( { model | hover = False }
            , Task.perform GotFileContent (File.toString file)
            )

        GotFileContent content ->
            ( case D.decodeString harDecoder content of
                Ok { log } ->
                    let
                        entries =
                            List.sortBy (\entry -> Time.posixToMillis entry.startedDateTime) log.entries
                    in
                    { model | fileContent = Just { log | entries = entries } }

                Err err ->
                    { model | error = Just <| D.errorToString err }
            , Cmd.none
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


initialView : InitialModel -> Html InitialMsg
initialView model =
    div
        [ style "border"
            (if model.hover then
                "6px dashed purple"

             else
                "6px dashed #ccc"
            )
        , style "border-radius" "20px"
        , style "width" "480px"
        , style "height" "100px"
        , style "margin" "100px auto"
        , style "padding" "20px"
        , style "display" "flex"
        , style "flex-direction" "column"
        , style "justify-content" "center"
        , style "align-items" "center"
        , hijackOn "dragenter" (D.succeed DragEnter)
        , hijackOn "dragover" (D.succeed DragEnter)
        , hijackOn "dragleave" (D.succeed DragLeave)
        , hijackOn "drop" dropDecoder
        ]
        [ button [ onClick Pick ] [ text "Open Dump File" ]
        , span [ style "color" "red" ] [ text <| Maybe.withDefault "" model.error ]
        ]


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


getEntryKind : Har.Entry -> EntryKind
getEntryKind entry =
    if entry.request.url == "/redux/state" then
        ReduxState

    else if String.startsWith "/redux/" entry.request.url then
        ReduxAction

    else if String.startsWith "/log/" entry.request.url then
        Log

    else if
        String.startsWith "https://" entry.request.url
            || String.startsWith "http://" entry.request.url
            || String.startsWith "/api/" entry.request.url
    then
        NetworkHttp

    else
        Others


entryKindLabel : Maybe EntryKind -> String
entryKindLabel kind =
    case kind of
        Nothing ->
            "All"

        Just ReduxState ->
            "Redux State"

        Just ReduxAction ->
            "Redux Action"

        Just Log ->
            "Log"

        Just NetworkHttp ->
            "Network HTTP"

        Just Others ->
            "Others"


stringToEntryKind : String -> Maybe EntryKind
stringToEntryKind s =
    case s of
        "0" ->
            Just ReduxState

        "1" ->
            Just ReduxAction

        "2" ->
            Just Log

        "3" ->
            Just NetworkHttp

        "4" ->
            Just Others

        _ ->
            Nothing


getEntryIcon : Har.Entry -> Html msg
getEntryIcon entry =
    case getEntryKind entry of
        ReduxState ->
            Icons.snapshotDoc

        ReduxAction ->
            Icons.actionDoc

        Log ->
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


msPerPx : Float
msPerPx =
    -- each pixel represents 100ms
    100.0


tableCellContentView : Time.Zone -> String -> Time.Posix -> Har.Entry -> Html msg
tableCellContentView tz column startTime entry =
    case column of
        "name" ->
            div [ class "table-body-cell-url" ]
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
            if comparePosix startTime entry.startedDateTime == GT then
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
                    , style "width" (String.fromFloat width ++ "px")
                    , style "margin-left" (String.fromFloat left ++ "px")
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


tableCellView : Time.Zone -> TableColumn -> Time.Posix -> Har.Entry -> Html msg
tableCellView tz column startTime entry =
    div
        [ class "table-body-cell"
        , style "width" <| cssVar <| tableColumnWidthVariableName column.id
        ]
        [ tableCellContentView tz column.id startTime entry ]


entryView : Time.Zone -> List TableColumn -> Int -> Time.Posix -> Int -> Har.Entry -> Html TableMsg
entryView tz columns selected startTime index entry =
    div
        [ class
            (if selected == index then
                "selected"

             else
                ""
            )
        , class "table-body-row"
        , onClick (Select index)
        ]
        (List.map (\column -> tableCellView tz column startTime entry) columns)


tableSortIcon : SortOrder -> Html msg
tableSortIcon sortOrder =
    case sortOrder of
        Asc ->
            Icons.sortAsc

        Desc ->
            Icons.sortDesc


tableHeaderCell : SortBy -> TableColumn -> Html TableMsg
tableHeaderCell ( sortColumn, sortOrder ) column =
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
                    [ div [ style "height" "100%" ] [] ]

                else
                    []
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
            [ div [] [ text <| entryKindLabel filter.kind ]
            , select [ onInput (stringToEntryKind >> SelectKind) ]
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


getFirstEntryStartTime : List Har.Entry -> Int -> Time.Posix
getFirstEntryStartTime entries startIndex =
    case List.drop startIndex entries of
        entry :: _ ->
            entry.startedDateTime

        _ ->
            Time.millisToPosix 0


tableBodyView : Time.Zone -> Time.Posix -> List TableColumn -> Int -> Int -> List Har.Entry -> Int -> Html TableMsg
tableBodyView tz startTime columns guidelineLeft selected entries scrollTop =
    let
        visibleColumns =
            if selected >= 0 then
                List.take 1 columns

            else
                columns

        firstEntryStartTime =
            getFirstEntryStartTime entries (floor <| toFloat scrollTop / 20)

        guidelineAlignOffset =
            100
                - (Debug.log "modBy" <|
                    modBy 100
                        (Debug.log "floor" <|
                            floor
                                ((toFloat <| Time.posixToMillis firstEntryStartTime - Time.posixToMillis startTime)
                                    / msPerPx
                                )
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
        (if selected >= 0 then
            text ""

         else
            div
                [ class "waterfall-guideline-container"
                , style "left" (String.fromInt (guidelineLeft + Debug.log "guidelineAlignOffset" guidelineAlignOffset) ++ "px")
                ]
                [ div
                    [ class "waterfall-guideline"
                    , style "left" (String.fromInt -guidelineAlignOffset ++ "px")
                    ]
                    []
                ]
        )
            :: List.indexedMap (entryView tz visibleColumns selected firstEntryStartTime) entries


tableHeadersView : SortBy -> List TableColumn -> Int -> Html TableMsg
tableHeadersView sortBy columns selected =
    let
        visibleColumns =
            if selected >= 0 then
                List.take 1 columns

            else
                columns
    in
    div [ class "table-header" ] <|
        List.map (tableHeaderCell sortBy) visibleColumns


tableView : Time.Zone -> Time.Posix -> TableModel -> Html TableMsg
tableView tz startTime { entries, sortBy, columns, columnWidths, selected, scrollTop } =
    let
        -- hide columns except first column when selected
        visibleColumns =
            if selected >= 0 then
                List.take 1 columns

            else
                columns

        guidelineLeft =
            totalWidth columnWidths visibleColumns
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
                        |> Maybe.map (\w -> String.fromInt w ++ "px")
                        |> Maybe.withDefault "auto"
                    )
                )
                visibleColumns
            )
        ]
        [ lazy3 tableHeadersView sortBy columns selected
        , lazy7 tableBodyView tz startTime columns guidelineLeft selected entries scrollTop
        ]


totalWidth : Dict String Int -> List TableColumn -> Int
totalWidth columnWidths =
    List.foldl
        (\column acc ->
            acc
                + (columnWidths
                    |> Dict.get column.id
                    |> Maybe.map (Basics.max 80)
                    |> Maybe.withDefault 0
                  )
        )
        0


isReduxStateEntry : Har.Entry -> Bool
isReduxStateEntry entry =
    entry.request.url == "/redux/state"


getReduxState : Har.Entry -> Maybe String
getReduxState entry =
    if isReduxStateEntry entry then
        case entry.response.content.text of
            Just text ->
                Just text

            _ ->
                Nothing

    else
        Nothing


detailTab : DetailTabName -> DetailTab -> Html OpenedMsg
detailTab selected { name, label } =
    button
        [ class "detail-header-tab"
        , class <|
            if name == selected then
                "selected"

            else
                ""
        , onClick (ChangeDetailTab name)
        ]
        [ text label ]


detailTabs : DetailTabName -> Har.Entry -> Html OpenedMsg
detailTabs tab _ =
    div [ class "detail-header-tabs" ] <|
        List.map (detailTab tab)
            [ { name = Preview, label = "Preview" }
            , { name = Headers, label = "Headers" }
            , { name = Request, label = "Request" }
            , { name = Response, label = "Response" }
            , { name = Raw, label = "Raw" }
            ]


jsonViewer : String -> Html msg
jsonViewer json =
    Html.node "json-viewer" [ attribute "data" json ] []


detailPreviewView : ClientInfo -> Har.Entry -> Html OpenedMsg
detailPreviewView clientInfo entry =
    if isReduxStateEntry entry && not (String.isEmpty clientInfo.href) then
        case getReduxState entry of
            Just s ->
                Html.node "agent-console-snapshot"
                    [ src <| clientInfo.href ++ "&snapshot=true"
                    , attribute "state" s
                    , attribute "time" <| Iso8601.fromTime entry.startedDateTime
                    ]
                    []

            _ ->
                text "No redux state found"

    else
        jsonViewer <| Maybe.withDefault "" entry.response.content.text


keyValue : { x | name : String, value : Html msg } -> Html msg
keyValue { name, value } =
    let
        name1 =
            if String.endsWith ":" name then
                name

            else
                name ++ ":"
    in
    div [ class "detail-body-header-item" ]
        [ span
            [ style "color" "var(--color)"
            , class "detail-body-header-key"
            ]
            [ text name1 ]
        , span [ class "detail-body-header-value" ] [ value ]
        ]


keyValueText : { x | name : String, value : String } -> Html msg
keyValueText { name, value } =
    keyValue { name = name, value = text value }


requestHeaderKeyValue : { x | name : String, value : String } -> Html msg
requestHeaderKeyValue { name, value } =
    if name == "Authorization" then
        div []
            [ keyValue
                { name = name
                , value =
                    div []
                        [ text value
                        , jsonViewer <|
                            "{\"payload\":"
                                ++ (Maybe.withDefault "" <| parseToken value)
                                ++ "}"
                        ]
                }
            ]

    else
        keyValueText { name = name, value = value }


noContent : Html msg
noContent =
    div [ class "detail-body", class "detail-body-empty" ] [ text "No content" ]


styleVar : String -> String -> Attribute msg
styleVar name value =
    attribute "style" (name ++ ": " ++ value)


detailView : DetailModel -> ClientInfo -> Har.Entry -> Html OpenedMsg
detailView detail clientInfo entry =
    section [ class "detail" ]
        [ div [ class "detail-header" ]
            [ button [ class "detail-close", onClick (TableAction <| Select -1) ] [ Icons.close ]
            , detailTabs detail.tab entry
            ]
        , case detail.tab of
            Preview ->
                div [ class "detail-body" ] [ detailPreviewView clientInfo entry ]

            Headers ->
                div
                    [ class "detail-body", class "detail-body-headers-container" ]
                    [ h3 [] [ text "Summary" ]
                    , div [ styleVar "--color" "var(--network-system-color)", class "detail-body-headers" ]
                        [ keyValueText { name = "URL", value = entry.request.url }
                        , keyValueText { name = "Method", value = String.toUpper entry.request.method }
                        , keyValueText { name = "Status", value = String.fromInt entry.response.status }
                        , keyValueText { name = "Address", value = Maybe.withDefault "" entry.serverIPAddress }
                        ]
                    , h3 [] [ text "Request Headers" ]
                    , div
                        [ styleVar "--color" "var(--network-header-color)"
                        , class "detail-body-headers"
                        ]
                        (List.map requestHeaderKeyValue entry.request.headers)
                    , h3 [] [ text "Response Headers" ]
                    , div
                        [ styleVar "--color" "var(--network-header-color)"
                        , class "detail-body-headers"
                        ]
                        (List.map keyValueText entry.response.headers)
                    , h3 [] [ text "Query String Parameters" ]
                    , div
                        [ styleVar "--color" "var(--text-color-tertiary)"
                        , class "detail-body-headers"
                        ]
                        (List.map keyValueText entry.request.queryString)
                    ]

            Request ->
                case entry.request.postData of
                    Just postData ->
                        case postData.text of
                            Just t ->
                                div [ class "detail-body" ] [ jsonViewer t ]

                            _ ->
                                noContent

                    _ ->
                        noContent

            Response ->
                case entry.response.content.text of
                    Just t ->
                        div [ class "detail-body" ] [ jsonViewer t ]

                    _ ->
                        noContent

            Raw ->
                case entry.response.content.text of
                    Just t ->
                        Html.node "code-editor" [ class "detail-body", attribute "content" t ] []

                    _ ->
                        noContent
        ]


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
                , Html.map TableAction (lazy3 tableView tz startTime model.table)
                , if model.table.selected >= 0 then
                    case List.head <| List.drop model.table.selected model.table.entries of
                        Just entry ->
                            lazy3 detailView model.detail model.clientInfo entry

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


dropDecoder : D.Decoder InitialMsg
dropDecoder =
    D.at [ "dataTransfer", "files" ] (D.oneOrMore (\f _ -> GotFile f) File.decoder)


hijackOn : String -> D.Decoder msg -> Attribute msg
hijackOn event decoder =
    preventDefaultOn event (D.map hijack decoder)


hijack : msg -> ( msg, Bool )
hijack msg =
    ( msg, True )
