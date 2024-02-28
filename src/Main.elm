module Main exposing (main)

import Browser
import File exposing (File)
import File.Select as Select
import Har
import HarDecoder exposing (harDecoder)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Icons
import Json.Decode as D
import List exposing (sortBy)
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
    | Opened OpenedModel


type alias OpenedModel =
    { log : Har.Log
    , table : TableModel
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Initial defaultInitialModel, Cmd.none )



-- UPDATE


type Msg
    = InitialMsg InitialMsg
    | OpenedMsg OpenedMsg


type InitialMsg
    = Pick
    | DragEnter
    | DragLeave
    | GotFile File
    | GotFileContent String


type OpenedMsg
    = TableAction TableAction


type SortOrder
    = Asc
    | Desc


type alias SortBy =
    ( String, SortOrder )


flipSortOrder : SortOrder -> SortOrder
flipSortOrder sortOrder =
    case sortOrder of
        Asc ->
            Desc

        Desc ->
            Asc


type TableAction
    = FlipSort String


type alias TableModel =
    { sortBy : SortBy
    , columns : List String
    , entries : List Har.Entry
    }


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
                                    ( Opened
                                        { log = log
                                        , table =
                                            { sortBy = ( "url", Asc )
                                            , columns = [ "url", "status" ]
                                            , entries = log.entries
                                            }
                                        }
                                    , Cmd.none
                                    )

                                _ ->
                                    ( Initial newModel, Cmd.map InitialMsg cmd )

                _ ->
                    ( model, Cmd.none )

        OpenedMsg openedMsg ->
            case model of
                Opened openedModel ->
                    case updateOpened openedMsg openedModel of
                        newOpenedModel ->
                            ( Opened newOpenedModel, Cmd.none )

                _ ->
                    ( model, Cmd.none )


compareEntry : String -> Har.Entry -> Har.Entry -> Order
compareEntry column a b =
    case column of
        "url" ->
            compareString a.request.url b.request.url

        "status" ->
            compareInt a.response.status b.response.status

        _ ->
            EQ


compareInt : Int -> Int -> Order
compareInt a b =
    if a < b then
        LT

    else if a > b then
        GT

    else
        EQ


compareString : String -> String -> Order
compareString a b =
    if a < b then
        LT

    else if a > b then
        GT

    else
        EQ


sortEntries : SortBy -> List Har.Entry -> List Har.Entry
sortEntries ( column, sortOrder ) =
    List.sortWith
        (\a b ->
            let
                order =
                    compareEntry column a b
            in
            case order of
                EQ ->
                    EQ

                LT ->
                    case sortOrder of
                        Asc ->
                            LT

                        Desc ->
                            GT

                GT ->
                    case sortOrder of
                        Asc ->
                            GT

                        Desc ->
                            LT
        )


updateOpened : OpenedMsg -> OpenedModel -> OpenedModel
updateOpened msg model =
    case msg of
        TableAction action ->
            case action of
                FlipSort column ->
                    let
                        table =
                            model.table

                        ( currentSortColumn, currentSortOrder ) =
                            table.sortBy

                        newSortBy =
                            if currentSortColumn == column then
                                ( column, flipSortOrder currentSortOrder )

                            else
                                ( column, Asc )

                        newEntries =
                            sortEntries newSortBy table.entries
                    in
                    { model | table = { table | sortBy = newSortBy, entries = newEntries } }


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
                    let
                        entries =
                            List.sortBy (\entry -> entry.startedDateTime) log.entries
                    in
                    { model | fileContent = Just { log | entries = entries } }

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


tableCellView : String -> Har.Entry -> Html msg
tableCellView column entry =
    case column of
        "url" ->
            text entry.request.url

        "status" ->
            text <| String.fromInt entry.response.status

        _ ->
            text ""


entryView : List String -> Har.Entry -> Html msg
entryView columns entry =
    tr [] <|
        List.map (\column -> td [] <| [ tableCellView column entry ]) columns


tableSortIcon : SortOrder -> Html msg
tableSortIcon sortOrder =
    case sortOrder of
        Asc ->
            Icons.sortAsc

        Desc ->
            Icons.sortDesc


tableHeaderCell : SortBy -> String -> Html TableAction
tableHeaderCell ( sortColumn, sortOrder ) column =
    let
        label =
            getColumnLabel column
    in
    th [ onClick (FlipSort column) ]
        [ div [ class "table-header" ]
            [ text label
            , if column == sortColumn then
                tableSortIcon sortOrder

              else
                div [] []
            ]
        ]


getColumnLabel : String -> String
getColumnLabel column =
    case column of
        "url" ->
            "URL"

        "status" ->
            "Status"

        _ ->
            column


tableView : TableModel -> Html TableAction
tableView { entries, sortBy, columns } =
    table [ class "main-table" ]
        [ thead []
            [ tr [] <|
                List.map (tableHeaderCell sortBy) columns
            ]
        , tbody [] <|
            List.map (entryView columns) entries
        ]


viewOpened : OpenedModel -> Html OpenedMsg
viewOpened { log, table } =
    Html.map TableAction (tableView table)


externalCss : String -> Html msg
externalCss url =
    Html.node "link" [ rel "stylesheet", href url ] []


view : Model -> Html Msg
view model =
    div [ class "app" ]
        [ externalCss "./assets/css/normalize.css"
        , externalCss "./assets/css/app.css"
        , externalCss "./assets/css/table.css"
        , externalCss "./assets/css/icons.css"
        , case model of
            Initial initialModel ->
                Html.map InitialMsg (initialView initialModel)

            Opened log ->
                Html.map OpenedMsg (viewOpened log)
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
