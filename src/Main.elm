module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Detail exposing (DetailModel, DetailMsg(..), detailViewContainer)
import DropFile exposing (DropFileModel, DropFileMsg(..), defaultDropFileModel, dropFileView)
import Har exposing (ClientInfo, EntryKind(..), SortOrder(..))
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy, lazy4)
import Initial exposing (InitialModel, InitialMsg, defaultInitialModel, initialView, updateInitial)
import List
import Table exposing (TableModel, TableMsg(..), defaultTableModel, tableFilterView, tableView, updateTable)
import Task
import Time



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
        Just tz ->
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
                [ Html.map TableAction (lazy tableFilterView table.filter)
                , Html.map TableAction (lazy4 tableView tz startTime table detail.show)
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
                model2 =
                    case action of
                        Select _ True _ ->
                            let
                                detailModel =
                                    model.detail
                            in
                            { model
                                | detail =
                                    let
                                        playbackState =
                                            detailModel.playbackState
                                    in
                                    { detailModel
                                        | show = True
                                        , playbackState =
                                            { playbackState
                                                | isPlaying = False
                                                , time = 0
                                            }
                                    }
                            }

                        _ ->
                            model

                ( table, cmd ) =
                    updateTable model.navKey action model2.log model2.table
            in
            ( { model2 | table = table }, Cmd.map TableAction cmd )

        GotTimezone tz ->
            ( { model | timezone = Just tz }, Cmd.none )

        DetailAction detailMsg ->
            let
                ( detail, cmd ) =
                    Detail.updateDetail model.detail detailMsg
            in
            ( { model | detail = detail }, Cmd.map DetailAction cmd )

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
