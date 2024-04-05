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


close : Html msg
close =
    icon "close"


jsDoc : Html msg
jsDoc =
    icon "jsdoc"


imageDoc : Html msg
imageDoc =
    icon "imagedoc"


networkDoc : Html msg
networkDoc =
    icon "networkdoc"
