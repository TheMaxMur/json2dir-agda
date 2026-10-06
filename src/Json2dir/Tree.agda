module Json2dir.Tree where

open import Json2dir.Base
open import Json2dir.Value
open import Json2dir.Spec
open import Json2dir.Native

attempt : IO ⊤ → IO (Result ⊤)
attempt action = catchIO (action >> pure (ok tt)) (λ _ e → pure (err e))

ignore : IO ⊤ → IO ⊤
ignore action = catchIO action (λ _ _ → pure tt)

contextual : String → String → IO ⊤ → IO (Result ⊤)
contextual message context action =
  attempt action >>= λ where
    (ok _) → pure (ok tt)
    (err e) → pure (err (message <> " at " <> quoted context <> ": " <> e))

create : String → String → IO ⊤ → IO (Result ⊤)
create kind = contextual ("couldn't create a " <> kind)

-- Pure bit arithmetic: set mode's 0o111 bits, preserving every other bit.
odd : Nat → Bool
odd n = mod-helper 0 1 n 1 == 1

half : Nat → Nat
half n = div-helper 0 1 n 1

hasBit : Nat → Nat → Bool
hasBit n zero = odd n
hasBit n (suc bit) = hasBit (half n) bit

executableMode : Nat → Nat
executableMode mode = mode +
  (if hasBit mode 0 then 0 else 1) +
  (if hasBit mode 3 then 0 else 8) +
  (if hasBit mode 6 then 0 else 64)

makeExecutable : String → String → IO (Result ⊤)
makeExecutable name context = catchIO
  (getMode name >>= λ mode →
    contextual "couldn't make the script executable" context (setMode name (executableMode mode)))
  (λ _ e → pure (err ("couldn't make the script executable at " <> quoted context <> ": " <> e)))

createDirectory : String → String → IO (Result ⊤)
createDirectory name context = catchIO
  (makeDirectory name >> pure (ok tt))
  (λ exists e → if exists then pure (ok tt)
    else pure (err ("couldn't create a directory at " <> quoted context <> ": " <> e)))

-- Fuel bounds traversal too: each step consumes a JSON node or member, so
-- the input-derived parser budget is more than sufficient.
mutual
  writeObject : Nat → String → List (Pair String Json) → IO (Result ⊤)
  writeObject zero _ _ = pure (err "tree traversal limit exceeded")
  writeObject (suc fuel) parent [] = pure (ok tt)
  writeObject (suc fuel) parent ((name , val) ∷ rest) with parseName name
  ... | err e = pure (err ("the key " <> quoted name <> " under " <> quoted parent <> " " <> e))
  ... | ok checked =
    ignore (removeFile name) >>
    writeEntry fuel name (parent <> "/" <> name) val >>= λ where
      (err e) → pure (err e)
      (ok _) → writeObject fuel parent rest

  writeEntry : Nat → String → String → Json → IO (Result ⊤)
  writeEntry zero _ _ _ = pure (err "tree traversal limit exceeded")
  writeEntry (suc fuel) name context val with classify val
  ... | err e = pure (err (e <> " while at " <> quoted context))
  ... | ok (file content) = create "regular file" context (writeFile name content)
  ... | ok (link target) =
    if contains '\x00' (primStringToList target)
    then pure (err ("couldn't create a symlink at " <> quoted context <> ": NUL in target"))
    else create "symlink" context (symlink target name)
  ... | ok (script content) =
    create "script" context (writeFile name content) >>= λ where
      (err e) → pure (err e)
      (ok _) → makeExecutable name context
  ... | ok (directory children) =
    createDirectory name context >>= λ where
      (err e) → pure (err e)
      (ok _) → contextual "couldn't set the current dir to the newly created path" context
        (changeDirectory name) >>= λ where
          (err e) → pure (err e)
          (ok _) → writeObject fuel context children >>= λ result →
            contextual "couldn't set the current dir to the dir above" context
              (changeDirectory "..") >>= λ where
                (err e) → pure (err e)
                (ok _) → pure result
