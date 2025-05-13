module Utils exposing
    ( GroupOption
    , compareInt
    , comparePosix
    , compareString
    , dropDownList
    , dropDownListWithGroup
    , dropWhile
    , dropWhileBefore
    , exportLiveSessionFileName
    , findItem
    , findMaybeItem
    , floatPx
    , formatSize
    , formatTime
    , getLanguage
    , getLast
    , indexOf
    , intPx
    , isMember
    , resizeDivider
    , styles
    , timespanMillis
    , virtualizedList
    )

import Html exposing (Attribute, Html, div, label, option, text)
import Html.Attributes exposing (class, property, style, value)
import Html.Events exposing (onInput)
import Html.Keyed as Keyed
import Iso8601
import Json.Decode as D
import Json.Encode as Encode
import String exposing (fromFloat, fromInt)
import Time


compareInt : Int -> Int -> Order
compareInt a b =
    if a < b then
        LT

    else if a > b then
        GT

    else
        EQ


comparePosix : Time.Posix -> Time.Posix -> Order
comparePosix a b =
    compareInt (Time.posixToMillis a) (Time.posixToMillis b)


compareString : String -> String -> Order
compareString a b =
    if a < b then
        LT

    else if a > b then
        GT

    else
        EQ


intPx : Int -> String
intPx n =
    fromInt n ++ "px"


floatPx : Float -> String
floatPx f =
    fromFloat f ++ "px"


toIntPad2 : Int -> String
toIntPad2 n =
    if n < 10 then
        "0" ++ String.fromInt n

    else
        String.fromInt n


toIntPad3 : Int -> String
toIntPad3 n =
    if n < 10 then
        "00" ++ String.fromInt n

    else if n < 100 then
        "0" ++ String.fromInt n

    else
        String.fromInt n


formatTime : Time.Zone -> Time.Posix -> String
formatTime tz time =
    toIntPad2 (Time.toHour tz time)
        ++ ":"
        ++ toIntPad2 (Time.toMinute tz time)
        ++ ":"
        ++ toIntPad2 (Time.toSecond tz time)
        ++ ","
        ++ toIntPad3 (Time.toMillis tz time)


exportLiveSessionFileName : Time.Posix -> String
exportLiveSessionFileName time =
    "ac-" ++ String.replace ":" "-" (Iso8601.fromTime time) ++ ".har"


formatSize : Int -> String
formatSize size =
    if size < 0 then
        "―"

    else if size < 1000 then
        String.fromInt size ++ " B"

    else if size < 1000000 then
        String.fromFloat (toFixed 2 (toFloat size / 1000)) ++ " KB"

    else
        String.fromFloat (toFixed 2 (toFloat size / 1000000)) ++ " MB"


toFixed : Int -> Float -> Float
toFixed n f =
    let
        factor =
            toFloat (10 ^ n)
    in
    (toFloat <| round (f * factor)) / factor


indexOfHelper : Int -> (a -> Bool) -> List a -> Maybe Int
indexOfHelper i predicate list =
    case list of
        [] ->
            Nothing

        x :: xs ->
            if predicate x then
                Just i

            else
                indexOfHelper (i + 1) predicate xs


indexOf : (a -> Bool) -> List a -> Maybe Int
indexOf =
    indexOfHelper 0


isMember : (a -> Bool) -> List a -> Bool
isMember predicate list =
    case list of
        [] ->
            False

        x :: xs ->
            if predicate x then
                True

            else
                isMember predicate xs


findItem : (a -> Bool) -> List a -> Maybe a
findItem predicate list =
    case list of
        [] ->
            Nothing

        x :: xs ->
            if predicate x then
                Just x

            else
                findItem predicate xs


findMaybeItemHelper : Int -> (Int -> a -> Maybe b) -> List a -> Maybe b
findMaybeItemHelper i f list =
    case list of
        [] ->
            Nothing

        x :: xs ->
            case f i x of
                Just y ->
                    Just y

                Nothing ->
                    findMaybeItemHelper (i + 1) f xs


findMaybeItem : (Int -> a -> Maybe b) -> List a -> Maybe b
findMaybeItem =
    findMaybeItemHelper 0


dropWhileBefore : (a -> Bool) -> List a -> List a
dropWhileBefore predicate list =
    case list of
        [] ->
            []

        x :: x1 :: xs ->
            if predicate x && (not <| predicate x1) then
                list

            else
                dropWhileBefore predicate (x1 :: xs)

        _ ->
            list


dropWhile : (a -> Bool) -> List a -> List a
dropWhile predicate list =
    case list of
        [] ->
            []

        x :: xs ->
            if predicate x then
                dropWhile predicate xs

            else
                list


timespanMillis : Time.Posix -> Time.Posix -> Int
timespanMillis start end =
    Time.posixToMillis end - Time.posixToMillis start


getLast : List a -> Maybe a
getLast list =
    case list of
        [] ->
            Nothing

        [ x ] ->
            Just x

        _ :: xs ->
            getLast xs



-- ATTRIBUTES


styles : List ( String, String ) -> Attribute msg
styles ss =
    let
        css =
            List.foldl
                (\( prop, val ) acc ->
                    String.append acc (prop ++ ":" ++ val ++ ";\n")
                )
                ""
                ss
    in
    property "style" <| Encode.string css



-- VIEWS


dropDownListCell : { value : String, label : String, onInput : String -> msg } -> List ( String, Html msg ) -> Html msg
dropDownListCell props children =
    label [ class "select" ]
        [ div [] [ text props.label ]
        , Keyed.node "select"
            [ onInput props.onInput
            , style "width" <| "calc(" ++ fromInt (String.length props.label) ++ "ch + " ++ "16px)"
            , value props.value
            ]
            children
        ]


type alias GroupOption =
    { label : String, subitems : List { label : String, value : String } }


groupOptionDisplayLabel : String -> GroupOption -> String
groupOptionDisplayLabel value groupOption =
    groupOption.subitems
        |> findItem (\item -> item.value == value)
        |> Maybe.map
            (\item ->
                if String.isEmpty groupOption.label then
                    item.label

                else
                    groupOption.label ++ " - " ++ item.label
            )
        |> Maybe.withDefault groupOption.label


maybeOrElse : Maybe a -> Maybe a -> Maybe a
maybeOrElse b a =
    case ( b, a ) of
        ( _, Just x ) ->
            Just x

        ( Just y, _ ) ->
            Just y

        _ ->
            Nothing


dropDownListWithGroup :
    { value : String, onInput : String -> msg }
    -> List GroupOption
    -> Html msg
dropDownListWithGroup props children =
    let
        lbl =
            children
                |> findItem
                    (\{ subitems } ->
                        isMember (\{ value } -> props.value == value) subitems
                    )
                |> maybeOrElse (List.head children)
                |> Maybe.map (groupOptionDisplayLabel props.value)
                |> Maybe.withDefault ""

        keyedOption item =
            ( item.value, option [ value item.value ] [ text item.label ] )
    in
    dropDownListCell
        { label = lbl
        , value = props.value
        , onInput = props.onInput
        }
    <|
        List.map
            (\{ label, subitems } ->
                case subitems of
                    [ item ] ->
                        keyedOption <|
                            if String.isEmpty label then
                                item

                            else
                                { label = label, value = item.value }

                    _ ->
                        ( label
                        , Keyed.node "optgroup"
                            [ property "label" <| Encode.string label ]
                            (List.map keyedOption subitems)
                        )
            )
            children


dropDownList : { value : String, onInput : String -> msg } -> List { label : String, value : String } -> Html msg
dropDownList props children =
    let
        lbl =
            children
                |> findItem (\child -> props.value == child.value)
                |> Maybe.map .label
                |> Maybe.withDefault (List.head children |> Maybe.map .label |> Maybe.withDefault "")
    in
    dropDownListCell
        { label = lbl
        , value = props.value
        , onInput = props.onInput
        }
    <|
        List.map (\item -> ( item.value, option [ value item.value ] [ text item.label ] )) children


virtualizedList :
    { scrollTop : Int
    , viewportHeight : Int
    , itemHeight : Int
    , items : List item
    , renderItem : List (Attribute msg) -> item -> ( String, Html msg )
    }
    -> Html msg
virtualizedList { scrollTop, viewportHeight, itemHeight, items, renderItem } =
    let
        overhead =
            5

        totalCount =
            List.length items

        totalHeight =
            totalCount * itemHeight

        i =
            Basics.max 0 <| floor <| toFloat scrollTop / toFloat itemHeight - overhead

        -- always start from even index, makes the background color consistant
        fromIndex =
            if isOdd i then
                i - 1

            else
                i

        visibleItemsCount =
            Basics.min totalCount <| ceiling <| toFloat viewportHeight / toFloat itemHeight + 2 * overhead

        visibleItems =
            items |> List.drop fromIndex |> List.take visibleItemsCount
    in
    div
        [ style "height" <| intPx totalHeight
        , style "position" "relative"
        ]
        [ Keyed.ol
            [ style "top" <| intPx <| fromIndex * itemHeight
            , style "position" "absolute"
            , style "width" "100%"
            , style "padding" "0"
            , style "margin" "0"
            ]
          <|
            List.map (renderItem []) visibleItems
        ]


resizeDivider : (Int -> Int -> value) -> Html value
resizeDivider onResize =
    Html.node "resize-divider"
        [ Html.Events.on "resize" <|
            D.field "detail" (D.map2 onResize (D.field "dx" D.int) (D.field "dy" D.int))
        ]
        []


isOdd : Int -> Bool
isOdd n =
    Basics.modBy 2 n == 1


getLanguage : String -> String
getLanguage path =
    if String.endsWith ".js" path then
        "javascript"

    else if String.endsWith ".ts" path then
        "typescript"

    else if String.endsWith ".css" path then
        "css"

    else if String.endsWith ".html" path then
        "html"

    else
        "json"
