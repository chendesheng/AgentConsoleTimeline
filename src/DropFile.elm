module DropFile exposing (DropFileModel, DropFileMsg(..), decodeFile, defaultDropFileModel, dropFileUpdate, dropFileView)

import File exposing (File)
import File.Download as Download
import Har
import HarDecoder exposing (decodeHar)
import Html exposing (..)
import Html.Attributes exposing (..)
import Json.Decode as D
import Task
import UnzipFile exposing (unzipFile)
import Utils



-- MODEL


type alias DropFileModel =
    { hover : Bool
    , error : Maybe String
    , fileName : String
    , fileContentString : String
    , fileContent : Maybe Har.Log
    , waitingOpenFile : Bool
    }


defaultDropFileModel : DropFileModel
defaultDropFileModel =
    { hover = False
    , error = Nothing
    , fileName = ""
    , fileContentString = ""
    , fileContent = Nothing
    , waitingOpenFile = False
    }



-- UPDATE


type DropFileMsg
    = NoOp
    | DragEnter
    | DragLeave
    | GotFile File
    | GotFileInBase64DataUrl String
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

        DragEnter ->
            ( { model | hover = True }, Cmd.none )

        DragLeave ->
            ( { model | hover = False }, Cmd.none )

        GotFile file ->
            let
                newModel =
                    { model | hover = False, fileName = File.name file }

                name =
                    File.name file
            in
            if String.endsWith ".zip" name then
                -- unzip too large file is too slow
                if File.size file > 1024 * 1024 * 100 then
                    ( { newModel | error = Just "file is too large (> 100 MB)" }
                    , Cmd.none
                    )

                else
                    ( newModel
                    , Task.perform GotFileInBase64DataUrl (File.toUrl file)
                    )

            else
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

        GotFileInBase64DataUrl url ->
            ( { model | waitingOpenFile = True }, unzipFile url )

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


dropFileView : String -> DropFileModel -> (DropFileMsg -> msg) -> List (Html msg) -> Html msg
dropFileView className model fn children =
    div
        [ class "drop-file-container"
        , class <|
            if model.hover then
                "drop-file-container--hover"

            else
                ""
        , class className
        , Utils.hijackOn "dragenter" (D.succeed <| fn DragEnter)
        , Utils.hijackOn "dragover" (D.succeed <| fn DragEnter)
        , Utils.hijackOn "dragleave" (D.succeed <| fn DragLeave)
        , Utils.hijackOn "drop" <| D.map fn dropDecoder
        ]
        children


dropDecoder : D.Decoder DropFileMsg
dropDecoder =
    D.at [ "dataTransfer", "files" ] (D.oneOrMore (\f _ -> GotFile f) File.decoder)
