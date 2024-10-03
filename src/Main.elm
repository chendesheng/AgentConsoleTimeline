module Main exposing (main)

import Browser
import Browser.Dom as Dom
import Browser.Navigation as Nav
import Detail exposing (DetailModel, DetailMsg(..), detailViewContainer)
import DropFile exposing (DropFileModel, DropFileMsg(..), defaultDropFileModel, dropFileView)
import Har exposing (ClientInfo, EntryKind(..), SortOrder(..))
import HarDecoder exposing (decodeHar)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy2, lazy3, lazy5, lazy6)
import Initial exposing (InitialModel, InitialMsg, defaultInitialModel, initialView, updateInitial)
import List
import RecentFile exposing (RecentFile, gotFileContent, saveRecentFile)
import Table exposing (TableModel, TableMsg(..), defaultTableModel, isSortByTime, subTable, tableFilterView, tableView, updateTable)
import Task
import Time
import Utils



-- MODEL


type Model
    = Initial InitialModel
    | Opened OpenedModel


type alias OpenedModel =
    { table : TableModel
    , timezone : Maybe Time.Zone
    , detail : DetailModel
    , clientInfo : ClientInfo
    , navKey : Nav.Key
    , fileName : String
    , log : Har.Log
    , dropFile : DropFileModel
    }


init : Nav.Key -> List RecentFile -> ( Model, Cmd Msg )
init navKey recentFiles =
    let
        model =
            defaultInitialModel navKey
    in
    ( Initial <| { model | recentFiles = recentFiles }, Cmd.none )



-- VIEW


viewOpened : OpenedModel -> Html OpenedMsg
viewOpened model =
    case model.timezone of
        Just _ ->
            let
                startTime =
                    model.log.entries
                        |> List.head
                        |> Maybe.map .startedDateTime
                        |> Maybe.withDefault (Time.millisToPosix 0)

                table =
                    model.table

                detail =
                    model.detail
            in
            dropFileView
                "app"
                model.dropFile
                DropFile
                [ Html.map TableAction (lazy2 tableFilterView table.waterfallMsPerPx table.filter)
                , Html.map TableAction (lazy3 tableView startTime table detail.show)
                , Html.map DetailAction
                    (lazy6 detailViewContainer
                        model.detail.snapshotPopout
                        (isSortByTime table)
                        model.clientInfo.href
                        table.selected
                        table.entries
                        model.detail
                    )
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



-- UPDATE


type Msg
    = InitialMsg InitialMsg
    | OpenedMsg OpenedMsg
    | NoOp


type OpenedMsg
    = TableAction TableMsg
    | GotTimezone Time.Zone
    | DetailAction DetailMsg
    | DropFile DropFileMsg


initOpened : String -> String -> Har.Log -> Nav.Key -> Maybe Int -> ( OpenedModel, Cmd OpenedMsg )
initOpened fileName fileContent log navKey initialViewportHeight =
    let
        table =
            { defaultTableModel | entries = log.entries, viewportHeight = Maybe.withDefault 0 initialViewportHeight }
    in
    ( { table = table
      , timezone = Nothing
      , detail = Detail.defaultDetailModel
      , clientInfo = Har.getClientInfo log.entries
      , navKey = navKey
      , fileName = fileName
      , log = log
      , dropFile = defaultDropFileModel
      }
    , Cmd.batch
        [ Task.perform GotTimezone Time.here
        , Task.attempt (\_ -> TableAction Table.NoOp) <| Dom.setViewportOf "table-body" 0 0
        , case initialViewportHeight of
            Nothing ->
                Task.attempt
                    (\res ->
                        case res of
                            Ok v ->
                                TableAction <| SetViewportHeight <| round v.scene.height - 60

                            _ ->
                                TableAction Table.NoOp
                    )
                    Dom.getViewport

            _ ->
                Cmd.none
        , saveRecentFile { fileName = fileName, fileContent = fileContent }
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        InitialMsg initialMsg ->
            case model of
                Initial initialModel ->
                    case updateInitial initialMsg initialModel of
                        ( newModel, cmd ) ->
                            case newModel.dropFile.fileContent of
                                Just log ->
                                    let
                                        ( m, cmd2 ) =
                                            initOpened
                                                newModel.dropFile.fileName
                                                newModel.dropFile.fileContentString
                                                log
                                                newModel.navKey
                                                Nothing
                                    in
                                    ( Opened m, Cmd.map OpenedMsg cmd2 )

                                _ ->
                                    ( Initial newModel, Cmd.map InitialMsg cmd )

                _ ->
                    ( model, Cmd.none )

        OpenedMsg openedMsg ->
            case model of
                Opened openedModel ->
                    case updateOpened openedMsg openedModel of
                        ( newOpenedModel, cmd ) ->
                            ( Opened newOpenedModel, Cmd.map OpenedMsg cmd )

                _ ->
                    ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


updateOpened : OpenedMsg -> OpenedModel -> ( OpenedModel, Cmd OpenedMsg )
updateOpened msg model =
    case msg of
        TableAction action ->
            let
                oldSelectedId =
                    model.table.selected

                ( table, cmd ) =
                    updateTable model.navKey action model.log model.table

                detailModel =
                    model.detail

                currentId =
                    if table.selected == oldSelectedId then
                        detailModel.currentId

                    else
                        table.selected
            in
            ( { model
                | detail =
                    { detailModel
                        | show =
                            case action of
                                Select _ True _ _ ->
                                    True

                                _ ->
                                    detailModel.show
                        , currentId = currentId
                    }
                , table = table
              }
            , Cmd.map TableAction cmd
            )

        GotTimezone tz ->
            let
                log =
                    model.log

                table =
                    model.table

                entries =
                    List.map
                        (\entry ->
                            { entry
                                | startedDateTimeStr =
                                    Utils.formatTime tz entry.startedDateTime
                            }
                        )
                        log.entries
            in
            ( { model
                | timezone = Just tz
                , table = { table | entries = entries }
                , log = { log | entries = entries }
              }
            , Cmd.none
            )

        DetailAction detailMsg ->
            let
                ( detail, cmd ) =
                    Detail.updateDetail model.detail detailMsg

                ( table, cmd1 ) =
                    case detailMsg of
                        ScrollToCurrentId ->
                            updateTable model.navKey (Select model.detail.currentId False True True) model.log model.table

                        _ ->
                            ( model.table, Cmd.none )

                clientInfo =
                    let
                        info =
                            model.clientInfo
                    in
                    case detailMsg of
                        SetHref href ->
                            { info | href = href }

                        _ ->
                            info
            in
            ( { model | detail = detail, table = table, clientInfo = clientInfo }
            , Cmd.batch [ Cmd.map DetailAction cmd, Cmd.map TableAction cmd1 ]
            )

        DropFile (GotFileContent fileContent log) ->
            initOpened model.dropFile.fileName fileContent log model.navKey (Just model.table.viewportHeight)

        DropFile dropMsg ->
            let
                ( dropFile, cmd ) =
                    DropFile.dropFileUpdate dropMsg model.dropFile
            in
            ( { model | dropFile = dropFile }, Cmd.map DropFile cmd )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        Initial _ ->
            gotFileContent
                (\str ->
                    case decodeHar str of
                        Just log ->
                            InitialMsg <| Initial.DropFile <| GotFileContent str log

                        _ ->
                            NoOp
                )

        Opened _ ->
            Sub.map (OpenedMsg << TableAction) subTable



-- MAIN


main : Program { recentFiles : List RecentFile } Model Msg
main =
    Browser.application
        { init = \flags _ key -> init key flags.recentFiles
        , view =
            \model ->
                { title =
                    case model of
                        Initial _ ->
                            "ACD"

                        Opened { table, fileName } ->
                            case Table.getSelectedEntry table of
                                Just entry ->
                                    fileName ++ " | " ++ Har.harEntryName entry

                                _ ->
                                    fileName
                , body = [ view model ]
                }
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = \_ -> NoOp
        , onUrlChange =
            \url ->
                case url.fragment of
                    Just fragment ->
                        case String.split "entry" fragment of
                            [ "", entryId ] ->
                                OpenedMsg <| TableAction (Select entryId False False True)

                            _ ->
                                NoOp

                    _ ->
                        NoOp
        }
