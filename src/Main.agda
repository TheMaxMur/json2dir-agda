module Main where

open import Json2dir.Base
open import Json2dir.Value
open import Json2dir.Json
open import Json2dir.Native
open import Json2dir.Tree

report : Result ⊤ → IO ⊤
report (ok _) = pure tt
report (err e) = stderr ("Error: " <> e <> ".") >> exitFailure

run : String → IO ⊤
run input with parse input
... | err e = report (err e)
... | ok (object entries) =
  writeObject (10 + 4 * length (primStringToList input)) "." entries >>= report
... | ok _ = report (err "expected provided JSON to be an object")

main : IO ⊤
main = args >>= λ where
  [] → catchIO (stdin >>= run)
    (λ _ e → report (err ("couldn't read stdin to an internal representation: " <> e)))
  (_ ∷ _) → stderr "Usage: json2dir < file.json" >> exitFailure
