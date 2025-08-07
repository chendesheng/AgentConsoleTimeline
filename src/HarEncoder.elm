module HarEncoder exposing (encodeEntry, encodeHar, encodeHarFile)

import Har exposing (..)
import Iso8601
import Json.Encode exposing (Value, bool, float, int, list, null, object, string)


encodeHar : Log -> Value
encodeHar log =
    encodeLog log


encodeHarFile : HarFile -> Value
encodeHarFile harFile =
    object
        [ ( "log", encodeLog harFile.log )
        ]


encodeLog : Log -> Value
encodeLog log =
    object
        [ ( "version", string log.version )
        , ( "creator", encodeCreator log.creator )
        , ( "browser", encodeMaybe encodeBrowser log.browser )
        , ( "pages", list encodePage log.pages )
        , ( "entries", list encodeEntry log.entries )
        , ( "comment", encodeMaybe string log.comment )
        ]


encodeCreator : Creator -> Value
encodeCreator creator =
    object
        [ ( "name", string creator.name )
        , ( "version", string creator.version )
        , ( "comment", encodeMaybe string creator.comment )
        ]


encodeBrowser : Browser -> Value
encodeBrowser browser =
    object
        [ ( "name", string browser.name )
        , ( "version", string browser.version )
        , ( "comment", encodeMaybe string browser.comment )
        ]


encodePage : Page -> Value
encodePage page =
    object
        [ ( "startedDateTime", string page.startedDateTime )
        , ( "id", string page.id )
        , ( "title", string page.title )
        , ( "pageTimings", encodePageTimings page.pageTimings )
        , ( "comment", encodeMaybe string page.comment )
        ]


encodePageTimings : PageTimings -> Value
encodePageTimings pageTimings =
    object
        [ ( "onContentLoad", encodeMaybe float pageTimings.onContentLoad )
        , ( "onLoad", encodeMaybe float pageTimings.onLoad )
        , ( "comment", encodeMaybe string pageTimings.comment )
        ]


encodeEntry : Entry -> Value
encodeEntry entry =
    object
        [ ( "pageref", encodeMaybe string entry.pageref )
        , ( "startedDateTime", Iso8601.encode entry.startedDateTime )
        , ( "time", float entry.time )
        , ( "request", encodeRequest entry.request )
        , ( "response", encodeResponse entry.response )
        , ( "cache", encodeCache entry.cache )
        , ( "timings", encodeTimings entry.timings )
        , ( "serverIPAddress", encodeMaybe string entry.serverIPAddress )
        , ( "connection", encodeMaybe string entry.connection )
        , ( "comment", encodeMaybe string entry.comment )
        ]


encodeRequest : Request -> Value
encodeRequest request =
    object
        [ ( "method", string request.method )
        , ( "url", string request.url )
        , ( "httpVersion", string request.httpVersion )
        , ( "cookies", list encodeCookie request.cookies )
        , ( "headers", list encodeHeader request.headers )
        , ( "queryString", list encodeQueryString request.queryString )
        , ( "postData", encodeMaybe encodePostData request.postData )
        , ( "headersSize", int request.headersSize )
        , ( "bodySize", int request.bodySize )
        , ( "comment", encodeMaybe string request.comment )
        ]


encodeResponse : Response -> Value
encodeResponse response =
    object
        [ ( "status", int response.status )
        , ( "statusText", string response.statusText )
        , ( "httpVersion", string response.httpVersion )
        , ( "cookies", list encodeCookie response.cookies )
        , ( "headers", list encodeHeader response.headers )
        , ( "content", encodeContent response.content )
        , ( "redirectURL", string response.redirectURL )
        , ( "headersSize", int response.headersSize )
        , ( "bodySize", int response.bodySize )
        , ( "comment", encodeMaybe string response.comment )
        ]


encodeCookie : Cookie -> Value
encodeCookie cookie =
    object
        [ ( "name", string cookie.name )
        , ( "value", string cookie.value )
        , ( "path", encodeMaybe string cookie.path )
        , ( "domain", encodeMaybe string cookie.domain )
        , ( "expires", encodeMaybe string cookie.expires )
        , ( "httpOnly", encodeMaybe bool cookie.httpOnly )
        , ( "secure", encodeMaybe bool cookie.secure )
        , ( "comment", encodeMaybe string cookie.comment )
        ]


encodeHeader : Header -> Value
encodeHeader header =
    object
        [ ( "name", string header.name )
        , ( "value", string header.value )
        , ( "comment", encodeMaybe string header.comment )
        ]


encodeQueryString : QueryString -> Value
encodeQueryString queryString =
    object
        [ ( "name", string queryString.name )
        , ( "value", string queryString.value )
        , ( "comment", encodeMaybe string queryString.comment )
        ]


encodePostData : PostData -> Value
encodePostData postData =
    object
        [ ( "mimeType", string postData.mimeType )
        , ( "params", encodeMaybe (list encodeParam) postData.params )
        , ( "text", encodeMaybe string postData.text )
        , ( "comment", encodeMaybe string postData.comment )
        ]


encodeParam : Param -> Value
encodeParam param =
    object
        [ ( "name", string param.name )
        , ( "value", encodeMaybe string param.value )
        , ( "fileName", encodeMaybe string param.fileName )
        , ( "contentType", encodeMaybe string param.contentType )
        , ( "comment", encodeMaybe string param.comment )
        ]


encodeContent : Content -> Value
encodeContent content =
    object
        [ ( "size", int content.size )
        , ( "compression", encodeMaybe int content.compression )
        , ( "mimeType", string content.mimeType )
        , ( "text", encodeMaybe string content.text )
        , ( "encoding", encodeMaybe string content.encoding )
        , ( "comment", encodeMaybe string content.comment )
        ]


encodeCache : Cache -> Value
encodeCache cache =
    object
        [ ( "beforeRequest", encodeMaybe encodeCacheState cache.beforeRequest )
        , ( "afterRequest", encodeMaybe encodeCacheState cache.afterRequest )
        , ( "comment", encodeMaybe string cache.comment )
        ]


encodeCacheState : CacheState -> Value
encodeCacheState cacheState =
    object
        [ ( "expires", encodeMaybe string cacheState.expires )
        , ( "lastAccess", string cacheState.lastAccess )
        , ( "eTag", string cacheState.eTag )
        , ( "hitCount", int cacheState.hitCount )
        , ( "comment", encodeMaybe string cacheState.comment )
        ]


encodeTimings : Timings -> Value
encodeTimings timings =
    object
        [ ( "blocked", encodeMaybe float timings.blocked )
        , ( "dns", encodeMaybe float timings.dns )
        , ( "connect", encodeMaybe float timings.connect )
        , ( "send", float timings.send )
        , ( "wait", float timings.wait )
        , ( "receive", float timings.receive )
        , ( "ssl", encodeMaybe float timings.ssl )
        , ( "comment", encodeMaybe string timings.comment )
        ]



-- Helper function to encode Maybe values


encodeMaybe : (a -> Value) -> Maybe a -> Value
encodeMaybe encoder maybeValue =
    case maybeValue of
        Just value ->
            encoder value

        Nothing ->
            null
