module Main exposing (main)

import Base64
import Browser
import File exposing (File)
import File.Select as Select
import Har
import HarDecoder exposing (harDecoder)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Icons
import Iso8601
import Json.Decode as D
import Json.Encode as Encode
import JsonTree as JT
import List exposing (sortBy)
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
    | SetTreeViewState JT.State
    | ChangeDetailTab DetailTabName


type SortOrder
    = Asc
    | Desc


type alias SortBy =
    ( TableColumnName, SortOrder )


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
    = FlipSort TableColumnName
    | ResizeColumn TableColumnName Int
    | Select Har.Entry
    | Unselect
    | KeyDown KeyCode
    | InputFilter String
    | SelectKind (Maybe EntryKind)


type TableColumnName
    = URL
    | Status
    | Time
    | Domain
    | Size
    | Method


type alias TableColumn =
    { name : TableColumnName
    , label : String
    , width : Int
    }


type EntryKind
    = ReduxState
    | NetworkHttp
    | Log
    | ReduxAction
    | Others


type alias TableModel =
    { sortBy : SortBy
    , columns : List TableColumn
    , entries : List Har.Entry
    , selected : Maybe Har.Entry
    , filterMatch : Maybe String
    , filterKind : Maybe EntryKind
    }


type DetailTabName
    = Preview
    | Headers
    | Request
    | Response


type alias DetailTab =
    { name : DetailTabName, label : String }


type alias DetailModel =
    { tab : DetailTabName
    , treeState : JT.State
    , treeRootNode : Maybe JT.Node
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
                                            { sortBy = ( URL, Asc )
                                            , columns =
                                                [ { name = URL, label = "Name", width = 250 }
                                                , { name = Method, label = "Method", width = 80 }
                                                , { name = Status, label = "Status", width = 80 }
                                                , { name = Time, label = "Time", width = 150 }
                                                , { name = Domain, label = "Domain", width = 150 }
                                                , { name = Size, label = "Size", width = 150 }
                                                ]
                                            , entries = log.entries
                                            , selected = Nothing
                                            , filterMatch = Nothing
                                            , filterKind = Nothing
                                            }
                                        , timezone = Nothing
                                        , detail =
                                            { treeState = JT.defaultState
                                            , treeRootNode = Nothing
                                            , tab = Preview
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


tableSelectIndex : Int -> TableModel -> TableModel
tableSelectIndex index table =
    let
        indexedEntries =
            List.indexedMap Tuple.pair table.entries

        newSelected =
            indexedEntries
                |> List.filter (\( i, _ ) -> i == index)
                |> List.head
                |> Maybe.map Tuple.second
    in
    { table | selected = newSelected }


tableGetSelectedIndex : TableModel -> Maybe Int
tableGetSelectedIndex table =
    case table.selected of
        Just selected ->
            table.entries
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, entry ) -> entry == selected)
                |> List.head
                |> Maybe.map Tuple.first

        _ ->
            Nothing


tableSelectNextEntry : TableModel -> Bool -> TableModel
tableSelectNextEntry table isUp =
    case tableGetSelectedIndex table of
        Just index ->
            let
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
            tableSelectIndex nextIndex table

        Nothing ->
            table


updateSelectNextEntry : OpenedModel -> Bool -> OpenedModel
updateSelectNextEntry model isUp =
    { model | table = tableSelectNextEntry model.table isUp }
        |> updateSelectEntry


compareEntry : TableColumnName -> Har.Entry -> Har.Entry -> Order
compareEntry column a b =
    case column of
        URL ->
            compareString a.request.url b.request.url

        Status ->
            compareInt a.response.status b.response.status

        Time ->
            compareInt (Time.posixToMillis a.startedDateTime) (Time.posixToMillis b.startedDateTime)

        Domain ->
            compareString a.request.url b.request.url

        Size ->
            compareInt (a.response.bodySize + a.request.bodySize) (b.response.bodySize + b.request.bodySize)

        Method ->
            compareString a.request.method b.request.method


compareInt : Int -> Int -> Order
compareInt a b =
    if a < b then
        LT

    else if a > b then
        GT

    else
        EQ


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


updateSelectEntry : OpenedModel -> OpenedModel
updateSelectEntry model =
    case model.table.selected of
        Just entry ->
            case entry.response.content.text of
                Just text ->
                    let
                        detail =
                            model.detail
                    in
                    case text |> JT.parseString |> Result.toMaybe of
                        Just node ->
                            { model
                                | detail =
                                    { detail
                                        | treeRootNode = Just node
                                        , treeState = JT.collapseToDepth 2 node JT.defaultState
                                    }
                            }

                        _ ->
                            { model | detail = { detail | treeRootNode = Nothing } }

                Nothing ->
                    model

        _ ->
            model


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

                Select entry ->
                    let
                        table =
                            model.table
                    in
                    { model | table = { table | selected = Just entry } } |> updateSelectEntry

                Unselect ->
                    let
                        table =
                            model.table

                        detail =
                            model.detail
                    in
                    { model
                        | table = { table | selected = Nothing }
                        , detail = { detail | treeRootNode = Nothing }
                    }

                KeyDown key ->
                    case key of
                        NoKey ->
                            model

                        arrow ->
                            updateSelectNextEntry model (arrow == ArrowUp)

                ResizeColumn column width ->
                    let
                        table =
                            model.table

                        columns =
                            List.map
                                (\c ->
                                    if c.name == column then
                                        { c | width = width }

                                    else
                                        c
                                )
                                table.columns
                    in
                    { model | table = { table | columns = columns } }

                InputFilter filter ->
                    let
                        table =
                            model.table

                        newEntries =
                            filterEntries (Just filter) table.filterKind model.log.entries
                    in
                    { model | table = { table | entries = newEntries, filterMatch = Just filter } }

                SelectKind kind ->
                    let
                        table =
                            model.table

                        newEntries =
                            filterEntries table.filterMatch kind model.log.entries
                    in
                    { model | table = { table | entries = newEntries, filterKind = kind } }

        GotTimezone tz ->
            { model | timezone = Just tz }

        SetTreeViewState state ->
            let
                detail =
                    model.detail
            in
            { model | detail = { detail | treeState = state } }

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
            ( { model
                | hover = False
              }
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
        , span [ style "color" "#ccc" ] [ text (Debug.toString model) ]
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


entryKindValue : EntryKind -> String
entryKindValue kind =
    case kind of
        ReduxState ->
            "0"

        ReduxAction ->
            "1"

        Log ->
            "2"

        NetworkHttp ->
            "3"

        Others ->
            "4"


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


tableCellView : Time.Zone -> TableColumnName -> Har.Entry -> Html msg
tableCellView tz column entry =
    case column of
        URL ->
            div [ class "table-body-cell-url" ]
                [ getEntryIcon entry
                , text <|
                    case List.head <| List.reverse <| String.indexes "/" entry.request.url of
                        Just i ->
                            String.dropLeft (i + 1) entry.request.url

                        _ ->
                            entry.request.url
                ]

        Status ->
            text <| String.fromInt entry.response.status

        Time ->
            text <|
                toIntPad2 (Time.toHour tz entry.startedDateTime)
                    ++ ":"
                    ++ toIntPad2 (Time.toMinute tz entry.startedDateTime)
                    ++ ":"
                    ++ toIntPad2 (Time.toSecond tz entry.startedDateTime)
                    ++ ","
                    ++ toIntPad3 (Time.toMillis tz entry.startedDateTime)

        Domain ->
            text <|
                if String.startsWith "http" entry.request.url then
                    case String.split "/" entry.request.url of
                        _ :: _ :: domain :: _ ->
                            domain

                        _ ->
                            entry.request.url

                else
                    "-"

        Size ->
            let
                size =
                    entry.response.bodySize + entry.request.bodySize
            in
            if size < 0 then
                text "-"

            else
                text <| String.fromInt (entry.response.bodySize + entry.request.bodySize)

        Method ->
            text entry.request.method


entryView : Time.Zone -> List TableColumn -> Maybe Har.Entry -> Har.Entry -> Html TableMsg
entryView tz columns selected entry =
    div
        [ class
            (case selected of
                Just selectedEntry ->
                    if selectedEntry == entry then
                        "selected"

                    else
                        ""

                _ ->
                    ""
            )
        , class "table-body-row"
        , onClick (Select entry)
        ]
        (List.map
            (\column ->
                div
                    [ class "table-body-cell"
                    , style "width" <| String.fromInt column.width ++ "px"
                    ]
                    [ tableCellView tz column.name entry ]
            )
            columns
        )


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
        , onClick (FlipSort column.name)
        , style "width" <| String.fromInt column.width ++ "px"
        , class <|
            if column.name == sortColumn then
                "sorted"

            else
                ""
        ]
        [ text column.label
        , if column.name == sortColumn then
            tableSortIcon sortOrder

          else
            div [] []
        ]


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


tableFilterView : TableModel -> Html TableMsg
tableFilterView model =
    section [ class "table-filter" ]
        [ input
            [ class "table-filter-input"
            , value (Maybe.withDefault "" model.filterMatch)
            , onInput InputFilter
            , type_ "search"
            , autofocus True
            , placeholder "Filter"
            ]
            []
        , label [ class "table-filter-select" ]
            [ div [] [ text <| entryKindLabel model.filterKind ]
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


tableView : Time.Zone -> TableModel -> Html TableMsg
tableView tz { entries, sortBy, columns, selected } =
    let
        -- hide columns except first column when selected
        visibleColumns =
            case selected of
                Just _ ->
                    List.take 1 columns

                _ ->
                    columns
    in
    section
        (case selected of
            Just _ ->
                [ class "table table--selected"
                , style "width" <| totalWidth visibleColumns
                ]

            _ ->
                [ class "table" ]
        )
        [ div [ class "table-header" ] <|
            List.map (tableHeaderCell sortBy) visibleColumns
        , div
            [ class "table-body"
            , tabindex 0
            , hijackOn "keydown" (D.map KeyDown keyDecoder)
            ]
          <|
            List.map (entryView tz visibleColumns selected) entries
        ]


totalWidth : List TableColumn -> String
totalWidth columns =
    columns
        |> List.foldl (\column acc -> acc + column.width) 0
        |> String.fromInt
        |> (\w -> w ++ "px")


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
detailTabs tab entry =
    div [ class "detail-header-tabs" ] <|
        List.map (detailTab tab)
            [ { name = Preview, label = "Preview" }
            , { name = Headers, label = "Headers" }
            , { name = Request, label = "Request" }
            , { name = Response, label = "Response" }
            ]


detailPreviewView : OpenedModel -> Har.Entry -> Html OpenedMsg
detailPreviewView { detail, clientInfo } entry =
    if isReduxStateEntry entry && not (String.isEmpty clientInfo.href) then
        case getReduxState entry of
            Just s ->
                Html.node "agent-console-snapshot"
                    [ src <| clientInfo.href ++ "&snapshot=true"
                    , attribute "state" s
                    , attribute "time" <|
                        (entry.time
                            |> round
                            |> Time.millisToPosix
                            |> Iso8601.fromTime
                        )
                    ]
                    []

            _ ->
                text "No redux state found"

    else
        case detail.treeRootNode of
            Just node ->
                JT.view node
                    { colors =
                        { string = "var(--syntax-highlight-string-color)"
                        , number = "var(--syntax-highlight-number-color)"
                        , bool = "var(--syntax-highlight-boolean-color)"
                        , null = "var(--syntax-highlight-symbol-color)"
                        , selectable = ""
                        }
                    , onSelect = Nothing
                    , toMsg = SetTreeViewState
                    }
                    detail.treeState

            _ ->
                text <| Maybe.withDefault "" entry.response.content.text


keyValue : { x | name : String, value : String } -> Html msg
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
        , span [ class "detail-body-header-value" ] [ text value ]
        ]


requestHeaderKeyValue : { x | name : String, value : String } -> Html msg
requestHeaderKeyValue { name, value } =
    if name == "Authorization" then
        div []
            [ keyValue
                { name = name, value = value }
            , div [ class "detail-body-header-token-value" ] [ text (Maybe.withDefault "" <| parseToken value) ]
            ]

    else
        keyValue { name = name, value = value }


styleVar : String -> String -> Attribute msg
styleVar name value =
    attribute "style" (name ++ ": " ++ value)


parseToken : String -> Maybe String
parseToken token =
    if String.startsWith "Bearer " token then
        let
            _ =
                token
                    |> String.dropLeft 7
                    |> String.split "."
                    |> Debug.log "splitted"
        in
        case
            token
                |> String.dropLeft 7
                |> String.split "."
        of
            [ _, meta, _ ] ->
                let
                    _ =
                        Debug.log "meta"
                in
                meta
                    |> Base64.decode
                    |> Result.toMaybe

            _ ->
                Nothing

    else
        Nothing


detailView : OpenedModel -> Har.Entry -> Html OpenedMsg
detailView model entry =
    section [ class "detail" ]
        [ div [ class "detail-header" ]
            [ button [ class "detail-close", onClick (TableAction Unselect) ] [ Icons.close ]
            , detailTabs model.detail.tab entry
            ]
        , div [ class "detail-body" ]
            [ case model.detail.tab of
                Preview ->
                    detailPreviewView model entry

                Headers ->
                    div
                        [ class "detail-body-headers-container" ]
                        [ h3 [] [ text "Summary" ]
                        , div [ styleVar "--color" "var(--network-system-color)", class "detail-body-headers" ]
                            [ keyValue { name = "URL", value = entry.request.url }
                            , keyValue { name = "Method", value = String.toUpper entry.request.method }
                            , keyValue { name = "Status", value = String.fromInt entry.response.status }
                            , keyValue { name = "Address", value = Maybe.withDefault "" entry.serverIPAddress }
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
                            (List.map keyValue entry.response.headers)
                        , h3 [] [ text "Query String Parameters" ]
                        , div
                            [ styleVar "--color" "var(--text-color-tertiary)"
                            , class "detail-body-headers"
                            ]
                            (List.map keyValue entry.request.queryString)
                        ]

                Request ->
                    case entry.request.postData of
                        Just postData ->
                            case postData.text of
                                Just t ->
                                    pre [ class "detail-body-raw" ] [ text t ]

                                _ ->
                                    text "No content"

                        _ ->
                            text "No content"

                Response ->
                    case entry.response.content.text of
                        Just t ->
                            pre [ class "detail-body-raw" ] [ text t ]

                        _ ->
                            text "No content"
            ]
        ]


viewOpened : OpenedModel -> Html OpenedMsg
viewOpened model =
    case model.timezone of
        Just tz ->
            div
                [ class "app" ]
                [ Html.map TableAction (tableFilterView model.table)
                , Html.map TableAction (tableView tz model.table)
                , case model.table.selected of
                    Just entry ->
                        detailView model entry

                    _ ->
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
