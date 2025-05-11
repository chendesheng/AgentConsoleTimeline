module Detail exposing (DetailModel, DetailMsg(..), defaultDetailModel, detailViewContainer, updateDetail)

import Browser.Dom as Dom
import Har exposing (EntryKind(..))
import Html exposing (..)
import Html.Attributes as Attr exposing (class, property, src, srcdoc, style)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy2, lazy4)
import Icons
import Iso8601
import Json.Decode as Decode
import Json.Encode as Encode
import List
import String
import Table exposing (TableFilter, isSortByTime)
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
    , snapshotPopout : Bool
    }


defaultDetailModel : DetailModel
defaultDetailModel =
    { tab = Preview
    , tool = Auto
    , show = False
    , currentId = ""
    , snapshotPopout = False
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


htmlViewer : String -> Html msg
htmlViewer html =
    let
        -- FIXME: decodeString here is wired
        s =
            html
                |> Decode.decodeString Decode.string
                |> Result.withDefault ""
    in
    iframe [ class "preview", srcdoc s ] []


svgViewer : String -> Html msg
svgViewer svg =
    iframe
        [ class "preview-svg"
        , srcdoc
            ("<style>"
                ++ "html,body{margin:0;padding:0;width:100%;height:100%;}"
                ++ "body{display:flex;justify-content:center;align-items:center;}"
                ++ "svg{max-width:100%;max-height:100%;margin:auto;}"
                ++ "</style>"
                ++ svg
            )
        ]
        []


jsonDataViewer : DetailViewTool -> Bool -> String -> String -> Html msg
jsonDataViewer tool initialExpanded className json =
    case tool of
        Raw ->
            codeEditor "json" json

        _ ->
            jsonViewer initialExpanded className json


reduxStateViewer : Bool -> DetailViewTool -> Bool -> List Har.Entry -> String -> String -> String -> String -> Maybe String -> Html DetailMsg
reduxStateViewer liveSession tool isSortByTime entries href pageName currentId entryId highlightVisitorId =
    case tool of
        Auto ->
            agentConsoleSnapshot liveSession isSortByTime entries href pageName currentId entryId highlightVisitorId

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


agentConsoleSnapshotPlayer : Bool -> List Har.Entry -> String -> Maybe String -> Html DetailMsg
agentConsoleSnapshotPlayer liveSession entries initialId highlightVisitorId =
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
                (\{ id, startedDateTime, comment } ->
                    Encode.object
                        [ ( "time", Encode.int <| Utils.timespanMillis firstEntryStartTime startedDateTime )
                        , ( "id", Encode.string id )
                        , ( "comment", Encode.string <| Maybe.withDefault "" comment )
                        ]
                )
            |> property "items"
        , Attr.max <| String.fromInt <| Utils.timespanMillis firstEntryStartTime lastEntryStartTime
        , property "initialId" <| Encode.string initialId
        , property "allowLive" <| Encode.bool liveSession
        , property "highlightVisitorId" <| Encode.string <| Maybe.withDefault "" <| highlightVisitorId
        , on "change" <|
            Decode.map SetCurrentId <|
                Decode.at [ "detail", "id" ] Decode.string
        , on "scrollToCurrent" <| Decode.succeed ScrollToCurrentId
        ]
        []


agentConsoleSnapshotProps : Bool -> String -> String -> List Har.Entry -> String -> List (Html.Attribute msg)
agentConsoleSnapshotProps isSortByTime href pageName entries currentId =
    let
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

        ( startedDateTime, state ) =
            case stateEntry of
                Just entry ->
                    case Har.getReduxState entry of
                        Just st ->
                            ( entry.startedDateTime, st )

                        Nothing ->
                            ( Time.millisToPosix 0, "" )

                Nothing ->
                    case prevStateEntry of
                        Just prevEntry ->
                            case Har.getReduxState prevEntry of
                                Just prevSt ->
                                    ( prevEntry.startedDateTime, prevSt )

                                Nothing ->
                                    ( Time.millisToPosix 0, "" )

                        Nothing ->
                            ( Time.millisToPosix 0, "" )
    in
    [ property "state" <| Encode.string state
    , property "time" <| Encode.string <| Iso8601.fromTime startedDateTime
    , property "actions" <| actions
    , src href
    , property "pageName" <| Encode.string pageName
    ]


agentConsoleSnapshotPopout : Bool -> String -> String -> List Har.Entry -> String -> Html DetailMsg
agentConsoleSnapshotPopout isSortByTime href pageName entries currentId =
    agentConsoleSnapshotFrame True isSortByTime href pageName entries currentId


agentConsoleSnapshotFrame : Bool -> Bool -> String -> String -> List Har.Entry -> String -> Html DetailMsg
agentConsoleSnapshotFrame isSnapshotPopout isSortByTime href pageName entries currentId =
    Html.node "agent-console-snapshot-frame"
        ((property "isPopout" <| Encode.bool isSnapshotPopout)
            :: agentConsoleSnapshotProps isSortByTime href pageName entries currentId
        )
        []


agentConsoleSnapshot : Bool -> Bool -> List Har.Entry -> String -> String -> String -> String -> Maybe String -> Html DetailMsg
agentConsoleSnapshot liveSession isSortByTime entries href pageName currentId entryId highlightVisitorId =
    div [ class "detail-body", class "agent-console-snapshot-container" ]
        [ Html.node "agent-console-snapshot"
            ([ Decode.string
                |> Decode.at [ "detail", "value" ]
                |> Decode.map (String.replace "&snapshot=true" "" >> SetHref)
                |> on "srcChange"
             , Decode.bool
                |> Decode.at [ "detail", "value" ]
                |> Decode.map SetSnapshotPopout
                |> on "popout"
             ]
                ++ agentConsoleSnapshotProps isSortByTime href pageName entries currentId
            )
            []
        , lazy4 agentConsoleSnapshotPlayer liveSession entries entryId highlightVisitorId
        ]


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


detailViewContainer : Bool -> Bool -> Bool -> String -> TableFilter -> String -> List Har.Entry -> DetailModel -> Html DetailMsg
detailViewContainer liveSession isSnapshotPopout isSortByTime href filter selected entries detail =
    if detail.show then
        case Utils.findItem (\entry -> entry.id == selected) entries of
            Just entry ->
                detailView liveSession isSnapshotPopout isSortByTime entries detail href filter.page filter.highlightVisitorId entry

            _ ->
                text ""

    else if isSnapshotPopout then
        agentConsoleSnapshotPopout isSortByTime href filter.page entries detail.currentId

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


detailView : Bool -> Bool -> Bool -> List Har.Entry -> DetailModel -> String -> String -> Maybe String -> Har.Entry -> Html DetailMsg
detailView liveSession isSnapshotPopout isSortByTime entries model href pageName highlightVisitorId entry =
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
        , div [ style "display" "none" ] <|
            if isSnapshotPopout then
                [ agentConsoleSnapshotPopout isSortByTime href pageName entries model.currentId ]

            else
                []
        , case selected of
            Preview ->
                case entryKind of
                    ReduxState ->
                        reduxStateViewer liveSession model.tool isSortByTime entries href pageName model.currentId entry.id highlightVisitorId

                    ReduxAction ->
                        reduxStateViewer liveSession model.tool isSortByTime entries href pageName model.currentId entry.id highlightVisitorId

                    LogMessage ->
                        entry
                            |> Har.getLogMessage
                            |> Maybe.map (jsonDataViewer model.tool True "detail-body")
                            |> Maybe.withDefault noContent

                    _ ->
                        case entry.response.content.text of
                            Just t ->
                                case entry.response.content.mimeType of
                                    "image/svg+xml" ->
                                        case model.tool of
                                            Raw ->
                                                codeEditor "html" t

                                            _ ->
                                                svgViewer t

                                    "image/jpeg" ->
                                        img [ class "preview-image", src <| "data:image/jpeg;base64," ++ t ] []

                                    "image/png" ->
                                        img [ class "preview-image", src <| "data:image/png;base64," ++ t ] []

                                    "text/javascript" ->
                                        codeEditor "javascript" t

                                    "text/css" ->
                                        codeEditor "css" t

                                    "text/html" ->
                                        case model.tool of
                                            Raw ->
                                                codeEditor "html" t

                                            _ ->
                                                htmlViewer t

                                    _ ->
                                        jsonDataViewer model.tool True "detail-body" t

                            _ ->
                                noContent

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
    | SetSnapshotPopout Bool


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

        SetSnapshotPopout isPopout ->
            ( { model | snapshotPopout = isPopout }, Cmd.none )
