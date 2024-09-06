module HarDecoder exposing (decodeHar)

import Har exposing (..)
import Iso8601
import Json.Decode as Decode exposing (Decoder, bool, decodeString, field, float, int, list, maybe, string)
import Time
import Url exposing (percentDecode)


decodeHar : String -> Maybe Log
decodeHar str =
    case decodeString harDecoder str of
        Ok { log } ->
            Just
                { log
                    | entries =
                        List.sortBy (\entry -> Time.posixToMillis entry.startedDateTime) log.entries
                }

        Err _ ->
            Nothing


harDecoder : Decoder HarFile
harDecoder =
    Decode.map HarFile
        (field "log" logDecoder)


logDecoder : Decoder Log
logDecoder =
    Decode.map6 Log
        (field "version" string)
        (field "creator" creatorDecoder)
        (maybe <| field "browser" browserDecoder)
        (field "pages" (list pageDecoder))
        (field "entries" entriesDecoder)
        (maybe <| field "comment" string)


entriesDecoder : Decoder (List Entry)
entriesDecoder =
    Decode.map
        (\entries ->
            List.indexedMap (\i entry -> { entry | id = String.fromInt i }) entries
        )
        (list entryDecoder)


creatorDecoder : Decoder Creator
creatorDecoder =
    Decode.map3 Creator
        (field "name" string)
        (field "version" string)
        (maybe <| field "comment" string)


browserDecoder : Decoder Browser
browserDecoder =
    Decode.map3 Browser
        (field "name" string)
        (field "version" string)
        (maybe <| field "comment" string)


pageDecoder : Decoder Page
pageDecoder =
    Decode.map5 Page
        (field "startedDateTime" string)
        (field "id" string)
        (field "title" string)
        (field "pageTimings" pageTimingsDecoder)
        (maybe <| field "comment" string)


pageTimingsDecoder : Decoder PageTimings
pageTimingsDecoder =
    Decode.map3 PageTimings
        (maybe <| field "onContentLoad" float)
        (maybe <| field "onLoad" float)
        (maybe <| field "comment" string)


entryDecoder : Decoder Entry
entryDecoder =
    map10 (Entry "" "")
        (maybe <| field "pageref" string)
        (field "startedDateTime" Iso8601.decoder)
        (field "time" float)
        (field "request" requestDecoder)
        (field "response" responseDecoder)
        (field "cache" cacheDecoder)
        (field "timings" timingsDecoder)
        (maybe <| field "serverIPAddress" string)
        (maybe <| field "connection" string)
        (maybe <| field "comment" string)


parseQueryString : String -> List QueryString
parseQueryString url =
    case String.split "?" url of
        [ _, queryString ] ->
            case String.split "&" queryString of
                [] ->
                    []

                _ ->
                    List.filterMap
                        (\query ->
                            case String.split "=" query of
                                [ name, value ] ->
                                    Just <|
                                        QueryString name
                                            (percentDecode value
                                                |> Maybe.withDefault value
                                            )
                                            Nothing

                                _ ->
                                    Nothing
                        )
                        (String.split "&" queryString)

        _ ->
            []


requestDecoder : Decoder Request
requestDecoder =
    map10
        (\method url httpVersion cookies headers queryString postData headersSize bodySize comment ->
            let
                query =
                    if List.isEmpty queryString then
                        parseQueryString url

                    else
                        queryString
            in
            Request method url httpVersion cookies headers query postData headersSize bodySize comment
        )
        (field "method" string)
        (field "url" string)
        (field "httpVersion" string)
        (field "cookies" (list cookieDecoder))
        (field "headers" (list headerDecoder))
        (field "queryString" (list queryStringDecoder))
        (maybe <| field "postData" postDataDecoder)
        (field "headersSize" int)
        (field "bodySize" int)
        (maybe <| field "comment" string)


responseDecoder : Decoder Response
responseDecoder =
    map10 Response
        (field "status" int)
        (field "statusText" string)
        (field "httpVersion" string)
        (field "cookies" (list cookieDecoder))
        (field "headers" (list headerDecoder))
        (field "content" contentDecoder)
        (field "redirectURL" string)
        (field "headersSize" int)
        (field "bodySize" int)
        (maybe <| field "comment" string)


cookieDecoder : Decoder Cookie
cookieDecoder =
    Decode.map8 Cookie
        (field "name" string)
        (field "value" string)
        (maybe <| field "path" string)
        (maybe <| field "domain" string)
        (maybe <| field "expires" string)
        (maybe <| field "httpOnly" bool)
        (maybe <| field "secure" bool)
        (maybe <| field "comment" string)


headerDecoder : Decoder Header
headerDecoder =
    Decode.map3 Header
        (field "name" string)
        (field "value" string)
        (maybe <| field "comment" string)


stringOrInt : Decoder String
stringOrInt =
    Decode.oneOf
        [ string
        , int |> Decode.map String.fromInt
        ]


queryStringDecoder : Decoder QueryString
queryStringDecoder =
    Decode.map3 QueryString
        (field "name" string)
        (field "value" stringOrInt
            |> maybe
            |> Decode.map (Maybe.withDefault "")
        )
        (maybe <| field "comment" string)


postDataDecoder : Decoder PostData
postDataDecoder =
    Decode.map4 PostData
        (field "mimeType" string)
        (maybe <| field "params" (list paramDecoder))
        (maybe <| field "text" string)
        (maybe <| field "comment" string)


paramDecoder : Decoder Param
paramDecoder =
    Decode.map5 Param
        (field "name" string)
        (maybe <| field "value" string)
        (maybe <| field "fileName" string)
        (maybe <| field "contentType" string)
        (maybe <| field "comment" string)


contentDecoder : Decoder Content
contentDecoder =
    Decode.map6 Content
        (field "size" int)
        (maybe <| field "compression" int)
        (field "mimeType" string)
        (maybe <| field "text" string)
        (maybe <| field "encoding" string)
        (maybe <| field "comment" string)


cacheDecoder : Decoder Cache
cacheDecoder =
    Decode.map3 Cache
        (maybe <| field "beforeRequest" cacheStateDecoder)
        (maybe <| field "afterRequest" cacheStateDecoder)
        (maybe <| field "comment" string)



-- CacheState Decoder


cacheStateDecoder : Decoder CacheState
cacheStateDecoder =
    Decode.map5 CacheState
        (maybe <| field "expires" string)
        (field "lastAccess" string)
        (field "eTag" string)
        (field "hitCount" int)
        (maybe <| field "comment" string)



-- Timings Decoder


timingsDecoder : Decoder Timings
timingsDecoder =
    Decode.map8 Timings
        (maybe <| field "blocked" float)
        (maybe <| field "dns" float)
        (maybe <| field "connect" float)
        (field "send" float)
        (field "wait" float)
        (field "receive" float)
        (maybe <| field "ssl" float)
        (maybe <| field "comment" string)


map10 :
    (a -> b -> c -> d -> e -> f -> g -> h -> i -> j -> k)
    -> Decoder a
    -> Decoder b
    -> Decoder c
    -> Decoder d
    -> Decoder e
    -> Decoder f
    -> Decoder g
    -> Decoder h
    -> Decoder i
    -> Decoder j
    -> Decoder k
map10 f a b c d e g h i j k =
    Decode.map3 (\f1 a1 b1 -> f1 a1 b1)
        (Decode.map8 f a b c d e g h i)
        j
        k
