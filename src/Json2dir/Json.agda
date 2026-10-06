{-# OPTIONS --safe #-}
module Json2dir.Json where

open import Json2dir.Base
open import Json2dir.Value
open import Json2dir.Number

bad : ∀ {A : Set} → Result A
bad = err "couldn't convert stdin to JSON"

hex : Char → Maybe Nat
hex c =
  if digit c then just (primCharToNat c - 48)
  else if not (primCharToNat c < 65) && (primCharToNat c < 71)
       then just (primCharToNat c - 55)
       else if not (primCharToNat c < 97) && (primCharToNat c < 103)
            then just (primCharToNat c - 87) else nothing

hex4 : List Char → Result (Pair Nat (List Char))
hex4 (a ∷ b ∷ c ∷ d ∷ rest) with hex a | hex b | hex c | hex d
... | just w | just x | just y | just z = ok ((4096 * w + 256 * x + 16 * y + z) , rest)
... | _ | _ | _ | _ = bad
hex4 _ = bad

lowSurrogate : Nat → List Char → Result (Pair Char (List Char))
lowSurrogate hi ('\\' ∷ 'u' ∷ cs) with hex4 cs
... | err e = err e
... | ok (lo , rest) =
  if not (lo < 56320) && (lo < 57344)
  then ok (primNatToChar (65536 + (hi - 55296) * 1024 + (lo - 56320)) , rest)
  else bad
lowSurrogate _ _ = bad

unicodeEscape : List Char → Result (Pair Char (List Char))
unicodeEscape cs with hex4 cs
... | err e = err e
... | ok (n , rest) =
  if (n < 55296) || not (n < 57344) then ok (primNatToChar n , rest)
  else if n < 56320 then lowSurrogate n rest else bad

escape : List Char → Result (Pair Char (List Char))
escape ('"' ∷ cs) = ok ('"' , cs)
escape ('\\' ∷ cs) = ok ('\\' , cs)
escape ('/' ∷ cs) = ok ('/' , cs)
escape ('b' ∷ cs) = ok ('\b' , cs)
escape ('f' ∷ cs) = ok ('\f' , cs)
escape ('n' ∷ cs) = ok ('\n' , cs)
escape ('r' ∷ cs) = ok ('\r' , cs)
escape ('t' ∷ cs) = ok ('\t' , cs)
escape ('u' ∷ cs) = unicodeEscape cs
escape _ = bad

stringBody : Nat → List Char → List Char → Result (Pair String (List Char))
stringBody zero _ _ = bad
stringBody (suc fuel) [] _ = bad
stringBody (suc fuel) ('"' ∷ rest) acc = ok (primStringFromList (reverse acc) , rest)
stringBody (suc fuel) ('\\' ∷ rest) acc with escape rest
... | err e = err e
... | ok (c , cs) = stringBody fuel cs (c ∷ acc)
stringBody (suc fuel) (c ∷ cs) acc =
  if primCharToNat c < 32 then bad else stringBody fuel cs (c ∷ acc)

literal : List Char → List Char → Result (List Char)
literal [] cs = ok cs
literal (_ ∷ _) [] = bad
literal (x ∷ xs) (c ∷ cs) =
  if primCharEquality x c then literal xs cs else bad

digits : List Char → List Char
digits [] = []
digits (c ∷ cs) = if digit c then digits cs else c ∷ cs

requiredDigits : List Char → Result (List Char)
requiredDigits [] = bad
requiredDigits (c ∷ cs) = if digit c then ok (digits cs) else bad

exponent : List Char → Result (List Char)
exponent ('+' ∷ cs) = requiredDigits cs
exponent ('-' ∷ cs) = requiredDigits cs
exponent cs = requiredDigits cs

afterFraction : List Char → Result (List Char)
afterFraction ('e' ∷ cs) = exponent cs
afterFraction ('E' ∷ cs) = exponent cs
afterFraction cs = ok cs

afterInteger : List Char → Result (List Char)
afterInteger ('.' ∷ cs) with requiredDigits cs
... | err e = err e
... | ok rest = afterFraction rest
afterInteger cs = afterFraction cs

unsignedNumber : List Char → Result (List Char)
unsignedNumber ('0' ∷ cs) = afterInteger cs
unsignedNumber (c ∷ cs) = if digit c then afterInteger (digits cs) else bad
unsignedNumber [] = bad

numberEnd : List Char → Result (List Char)
numberEnd ('-' ∷ cs) = unsignedNumber cs
numberEnd cs = unsignedNumber cs

take : ∀ {A : Set} → Nat → List A → List A
take zero _ = []
take (suc n) [] = []
take (suc n) (x ∷ xs) = x ∷ take n xs

parseNumber : List Char → Result (Pair Json (List Char))
parseNumber cs with numberEnd cs
... | err e = err e
... | ok rest =
  if finiteNumber (take (length cs - length rest) cs)
  then ok (number (primStringFromList (take (length cs - length rest) cs)) , rest)
  else bad

-- Fuel decreases at every recursive parser transition, including after a
-- nested value returns. Four transitions per input character suffice; the
-- separate depth budget matches serde_json's default limit: its counter
-- starts at 128 and rejects a container when the decremented counter is 0.
mutual
  value : Nat → Nat → List Char → Result (Pair Json (List Char))
  value zero _ _ = bad
  value (suc fuel) depth cs = token fuel depth (skipSpace cs)

  token : Nat → Nat → List Char → Result (Pair Json (List Char))
  token zero _ _ = bad
  token (suc fuel) depth ('"' ∷ cs) with stringBody fuel cs []
  ... | err e = err e
  ... | ok (s , rest) = ok (string s , rest)
  token (suc fuel) zero ('{' ∷ cs) = bad
  token (suc fuel) (suc depth) ('{' ∷ cs) = objectStart fuel depth (skipSpace cs)
  token (suc fuel) zero ('[' ∷ cs) = bad
  token (suc fuel) (suc depth) ('[' ∷ cs) = arrayStart fuel depth (skipSpace cs)
  token (suc fuel) depth ('t' ∷ cs) with literal ('r' ∷ 'u' ∷ 'e' ∷ []) cs
  ... | err e = err e
  ... | ok rest = ok (boolean true , rest)
  token (suc fuel) depth ('f' ∷ cs) with literal ('a' ∷ 'l' ∷ 's' ∷ 'e' ∷ []) cs
  ... | err e = err e
  ... | ok rest = ok (boolean false , rest)
  token (suc fuel) depth ('n' ∷ cs) with literal ('u' ∷ 'l' ∷ 'l' ∷ []) cs
  ... | err e = err e
  ... | ok rest = ok (null , rest)
  token (suc fuel) depth [] = bad
  token (suc fuel) depth (c ∷ cs) =
    if digit c || primCharEquality c '-' then parseNumber (c ∷ cs) else bad

  objectStart : Nat → Nat → List Char → Result (Pair Json (List Char))
  objectStart zero _ _ = bad
  objectStart (suc fuel) depth ('}' ∷ rest) = ok (object [] , rest)
  objectStart (suc fuel) depth cs = member fuel depth cs []

  member : Nat → Nat → List Char → List (Pair String Json) → Result (Pair Json (List Char))
  member zero _ _ _ = bad
  member (suc fuel) depth ('"' ∷ cs) acc with stringBody fuel cs []
  ... | err e = err e
  ... | ok (key , rest) = colon fuel depth (skipSpace rest) key acc
  member (suc fuel) depth _ _ = bad

  colon : Nat → Nat → List Char → String → List (Pair String Json) → Result (Pair Json (List Char))
  colon zero _ _ _ _ = bad
  colon (suc fuel) depth (':' ∷ cs) key acc with value fuel depth cs
  ... | err e = err e
  ... | ok (v , rest) = objectTail fuel depth (skipSpace rest) (insert (key , v) acc)
  colon (suc fuel) depth _ _ _ = bad

  objectTail : Nat → Nat → List Char → List (Pair String Json) → Result (Pair Json (List Char))
  objectTail zero _ _ _ = bad
  objectTail (suc fuel) depth ('}' ∷ rest) acc = ok (object acc , rest)
  objectTail (suc fuel) depth (',' ∷ cs) acc = member fuel depth (skipSpace cs) acc
  objectTail (suc fuel) depth _ _ = bad

  arrayStart : Nat → Nat → List Char → Result (Pair Json (List Char))
  arrayStart zero _ _ = bad
  arrayStart (suc fuel) depth (']' ∷ rest) = ok (array [] , rest)
  arrayStart (suc fuel) depth cs = element fuel depth cs []

  element : Nat → Nat → List Char → List Json → Result (Pair Json (List Char))
  element zero _ _ _ = bad
  element (suc fuel) depth cs acc with value fuel depth cs
  ... | err e = err e
  ... | ok (v , rest) = arrayTail fuel depth (skipSpace rest) (v ∷ acc)

  arrayTail : Nat → Nat → List Char → List Json → Result (Pair Json (List Char))
  arrayTail zero _ _ _ = bad
  arrayTail (suc fuel) depth (']' ∷ rest) acc = ok (array (reverse acc) , rest)
  arrayTail (suc fuel) depth (',' ∷ cs) acc = element fuel depth (skipSpace cs) acc
  arrayTail (suc fuel) depth _ _ = bad

parse : String → Result Json
parse s with value (10 + 4 * length (primStringToList s)) 127 (primStringToList s)
... | err e = err e
... | ok (v , rest) with skipSpace rest
...   | [] = ok v
...   | _ ∷ _ = bad
