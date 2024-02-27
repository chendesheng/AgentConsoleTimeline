module Main exposing (main)

import Browser
import File exposing (File)
import File.Select as Select
import Har
import HarDecoder exposing (harDecoder)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Task



-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



-- MODEL


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


type Model
    = Initial InitialModel
    | Opened Har.Log


init : () -> ( Model, Cmd Msg )
init _ =
    ( Initial defaultInitialModel, Cmd.none )



-- UPDATE


type Msg
    = InitialMsg InitialMsg


type InitialMsg
    = Pick
    | DragEnter
    | DragLeave
    | GotFile File
    | GotFileContent String


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
                                    ( Opened log, Cmd.none )

                                _ ->
                                    ( Initial newModel, Cmd.map InitialMsg cmd )

                _ ->
                    ( model, Cmd.none )


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
            ( { model
                | hover = False
              }
            , Task.perform GotFileContent (File.toString file)
            )

        GotFileContent content ->
            ( case D.decodeString harDecoder content of
                Ok { log } ->
                    { model | fileContent = Just log }

                Err err ->
                    { model | error = Just <| D.errorToString err }
            , Cmd.none
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


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
        , span [ style "color" "#ccc" ] [ text (Debug.toString model) ]
        , span [ style "color" "red" ] [ text <| Maybe.withDefault "" model.error ]
        ]


entryView : Har.Entry -> Html msg
entryView entry =
    tr [] <|
        [ td [] <| [ text entry.request.url ]
        , td [] <| [ text (String.fromInt entry.response.status) ]
        ]


tableHeaderCell : String -> Html msg
tableHeaderCell s =
    th []
        [ text s
        , div [] []
        ]


viewOpened : Har.Log -> Html msg
viewOpened log =
    table [ class "main-table" ]
        [ thead []
            [ tr []
                [ tableHeaderCell "URL"
                , tableHeaderCell "Status"
                ]
            ]
        , tbody [] <|
            List.map entryView log.entries
        ]


externalCss : String -> Html msg
externalCss url =
    Html.node "link" [ rel "stylesheet", href url ] []


view : Model -> Html Msg
view model =
    div []
        [ externalCss "./assets/css/normalize.css"
        , externalCss "./assets/css/table.css"
        , externalCss "./assets/css/icon.css"
        , case model of
            Initial initialModel ->
                Html.map InitialMsg (initialView initialModel)

            Opened log ->
                viewOpened log
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
