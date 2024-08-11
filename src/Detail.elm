module Detail exposing (DetailModel, DetailMsg(..), defaultDetailModel, detailViewContainer, updateDetail)

import Browser.Dom as Dom
import Har
import Html exposing (..)
import Html.Attributes as Attr exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy2)
import Icons
import Iso8601
import List
import Process
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


type alias PlaybackState =
    { isPlaying : Bool, time : Int }


type alias DetailModel =
    { tab : DetailTabName
    , show : Bool
    , playbackState : PlaybackState
    }


defaultDetailModel : DetailModel
defaultDetailModel =
    { tab = Preview
    , show = False
    , playbackState =
        { isPlaying = False
        , time = 0
        }
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
            if Har.isReduxStateEntry entry then
                [ { name = Preview, label = "Preview" }
                , { name = StateChanges, label = "Changes" }
                , { name = Raw, label = "Raw" }
                ]

            else
                [ { name = Preview, label = "Preview" }
                , { name = Headers, label = "Headers" }
                , { name = Request, label = "Request" }
                , { name = Response, label = "Response" }
                , { name = Raw, label = "Raw" }
                ]


jsonViewer : String -> Html msg
jsonViewer json =
    Html.node "json-viewer" [ class "detail-body", attribute "data" json ] []


agentConsoleSnapshot : List Har.Entry -> PlaybackState -> String -> Har.Entry -> Html PlaybackMsg
agentConsoleSnapshot entries playbackState href entry =
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
                |> List.filter (\e -> Utils.timespanMillis entry.startedDateTime e.startedDateTime <= playbackState.time)
                |> Utils.getLast
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
                    [ div [ class "agent-console-snapshot-player" ]
                        [ if playbackState.isPlaying then
                            button [ onClick Pause ] [ text "❚❚" ]

                          else
                            button [ onClick Play ] [ text "▶" ]
                        , input
                            [ type_ "range"
                            , Attr.min <| String.fromInt <| Utils.timespanMillis entry.startedDateTime firstEntryStartTime
                            , Attr.max <| String.fromInt <| Utils.timespanMillis entry.startedDateTime lastEntryStartTime
                            , Attr.value <| String.fromInt playbackState.time
                            , Attr.step "1"
                            , onInput (Seek << Maybe.withDefault 0 << String.toInt)
                            ]
                            []
                        ]
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
                        , jsonViewer <|
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
    if Har.isReduxStateEntry entry then
        case tab of
            Request ->
                Preview

            Response ->
                Preview

            Headers ->
                Preview

            _ ->
                tab

    else
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
    in
    section [ class "detail" ]
        [ div [ class "detail-header" ]
            [ button [ class "detail-close", onClick HideDetail ] [ Icons.close ]
            , lazy2 detailTabs selected entry
            ]
        , case selected of
            Preview ->
                if Har.isReduxStateEntry entry then
                    Html.map Player <| agentConsoleSnapshot entries model.playbackState href entry

                else
                    jsonViewer <| Maybe.withDefault "" entry.response.content.text

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
                                div [ class "detail-body" ] [ jsonViewer t ]

                            _ ->
                                noContent

                    _ ->
                        noContent

            Response ->
                case entry.response.content.text of
                    Just t ->
                        div [ class "detail-body" ] [ jsonViewer t ]

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
                case entry.response.content.text of
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
    | Player PlaybackMsg


type PlaybackMsg
    = Play
    | Pause
    | Tick
    | Seek Int


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

        Player playbackMsg ->
            let
                ( state, cmd ) =
                    updatePlaybackState playbackMsg model.playbackState
            in
            ( { model | playbackState = state }, Cmd.map Player cmd )


updatePlaybackState : PlaybackMsg -> PlaybackState -> ( PlaybackState, Cmd PlaybackMsg )
updatePlaybackState msg playbackState =
    case msg of
        Play ->
            if playbackState.isPlaying then
                ( playbackState, Cmd.none )

            else
                ( { playbackState | isPlaying = True }, Task.perform (\_ -> Tick) (Process.sleep 20) )

        Pause ->
            if playbackState.isPlaying then
                ( { playbackState | isPlaying = False }, Cmd.none )

            else
                ( playbackState, Cmd.none )

        Tick ->
            if playbackState.isPlaying then
                ( { playbackState | time = playbackState.time + 20 }, Task.perform (\_ -> Tick) (Process.sleep 20) )

            else
                ( playbackState, Cmd.none )

        Seek time ->
            ( { playbackState | time = time }, Cmd.none )
