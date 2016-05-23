module Bugzilla exposing (Model, Msg, update, view, init)

import Debug
import Dict exposing (Dict)
import Html exposing (..)
-- import Html.Attributes exposing (..)
import Http
import Json.Decode exposing ((:=), Decoder, at, andThen, int, list, string, maybe, object3, succeed)
import Json.Decode.Extra exposing ((|:), dict2)
import Regex
import String
import Task


-- MODEL


type alias Model =
  Dict Int Bug


init : (Model, Cmd Msg)
init =
  (Dict.empty, fetch)


-- TYPES


type alias Bug =
  { id : Int
  , summary : String
  , product : String
  , component : String
  , state : Maybe State
  , priority: Maybe Priority
  }


type State
  = Unconfirmed
  | New
  | Assigned
  | Reopened
  | Resolved Resolution
  | Verified Resolution


type Resolution
  = Fixed
  | Invalid
  | WontFix
  | Duplicate Int
  | WorksForMe
  | Incomplete


type Priority
  = P1
  | P2
  | P3
  | PX


-- UPDATE


type Msg
  = FetchOk (Dict Int Bug)
  | FetchFail Http.Error


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    FetchFail _ ->
      (model, Cmd.none)

    FetchOk bugs ->
      (bugs, Cmd.none)


-- VIEW


view : Model -> Html Msg
view model =
  div
    []
    [ h1 [] [ text ("Count of bugs: " ++ (toString <| Dict.size model)) ]
    , table
        []
        [ thead
            []
            [ tr
                []
                [ th [] [ text "ID" ]
                , th [] [ text "Summary "]
                ]
            ]
        , tbody
            []
            (Dict.values model
              |> List.map (\bug ->
                   tr
                     []
                     [ td [] [ text (toString bug.id) ]
                     , td [] [ text bug.summary ]
                     ])
            )
        ]
    ]




-- HTTP


fetch : Cmd Msg
fetch =
  let
    url =
      Http.url
        -- "https://bugzilla.mozilla.org/rest/bug"
        "http://localhost:3000/db"
        [ (,) "keywords" "DevAdvocacy"
        , (,)
            "include_fields"
            (String.join ","
              [ "id"
              , "summary"
              , "status"
              , "resolution"
              , "dupe_of"
              , "product"
              , "component"
              , "whiteboard"
              ])
        ]
  in
    Task.perform FetchFail FetchOk (Http.get bugDecoder url)


-- JSON


bugDecoder : Decoder (Dict Int Bug)
bugDecoder =
  -- In theory, I should be able to do this with Json.Decode.Extra.dict2...
  at ["bugs"] (list decBug)
    |> Json.Decode.map (List.map (\bug -> (,) bug.id bug))
    |> Json.Decode.map Dict.fromList


decId : Decoder Int
decId =
  "id" := int


decBug : Decoder Bug
decBug =
  succeed Bug
    |: ("id" := int)
    |: ("summary" := string)
    |: ("product" := string)
    |: ("component" := string)
    |: andThen -- "state"
         (object3 (,,)
           ("status" := string)
           ("resolution" := string)
           ("dupe_of" := maybe int))
         decState
    |: andThen -- "priority"
         ("whiteboard" := string)
         decPrio


decState : (String, String, Maybe Int) -> Decoder (Maybe State)
decState (status, resolution, dupeOf) =
  let
    resolution' =
      case resolution of
        "FIXED" ->
          Just Fixed

        "INVALID" ->
          Just Invalid

        "WONTFIX" ->
          Just WontFix

        "DUPLICATE" ->
          Maybe.map (\id -> Duplicate id) dupeOf

        "WORKSFORME" ->
          Just WorksForMe

        "INCOMPLETE" ->
          Just Incomplete

        _ ->
          Nothing

    state =
      case status of
        "UNCONFIRMED" ->
          Just Unconfirmed

        "NEW" ->
          Just New

        "ASSIGNED" ->
          Just Assigned

        "REOPENED" ->
          Just Reopened

        "RESOLVED" ->
          Maybe.map (\x -> Resolved x) resolution'

        "VERIFIED" ->
          Maybe.map (\x -> Verified x) resolution'

        _ ->
          Nothing
  in
    succeed state


decPrio : String -> Decoder (Maybe Priority)
decPrio whiteboard =
  let
    pattern =
      Regex.regex "\\[devrel:p(.)\\]"

    matches =
      Regex.find (Regex.AtMost 1) pattern (String.toLower whiteboard)

    submatches =
      List.map (\x -> x.submatches) matches

    priority =
      case submatches of
        [Just "1" :: _] -> Just P1
        [Just "2" :: _] -> Just P2
        [Just "3" :: _] -> Just P3
        [Just "x" :: _] -> Just PX
        _ -> Nothing
  in
    succeed priority
