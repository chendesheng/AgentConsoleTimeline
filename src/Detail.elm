module Detail exposing (DetailModel, DetailMsg(..), defaultDetailModel, detailViewContainer, updateDetail)

import Browser.Dom as Dom
import Har exposing (EntryKind(..))
import Html exposing (..)
import Html.Attributes as Attr exposing (class, property, src, style)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy2)
import Icons
import Iso8601
import Json.Decode as Decode
import Json.Encode as Encode
import List
import String
import Table exposing (isSortByTime)
import Task
import Time
import TokenDecoder exposing (parseToken)
import Url
import Utils



-- MODEL


type DetailTabName
    = Preview
    | Headers
    | Request
    | Response
    | StateChanges


type DetailViewTool
    = Auto
    | JsonTree
    | Raw


type alias DetailTab =
    { name : DetailTabName, label : String }


type alias DetailModel =
    { tab : DetailTabName
    , tool : DetailViewTool
    , show : Bool
    , currentId : String
    }


defaultDetailModel : DetailModel
defaultDetailModel =
    { tab = Preview
    , tool = Auto
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
                    , { name = StateChanges, label = "Changes" }
                    ]

                ReduxAction ->
                    [ { name = Preview, label = "Preview" }
                    , { name = Request, label = "Action" }
                    , { name = Response, label = "Trace" }
                    ]

                LogMessage ->
                    [ { name = Preview, label = "Preview" }
                    ]

                Others ->
                    [ { name = Preview, label = "Preview" }
                    , { name = Response, label = "Content" }
                    ]

                _ ->
                    [ { name = Preview, label = "Preview" }
                    , { name = Headers, label = "Headers" }
                    , { name = Request, label = "Request" }
                    , { name = Response, label = "Response" }
                    ]


jsonViewer : Bool -> String -> String -> Html msg
jsonViewer initialExpanded className json =
    Html.node "json-tree"
        [ class className
        , property "data" <| Encode.string json
        , property "initialExpanded" <| Encode.bool initialExpanded
        ]
        []


codeEditor : String -> String -> Html msg
codeEditor lang content =
    Html.node "monaco-editor"
        [ class "detail-body"
        , property "content" <| Encode.string content
        , property "language" <| Encode.string lang
        ]
        []


jsonDataViewer : DetailViewTool -> Bool -> String -> String -> Html msg
jsonDataViewer tool initialExpanded className json =
    case tool of
        Raw ->
            codeEditor "json" json

        _ ->
            jsonViewer initialExpanded className json


reduxStateViewer : DetailViewTool -> Bool -> List Har.Entry -> String -> String -> String -> Html DetailMsg
reduxStateViewer tool isSortByTime entries href currentId entryId =
    case tool of
        Auto ->
            agentConsoleSnapshot isSortByTime entries href currentId entryId

        JsonTree ->
            case Har.findStateEntryAndPrevStateEntry entries currentId of
                ( _, Just entry, _ ) ->
                    entry
                        |> Har.getReduxState
                        |> Maybe.map (jsonViewer True "detail-body")
                        |> Maybe.withDefault noContent

                _ ->
                    noContent

        _ ->
            case Har.findStateEntryAndPrevStateEntry entries currentId of
                ( _, Just entry, _ ) ->
                    entry
                        |> Har.getReduxState
                        |> Maybe.map (codeEditor "json")
                        |> Maybe.withDefault noContent

                _ ->
                    noContent


agentConsoleSnapshotPlayer : List Har.Entry -> String -> Html DetailMsg
agentConsoleSnapshotPlayer entries initialId =
    let
        stateEntries =
            entries
                |> List.filter Har.isReduxEntry
                |> Har.sortEntries ( "time", Har.Asc )

        firstEntryStartTime =
            Har.getFirstEntryStartTime entries 0

        lastEntryStartTime =
            Utils.getLast stateEntries
                |> Maybe.map .startedDateTime
                |> Maybe.withDefault (Time.millisToPosix 0)
    in
    Html.node "agent-console-snapshot-player"
        [ stateEntries
            |> Encode.list
                (\{ id, startedDateTime } ->
                    Encode.object
                        [ ( "time", Encode.int <| Utils.timespanMillis firstEntryStartTime startedDateTime )
                        , ( "id", Encode.string id )
                        ]
                )
            |> property "items"
        , Attr.max <| String.fromInt <| Utils.timespanMillis firstEntryStartTime lastEntryStartTime
        , property "initialId" <| Encode.string initialId
        , on "change" <|
            Decode.map SetCurrentId <|
                Decode.at [ "detail", "id" ] Decode.string
        , on "scrollToCurrent" <| Decode.succeed ScrollToCurrentId
        ]
        []


agentConsoleSnapshot : Bool -> List Har.Entry -> String -> String -> String -> Html DetailMsg
agentConsoleSnapshot isSortByTime entries href currentId entryId =
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

        ( stateEntry, prevStateEntry, nonStateEntries ) =
            Har.findStateEntryAndPrevStateEntry entries currentId

        actions =
            if isSortByTime && stateEntry == Nothing then
                nonStateEntries
                    |> Har.filterByKind (Just ReduxAction)
                    |> List.map (\e -> Har.getRequestBody e |> Maybe.withDefault "")
                    |> Encode.list Encode.string

            else
                -- pass empty actions when entries are not sorted by time
                -- because when entries are not sorted by time, the states/actions are not in order
                Encode.list (\a -> a) []

        { startedDateTime, state } =
            case stateEntry of
                Just entry ->
                    case Har.getReduxState entry of
                        Just st ->
                            { startedDateTime = entry.startedDateTime, state = st }

                        Nothing ->
                            { startedDateTime = Time.millisToPosix 0, state = "" }

                Nothing ->
                    case prevStateEntry of
                        Just prevEntry ->
                            case Har.getReduxState prevEntry of
                                Just prevSt ->
                                    { startedDateTime = prevEntry.startedDateTime, state = prevSt }

                                Nothing ->
                                    { startedDateTime = Time.millisToPosix 0, state = "" }

                        Nothing ->
                            { startedDateTime = Time.millisToPosix 0, state = "" }

        href2 =
            if String.contains "isSuperAgent=true" href && String.contains "agentconsole.html" href then
                String.replace "agentconsole.html" "superagent.html" href

            else
                href
    in
    div [ class "detail-body", class "agent-console-snapshot-container" ] <|
        Html.node "agent-console-snapshot"
            [ src <| href2 ++ "&snapshot=true"
            , property "state" <| Encode.string state
            , property "time" <| Encode.string <| Iso8601.fromTime startedDateTime
            , property "actions" <| actions
            , Decode.string
                |> Decode.at [ "detail", "value" ]
                |> Decode.map (String.replace "&snapshot=true" "" >> SetHref)
                |> on "srcChange"
            ]
            []
            :: (if showPlayback then
                    [ lazy2 agentConsoleSnapshotPlayer entries entryId ]

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


parseCookies : String -> String
parseCookies text =
    text
        |> String.split ";"
        |> List.map String.trim
        |> List.filter ((/=) "")
        |> List.filterMap
            (\cookie ->
                case String.split "=" cookie of
                    [ name, value ] ->
                        case Url.percentDecode value of
                            Just decoded ->
                                Just ( name, decoded )

                            _ ->
                                Just ( name, value )

                    _ ->
                        Nothing
            )
        |> Encode.list
            (\( name, value ) ->
                Encode.object
                    [ ( "name", Encode.string name )
                    , ( "value", Encode.string value )
                    ]
            )
        |> Encode.encode 0


requestHeaderKeyValue : { x | name : String, value : String } -> Html msg
requestHeaderKeyValue { name, value } =
    keyValue
        { name = name
        , value =
            if String.toLower name == "authorization" then
                div []
                    [ text value
                    , case parseToken value of
                        Ok v ->
                            jsonViewer False "" <| "{\"payload\":" ++ v ++ "}"

                        _ ->
                            text ""
                    ]

            else if String.toLower name == "cookie" then
                div []
                    [ text value
                    , jsonViewer False "" <| "{\"payload\":" ++ parseCookies value ++ "}"
                    ]

            else
                text value
        }


noContent : Html msg
noContent =
    div [ class "detail-body", class "detail-body-empty" ] [ text "No content" ]


styleVar : String -> String -> Attribute msg
styleVar name value =
    property "style" <| Encode.string (name ++ ": " ++ value)


detailViewContainer : Bool -> String -> String -> List Har.Entry -> DetailModel -> Html DetailMsg
detailViewContainer isSortByTime href selected entries detail =
    if detail.show then
        case Utils.findItem (\entry -> entry.id == selected) entries of
            Just entry ->
                detailView isSortByTime entries detail href entry

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
                Headers ->
                    Preview

                StateChanges ->
                    Preview

                _ ->
                    tab

        _ ->
            case tab of
                StateChanges ->
                    Preview

                _ ->
                    tab


viewToolToString : DetailViewTool -> String
viewToolToString tool =
    case tool of
        Auto ->
            "auto"

        JsonTree ->
            "jsonTree"

        Raw ->
            "raw"


stringToViewTool : String -> DetailViewTool
stringToViewTool tool =
    case tool of
        "auto" ->
            Auto

        "jsonTree" ->
            JsonTree

        "raw" ->
            Raw

        _ ->
            Auto


detailViewToolsOptions : List DetailViewTool -> List { value : String, label : String }
detailViewToolsOptions =
    List.map
        (\tool ->
            { value = viewToolToString tool
            , label =
                case tool of
                    Auto ->
                        "Auto"

                    JsonTree ->
                        "JSON Tree"

                    Raw ->
                        "Raw"
            }
        )


detailView : Bool -> List Har.Entry -> DetailModel -> String -> Har.Entry -> Html DetailMsg
detailView isSortByTime entries model href entry =
    let
        selected =
            resolveSelectedTab model.tab entry

        entryKind =
            Har.getEntryKind entry

        tools =
            case selected of
                Preview ->
                    case entryKind of
                        ReduxState ->
                            [ Auto, JsonTree, Raw ]

                        ReduxAction ->
                            [ Auto, JsonTree, Raw ]

                        NetworkHttp ->
                            [ Auto, Raw ]

                        _ ->
                            []

                Headers ->
                    []

                Request ->
                    [ Auto, Raw ]

                Response ->
                    [ Auto, Raw ]

                StateChanges ->
                    []
    in
    section [ class "detail" ]
        [ div [ class "detail-header" ]
            [ button [ class "detail-close", onClick HideDetail ] [ Icons.close ]
            , lazy2 detailTabs selected entry
            , if List.isEmpty tools then
                text ""

              else
                Utils.dropDownList
                    { value = viewToolToString model.tool
                    , onInput = stringToViewTool >> ChangeViewTool
                    }
                    (detailViewToolsOptions tools)
            ]
        , case selected of
            Preview ->
                case entryKind of
                    ReduxState ->
                        reduxStateViewer model.tool isSortByTime entries href model.currentId entry.id

                    ReduxAction ->
                        reduxStateViewer model.tool isSortByTime entries href model.currentId entry.id

                    LogMessage ->
                        entry
                            |> Har.getLogMessage
                            |> Maybe.map (jsonDataViewer model.tool True "detail-body")
                            |> Maybe.withDefault noContent

                    _ ->
                        entry.response.content.text
                            |> Maybe.map (jsonDataViewer model.tool True "detail-body")
                            |> Maybe.withDefault noContent

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
                entry
                    |> Har.getRequestBody
                    |> Maybe.map (jsonDataViewer model.tool True "detail-body")
                    |> Maybe.withDefault noContent

            Response ->
                case entry.response.content.text of
                    Just t ->
                        jsonDataViewer model.tool (entryKind /= ReduxState) "detail-body" t

                    _ ->
                        noContent

            StateChanges ->
                let
                    lang =
                        case entryKind of
                            NetworkHttp ->
                                case Url.fromString entry.request.url of
                                    Just { path } ->
                                        Utils.getLanguage path

                                    _ ->
                                        "json"

                            _ ->
                                "json"
                in
                case Har.getReduxState entry of
                    Just modified ->
                        case Har.findStateEntryAndPrevStateEntry entries entry.id of
                            ( _, Just prevEntry, _ ) ->
                                case Har.getReduxState prevEntry of
                                    Just original ->
                                        Html.node "monaco-diff-editor"
                                            [ class "detail-body"
                                            , property "original" <| Encode.string original
                                            , property "modified" <| Encode.string modified
                                            , property "language" <| Encode.string lang
                                            ]
                                            []

                                    _ ->
                                        text ""

                            _ ->
                                text ""

                    _ ->
                        text ""
        ]



-- UPDATE


type DetailMsg
    = NoOp
    | ChangeDetailTab DetailTabName
    | HideDetail
    | SetCurrentId String
    | SetHref String
    | ScrollToCurrentId
    | ChangeViewTool DetailViewTool


updateDetail : DetailModel -> DetailMsg -> ( DetailModel, Cmd DetailMsg )
updateDetail model detailMsg =
    case detailMsg of
        NoOp ->
            ( model, Cmd.none )

        SetHref _ ->
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

        ChangeViewTool tool ->
            ( { model | tool = tool }, Cmd.none )
