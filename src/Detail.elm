module Detail exposing (DetailModel, DetailMsg(..), defaultDetailModel, detailViewContainer, updateDetail)

import Browser.Dom as Dom
import Har exposing (EntryKind(..))
import Html exposing (..)
import Html.Attributes as Attr exposing (attribute, class, property, src, srcdoc, style)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy, lazy2, lazy3, lazy4, lazy5)
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
    , quickPreview : Maybe { id : String, clientX : Float }
    , snapshotPopout : Bool
    }


defaultDetailModel : DetailModel
defaultDetailModel =
    { tab = Preview
    , tool = Auto
    , show = False
    , currentId = ""
    , quickPreview = Nothing
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


detailTabsByEntryKind : EntryKind -> List DetailTab
detailTabsByEntryKind entryKind =
    case entryKind of
        ReduxState ->
            [ { name = Preview, label = "Preview" }
            , { name = Request, label = "Changes" }
            , { name = Response, label = "Content" }
            ]

        ReduxAction ->
            [ { name = Preview, label = "Preview" }
            , { name = Request, label = "Action" }
            , { name = Response, label = "Trace" }
            ]

        NetworkHttp ->
            [ { name = Preview, label = "Preview" }
            , { name = Headers, label = "Headers" }
            , { name = Request, label = "Request" }
            , { name = Response, label = "Response" }
            ]

        LogMessage ->
            [ { name = Preview, label = "Preview" }
            , { name = Response, label = "Content" }
            ]

        Others ->
            [ { name = Preview, label = "Preview" }
            , { name = Response, label = "Content" }
            ]


detailTabs : DetailTabName -> Har.Entry -> Html DetailMsg
detailTabs selected entry =
    div [ class "detail-header-tabs" ] <|
        List.map (detailTab selected) <|
            detailTabsByEntryKind (Har.getEntryKind entry)


jsonViewer : Bool -> String -> String -> Html msg
jsonViewer initialExpanded className json =
    Html.node "json-tree"
        [ class className
        , property "data" <| Encode.string json
        , property "initialExpanded" <| Encode.bool initialExpanded
        ]
        []


imageViewer : String -> String -> Html msg
imageViewer image mimeType =
    img [ class "preview-image", src <| "data:" ++ mimeType ++ ";base64," ++ image ] []


codeEditor : String -> Bool -> String -> Html msg
codeEditor lang format content =
    Html.node "monaco-editor"
        [ class "detail-body"
        , property "content" <| Encode.string content
        , property "language" <| Encode.string lang
        , property "format" <| Encode.bool format
        ]
        []


codeDiffEditor : String -> String -> String -> Html msg
codeDiffEditor lang original modified =
    Html.node "monaco-diff-editor"
        [ class "detail-body"
        , property "original" <| Encode.string original
        , property "modified" <| Encode.string modified
        , property "language" <| Encode.string lang
        ]
        []


hexEditor : String -> Html msg
hexEditor content =
    Html.node "hex-editor"
        [ class "detail-body"
        , property "data" <| Encode.string content
        ]
        []


htmlViewer : String -> Html msg
htmlViewer html =
    let
        -- FIXME: decodeString here is wired
        s =
            html
                |> Decode.decodeString Decode.string
                |> Result.withDefault html
    in
    iframe [ class "preview", srcdoc s ] []


pdfViewer : String -> String -> Html msg
pdfViewer html url =
    iframe
        [ class "preview"
        , srcdoc <|
            "<html><head><script>"
                ++ "window.onload = function() {"
                ++ "   document.body.innerHTML = window.atob(\""
                ++ html
                ++ "\").replace('about:blank', '"
                ++ url
                ++ "');"
                ++ "}"
                ++ "</script></head><body></body></html>"
        ]
        []


audioViewer : String -> String -> String -> Html msg
audioViewer mime id audio =
    -- use keyed node to recreate audio element when id changed, otherwise we need call the .load method which is not supported in elm
    Keyed.node "div"
        [ class "detail-body audio" ]
        [ ( id
          , Html.audio
                [ Attr.controls True
                , Attr.autoplay False
                , attribute "autobuffer" "autobuffer"
                ]
                [ Html.source [ src ("data:" ++ mime ++ ";base64," ++ audio) ] []
                ]
          )
        ]


fontViewer : String -> String -> Html msg
fontViewer font format =
    iframe
        [ class "preview"
        , srcdoc
            ("<style>"
                ++ "@font-face{font-family: preview;src: url(data:application/x-font-"
                ++ format
                ++ ";charset=utf-8;base64,"
                ++ font
                ++ ") format('"
                ++ format
                ++ "');}"
                ++ "html,body{margin:0;padding:0;width:100%;height:100%;}"
                ++ "body{text-align:center;white-space:wrap;display:flex;flex-direction:column;justify-content:center;}"
                ++ "p{font-family:preview;font-size:50px;word-break:break-all;margin:0;}"
                ++ "</style>"
                ++ "<body>"
                ++ "<p>ABCDEFGHIJKLM</p>"
                ++ "<p>NOPQRSTUVWXYZ</p>"
                ++ "<p>abcdefghijklm</p>"
                ++ "<p>nopqrstuvwxyz</p>"
                ++ "<p>1234567890</p>"
                ++ "</body>"
            )
        ]
        []


svgViewer : String -> Html msg
svgViewer svg =
    iframe
        [ class "preview-svg"
        , srcdoc
            ("<style>"
                ++ "html,body{margin:0;padding:0;width:100%;height:100%;color-scheme: dark;}"
                ++ "body{display:flex;justify-content:center;align-items:center;}"
                -- safari browser need min-width 100%, otherwise some svg with no width will be too small
                ++ "svg{max-width:100%;max-height:100%;margin:auto;min-width:100%;}"
                ++ "</style>"
                ++ svg
            )
        ]
        []


jsonDataViewer : DetailViewTool -> Bool -> Bool -> String -> String -> Html msg
jsonDataViewer tool initialExpanded format className json =
    case tool of
        Raw ->
            codeEditor "json" format json

        _ ->
            jsonViewer initialExpanded className json


agentConsoleSnapshotPlayer : Bool -> List Har.Entry -> String -> Maybe String -> Html DetailMsg
agentConsoleSnapshotPlayer liveSession entries initialId highlightVisitorId =
    let
        stateEntries =
            entries
                |> List.filter Har.isReduxEntry
                |> Har.sortEntries ( "time", Har.Asc )

        firstEntryStartTime =
            Har.getFirstEntryStartTime stateEntries 0

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
        , on "hover" <|
            Decode.map2 QuickPreview
                (Decode.at [ "detail", "id" ] Decode.string)
                (Decode.at [ "detail", "clientX" ] Decode.float)
        , on "unhover" <| Decode.succeed HideQuickPreview
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
    [ property "state" <| Encode.string <| state
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


snapshotQuickPreview : Maybe { id : String, clientX : Float } -> String -> String -> List Har.Entry -> Html DetailMsg
snapshotQuickPreview quickPreview href pageName entries =
    let
        ( id, clientX, display ) =
            case quickPreview of
                Just p ->
                    ( p.id, p.clientX, "block" )

                _ ->
                    ( "", 0, "none" )
    in
    div
        [ class "quick-preview-container"
        , style "left" <| Utils.floatPx (clientX / 0.2)
        , style "display" display
        ]
        [ agentConsoleSnapshotFrame False False (href ++ "&snapshot=true") pageName entries id ]


agentConsoleSnapshot : Bool -> Bool -> List Har.Entry -> String -> String -> String -> Maybe { id : String, clientX : Float } -> String -> Maybe String -> Html DetailMsg
agentConsoleSnapshot liveSession isSortByTime entries href pageName currentId quickPreview entryId highlightVisitorId =
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
        , lazy4 snapshotQuickPreview quickPreview href pageName entries
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


previewNotAvailable : Html msg
previewNotAvailable =
    div [ class "detail-body", class "detail-body-empty" ] [ text "Preview not available" ]


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


resolveSelectedTab : DetailTabName -> EntryKind -> DetailTabName
resolveSelectedTab tab entryKind =
    entryKind
        |> detailTabsByEntryKind
        |> Utils.findItem (\{ name } -> name == tab)
        |> Maybe.map .name
        |> Maybe.withDefault Preview


resolveSelectedTool : DetailTabName -> EntryKind -> DetailViewTool -> DetailViewTool
resolveSelectedTool tabName entryKind tool =
    getTools tabName entryKind
        |> Utils.findItem (\t -> t == tool)
        |> Maybe.withDefault
            (case entryKind of
                ReduxState ->
                    Auto

                _ ->
                    Raw
            )


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


responseView : DetailViewTool -> Har.Entry -> Html msg
responseView tool entry =
    case entry.response.content.text of
        Just t ->
            let
                mimeType =
                    entry.response.content.mimeType
            in
            case String.split "/" mimeType of
                [ "image", "svg+xml" ] ->
                    case tool of
                        Raw ->
                            codeEditor "html" False t

                        _ ->
                            svgViewer t

                [ "image", _ ] ->
                    case tool of
                        Raw ->
                            hexEditor t

                        _ ->
                            imageViewer t mimeType

                [ "text", "javascript" ] ->
                    codeEditor "javascript" (tool /= Raw) t

                [ "application", "javascript" ] ->
                    codeEditor "javascript" (tool /= Raw) t

                [ "text", "css" ] ->
                    codeEditor "css" (tool /= Raw) t

                [ "text", "html" ] ->
                    case tool of
                        Raw ->
                            codeEditor "html" False t

                        _ ->
                            htmlViewer t

                [ "audio", _ ] ->
                    case tool of
                        Raw ->
                            hexEditor t

                        _ ->
                            audioViewer mimeType entry.id t

                [ "font", "woff2" ] ->
                    case tool of
                        Raw ->
                            hexEditor t

                        _ ->
                            fontViewer t "woff2"

                [ "font", "woff" ] ->
                    case tool of
                        Raw ->
                            hexEditor t

                        _ ->
                            fontViewer t "woff"

                [ "font", "ttf" ] ->
                    case tool of
                        Raw ->
                            hexEditor t

                        _ ->
                            fontViewer t "truetype"

                [ "application", "pdf" ] ->
                    case tool of
                        Raw ->
                            hexEditor t

                        _ ->
                            pdfViewer t entry.request.url

                [ "application", "vnd.yt-ump" ] ->
                    case tool of
                        Raw ->
                            hexEditor t

                        _ ->
                            previewNotAvailable

                _ ->
                    let
                        entryKind =
                            Har.getEntryKind entry
                    in
                    jsonDataViewer
                        tool
                        (entryKind /= ReduxState)
                        (entryKind /= NetworkHttp)
                        "detail-body"
                        t

        _ ->
            previewNotAvailable


getTools : DetailTabName -> EntryKind -> List DetailViewTool
getTools tabName entryKind =
    case ( tabName, entryKind ) of
        ( Request, ReduxAction ) ->
            [ JsonTree, Raw ]

        ( Response, ReduxAction ) ->
            [ JsonTree, Raw ]

        ( Response, ReduxState ) ->
            [ JsonTree, Raw ]

        _ ->
            []


toolsSelect : DetailTabName -> EntryKind -> DetailViewTool -> Html DetailMsg
toolsSelect tabName entryKind tool =
    let
        tools =
            getTools tabName entryKind
    in
    if List.isEmpty tools then
        text ""

    else
        Utils.dropDownList
            { value = viewToolToString tool
            , onInput = stringToViewTool >> ChangeViewTool
            }
            (detailViewToolsOptions tools)


stateChangeViewer : Har.Entry -> List Har.Entry -> Html msg
stateChangeViewer entry entries =
    case Har.getReduxState entry of
        Just modified ->
            case Har.findStateEntryAndPrevStateEntry entries entry.id of
                ( _, Just prevEntry, _ ) ->
                    case Har.getReduxState prevEntry of
                        Just original ->
                            codeDiffEditor "json" original modified

                        _ ->
                            text ""

                _ ->
                    text ""

        _ ->
            text ""


headersView : Har.Entry -> Html msg
headersView entry =
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


detailCloseButton : Html DetailMsg
detailCloseButton =
    button [ class "detail-close", onClick HideDetail ] [ Icons.close ]


detailView : Bool -> Bool -> Bool -> List Har.Entry -> DetailModel -> String -> String -> Maybe String -> Har.Entry -> Html DetailMsg
detailView liveSession isSnapshotPopout isSortByTime entries model href pageName highlightVisitorId entry =
    let
        entryKind =
            Har.getEntryKind entry

        selected =
            resolveSelectedTab model.tab entryKind

        tool =
            resolveSelectedTool selected entryKind model.tool
    in
    section [ class "detail" ]
        [ div [ class "detail-header" ]
            [ detailCloseButton
            , lazy2 detailTabs selected entry
            , lazy3 toolsSelect selected entryKind model.tool
            ]
        , if isSnapshotPopout then
            div [ style "display" "none" ]
                [ lazy5 agentConsoleSnapshotPopout isSortByTime href pageName entries model.currentId ]

          else
            text ""
        , case selected of
            Preview ->
                case entryKind of
                    ReduxState ->
                        agentConsoleSnapshot liveSession isSortByTime entries href pageName model.currentId model.quickPreview entry.id highlightVisitorId

                    ReduxAction ->
                        agentConsoleSnapshot liveSession isSortByTime entries href pageName model.currentId model.quickPreview entry.id highlightVisitorId

                    LogMessage ->
                        entry
                            |> Har.getLogMessage
                            |> Maybe.map (jsonViewer True "detail-body")
                            |> Maybe.withDefault noContent

                    _ ->
                        responseView Auto entry

            Headers ->
                lazy headersView entry

            Request ->
                case entryKind of
                    ReduxState ->
                        stateChangeViewer entry entries

                    _ ->
                        entry
                            |> Har.getRequestBody
                            |> Maybe.map (jsonDataViewer tool True True "detail-body")
                            |> Maybe.withDefault noContent

            Response ->
                responseView tool entry
        ]



-- UPDATE


type DetailMsg
    = NoOp
    | ChangeDetailTab DetailTabName
    | HideDetail
    | SetCurrentId String
    | QuickPreview String Float
    | HideQuickPreview
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

        QuickPreview id clientX ->
            ( { model | quickPreview = Just { id = id, clientX = Debug.log "clientX" clientX } }, Cmd.none )

        HideQuickPreview ->
            ( { model | quickPreview = Nothing }, Cmd.none )

        ScrollToCurrentId ->
            ( model, Cmd.none )

        ChangeViewTool tool ->
            ( { model | tool = tool }, Cmd.none )

        SetSnapshotPopout isPopout ->
            ( { model | snapshotPopout = isPopout }, Cmd.none )
