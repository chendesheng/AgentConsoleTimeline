module DropFile exposing (DropFileModel, DropFileMsg(..), defaultDropFileModel, dropFileUpdate, dropFileView)

import File exposing (File)
import File.Download as Download
import Har
import HarDecoder exposing (decodeHar)
import Html exposing (..)
import Html.Attributes exposing (..)
import Json.Decode as D
import Task exposing (Task)
import Utils
import Zip
import Zip.Entry as ZipEntry



-- MODEL


type alias DropFileModel =
    { hover : Bool
    , error : Maybe String
    , fileName : String
    , fileContentString : String
    , fileContent : Maybe Har.Log
    }


defaultDropFileModel : DropFileModel
defaultDropFileModel =
    { hover = False
    , error = Nothing
    , fileName = ""
    , fileContentString = ""
    , fileContent = Nothing
    }



-- UPDATE


type DropFileMsg
    = NoOp
    | DragEnter
    | DragLeave
    | GotFile File
    | GotFileContent String Har.Log
    | ReadFileError String
    | DownloadFile


readFile : File -> Task String String
readFile file =
    let
        name =
            File.name file

        fail message =
            Task.fail <| "Unzip " ++ name ++ ": " ++ message
    in
    if String.endsWith ".zip" name then
        -- unzip too large file is too slow
        if File.size file > 1024 * 1024 * 50 then
            fail "file is too large (> 50 MB)"

        else
            file
                |> File.toBytes
                |> Task.andThen
                    (\bytes ->
                        bytes
                            |> Zip.fromBytes
                            |> Maybe.andThen
                                (\zip ->
                                    case
                                        zip
                                            |> Zip.entries
                                            |> List.filter (not << ZipEntry.isDirectory)
                                            |> List.head
                                    of
                                        Just entry ->
                                            entry
                                                |> ZipEntry.toString
                                                |> Result.toMaybe
                                                |> Maybe.map Task.succeed

                                        _ ->
                                            Just <| fail "no files found"
                                )
                            |> Maybe.withDefault (fail "format error")
                    )

    else
        File.toString file


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
            ( { model | hover = False, fileName = File.name file }
            , Task.attempt
                (\res ->
                    case res of
                        Ok str ->
                            str
                                |> decodeHar
                                |> Maybe.map (GotFileContent str)
                                |> Maybe.withDefault (ReadFileError <| "File format error: " ++ File.name file)

                        Err error ->
                            ReadFileError error
                )
                (readFile file)
            )

        GotFileContent fileContentString file ->
            ( { model | fileContentString = fileContentString, fileContent = Just file, error = Nothing }, Cmd.none )

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
