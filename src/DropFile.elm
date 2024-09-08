module DropFile exposing (DropFileModel, DropFileMsg(..), defaultDropFileModel, dropFileUpdate, dropFileView)

import File exposing (File)
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


readFile : File -> Task x String
readFile file =
    let
        name =
            File.name file
    in
    if String.endsWith ".zip" name then
        -- TODO: handle error
        file
            |> File.toBytes
            |> Task.map
                (\bytes ->
                    bytes
                        |> Zip.fromBytes
                        |> Maybe.andThen
                            (\zip ->
                                zip
                                    |> Zip.entries
                                    |> List.filter (not << ZipEntry.isDirectory)
                                    |> List.head
                                    |> Maybe.andThen (ZipEntry.toString >> Result.toMaybe)
                            )
                        |> Maybe.withDefault ""
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
            , Task.perform
                (\str ->
                    str
                        |> decodeHar
                        |> Maybe.map (GotFileContent str)
                        |> Maybe.withDefault NoOp
                )
                (readFile file)
            )

        GotFileContent fileContentString file ->
            ( { model | fileContentString = fileContentString, fileContent = Just file }, Cmd.none )



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
