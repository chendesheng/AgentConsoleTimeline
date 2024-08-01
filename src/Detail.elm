module Detail exposing (..)

import Har
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Icons
import Iso8601
import List
import String
import TokenDecoder exposing (parseToken)


type DetailMsg
    = ChangeDetailTab DetailTabName
    | HideDetail


type DetailTabName
    = Preview
    | Headers
    | Request
    | Response
    | Raw


type alias DetailTab =
    { name : DetailTabName, label : String }


type alias DetailModel =
    { tab : DetailTabName
    , show : Bool
    }


defaultDetailModel : DetailModel
defaultDetailModel =
    { tab = Preview
    , show = False
    }


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
detailTabs tab _ =
    div [ class "detail-header-tabs" ] <|
        List.map (detailTab tab)
            [ { name = Preview, label = "Preview" }
            , { name = Headers, label = "Headers" }
            , { name = Request, label = "Request" }
            , { name = Response, label = "Response" }
            , { name = Raw, label = "Raw" }
            ]


jsonViewer : String -> Html msg
jsonViewer json =
    Html.node "json-viewer" [ attribute "data" json ] []


detailPreviewView : String -> Har.Entry -> Html DetailMsg
detailPreviewView href entry =
    if isReduxStateEntry entry && not (String.isEmpty href) then
        case getReduxState entry of
            Just s ->
                Html.node "agent-console-snapshot"
                    [ src <| href ++ "&snapshot=true"
                    , attribute "state" s
                    , attribute "time" <| Iso8601.fromTime entry.startedDateTime
                    ]
                    []

            _ ->
                text "No redux state found"

    else
        jsonViewer <| Maybe.withDefault "" entry.response.content.text


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


detailView : DetailModel -> String -> Har.Entry -> Html DetailMsg
detailView detail href entry =
    section [ class "detail" ]
        [ div [ class "detail-header" ]
            [ button [ class "detail-close", onClick HideDetail ] [ Icons.close ]
            , detailTabs detail.tab entry
            ]
        , case detail.tab of
            Preview ->
                div [ class "detail-body" ] [ detailPreviewView href entry ]

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

            Raw ->
                case entry.response.content.text of
                    Just t ->
                        Html.node "code-editor" [ class "detail-body", attribute "content" t ] []

                    _ ->
                        noContent
        ]


isReduxStateEntry : Har.Entry -> Bool
isReduxStateEntry entry =
    entry.request.url == "/redux/state"


getReduxState : Har.Entry -> Maybe String
getReduxState entry =
    if isReduxStateEntry entry then
        case entry.response.content.text of
            Just text ->
                Just text

            _ ->
                Nothing

    else
        Nothing


updateDetail : DetailModel -> DetailMsg -> DetailModel
updateDetail model detailMsg =
    case detailMsg of
        ChangeDetailTab tab ->
            { model | tab = tab }

        HideDetail ->
            { model | show = False }
