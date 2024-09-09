module Initial exposing (..)

import Browser.Navigation as Nav
import DropFile exposing (DropFileModel, DropFileMsg(..), dropFileView)
import File.Select as Select
import HarDecoder exposing (decodeHar)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import RecentFile exposing (RecentFile, clearRecentFiles, getFileContent)



-- MODEL


type alias InitialModel =
    { navKey : Nav.Key
    , dropFile : DropFileModel
    , recentFiles : List RecentFile
    }


defaultInitialModel : Nav.Key -> InitialModel
defaultInitialModel navKey =
    { navKey = navKey
    , dropFile = DropFile.defaultDropFileModel
    , recentFiles = []
    }



-- VIEW


initialView : InitialModel -> Html InitialMsg
initialView model =
    dropFileView "initial-container"
        model.dropFile
        DropFile
        [ span [ style "color" "red" ] [ text <| Maybe.withDefault "" model.dropFile.error ]
        , ul [ class "recent-files" ]
            (li [] [ a [ href "#", onClick Pick ] [ text "Open…" ] ]
                :: li [] [ a [ href "#", onClick ClickClearRecentFiles ] [ text "Clear Recent Files" ] ]
                :: li []
                    [ text
                        (if List.isEmpty model.recentFiles then
                            ""

                         else
                            "⸻"
                        )
                    ]
                :: List.map
                    (\{ key, fileName } ->
                        li
                            []
                            [ a
                                [ onClick (ClickRecentFile key fileName)
                                , href "#"
                                ]
                                [ text fileName ]
                            ]
                    )
                    model.recentFiles
            )
        ]



-- UPDATE


type InitialMsg
    = Pick
    | DropFile DropFileMsg
    | ClickRecentFile String String
    | ClickClearRecentFiles


updateInitial : InitialMsg -> InitialModel -> ( InitialModel, Cmd InitialMsg )
updateInitial msg model =
    case msg of
        Pick ->
            ( model, Select.file [ "*" ] (DropFile << GotFile) )

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
                |> Cmd.map
                    (\str ->
                        str
                            |> decodeHar
                            |> Maybe.map (GotFileContent str)
                            |> Maybe.withDefault NoOp
                            |> DropFile
                    )
            )

        ClickClearRecentFiles ->
            ( { model | recentFiles = [] }, clearRecentFiles () )
