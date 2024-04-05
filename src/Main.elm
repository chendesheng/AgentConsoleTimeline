module Main exposing (main)

import Browser
import Browser.Events exposing (onKeyDown)
import File exposing (File)
import File.Select as Select
import Har
import HarDecoder exposing (harDecoder)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Icons
import Json.Decode as D
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
    , treeState : JT.State
    , treeRootNode : Maybe JT.Node
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
    = TableAction TableAction
    | GotTimezone Time.Zone
    | SetTreeViewState JT.State


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


type TableAction
    = FlipSort TableColumnName
    | ResizeColumn TableColumnName Int
    | Select Har.Entry
    | Unselect
      -- key events
    | KeyDown KeyCode


type TableColumnName
    = URL
    | Status
    | Time
    | Domain
    | Size


type alias TableColumn =
    { name : TableColumnName
    , label : String
    , width : Int
    }


type alias TableModel =
    { sortBy : SortBy
    , columns : List TableColumn
    , entries : List Har.Entry
    , selected : Maybe Har.Entry
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
                                                , { name = Status, label = "Status", width = 100 }
                                                , { name = Time, label = "Time", width = 150 }
                                                , { name = Domain, label = "Domain", width = 150 }
                                                , { name = Size, label = "Size", width = 150 }
                                                ]
                                            , entries = log.entries
                                            , selected = Nothing
                                            }
                                        , timezone = Nothing
                                        , treeState = JT.defaultState
                                        , treeRootNode = Nothing
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
                |> List.filter (\( i, entry ) -> i == index)
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
                |> List.filter (\( i, entry ) -> entry == selected)
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
                    case text |> JT.parseString |> Result.toMaybe of
                        Just node ->
                            { model
                                | treeRootNode = Just node
                                , treeState = JT.collapseToDepth 2 node JT.defaultState
                            }

                        _ ->
                            { model | treeRootNode = Nothing }

                Nothing ->
                    model

        _ ->
            model


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
                    in
                    { model
                        | table = { table | selected = Nothing }
                        , treeRootNode = Nothing
                    }

                KeyDown key ->
                    case key of
                        ArrowUp ->
                            { model | table = tableSelectNextEntry model.table True }
                                |> updateSelectEntry

                        ArrowDown ->
                            { model | table = tableSelectNextEntry model.table False }
                                |> updateSelectEntry

                        _ ->
                            model

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

        GotTimezone tz ->
            { model | timezone = Just tz }

        SetTreeViewState state ->
            { model | treeState = state }


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


getEntryIcon : Har.Entry -> Html msg
getEntryIcon entry =
    if entry.request.url == "/redux/state" then
        Icons.imageDoc

    else if String.startsWith "https://" entry.request.url || String.startsWith "http://" entry.request.url then
        Icons.networkDoc

    else
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


entryView : Time.Zone -> List TableColumn -> Maybe Har.Entry -> Har.Entry -> Html TableAction
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


tableHeaderCell : SortBy -> TableColumn -> Html TableAction
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


tableView : Time.Zone -> TableModel -> Html TableAction
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


detailView : OpenedModel -> Har.Entry -> Html OpenedMsg
detailView { treeState, treeRootNode, clientInfo } entry =
    section [ class "detail" ]
        [ div [ class "detail-header" ]
            [ button [ class "detail-close", onClick (TableAction Unselect) ] [ Icons.close ] ]
        , div [ class "detail-body" ]
            [ case treeRootNode of
                Just node ->
                    if isReduxStateEntry entry && not (String.isEmpty clientInfo.href) then
                        case getReduxState entry of
                            Just s ->
                                Html.node "agent-console-snapshot"
                                    [ src <| clientInfo.href ++ "&snapshot=true"
                                    , attribute "state" s
                                    ]
                                    []

                            _ ->
                                text "No redux state found"

                    else
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
                            treeState

                _ ->
                    text <| Maybe.withDefault "" entry.response.content.text
            ]
        ]


viewOpened : OpenedModel -> Html OpenedMsg
viewOpened model =
    case model.timezone of
        Just tz ->
            div
                [ class "app" ]
                [ Html.map TableAction (tableView tz model.table)
                , case model.table.selected of
                    Just entry ->
                        detailView model entry

                    _ ->
                        text ""
                ]

        _ ->
            div [] [ text "Loading..." ]


externalCss : String -> Html msg
externalCss url =
    Html.node "link" [ rel "stylesheet", href url ] []


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
