module Initial exposing (..)

import Detail exposing (DetailMsg(..), DetailTabName(..))
import File exposing (File)
import File.Select as Select
import Har
import HarDecoder exposing (harDecoder)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import List
import Task
import Time


type alias InitialModel =
    { hover : Bool
    , error : Maybe String
    , fileContent : Maybe Har.Log
    }


defaultInitialModel : InitialModel
defaultInitialModel =
    { hover = False
    , error = Nothing
    , fileContent = Nothing
    }


type InitialMsg
    = Pick
    | DragEnter
    | DragLeave
    | GotFile File
    | GotFileContent String


initialView : InitialModel -> Html InitialMsg
initialView model =
    div
        [ style "border"
            (if model.hover then
                "6px dashed purple"

             else
                "6px dashed #ccc"
            )
        , style "border-radius" "20px"
        , style "width" "480px"
        , style "height" "100px"
        , style "margin" "100px auto"
        , style "padding" "20px"
        , style "display" "flex"
        , style "flex-direction" "column"
        , style "justify-content" "center"
        , style "align-items" "center"
        , hijackOn "dragenter" (D.succeed DragEnter)
        , hijackOn "dragover" (D.succeed DragEnter)
        , hijackOn "dragleave" (D.succeed DragLeave)
        , hijackOn "drop" dropDecoder
        ]
        [ button [ onClick Pick ] [ text "Open Dump File" ]
        , span [ style "color" "red" ] [ text <| Maybe.withDefault "" model.error ]
        ]


dropDecoder : D.Decoder InitialMsg
dropDecoder =
    D.at [ "dataTransfer", "files" ] (D.oneOrMore (\f _ -> GotFile f) File.decoder)


hijackOn : String -> D.Decoder msg -> Attribute msg
hijackOn event decoder =
    preventDefaultOn event (D.map hijack decoder)


hijack : msg -> ( msg, Bool )
hijack msg =
    ( msg, True )


updateInitial : InitialMsg -> InitialModel -> ( InitialModel, Cmd InitialMsg )
updateInitial msg model =
    case msg of
        Pick ->
            ( model
            , Select.file [ "*" ] GotFile
            )

        DragEnter ->
            ( { model | hover = True }
            , Cmd.none
            )

        DragLeave ->
            ( { model | hover = False }
            , Cmd.none
            )

        GotFile file ->
            ( { model | hover = False }
            , Task.perform GotFileContent (File.toString file)
            )

        GotFileContent content ->
            ( case D.decodeString harDecoder content of
                Ok { log } ->
                    let
                        entries =
                            List.sortBy (\entry -> Time.posixToMillis entry.startedDateTime) log.entries
                    in
                    { model | fileContent = Just { log | entries = entries } }

                Err err ->
                    { model | error = Just <| D.errorToString err }
            , Cmd.none
            )
