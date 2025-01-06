port module UnzipFile exposing (..)

{-| input base64 data url
-}


port unzipFile : String -> Cmd msg


port gotUnzippedFile : ({ fileName : String, content : String } -> msg) -> Sub msg


port gotUnzippedFileError : (String -> msg) -> Sub msg
