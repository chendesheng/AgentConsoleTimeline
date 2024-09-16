port module RecentFile exposing (..)


port saveRecentFile : { fileName : String, fileContent : String } -> Cmd msg


port getFileContent : String -> Cmd msg



-- port getRecentFiles : () -> Cmd msg


port gotFileContent : (String -> msg) -> Sub msg


port gotRecentFiles : (List RecentFile -> msg) -> Sub msg


port clearRecentFiles : () -> Cmd msg


port deleteRecentFile : String -> Cmd msg


type alias RecentFile =
    { key : String
    , fileName : String
    , lastOpenTime : Int
    }
