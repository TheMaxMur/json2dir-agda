{-# OPTIONS --safe #-}
module Json2dir.Value where

open import Json2dir.Base

data Json : Set where
  object : List (Pair String Json) → Json
  array : List Json → Json
  string : String → Json
  number : String → Json
  boolean : Bool → Json
  null : Json

-- serde_json's default maps use sorted keys, with the last duplicate winning.
charsLess : List Char → List Char → Bool
charsLess [] [] = false
charsLess [] (_ ∷ _) = true
charsLess (_ ∷ _) [] = false
charsLess (x ∷ xs) (y ∷ ys) =
  if primCharEquality x y then charsLess xs ys
  else primCharToNat x < primCharToNat y

insert : Pair String Json → List (Pair String Json) → List (Pair String Json)
insert item [] = item ∷ []
insert (key , val) ((name , old) ∷ rest) =
  if primStringEquality key name then (key , val) ∷ rest
  else if charsLess (primStringToList key) (primStringToList name)
       then (key , val) ∷ (name , old) ∷ rest
       else (name , old) ∷ insert (key , val) rest
