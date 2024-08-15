module Detail exposing (DetailModel, DetailMsg(..), defaultDetailModel, detailViewContainer, updateDetail)

import Browser.Dom as Dom
import Har exposing (EntryKind(..))
import Html exposing (..)
import Html.Attributes as Attr exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy2)
import Icons
import Iso8601
import Json.Decode as Decode
import Json.Encode as Encode
import List
import String
import Task
import TokenDecoder exposing (parseToken)
import Utils



-- MODEL


type DetailTabName
    = Preview
    | Headers
    | Request
    | Response
    | StateChanges
    | Raw


type alias DetailTab =
    { name : DetailTabName, label : String }


type alias DetailModel =
    { tab : DetailTabName
    , show : Bool
    , currentId : String
    }


defaultDetailModel : DetailModel
defaultDetailModel =
    { tab = Preview
    , show = False
    , currentId = ""
    }



-- VIEW


detailTab : DetailTabName -> DetailTab -> Html DetailMsg
detailTab selected { name, label } =
    button
        [ class "detail-header-tab"
        , class <|
            if name == selected then
                "selected"

            else
                ""
        , onClick (ChangeDetailTab name)
        ]
        [ text label ]


detailTabs : DetailTabName -> Har.Entry -> Html DetailMsg
detailTabs selected entry =
    div [ class "detail-header-tabs" ] <|
        List.map (detailTab selected) <|
            case Har.getEntryKind entry of
                ReduxState ->
                    [ { name = Preview, label = "Preview" }
                    , { name = Response, label = "State" }
                    , { name = StateChanges, label = "Changes" }
                    , { name = Raw, label = "Raw" }
                    ]

                ReduxAction ->
                    [ { name = Preview, label = "Preview" }
                    , { name = Response, label = "Trace" }
                    , { name = Raw, label = "Raw" }
                    ]

                LogMessage ->
                    [ { name = Preview, label = "Preview" }
                    , { name = Response, label = "Message" }
                    , { name = Raw, label = "Raw" }
                    ]

                Others ->
                    [ { name = Preview, label = "Preview" }
                    , { name = Response, label = "Content" }
                    , { name = Raw, label = "Raw" }
                    ]

                _ ->
                    [ { name = Preview, label = "Preview" }
                    , { name = Headers, label = "Headers" }
                    , { name = Request, label = "Request" }
                    , { name = Response, label = "Response" }
                    , { name = Raw, label = "Raw" }
                    ]


jsonViewer : Bool -> String -> String -> Html msg
jsonViewer initialExpanded className json =
    Html.node "json-tree"
        ([ class className
         , attribute "data" json
         ]
            ++ (if initialExpanded then
                    [ attribute "initial-expanded" "" ]

                else
                    []
               )
        )
        []


agentConsoleSnapshot : List Har.Entry -> String -> String -> Har.Entry -> Html DetailMsg
agentConsoleSnapshot entries href currentId entry =
    let
        stateEntries =
            entries
                |> Har.filterEntries "" (Just Har.ReduxState)
                |> Har.sortEntries ( "time", Har.Asc )

        showPlayback =
            case stateEntries of
                [] ->
                    False

                [ _ ] ->
                    False

                _ ->
                    True

        firstEntryStartTime =
            Har.getFirstEntryStartTime entries 0

        lastEntry =
            Utils.getLast stateEntries
                |> Maybe.withDefault entry

        lastEntryStartTime =
            lastEntry.startedDateTime

        entry1 =
            stateEntries
                |> Utils.findItem (\e -> e.id == currentId)
                |> Maybe.withDefault lastEntry

        state =
            Har.getReduxState entry1
                |> Maybe.withDefault ""
    in
    div [ class "detail-body", class "agent-console-snapshot-container" ] <|
        Html.node "agent-console-snapshot"
            [ src <| href ++ "&snapshot=true"
            , attribute "state" state
            , attribute "time" <| Iso8601.fromTime entry1.startedDateTime
            ]
            []
            :: (if showPlayback then
                    [ Html.node "agent-console-snapshot-player"
                        [ stateEntries
                            |> List.map
                                (\{ id, startedDateTime } ->
                                    Encode.object
                                        [ ( "time", Encode.int <| Utils.timespanMillis firstEntryStartTime startedDateTime )
                                        , ( "id", Encode.string id )
                                        ]
                                )
                            |> Encode.list (\a -> a)
                            |> Encode.encode 0
                            |> attribute "items"
                        , Attr.min <| String.fromInt 0
                        , Attr.max <| String.fromInt <| Utils.timespanMillis firstEntryStartTime lastEntryStartTime
                        , attribute "initialTime" <|
                            String.fromInt <|
                                Utils.timespanMillis firstEntryStartTime entry.startedDateTime
                        , on "timeChange" <|
                            Decode.map SetCurrentId <|
                                Decode.at [ "detail", "id" ] Decode.string
                        , on "scrollToCurrent" <| Decode.succeed ScrollToCurrentId
                        ]
                        []
                    ]

                else
                    []
               )


keyValue : { x | name : String, value : Html msg } -> Html msg
keyValue { name, value } =
    let
        name1 =
            if String.endsWith ":" name then
                name

            else
                name ++ ":"
    in
    div [ class "detail-body-header-item" ]
        [ span
            [ style "color" "var(--color)"
            , class "detail-body-header-key"
            ]
            [ text name1 ]
        , span [ class "detail-body-header-value" ] [ value ]
        ]


keyValueText : { x | name : String, value : String } -> Html msg
keyValueText { name, value } =
    keyValue { name = name, value = text value }


requestHeaderKeyValue : { x | name : String, value : String } -> Html msg
requestHeaderKeyValue { name, value } =
    if name == "Authorization" then
        div []
            [ keyValue
                { name = name
                , value =
                    div []
                        [ text value
                        , jsonViewer False "" <|
                            "{\"payload\":"
                                ++ (Result.withDefault "" <| parseToken value)
                                ++ "}"
                        ]
                }
            ]

    else
        keyValueText { name = name, value = value }


noContent : Html msg
noContent =
    div [ class "detail-body", class "detail-body-empty" ] [ text "No content" ]


styleVar : String -> String -> Attribute msg
styleVar name value =
    attribute "style" (name ++ ": " ++ value)


detailViewContainer : String -> String -> List Har.Entry -> DetailModel -> Html DetailMsg
detailViewContainer href selected entries detail =
    if detail.show then
        case Har.findEntryAndPrevStateEntry entries selected of
            ( Just entry, prevStateEntry ) ->
                detailView entries detail href entry prevStateEntry

            _ ->
                text ""

    else
        text ""


resolveSelectedTab : DetailTabName -> Har.Entry -> DetailTabName
resolveSelectedTab tab entry =
    case Har.getEntryKind entry of
        ReduxState ->
            case tab of
                Request ->
                    Preview

                Headers ->
                    Preview

                _ ->
                    tab

        ReduxAction ->
            case tab of
                Request ->
                    Preview

                Headers ->
                    Preview

                _ ->
                    tab

        _ ->
            case tab of
                StateChanges ->
                    Preview

                _ ->
                    tab


detailView : List Har.Entry -> DetailModel -> String -> Har.Entry -> Maybe Har.Entry -> Html DetailMsg
detailView entries model href entry prevStateEntry =
    let
        selected =
            resolveSelectedTab model.tab entry

        entryKind =
            Har.getEntryKind entry
    in
    section [ class "detail" ]
        [ div [ class "detail-header" ]
            [ button [ class "detail-close", onClick HideDetail ] [ Icons.close ]
            , lazy2 detailTabs selected entry
            ]
        , case selected of
            Preview ->
                case entryKind of
                    ReduxState ->
                        agentConsoleSnapshot entries href model.currentId entry

                    ReduxAction ->
                        jsonViewer True "detail-body" <| Maybe.withDefault "" <| Har.getRequestBody entry

                    _ ->
                        jsonViewer True "detail-body" <| Maybe.withDefault "" entry.response.content.text

            Headers ->
                div
                    [ class "detail-body", class "detail-body-headers-container" ]
                    [ h3 [] [ text "Summary" ]
                    , div [ styleVar "--color" "var(--network-system-color)", class "detail-body-headers" ]
                        [ keyValueText { name = "URL", value = entry.request.url }
                        , keyValueText { name = "Method", value = String.toUpper entry.request.method }
                        , keyValueText { name = "Status", value = String.fromInt entry.response.status }
                        , keyValueText { name = "Address", value = Maybe.withDefault "" entry.serverIPAddress }
                        ]
                    , h3 [] [ text "Request Headers" ]
                    , div
                        [ styleVar "--color" "var(--network-header-color)"
                        , class "detail-body-headers"
                        ]
                        (List.map requestHeaderKeyValue entry.request.headers)
                    , h3 [] [ text "Response Headers" ]
                    , div
                        [ styleVar "--color" "var(--network-header-color)"
                        , class "detail-body-headers"
                        ]
                        (List.map keyValueText entry.response.headers)
                    , h3 [] [ text "Query String Parameters" ]
                    , div
                        [ styleVar "--color" "var(--text-color-tertiary)"
                        , class "detail-body-headers"
                        ]
                        (List.map keyValueText entry.request.queryString)
                    ]

            Request ->
                case entry.request.postData of
                    Just postData ->
                        case postData.text of
                            Just t ->
                                jsonViewer True "detail-body" t

                            _ ->
                                noContent

                    _ ->
                        noContent

            Response ->
                case entry.response.content.text of
                    Just t ->
                        jsonViewer (entryKind /= ReduxState) "detail-body" t

                    _ ->
                        noContent

            StateChanges ->
                case Har.getReduxState entry of
                    Just modified ->
                        case prevStateEntry of
                            Just prevEntry ->
                                case Har.getReduxState prevEntry of
                                    Just original ->
                                        Html.node "monaco-diff-editor"
                                            [ class "detail-body"
                                            , attribute "original" original
                                            , attribute "modified" modified
                                            ]
                                            []

                                    _ ->
                                        text ""

                            _ ->
                                text ""

                    _ ->
                        text ""

            Raw ->
                let
                    txt =
                        case entryKind of
                            ReduxAction ->
                                Har.getRequestBody entry

                            _ ->
                                entry.response.content.text
                in
                case txt of
                    Just t ->
                        Html.node "monaco-editor" [ class "detail-body", attribute "content" t ] []

                    _ ->
                        noContent
        ]



-- UPDATE


type DetailMsg
    = NoOp
    | ChangeDetailTab DetailTabName
    | HideDetail
    | SetCurrentId String
    | ScrollToCurrentId


updateDetail : DetailModel -> DetailMsg -> ( DetailModel, Cmd DetailMsg )
updateDetail model detailMsg =
    case detailMsg of
        NoOp ->
            ( model, Cmd.none )

        ChangeDetailTab tab ->
            ( { model | tab = tab }, Cmd.none )

        HideDetail ->
            ( { model | show = False }
            , Task.attempt (\_ -> NoOp) <| Dom.focus "table-body"
            )

        SetCurrentId id ->
            ( { model | currentId = id }, Cmd.none )

        ScrollToCurrentId ->
            ( model, Cmd.none )
