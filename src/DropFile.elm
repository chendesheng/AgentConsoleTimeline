module DropFile exposing (DropFileModel, DropFileMsg(..), defaultDropFileModel, dropFileUpdate, dropFileView)

import File exposing (File)
import Har
import HarDecoder exposing (harDecoder)
import Html exposing (..)
import Html.Attributes exposing (..)
import Json.Decode as D
import Task
import Time
import Utils



-- MODEL


type alias DropFileModel =
    { hover : Bool
    , error : Maybe String
    , fileContent : Maybe Har.Log
    }


defaultDropFileModel : DropFileModel
defaultDropFileModel =
    { hover = False
    , error = Nothing
    , fileContent = Nothing
    }



-- UPDATE


type DropFileMsg
    = NoOp
    | DragEnter
    | DragLeave
    | GotFile File
    | GotFileContent Har.Log


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
            ( { model | hover = False }
            , Task.perform
                (\str ->
                    case D.decodeString harDecoder str of
                        Ok { log } ->
                            GotFileContent
                                { log
                                    | entries =
                                        List.sortBy (\entry -> Time.posixToMillis entry.startedDateTime) log.entries
                                }

                        Err _ ->
                            NoOp
                )
                (File.toString file)
            )

        GotFileContent file ->
            ( { model | fileContent = Just file }, Cmd.none )



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
