module Main exposing (main)

import Browser
import Detail exposing (DetailModel, DetailMsg(..), detailViewContainer)
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
    { log : Har.Log
    , table : TableModel
    , timezone : Maybe Time.Zone
    , detail : DetailModel
    , clientInfo : ClientInfo
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Initial defaultInitialModel, Cmd.none )



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
            div
                [ class "app" ]
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


type OpenedMsg
    = TableAction TableMsg
    | GotTimezone Time.Zone
    | DetailAction DetailMsg


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


updateOpened : OpenedMsg -> OpenedModel -> OpenedModel
updateOpened msg model =
    case msg of
        TableAction action ->
            let
                model2 =
                    case action of
                        Select _ True ->
                            let
                                detailModel =
                                    model.detail
                            in
                            { model | detail = { detailModel | show = True } }

                        _ ->
                            model
            in
            { model2 | table = updateTable action model2.log model2.table }

        GotTimezone tz ->
            { model | timezone = Just tz }

        DetailAction detailMsg ->
            { model | detail = Detail.updateDetail model.detail detailMsg }



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
