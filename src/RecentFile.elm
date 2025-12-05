port module RecentFile exposing (..)

import JsonFile exposing (JsonFile)


port saveRecentFile : { fileName : String, fileContent : String } -> Cmd msg


port getFileContent : String -> Cmd msg



-- port getRecentFiles : () -> Cmd msg


port setWaitOpeningFile : (String -> msg) -> Sub msg


port gotFileContent : (JsonFile -> msg) -> Sub msg


port gotRecentFiles : (List RecentFile -> msg) -> Sub msg


port clearRecentFiles : () -> Cmd msg


port deleteRecentFile : String -> Cmd msg


type alias RecentFile =
    { key : String
    , fileName : String
    , lastOpenTime : Int
    , size : Int
    }
