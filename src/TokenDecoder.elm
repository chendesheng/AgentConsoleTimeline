module TokenDecoder exposing (parseToken)

import Base64


{-| returns token payload
-}
parseToken : String -> Result String String
parseToken token =
    if String.startsWith "Bearer " token then
        case
            token
                |> String.dropLeft 7
                |> String.split "."
        of
            [ _, payload, _ ] ->
                Base64.decode payload

            _ ->
                Result.Err "Invalid token format"

    else
        Result.Err "Invalid token format"
