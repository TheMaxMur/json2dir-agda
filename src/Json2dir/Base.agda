{-# OPTIONS --safe #-}
module Json2dir.Base where

open import Agda.Builtin.Bool public
open import Agda.Builtin.Nat public
open import Agda.Builtin.Char public
open import Agda.Builtin.String public
open import Agda.Builtin.List public
open import Agda.Builtin.Maybe public
open import Agda.Builtin.Unit public
open import Agda.Builtin.Equality public

infixr 3 _&&_
infixr 2 _||_
infixr 5 _++_
infixr 4 _<>_
infix 0 if_then_else_

not : Bool → Bool
not true = false
not false = true

_&&_ _||_ : Bool → Bool → Bool
true && b = b
false && b = false
true || b = true
false || b = b

if_then_else_ : ∀ {A : Set} → Bool → A → A → A
if true then x else y = x
if false then x else y = y

_<>_ : String → String → String
_<>_ = primStringAppend

record Pair (A B : Set) : Set where
  constructor _,_
  field fst : A
        snd : B
open Pair public

data Result (A : Set) : Set where
  ok : A → Result A
  err : String → Result A

_++_ : ∀ {A : Set} → List A → List A → List A
[] ++ ys = ys
(x ∷ xs) ++ ys = x ∷ (xs ++ ys)

length : ∀ {A : Set} → List A → Nat
length [] = zero
length (_ ∷ xs) = suc (length xs)

reverseAcc : ∀ {A : Set} → List A → List A → List A
reverseAcc [] ys = ys
reverseAcc (x ∷ xs) ys = reverseAcc xs (x ∷ ys)

reverse : ∀ {A : Set} → List A → List A
reverse xs = reverseAcc xs []

contains : Char → List Char → Bool
contains c [] = false
contains c (x ∷ xs) = primCharEquality c x || contains c xs

digit : Char → Bool
digit c = not (primCharToNat c < 48) && (primCharToNat c < 58)

space : Char → Bool
space c = primCharEquality c ' ' || primCharEquality c '\n' ||
          primCharEquality c '\r' || primCharEquality c '\t'

skipSpace : List Char → List Char
skipSpace [] = []
skipSpace (c ∷ cs) = if space c then skipSpace cs else c ∷ cs

quoted : String → String
quoted s = "\"" <> s <> "\""
