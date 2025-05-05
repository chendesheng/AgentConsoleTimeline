module DropFile exposing (DropFileModel, DropFileMsg(..), defaultDropFileModel, dropFileUpdate, dropFileView)

import File.Download as Download
import Har
import HarDecoder exposing (harDecoder)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (on)
import Json.Decode as D
import JsonFile exposing (JsonFile, jsonFileDecoder)



-- MODEL


type alias DropFileModel =
    { error : Maybe String
    , fileName : String
    , fileContentString : String
    , fileContent : Maybe Har.Log
    }


defaultDropFileModel : DropFileModel
defaultDropFileModel =
    { error = Nothing
    , fileName = ""
    , fileContentString = ""
    , fileContent = Nothing
    }



-- UPDATE


type DropFileMsg
    = NoOp
    | GotJsonFile JsonFile
    | ReadFileError String
    | DownloadFile


dropFileUpdate : DropFileMsg -> DropFileModel -> ( DropFileModel, Cmd DropFileMsg )
dropFileUpdate msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        GotJsonFile { name, text, json } ->
            let
                res =
                    D.decodeValue harDecoder json
            in
            ( { model
                | fileName = name
                , fileContentString = text
                , fileContent =
                    case res of
                        Ok harFile ->
                            Just harFile.log

                        Err _ ->
                            Nothing
                , error =
                    case res of
                        Ok _ ->
                            Nothing

                        Err _ ->
                            Just <| "Decode file " ++ name ++ " failed"
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
        [ class "drop-file-container"
        , class className
        , on "change" <| D.map (fn << GotJsonFile) <| D.field "detail" jsonFileDecoder
        , on "error" <| D.map (fn << ReadFileError) <| D.field "detail" D.string
        ]
        children
