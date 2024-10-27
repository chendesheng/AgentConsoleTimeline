module Initial exposing (..)

import Browser.Navigation as Nav
import DropFile exposing (DropFileModel, DropFileMsg, decodeFile, dropFileView)
import File.Select as Select
import HarDecoder exposing (decodeHar)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy3)
import Icons
import RecentFile exposing (RecentFile, clearRecentFiles, deleteRecentFile, getFileContent)
import Remote
import Table exposing (tableFilterView, tableView)
import Time
import Utils



-- MODEL


type alias InitialModel =
    { navKey : Nav.Key
    , dropFile : DropFileModel
    , recentFiles : List RecentFile
    , remoteSessionIds : List String
    , waitingRemoteSession : Maybe String
    , remoteAddress : String
    }


defaultInitialModel : Nav.Key -> String -> InitialModel
defaultInitialModel navKey remoteAddress =
    { navKey = navKey
    , dropFile = DropFile.defaultDropFileModel
    , recentFiles = []
    , remoteSessionIds = []
    , waitingRemoteSession = Nothing
    , remoteAddress = remoteAddress
    }



-- VIEW


liveSessionList : String -> List String -> Html InitialMsg
liveSessionList remoteAddress remoteSessionIds =
    ul [ class "remote" ]
        (h3 [] [ text "Live Sessions" ]
            :: List.map
                (\sessionId ->
                    let
                        url =
                            "wss://" ++ remoteAddress ++ "/connect?session=" ++ sessionId
                    in
                    li
                        []
                        [ button
                            [ onClick (ClickRemoteSession url) ]
                            [ text url ]
                        ]
                )
                remoteSessionIds
        )


recentFilesList : List RecentFile -> Html InitialMsg
recentFilesList recentFiles =
    ul [] <|
        h3 [] [ text "Recent Files" ]
            :: List.map
                (\{ key, fileName, size } ->
                    li
                        []
                        [ button
                            [ onClick (ClickRecentFile key fileName)
                            ]
                            [ text <| fileName ++ " (" ++ Utils.formatSize size ++ ")"
                            ]
                        , text " "
                        , button
                            [ onClick (ClickDeleteRecentFile key)
                            , class "close"
                            ]
                            [ text "✕" ]
                        ]
                )
                recentFiles


initialView : InitialModel -> Html InitialMsg
initialView model =
    dropFileView "app initial-container"
        model.dropFile
        DropFile
        [ Html.map (\_ -> NoOp) <| tableFilterView False Nothing False { match = "", kind = Nothing }
        , Html.map (\_ -> NoOp) (lazy3 tableView (Time.millisToPosix 0) Table.defaultTableModel False)
        , div [ class "initial-dialog-container" ] <|
            case model.waitingRemoteSession of
                Just url ->
                    [ div [ class "initial-dialog", class "waiting-remote-session" ]
                        [ Icons.spinning
                        , text <| "Waiting for " ++ url ++ " to connect…"
                        ]
                    ]

                _ ->
                    [ span [ class "error" ] [ text <| Maybe.withDefault "" model.dropFile.error ]
                    , div [ class "initial-dialog" ]
                        [ span [ class "actions" ]
                            [ button [ onClick Pick ] [ text "Open…" ]
                            , button [ onClick ClickClearRecentFiles ] [ text "Clear Recent Files" ]
                            , span [ class "version" ] [ text "v1.0" ]
                            ]
                        , div [ class "bar" ] []
                        , if List.isEmpty model.remoteSessionIds then
                            text ""

                          else
                            liveSessionList model.remoteAddress model.remoteSessionIds
                        , recentFilesList model.recentFiles
                        ]
                    ]
        ]



-- UPDATE


type InitialMsg
    = NoOp
    | Pick
    | DropFile DropFileMsg
    | ClickRecentFile String String
    | ClickClearRecentFiles
    | ClickDeleteRecentFile String
    | GotRemoteSessions (List String)
    | ClickRemoteSession String
    | CloseRemote


updateInitial : InitialMsg -> InitialModel -> ( InitialModel, Cmd InitialMsg )
updateInitial msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        GotRemoteSessions sessionIds ->
            ( { model | remoteSessionIds = sessionIds }, Cmd.none )

        ClickRemoteSession url ->
            ( { model | waitingRemoteSession = Just url }, Remote.connectRemoteSource url )

        CloseRemote ->
            ( { model | waitingRemoteSession = Nothing }, Cmd.none )

        Pick ->
            ( model, Select.file [ "*" ] (DropFile << DropFile.GotFile) )

        DropFile dropMsg ->
            let
                ( newDropFile, cmd ) =
                    DropFile.dropFileUpdate dropMsg model.dropFile
            in
            ( { model | dropFile = newDropFile }, Cmd.map DropFile cmd )

        ClickRecentFile key fileName ->
            let
                dropFile =
                    model.dropFile
            in
            ( { model | dropFile = { dropFile | fileName = fileName } }
            , key
                |> getFileContent
                |> Cmd.map (\str -> DropFile <| decodeFile fileName str)
            )

        ClickClearRecentFiles ->
            ( { model | recentFiles = [] }, clearRecentFiles () )

        ClickDeleteRecentFile key ->
            ( { model | recentFiles = List.filter (\f -> f.key /= key) model.recentFiles }
            , deleteRecentFile key
            )
