module Utils exposing (..)

import Html exposing (Attribute)
import Html.Attributes exposing (attribute)
import Html.Events exposing (preventDefaultOn)
import Json.Decode as D
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


floatToString : Int -> Float -> String
floatToString fixed f =
    let
        s =
            fromFloat (toFixed fixed f)

        parts =
            String.split "." s
    in
    case parts of
        [ n ] ->
            n ++ "." ++ String.repeat fixed "0"

        [ n, fraction ] ->
            n ++ "." ++ fraction ++ String.repeat (fixed - String.length fraction) "0"

        _ ->
            ""


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
    attribute "style" css


hijackOn : String -> D.Decoder msg -> Attribute msg
hijackOn event decoder =
    preventDefaultOn event (D.map hijack decoder)


hijack : msg -> ( msg, Bool )
hijack msg =
    ( msg, True )
