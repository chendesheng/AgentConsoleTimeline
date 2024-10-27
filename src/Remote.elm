port module Remote exposing (..)

import Http
import Json.Decode as Decode


port connectRemoteSource : String -> Cmd msg


port gotRemoteClose : (String -> msg) -> Sub msg


port gotRemoteHarLog : (String -> msg) -> Sub msg


port gotRemoteHarEntry : (String -> msg) -> Sub msg


getSessions : String -> (List String -> msg) -> Cmd msg
getSessions address tagger =
    Http.get
        { url = "https://" ++ address ++ "/sessions"
        , expect =
            Http.expectJson
                (Result.withDefault [] >> tagger)
                (Decode.list Decode.string)
        }
