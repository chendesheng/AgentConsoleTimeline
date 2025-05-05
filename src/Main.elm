port module Main exposing (main)

import Browser
import Browser.Dom as Dom
import Detail exposing (DetailModel, DetailMsg(..), detailViewContainer)
import DropFile exposing (DropFileModel, DropFileMsg(..), defaultDropFileModel, dropFileView)
import Har exposing (ClientInfo, EntryKind(..), SortOrder(..))
import HarDecoder
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy3, lazy5, lazy8)
import Initial exposing (InitialModel, InitialMsg(..), defaultInitialModel, initialView, updateInitial)
import Json.Decode as Decode
import List
import RecentFile exposing (RecentFile, gotFileContent, saveRecentFile)
import Remote
import Table
    exposing
        ( TableModel
        , TableMsg(..)
        , defaultTableModel
        , isScrollbarInBottom
        , isSortByTime
        , scrollToBottom
        , subTable
        , tableFilterView
        , tableView
        , updateTable
        )
import Task
import Time
import Utils


port closePopoutWindow : () -> Cmd msg



-- MODEL


type Model
    = Initial InitialModel
    | Opened OpenedModel


type alias OpenedModel =
    { table : TableModel
    , timezone : Maybe Time.Zone
    , detail : DetailModel
    , clientInfo : ClientInfo
    , fileName : String
    , log : Har.Log
    , dropFile : DropFileModel
    }


init : String -> List RecentFile -> ( Model, Cmd Msg )
init remoteAddress recentFiles =
    let
        model =
            defaultInitialModel remoteAddress
    in
    ( Initial <| { model | recentFiles = recentFiles }
    , Remote.getSessions remoteAddress (GotRemoteSessions >> InitialMsg)
    )


isLiveSession : String -> Bool
isLiveSession fileName =
    String.startsWith "wss://" fileName



-- VIEW


viewOpened : OpenedModel -> Html OpenedMsg
viewOpened model =
    case model.timezone of
        Just _ ->
            let
                startTime =
                    model.log.entries
                        |> Utils.findItem (\entry -> entry.pageref == Just model.table.filter.page)
                        |> Maybe.map .startedDateTime
                        |> Maybe.withDefault (Time.millisToPosix 0)

                table =
                    model.table

                detail =
                    model.detail
            in
            dropFileView
                "app"
                DropFile
                [ Html.map TableAction
                    (lazy5
                        tableFilterView
                        (isLiveSession model.fileName)
                        model.dropFile.error
                        True
                        model.log.pages
                        table.filter
                    )
                , Html.map TableAction (lazy3 tableView startTime table detail.show)
                , Html.map DetailAction
                    (lazy8 detailViewContainer
                        (isLiveSession model.fileName)
                        model.detail.snapshotPopout
                        (isSortByTime table)
                        table.href
                        table.filter.page
                        table.selectHistory.present
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
    | AddHarEntries (List Har.Entry)


initOpened : String -> String -> Har.Log -> Maybe Int -> ( OpenedModel, Cmd OpenedMsg )
initOpened fileName fileContent log initialViewportHeight =
    let
        filter =
            defaultTableModel.filter

        clientInfo =
            Har.getClientInfo log.entries

        table =
            { defaultTableModel
                | entries = log.entries
                , entriesCount = List.length log.entries
                , viewportHeight = Maybe.withDefault 0 initialViewportHeight
                , filter = { filter | page = log.pages |> List.head |> Maybe.map .id |> Maybe.withDefault "" }
                , href =
                    case log.pages |> List.head |> Maybe.map .title of
                        Just title ->
                            if String.startsWith "https://" title then
                                title

                            else
                                clientInfo.href

                        Nothing ->
                            clientInfo.href
            }

        isLive =
            isLiveSession fileName
    in
    ( { table = table
      , timezone = Nothing
      , detail = Detail.defaultDetailModel
      , clientInfo = clientInfo
      , fileName = fileName
      , log = log
      , dropFile =
            { defaultDropFileModel
                | fileName =
                    if isLive then
                        Utils.exportLiveSessionFileName clientInfo.time

                    else
                        fileName
                , fileContentString = fileContent
            }
      }
    , Cmd.batch
        [ Task.perform GotTimezone Time.here
        , Task.attempt (\_ -> TableAction Table.NoOp) <| Dom.setViewportOf "table-body" 0 0
        , closePopoutWindow ()
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
        , if isLive then
            Cmd.none

          else
            saveRecentFile { fileName = fileName, fileContent = fileContent }
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
                                                (Maybe.withDefault newModel.dropFile.fileName newModel.waitingRemoteSession)
                                                newModel.dropFile.fileContentString
                                                log
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
        TableAction (GotImportFile (Ok file)) ->
            updateOpened (DropFile (GotJsonFile file)) model

        TableAction (GotImportFile (Err error)) ->
            updateOpened (DropFile (ReadFileError error)) model

        TableAction Export ->
            updateOpened (DropFile DownloadFile) model

        TableAction action ->
            let
                oldSelectedId =
                    model.table.selectHistory.present

                ( table, cmd ) =
                    updateTable action model.log model.table

                detailModel =
                    model.detail

                currentId =
                    if table.selectHistory.present == oldSelectedId then
                        detailModel.currentId

                    else
                        table.selectHistory.present
            in
            ( { model
                | detail =
                    { detailModel
                        | show =
                            case action of
                                Select _ True _ ->
                                    True

                                _ ->
                                    detailModel.show
                        , currentId = currentId
                    }
                , table = table
              }
            , Cmd.map TableAction cmd
            )

        -- TODO: setup timezone at the initial UI
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

                tableEntries =
                    Har.filterByPage table.filter.page entries
            in
            ( { model
                | timezone = Just tz
                , table =
                    { table
                        | entries = tableEntries
                        , entriesCount = List.length tableEntries
                    }
                , log = { log | entries = entries }
              }
            , if isLiveSession model.fileName then
                Cmd.map TableAction <| scrollToBottom table

              else
                Cmd.none
            )

        DetailAction detailMsg ->
            let
                ( detail, cmd ) =
                    Detail.updateDetail model.detail detailMsg

                ( table, cmd1 ) =
                    case detailMsg of
                        Detail.SetHref href ->
                            updateTable (Table.SetHref href) model.log model.table

                        Detail.ScrollToCurrentId ->
                            updateTable (Select model.detail.currentId False True) model.log model.table

                        _ ->
                            ( model.table, Cmd.none )
            in
            ( { model | detail = detail, table = table }
            , Cmd.batch [ Cmd.map DetailAction cmd, Cmd.map TableAction cmd1 ]
            )

        DropFile dropMsg ->
            let
                ( dropFile, cmd ) =
                    DropFile.dropFileUpdate dropMsg model.dropFile
            in
            ( { model | dropFile = dropFile }, Cmd.map DropFile cmd )

        AddHarEntries newEntries ->
            let
                log =
                    model.log

                table =
                    model.table

                count =
                    List.length log.entries

                entries =
                    List.append
                        -- log.entries should always sorted by startedDateTime
                        log.entries
                    <|
                        List.indexedMap
                            (\i entry ->
                                { entry
                                    | id = String.fromInt (count + i)
                                    , startedDateTimeStr =
                                        Utils.formatTime (Maybe.withDefault Time.utc model.timezone) entry.startedDateTime
                                }
                            )
                            newEntries

                filteredEntries =
                    entries
                        |> Har.filterEntries table.filter.page table.filter.match table.filter.kind
                        |> Har.sortEntries table.sortBy

                newTable =
                    { table
                        | entries = filteredEntries
                        , entriesCount = List.length filteredEntries
                    }
            in
            ( { model
                | log = { log | entries = entries }
                , table = newTable
              }
            , if isScrollbarInBottom table then
                Cmd.map TableAction <| scrollToBottom newTable

              else
                Cmd.none
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        Initial { waitingRemoteSession } ->
            Sub.batch
                [ gotFileContent
                    (\jsonFile -> InitialMsg <| Initial.DropFile <| GotJsonFile jsonFile)
                , case waitingRemoteSession of
                    Just _ ->
                        Remote.gotRemoteHarLog
                            (\s ->
                                s
                                    |> Decode.decodeString Decode.value
                                    |> Result.map (\log -> InitialMsg <| Initial.DropFile <| GotJsonFile { name = s, text = s, json = log })
                                    |> Result.withDefault NoOp
                            )

                    _ ->
                        Sub.none
                ]

        Opened { fileName } ->
            Sub.batch
                [ Sub.map (OpenedMsg << TableAction) subTable
                , if isLiveSession fileName then
                    Remote.gotRemoteHarEntry
                        (\s ->
                            s
                                |> Decode.decodeString (Decode.list HarDecoder.entryDecoder)
                                |> Result.map (AddHarEntries >> OpenedMsg)
                                |> Result.withDefault NoOp
                        )

                  else
                    Sub.none
                ]



-- MAIN


main : Program { remoteAddress : String, recentFiles : List RecentFile } Model Msg
main =
    Browser.document
        { init = \flags -> init flags.remoteAddress flags.recentFiles
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
        }
