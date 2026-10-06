-- SPDX-License-Identifier: WTFPL
-- Theorem counterparts of the Lean specification (see third_party/README.md).
{-# OPTIONS --safe #-}
module Json2dir.Proofs where

open import Json2dir.Base
open import Json2dir.Value
open import Json2dir.Spec

andLeft : ∀ a b → (a && b) ≡ true → a ≡ true
andLeft true b h = refl
andLeft false b ()

andRight : ∀ a b → (a && b) ≡ true → b ≡ true
andRight true b h = h
andRight false b ()

notTrue : ∀ b → not b ≡ true → b ≡ false
notTrue true ()
notTrue false h = refl

-- The executable consumes a certified SafeName. These theorems concern the
-- actual parseName/interpretParts functions, not a separate model.
interpretParts-safe : ∀ parts prefix name →
  interpretParts parts prefix ≡ ok name → safeComponent (component name) ≡ true
interpretParts-safe parts prefix name h = certified name

parseName-safe : ∀ input name →
  parseName input ≡ ok name → safeComponent (component name) ≡ true
parseName-safe input name h = certified name

interpretParts-shape : ∀ parts prefix name →
  interpretParts parts prefix ≡ ok name →
  Pair (parts ≡ (component name ∷ [])) (prefix ≡ false)
interpretParts-shape [] true name ()
interpretParts-shape (_ ∷ _) true name ()
interpretParts-shape [] false name ()
interpretParts-shape (part ∷ []) false name h with decide (safeComponent part)
... | nothing = impossible h
  where
    impossible : err "is a non-regular path component" ≡ ok name →
      Pair ((part ∷ []) ≡ (component name ∷ [])) (false ≡ false)
    impossible ()
... | just proof with h
...   | refl = refl , refl
interpretParts-shape (_ ∷ _ ∷ _) false name ()

parseName-single-component : ∀ input name →
  parseName input ≡ ok name →
  Pair (regularParts (partsAcc (primStringToList input) []) ≡ (component name ∷ []))
       (hasPrefix (primStringToList input) ≡ false)
parseName-single-component input name h = interpretParts-shape _ _ name h

record NoTraversal (part : String) : Set where
  field
    nonempty : primStringEquality part "" ≡ false
    not-dot : primStringEquality part "." ≡ false
    not-parent : primStringEquality part ".." ≡ false
    no-slash : contains '/' (primStringToList part) ≡ false
    no-nul : contains '\x00' (primStringToList part) ≡ false

safe-noTraversal : ∀ part → safeComponent part ≡ true → NoTraversal part
safe-noTraversal part h = record
  { nonempty = notTrue _ (andLeft a (b && (c && (d && e))) h)
  ; not-dot = notTrue _ (andLeft b (c && (d && e)) h₁)
  ; not-parent = notTrue _ (andLeft c (d && e) h₂)
  ; no-slash = notTrue _ (andLeft d e h₃)
  ; no-nul = notTrue _ (andRight d e h₃)
  }
  where
    a = not (primStringEquality part "")
    b = not (primStringEquality part ".")
    c = not (primStringEquality part "..")
    d = not (contains '/' (primStringToList part))
    e = not (contains '\x00' (primStringToList part))
    h₁ : (b && (c && (d && e))) ≡ true
    h₁ = andRight a (b && (c && (d && e))) h
    h₂ : (c && (d && e)) ≡ true
    h₂ = andRight b (c && (d && e)) h₁
    h₃ : (d && e) ≡ true
    h₃ = andRight c (d && e) h₂

parseName-noTraversal : ∀ input name →
  parseName input ≡ ok name → NoTraversal (component name)
parseName-noTraversal input name h = safe-noTraversal (component name) (certified name)

classify-directory : ∀ children → classify (object children) ≡ ok (directory children)
classify-directory children = refl

classify-file : ∀ content → classify (string content) ≡ ok (file content)
classify-file content = refl

classify-link : ∀ target →
  classify (array (string "link" ∷ string target ∷ [])) ≡ ok (link target)
classify-link target = refl

classify-script : ∀ content →
  classify (array (string "script" ∷ string content ∷ [])) ≡ ok (script content)
classify-script content = refl

classify-unknown-kind : ∀ kind payload →
  primStringEquality kind "link" ≡ false →
  primStringEquality kind "script" ≡ false →
  classify (array (string kind ∷ string payload ∷ [])) ≡ err invalidArrayKind
classify-unknown-kind kind payload h₁ h₂ rewrite h₁ | h₂ = refl

classify-empty-array : classify (array []) ≡ err invalidArray
classify-empty-array = refl

classify-null : classify null ≡ err invalidPart
classify-null = refl

classify-bool : ∀ b → classify (boolean b) ≡ err invalidPart
classify-bool b = refl

classify-num : ∀ n → classify (number n) ≡ err invalidPart
classify-num n = refl
