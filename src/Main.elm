module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Detail exposing (DetailModel, DetailMsg(..), detailViewContainer)
import DropFile exposing (DropFileModel, DropFileMsg(..), defaultDropFileModel, dropFileView)
import Har exposing (ClientInfo, EntryKind(..), SortOrder(..))
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy2, lazy3, lazy4)
import Initial exposing (InitialModel, InitialMsg, defaultInitialModel, initialView, updateInitial)
import List
import Table exposing (TableModel, TableMsg(..), defaultTableModel, tableFilterView, tableView, updateTable)
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
    , log : Har.Log
    , dropFile : DropFileModel
    }


init : Nav.Key -> ( Model, Cmd Msg )
init navKey =
    ( Initial <| defaultInitialModel navKey, Cmd.none )



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
                    (lazy4 detailViewContainer
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


initOpened : Har.Log -> Nav.Key -> ( OpenedModel, Cmd OpenedMsg )
initOpened log navKey =
    ( { table = { defaultTableModel | entries = log.entries }
      , timezone = Nothing
      , detail = Detail.defaultDetailModel
      , clientInfo = Har.getClientInfo log.entries
      , navKey = navKey
      , log = log
      , dropFile = defaultDropFileModel
      }
    , Task.perform GotTimezone Time.here
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
                                            initOpened log newModel.navKey
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
                            let
                                ( table2, cmd2 ) =
                                    updateTable model.navKey (Select model.detail.currentId False True) model.log model.table
                            in
                            ( table2
                            , Cmd.batch
                                [ cmd2
                                , Utils.scrollIntoView <| "entry" ++ model.detail.currentId
                                ]
                            )

                        _ ->
                            ( model.table, Cmd.none )
            in
            ( { model | detail = detail, table = table }
            , Cmd.batch
                [ Cmd.map DetailAction cmd
                , Cmd.map TableAction cmd1
                ]
            )

        DropFile (GotFileContent log) ->
            initOpened log model.navKey

        DropFile dropMsg ->
            let
                ( dropFile, cmd ) =
                    DropFile.dropFileUpdate dropMsg model.dropFile
            in
            ( { model | dropFile = dropFile }, Cmd.map DropFile cmd )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- MAIN


main : Program () Model Msg
main =
    Browser.application
        { init = \_ _ key -> init key
        , view = \model -> { title = "", body = [ view model ] }
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = \_ -> NoOp
        , onUrlChange =
            \url ->
                case url.fragment of
                    Just fragment ->
                        case String.split "entry" fragment of
                            [ "", entryId ] ->
                                OpenedMsg <| TableAction (Select entryId False False)

                            _ ->
                                NoOp

                    _ ->
                        NoOp
        }
