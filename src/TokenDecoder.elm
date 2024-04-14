module TokenDecoder exposing (parseToken)

import Base64
import Iso8601
import Json.Decode as Decode exposing (Decoder, field)
import Json.Encode as Encode
import Time


{-| returns token payload
-}
parseToken : String -> Maybe String
parseToken token =
    if String.startsWith "Bearer " token then
        let
            _ =
                token
                    |> String.dropLeft 7
                    |> String.split "."
                    |> Debug.log "splitted"
        in
        case
            token
                |> String.dropLeft 7
                |> String.split "."
        of
            [ _, payload, _ ] ->
                payload
                    |> Base64.decode
                    |> Result.toMaybe
                    |> Maybe.andThen (\decoded -> Decode.decodeString tokenPayloadDecoder decoded |> Result.toMaybe)
                    |> Maybe.map encodeTokenPayload

            _ ->
                Nothing

    else
        Nothing


type alias TokenPayload =
    { iss : String
    , exp : Time.Posix
    , nbf : Time.Posix
    , jti : String
    , thumbprint : String
    , aud : String
    , siteId : String
    , agentId : String
    }


decodePosix : Decoder Time.Posix
decodePosix =
    Decode.int |> Decode.map (\seconds -> Time.millisToPosix (seconds * 1000))


tokenPayloadDecoder : Decoder TokenPayload
tokenPayloadDecoder =
    Decode.map8 TokenPayload
        (field "iss" Decode.string)
        (field "exp" decodePosix)
        (field "nbf" decodePosix)
        (field "jti" Decode.string)
        (field "thumbprint" Decode.string)
        (field "aud" Decode.string)
        (field "siteId" Decode.string)
        (field "agentId" Decode.string)


encodeTokenPayload : TokenPayload -> String
encodeTokenPayload payload =
    Encode.object
        [ ( "iss", Encode.string payload.iss )
        , ( "exp", Encode.string (Iso8601.fromTime payload.exp) )
        , ( "nbf", Encode.string (Iso8601.fromTime payload.nbf) )
        , ( "jti", Encode.string payload.jti )
        , ( "thumbprint", Encode.string payload.thumbprint )
        , ( "aud", Encode.string payload.aud )
        , ( "siteId", Encode.string payload.siteId )
        , ( "agentId", Encode.string payload.agentId )
        ]
        |> Encode.encode 0
