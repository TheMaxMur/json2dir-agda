module Json2dir.Native where

open import Json2dir.Base
open import Agda.Builtin.IO public

-- Trusted OS boundary only. No JSON, path policy, traversal or CLI logic is
-- implemented by the backend. The portable pure modules all use --safe.
postulate
  pure : ∀ {A : Set} → A → IO A
  _>>=_ : ∀ {A B : Set} → IO A → (A → IO B) → IO B
  catchIO : ∀ {A : Set} → IO A → (Bool → String → IO A) → IO A
  args : IO (List String)
  stdin : IO String
  stderr : String → IO ⊤
  exitFailure : IO ⊤
  removeFile : String → IO ⊤
  makeDirectory : String → IO ⊤
  changeDirectory : String → IO ⊤
  writeFile : String → String → IO ⊤
  symlink : String → String → IO ⊤
  getMode : String → IO Nat
  setMode : String → Nat → IO ⊤

infixl 1 _>>=_ _>>_
_>>_ : ∀ {A B : Set} → IO A → IO B → IO B
x >> y = x >>= λ _ → y

{-# FOREIGN GHC import qualified Control.Exception as E #-}
{-# FOREIGN GHC import qualified Data.ByteString as BS #-}
{-# FOREIGN GHC import qualified Data.Text as T #-}
{-# FOREIGN GHC import qualified Data.Text.Encoding as TE #-}
{-# FOREIGN GHC import qualified System.Directory as D #-}
{-# FOREIGN GHC import qualified System.Environment as Env #-}
{-# FOREIGN GHC import qualified System.Exit as Exit #-}
{-# FOREIGN GHC import qualified System.IO as S #-}
{-# FOREIGN GHC import qualified System.IO.Error as SE #-}
{-# FOREIGN GHC import qualified System.Posix.Files as P #-}

{-# COMPILE GHC pure = \_ -> return #-}
{-# COMPILE GHC _>>=_ = \_ _ -> (>>=) #-}
{-# COMPILE GHC catchIO = \_ action handler -> E.catch action (\e -> handler (SE.isAlreadyExistsError e) (T.pack (E.displayException (e :: E.IOException)))) #-}
{-# COMPILE GHC args = fmap (map T.pack) Env.getArgs #-}
{-# COMPILE GHC stdin = BS.getContents >>= either (E.throwIO . SE.userError . show) return . TE.decodeUtf8' #-}
{-# COMPILE GHC stderr = \s -> BS.hPut S.stderr (TE.encodeUtf8 (T.snoc s '\n')) #-}
{-# COMPILE GHC exitFailure = Exit.exitFailure #-}
{-# COMPILE GHC removeFile = D.removeFile . T.unpack #-}
{-# COMPILE GHC makeDirectory = D.createDirectory . T.unpack #-}
{-# COMPILE GHC changeDirectory = D.setCurrentDirectory . T.unpack #-}
{-# COMPILE GHC writeFile = \path content -> BS.writeFile (T.unpack path) (TE.encodeUtf8 content) #-}
{-# COMPILE GHC symlink = \target path -> P.createSymbolicLink (T.unpack target) (T.unpack path) #-}
{-# COMPILE GHC getMode = fmap (toInteger . P.fileMode) . P.getFileStatus . T.unpack #-}
{-# COMPILE GHC setMode = \path mode -> P.setFileMode (T.unpack path) (fromInteger mode) #-}
