module Icons exposing (..)

import Html exposing (Html)
import Html.Attributes exposing (class)


icon : String -> Html msg
icon name =
    Html.node "i"
        [ class "icon"
        , class name
        ]
        []


objectType : Html msg
objectType =
    icon "type-icons-type-object"


stringType : Html msg
stringType =
    icon "type-icons-type-string"


sortAsc : Html msg
sortAsc =
    icon "sort-asc"


sortDesc : Html msg
sortDesc =
    icon "sort-desc"
