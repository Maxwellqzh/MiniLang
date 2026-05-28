module MiniLang.Backend.Value where

import qualified Data.Map as Map
import MiniLang.Parsing.Syntax (Stmt)

type Env = Map.Map String Value

data Value
  = VInt Int
  | VBool Bool
  | VString String
  | VUnit
  | VFunction [String] [Stmt] Env

instance Eq Value where
  VInt left == VInt right = left == right
  VBool left == VBool right = left == right
  VString left == VString right = left == right
  VUnit == VUnit = True
  VFunction {} == VFunction {} = False
  _ == _ = False

instance Show Value where
  show (VInt value) = show value
  show (VBool True) = "true"
  show (VBool False) = "false"
  show (VString value) = show value
  show VUnit = "unit"
  show VFunction {} = "<function>"
