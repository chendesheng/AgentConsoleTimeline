module Har exposing (..)

{-| <https://github.com/ahmadnassri/har-spec/blob/master/versions/1.2.md>
-}


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
    { pageref : Maybe String -- Reference to the parent page.
    , startedDateTime : String -- The date and time the request started.
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
    , params : List Param -- List of parameters.
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
