module DropFile exposing (DropFileModel, DropFileMsg(..), decodeFile, defaultDropFileModel, dropFileUpdate, dropFileView)

import File exposing (File)
import File.Download as Download
import Har
import HarDecoder exposing (decodeHar)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (on)
import Json.Decode as D
import Task



-- MODEL


type alias DropFileModel =
    { error : Maybe String
    , fileName : String
    , fileContentString : String
    , fileContent : Maybe Har.Log
    , waitingOpenFile : Bool
    }


defaultDropFileModel : DropFileModel
defaultDropFileModel =
    { error = Nothing
    , fileName = ""
    , fileContentString = ""
    , fileContent = Nothing
    , waitingOpenFile = False
    }



-- UPDATE


type DropFileMsg
    = NoOp
    | GotFile File
    | GotFileContent String Har.Log
    | ReadFileError String
    | DownloadFile


decodeFile : String -> String -> DropFileMsg
decodeFile fileName fileContent =
    case decodeHar fileContent of
        Ok log ->
            GotFileContent fileContent log

        Err _ ->
            ReadFileError <| "Decode file " ++ fileName ++ " failed."


dropFileUpdate : DropFileMsg -> DropFileModel -> ( DropFileModel, Cmd DropFileMsg )
dropFileUpdate msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        GotFile file ->
            let
                name =
                    File.name file

                newModel =
                    { model | fileName = name }
            in
            ( newModel
            , Task.attempt
                (\res ->
                    case res of
                        Ok str ->
                            decodeFile name str

                        Err error ->
                            ReadFileError error
                )
                (File.toString file)
            )

        GotFileContent fileContentString file ->
            ( { model
                | fileContentString = fileContentString
                , fileContent = Just file
                , error = Nothing
                , waitingOpenFile = False
              }
            , Cmd.none
            )

        ReadFileError error ->
            ( { model | error = Just error }, Cmd.none )

        DownloadFile ->
            case model.fileContentString of
                "" ->
                    ( model, Cmd.none )

                s ->
                    ( model, Download.string model.fileName "text/plain" s )



-- VIEW


dropFileView : String -> (DropFileMsg -> msg) -> List (Html msg) -> Html msg
dropFileView className fn children =
    Html.node "drop-zip-file"
        [ class className
        , on "change" <| D.map (fn << GotFile) <| D.field "detail" File.decoder
        , on "error" <| D.map (fn << ReadFileError) <| D.field "detail" D.string
        ]
        children
