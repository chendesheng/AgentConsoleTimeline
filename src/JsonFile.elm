module JsonFile exposing (JsonFile, jsonFileDecoder)

import Json.Decode as D


type alias JsonFile =
    { name : String
    , text : String
    , json : D.Value
    }


jsonFileDecoder : D.Decoder JsonFile
jsonFileDecoder =
    D.map3 (\name text json -> { name = name, text = text, json = json })
        (D.field "name" D.string)
        (D.field "text" D.string)
        (D.field "json" D.value)
