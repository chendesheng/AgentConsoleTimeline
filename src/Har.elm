module Har exposing (..)

import Json.Decode as D
import Regex exposing (Match)
import Time
import Utils



{- <https://github.com/ahmadnassri/har-spec/blob/master/versions/1.2.md> -}


type alias HarFile =
    { log : Log -- The root log object.
    }


{-| Represents the root log object in a HAR file.
-}
type alias Log =
    { version : String -- Version number of the HAR format.
    , creator : Creator -- Information about the software that created the HAR file.
    , browser : Maybe Browser -- Information about the browser that made the requests.
    , pages : List Page -- List of pages in the HAR log.
    , entries : List Entry -- List of all requests/responses in the log.
    , comment : Maybe String -- A comment provided by the user or the application.
    }


{-| Information about the software that created the HAR file.
-}
type alias Creator =
    { name : String -- Name of the application that created the HAR file.
    , version : String -- Version of the application.
    , comment : Maybe String -- Additional information about the creator.
    }


{-| Information about the browser that made the requests.
-}
type alias Browser =
    { name : String -- Name of the browser.
    , version : String -- Version of the browser.
    , comment : Maybe String -- Additional information about the browser.
    }


{-| Represents a single page and its associated properties in the HAR log.
-}
type alias Page =
    { startedDateTime : String -- The date and time the page load started.
    , id : String -- Unique identifier for the page.
    , title : String -- Title of the page.
    , pageTimings : PageTimings -- Timing information for various events in the page load.
    , comment : Maybe String -- Additional information about the page.
    }


{-| Timing information for various events in the page load.
-}
type alias PageTimings =
    { onContentLoad : Maybe Float -- Time when the page's content has finished loading.
    , onLoad : Maybe Float -- Time when the page is fully loaded.
    , comment : Maybe String -- Additional information about page timings.
    }


{-| Represents an individual request/response pair in the HAR log.
-}
type alias Entry =
    { id : String -- Unique identifier (index) for the entry.
    , startedDateTimeStr : String
    , pageref : Maybe String -- Reference to the parent page.
    , startedDateTime : Time.Posix -- The date and time the request started.
    , time : Float -- Total time for the request in milliseconds.
    , request : Request -- The request information.
    , response : Response -- The response information.
    , cache : Cache -- Information about cache usage.
    , timings : Timings -- Timing breakdown for the request.
    , serverIPAddress : Maybe String -- IP address of the server.
    , connection : Maybe String -- ID of the TCP/IP connection.
    , comment : Maybe String -- Additional information about the entry.
    }


{-| Details of the request.
-}
type alias Request =
    { method : String -- HTTP method (GET, POST, etc.).
    , url : String -- The full URL of the request.
    , httpVersion : String -- The HTTP version.
    , cookies : List Cookie -- List of cookies.
    , headers : List Header -- List of headers.
    , queryString : List QueryString -- The query string parameters.
    , postData : Maybe PostData -- Posted data information.
    , headersSize : Int -- Total size of the request headers.
    , bodySize : Int -- Size of the request body.
    , comment : Maybe String -- Additional information about the request.
    }


{-| Details of the response.
-}
type alias Response =
    { status : Int -- HTTP status code.
    , statusText : String -- HTTP status text.
    , httpVersion : String -- The HTTP version.
    , cookies : List Cookie -- List of cookies.
    , headers : List Header -- List of headers.
    , content : Content -- The content of the response.
    , redirectURL : String -- If the response was a redirect, the URL of the redirect.
    , headersSize : Int -- Total size of the response headers.
    , bodySize : Int -- Size of the response body.
    , comment : Maybe String -- Additional information about the response.
    }


{-| Represents a single cookie.
-}
type alias Cookie =
    { name : String -- The name of the cookie.
    , value : String -- The value of the cookie.
    , path : Maybe String -- Path attribute of the cookie.
    , domain : Maybe String -- Domain attribute of the cookie.
    , expires : Maybe String -- Expiry date of the cookie.
    , httpOnly : Maybe Bool -- Indicates if the cookie is HTTPOnly.
    , secure : Maybe Bool -- Indicates if the cookie is Secure.
    , comment : Maybe String -- Additional information about the cookie.
    }


{-| Represents a single header.
-}
type alias Header =
    { name : String -- The name of the header.
    , value : String -- The value of the header.
    , comment : Maybe String -- Additional information about the header.
    }


{-| Represents a single query string parameter.
-}
type alias QueryString =
    { name : String -- The name of the parameter.
    , value : String -- The value of the parameter.
    , comment : Maybe String -- Additional information about the parameter.
    }


{-| Represents posted data in a request.
-}
type alias PostData =
    { mimeType : String -- The MIME type of the posted data.

    -- text and params fields are mutually exclusive.
    , params : Maybe (List Param) -- List of parameters.
    , text : Maybe String -- The raw text of the posted data.
    , comment : Maybe String -- Additional information about the posted data.
    }


{-| Represents a parameter in the posted data.
-}
type alias Param =
    { name : String -- The name of the parameter.
    , value : Maybe String -- The value of the parameter.
    , fileName : Maybe String -- The filename (for file parameters).
    , contentType : Maybe String -- The content type of the file.
    , comment : Maybe String -- Additional information about the parameter.
    }


{-| Represents the content of a response.
-}
type alias Content =
    { size : Int -- Size of the response body in bytes.
    , compression : Maybe Int -- Size saved by compression.
    , mimeType : String -- MIME type of the response.
    , text : Maybe String -- Text content of the response.
    , encoding : Maybe String -- Encoding used for text content.
    , comment : Maybe String -- Additional information about the content.
    }


{-| Represents cache information for a request.
-}
type alias Cache =
    { beforeRequest : Maybe CacheState -- State of the cache entry before the request.
    , afterRequest : Maybe CacheState -- State of the cache entry after the request.
    , comment : Maybe String -- Additional information about the cache usage.
    }


{-| Represents the state of a cache entry.
-}
type alias CacheState =
    { expires : Maybe String -- The expiration time of the cache entry.
    , lastAccess : String -- The last time the cache entry was accessed.
    , eTag : String -- The ETag of the cache entry.
    , hitCount : Int -- Number of times the cache entry has been accessed.
    , comment : Maybe String -- Additional information about the cache state.
    }


{-| Breakdown of timing information for a request.
-}
type alias Timings =
    { blocked : Maybe Float -- Time spent in a queue or blocked.
    , dns : Maybe Float -- DNS resolution time.
    , connect : Maybe Float -- Time taken to establish TCP connection.
    , send : Float -- Time spent sending the request.
    , wait : Float -- Time spent waiting for a response.
    , receive : Float -- Time taken to read the response.
    , ssl : Maybe Float -- Time taken for SSL/TLS negotiation.
    , comment : Maybe String -- Additional information about the timings.
    }


getFirstEntryStartTime : List Entry -> Int -> Time.Posix
getFirstEntryStartTime entries startIndex =
    case List.drop startIndex entries of
        entry :: _ ->
            entry.startedDateTime

        _ ->
            Time.millisToPosix 0


compareEntry : String -> Entry -> Entry -> Order
compareEntry column a b =
    case column of
        "name" ->
            Utils.compareString (harEntryName a) (harEntryName b)

        "status" ->
            Utils.compareInt a.response.status b.response.status

        "time" ->
            Utils.comparePosix a.startedDateTime b.startedDateTime

        "domain" ->
            Utils.compareString a.request.url b.request.url

        "size" ->
            Utils.compareInt (a.response.bodySize + a.request.bodySize) (b.response.bodySize + b.request.bodySize)

        "method" ->
            Utils.compareString a.request.method b.request.method

        "waterfall" ->
            Utils.comparePosix a.startedDateTime b.startedDateTime

        _ ->
            EQ


type SortOrder
    = Asc
    | Desc


type alias SortBy =
    ( String, SortOrder )


flipSortOrder : SortOrder -> SortOrder
flipSortOrder sortOrder =
    case sortOrder of
        Asc ->
            Desc

        Desc ->
            Asc


sortEntries : SortBy -> List Entry -> List Entry
sortEntries ( column, sortOrder ) =
    List.sortWith
        (\a b ->
            let
                order =
                    compareEntry column a b
            in
            case order of
                EQ ->
                    EQ

                LT ->
                    case sortOrder of
                        Asc ->
                            LT

                        Desc ->
                            GT

                GT ->
                    case sortOrder of
                        Asc ->
                            GT

                        Desc ->
                            LT
        )


type EntryKind
    = LogMessage
    | NetworkHttp
    | Others
    | ReduxAction
    | ReduxState


getEntryKind : Entry -> EntryKind
getEntryKind entry =
    if entry.request.url == "/redux/state" then
        ReduxState

    else if String.startsWith "/redux/" entry.request.url then
        ReduxAction

    else if String.startsWith "/log/" entry.request.url then
        LogMessage

    else if
        String.startsWith "https://" entry.request.url
            || String.startsWith "http://" entry.request.url
            || String.startsWith "/api/" entry.request.url
    then
        NetworkHttp

    else
        Others


entryKindLabel : Maybe EntryKind -> String
entryKindLabel kind =
    case kind of
        Nothing ->
            "All"

        Just ReduxState ->
            "Redux"

        Just ReduxAction ->
            "Redux"

        Just LogMessage ->
            "Log"

        Just NetworkHttp ->
            "Network HTTP"

        Just Others ->
            "Others"


stringToEntryKind : String -> Maybe EntryKind
stringToEntryKind s =
    case s of
        "0" ->
            Just ReduxState

        "1" ->
            Just LogMessage

        "2" ->
            Just NetworkHttp

        "3" ->
            Just Others

        _ ->
            Nothing


entryKindValue : Maybe EntryKind -> String
entryKindValue kind =
    case kind of
        Just ReduxState ->
            "0"

        Just LogMessage ->
            "1"

        Just NetworkHttp ->
            "2"

        Just Others ->
            "3"

        _ ->
            ""


filterByKind : Maybe EntryKind -> List Entry -> List Entry
filterByKind kind entries =
    case kind of
        Just ReduxState ->
            List.filter isReduxEntry entries

        Just kd ->
            entries
                |> List.filter (\entry -> getEntryKind entry == kd)

        Nothing ->
            entries


entryContainsStr : String -> Entry -> Bool
entryContainsStr w entry =
    let
        headerContains =
            .value >> String.toLower >> String.contains w
    in
    (entry.request.url
        |> String.toLower
        |> String.contains w
    )
        || List.any headerContains entry.request.headers
        || (entry.request.postData
                |> Maybe.andThen .text
                |> Maybe.withDefault ""
                |> String.toLower
                |> String.contains w
           )
        || List.any headerContains entry.response.headers
        || (entry.response.content.text
                |> Maybe.withDefault ""
                |> String.toLower
                |> String.contains w
           )


filterByMatch : String -> List Entry -> List Entry
filterByMatch match entries =
    case String.trim match of
        "" ->
            entries

        filter ->
            let
                loweredFilter =
                    String.toLower filter
            in
            List.filter (entryContainsStr loweredFilter) entries


filterEntries : String -> Maybe EntryKind -> List Entry -> List Entry
filterEntries match kind entries =
    entries
        |> filterByKind kind
        |> filterByMatch match


type alias ClientInfo =
    { href : String
    , userAgent : String
    , version : String
    , commit : String
    , time : Time.Posix
    }


getClientInfo : List Entry -> ClientInfo
getClientInfo entries =
    let
        clientInfoDecoder =
            D.map5 ClientInfo
                (D.field "href" D.string)
                (D.field "userAgent" D.string)
                (D.field "version" D.string)
                (D.field "commit" D.string)
                (D.succeed <| Time.millisToPosix 0)

        emptyClientInfo =
            ClientInfo "" "" "" "" <| Time.millisToPosix 0
    in
    case List.filter (\entry -> entry.request.url == "/log/message") entries of
        entry :: rest ->
            case entry.response.content.text of
                Just text ->
                    case D.decodeString clientInfoDecoder text of
                        Ok clientInfo ->
                            { clientInfo | time = entry.startedDateTime }

                        Err _ ->
                            getClientInfo rest

                _ ->
                    getClientInfo rest

        _ ->
            emptyClientInfo


isReduxStateEntry : Entry -> Bool
isReduxStateEntry entry =
    entry.request.url == "/redux/state"


isReduxEntry : Entry -> Bool
isReduxEntry entry =
    String.startsWith "/redux/" entry.request.url


getReduxState : Entry -> Maybe String
getReduxState entry =
    if isReduxStateEntry entry then
        entry.response.content.text

    else
        Nothing


getRequestBody : Entry -> Maybe String
getRequestBody entry =
    Maybe.andThen .text entry.request.postData


getLogMessage : Entry -> Maybe String
getLogMessage entry =
    case entry.response.content.text of
        Nothing ->
            getRequestBody entry

        Just "" ->
            getRequestBody entry

        e ->
            e


findStateEntryAndPrevStateEntryHelper : List Entry -> String -> Maybe Entry -> List Entry -> ( Maybe Entry, Maybe Entry, List Entry )
findStateEntryAndPrevStateEntryHelper entries id prevStateEntry nonStateEntries =
    case entries of
        entry :: rest ->
            if entry.id == id then
                if isReduxStateEntry entry then
                    ( Just entry, prevStateEntry, List.reverse nonStateEntries )

                else
                    ( Nothing, prevStateEntry, List.reverse <| entry :: nonStateEntries )

            else if isReduxStateEntry entry then
                findStateEntryAndPrevStateEntryHelper rest id (Just entry) []

            else
                findStateEntryAndPrevStateEntryHelper rest id prevStateEntry (entry :: nonStateEntries)

        [] ->
            ( Nothing, Nothing, [] )


{-| Returns state entry of id, prevStateEntry of the entry, entries between the prevStateEntry and the entry (including the entry if it is not redux state entry).
-}
findStateEntryAndPrevStateEntry : List Entry -> String -> ( Maybe Entry, Maybe Entry, List Entry )
findStateEntryAndPrevStateEntry entries id =
    findStateEntryAndPrevStateEntryHelper entries id Nothing []


harEntryName : Entry -> String
harEntryName entry =
    let
        slashIndexes =
            List.reverse <| String.indexes "/" entry.request.url
    in
    case getEntryKind entry of
        ReduxAction ->
            case slashIndexes of
                _ :: j :: _ ->
                    String.dropLeft (j + 1) entry.request.url

                _ ->
                    entry.request.url

        ReduxState ->
            "state/" ++ entry.id

        _ ->
            case slashIndexes of
                i :: _ ->
                    String.dropLeft (i + 1) entry.request.url

                _ ->
                    entry.request.url


getNextReduxEntryIndex : List Entry -> Int -> Int
getNextReduxEntryIndex entries index =
    entries
        |> List.drop (index + 1)
        |> Utils.indexOf (\entry -> isReduxEntry entry)
        |> Maybe.map (\d -> index + 1 + d)
        |> Maybe.withDefault index


getPrevReduxEntryIndex : List Entry -> Int -> Int
getPrevReduxEntryIndex entries index =
    entries
        |> List.take index
        |> List.reverse
        |> Utils.indexOf (\entry -> isReduxEntry entry)
        |> Maybe.map (\d -> index - d - 1)
        |> Maybe.withDefault index


searchEntry : List Entry -> String -> List { id : String, index : Int, name : String, matches : List Match }
searchEntry entries keyword =
    entries
        |> List.indexedMap
            (\index entry ->
                let
                    name =
                        harEntryName entry
                in
                { id = entry.id
                , index = index
                , name = name
                , matches =
                    keyword
                        |> Regex.fromStringWith { caseInsensitive = True, multiline = False }
                        |> Maybe.map (\re -> Regex.find re name)
                        |> Maybe.withDefault []
                }
            )
        |> List.filter (\{ matches } -> List.isEmpty matches == False)


findEntry : String -> List Entry -> String -> Maybe { id : String, index : Int, name : String, matches : List Match }
findEntry selected entries keyword =
    let
        startIndex =
            entries
                |> Utils.indexOf (\entry -> entry.id == selected)
                |> Maybe.map ((+) 1)
                |> Maybe.withDefault 0
    in
    entries
        |> List.drop startIndex
        |> Utils.findMaybeItem
            (\index entry ->
                let
                    name =
                        harEntryName entry
                in
                keyword
                    |> Regex.fromStringWith { caseInsensitive = True, multiline = False }
                    |> Maybe.map
                        (\re ->
                            name
                                |> Regex.find re
                                |> List.head
                                |> Maybe.map
                                    (\match ->
                                        { id = entry.id
                                        , matches = [ match ]
                                        , name = name
                                        , index = startIndex + index
                                        }
                                    )
                        )
                    |> Maybe.withDefault Nothing
            )


isHttpFailedEntry : Entry -> Bool
isHttpFailedEntry entry =
    case getEntryKind entry of
        NetworkHttp ->
            entry.response.status > 399

        _ ->
            False
