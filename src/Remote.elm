port module Remote exposing (..)

import Http
import Json.Decode as Decode


port connectRemoteSource : String -> Cmd msg


port gotRemoteClose : (String -> msg) -> Sub msg


port gotRemoteHarLog : (String -> msg) -> Sub msg


port gotRemoteHarEntry : (String -> msg) -> Sub msg


address : String
address =
    "localhost:5174"


getSessions : (List String -> msg) -> Cmd msg
getSessions tagger =
    Http.get
        { url = "https://" ++ address ++ "/sessions"
        , expect =
            Http.expectJson
                (Result.withDefault [] >> tagger)
                (Decode.list Decode.string)
        }
