-- SPDX-License-Identifier: MIT
-- Range algorithm adapted from serde_json 1.0.141 (see third_party/README.md).
{-# OPTIONS --safe #-}
module Json2dir.Number where

open import Json2dir.Base
open import Agda.Builtin.Float

-- Values themselves are unsupported directory entries. We still check every
-- numeric token before any writes (even one hidden by a duplicate key).
-- Match serde_json's default u64-significand / binary64 range check using
-- Agda arithmetic and built-in Float operations, without a foreign parser.
record Parts : Set where
  constructor parts
  field
    significand : Nat
    positiveExp : Nat
    negativeExp : Nat
    remainder : List Char
open Parts

discardInteger : List Char → Nat → Nat → Parts
discardInteger [] sig extra = parts sig extra 0 []
discardInteger (c ∷ cs) sig extra =
  if digit c then discardInteger cs sig (suc extra)
  else parts sig extra 0 (c ∷ cs)

integerParts : List Char → Nat → Parts
integerParts [] sig = parts sig 0 0 []
integerParts (c ∷ cs) sig =
  if digit c then
    if sig * 10 + (primCharToNat c - 48) < 18446744073709551616
    then integerParts cs (sig * 10 + (primCharToNat c - 48))
    else discardInteger cs sig 1
  else parts sig 0 0 (c ∷ cs)

discardFraction : List Char → List Char
discardFraction [] = []
discardFraction (c ∷ cs) = if digit c then discardFraction cs else c ∷ cs

fractionParts : List Char → Nat → Nat → Nat → Parts
fractionParts [] sig pos neg = parts sig pos neg []
fractionParts (c ∷ cs) sig pos neg =
  if digit c then
    if sig * 10 + (primCharToNat c - 48) < 18446744073709551616
    then fractionParts cs (sig * 10 + (primCharToNat c - 48)) pos (suc neg)
    else parts sig pos neg (discardFraction cs)
  else parts sig pos neg (c ∷ cs)

withFraction : Parts → Parts
withFraction (parts sig pos neg ('.' ∷ cs)) = fractionParts cs sig pos neg
withFraction p = p

cappedExponent : List Char → Nat → Nat
cappedExponent [] n = n
cappedExponent (c ∷ cs) n =
  if n < 2147483648 then cappedExponent cs (n * 10 + (primCharToNat c - 48))
  else 2147483648

pow10 : Nat → Nat
pow10 zero = 1
pow10 (suc n) = 10 * pow10 n

finiteParts : Nat → Nat → Nat → Bool
finiteParts zero pos neg = true
finiteParts sig pos neg =
  if pos < neg then true
  else if 308 < (pos - neg) then false
       else not (primFloatIsInfinite
         (primFloatTimes (primNatToFloat sig) (primNatToFloat (pow10 (pos - neg)))))

withExponent : Bool → List Char → Nat → Nat → Nat → Bool
withExponent positive cs sig pos neg =
  if 2147483647 < cappedExponent cs 0
  then (sig == 0) || not positive
  else if positive then finiteParts sig (pos + cappedExponent cs 0) neg
       else finiteParts sig pos (neg + cappedExponent cs 0)

exponentSign : List Char → Nat → Nat → Nat → Bool
exponentSign ('-' ∷ cs) = withExponent false cs
exponentSign ('+' ∷ cs) = withExponent true cs
exponentSign cs = withExponent true cs

checkParts : Parts → Bool
checkParts (parts sig pos neg ('e' ∷ cs)) = exponentSign cs sig pos neg
checkParts (parts sig pos neg ('E' ∷ cs)) = exponentSign cs sig pos neg
checkParts (parts sig pos neg _) = finiteParts sig pos neg

finiteUnsigned : List Char → Bool
finiteUnsigned cs = checkParts (withFraction (integerParts cs 0))

finiteNumber : List Char → Bool
finiteNumber ('-' ∷ cs) = finiteUnsigned cs
finiteNumber cs = finiteUnsigned cs
