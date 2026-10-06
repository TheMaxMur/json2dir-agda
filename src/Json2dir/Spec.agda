-- SPDX-License-Identifier: WTFPL
-- Adapted from tsalkenov/json2dir-lean, Spec.lean (see third_party/README.md).
{-# OPTIONS --safe #-}
module Json2dir.Spec where

open import Json2dir.Base
open import Json2dir.Value

safeComponent : String → Bool
safeComponent part = not (primStringEquality part "") &&
  (not (primStringEquality part ".") &&
  (not (primStringEquality part "..") &&
  (not (contains '/' (primStringToList part)) &&
   not (contains '\x00' (primStringToList part)))))

record SafeName : Set where
  constructor safeName
  field
    component : String
    certified : safeComponent component ≡ true
open SafeName public

decide : (b : Bool) → Maybe (b ≡ true)
decide true = just refl
decide false = nothing

partsAcc : List Char → List Char → List String
partsAcc [] acc = primStringFromList (reverse acc) ∷ []
partsAcc ('/' ∷ cs) acc = primStringFromList (reverse acc) ∷ partsAcc cs []
partsAcc (c ∷ cs) acc = partsAcc cs (c ∷ acc)

regularParts : List String → List String
regularParts [] = []
regularParts (p ∷ ps) =
  if primStringEquality p "" || primStringEquality p "."
  then regularParts ps else p ∷ regularParts ps

hasPrefix : List Char → Bool
hasPrefix ('/' ∷ _) = true
hasPrefix ('.' ∷ '/' ∷ _) = true
hasPrefix ('.' ∷ []) = true
hasPrefix _ = false

interpretParts : List String → Bool → Result SafeName
interpretParts [] true = err "is a non-regular path component"
interpretParts _ true = err "must have exactly one path component"
interpretParts (part ∷ []) false with decide (safeComponent part)
... | just proof = ok (safeName part proof)
... | nothing = err "is a non-regular path component"
interpretParts _ false = err "must have exactly one path component"

parseName : String → Result SafeName
parseName name = interpretParts
  (regularParts (partsAcc (primStringToList name) []))
  (hasPrefix (primStringToList name))

data Entry : Set where
  directory : List (Pair String Json) → Entry
  file link script : String → Entry

invalidPart invalidArray invalidArrayKind : String
invalidPart = "expected a JSON value to be an object, an array, or a string"
invalidArray = "expected a JSON array to be of the form [type, payload]"
invalidArrayKind = "expected a JSON array's first element to be either \"link\" or \"script\""

classify : Json → Result Entry
classify (object children) = ok (directory children)
classify (string content) = ok (file content)
classify (array (string kind ∷ string payload ∷ [])) =
  if primStringEquality kind "link" then ok (link payload)
  else if primStringEquality kind "script" then ok (script payload)
       else err invalidArrayKind
classify (array _) = err invalidArray
classify _ = err invalidPart
