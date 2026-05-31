module MiniLang.Backend.Value where

import Data.List (intercalate)
import qualified Data.Map as Map
import MiniLang.Parsing.Syntax (Stmt)

type Env = Map.Map String Value

data Value
  = VInt Int
  | VFloat Double
  | VBool Bool
  | VString String
  | VUnit
  | VFunction [String] [Stmt] Env
  | VConstructor String [Value]
  | VConstructorFunction String Int

instance Eq Value where
  VInt left == VInt right = left == right
  VFloat left == VFloat right = left == right
  VBool left == VBool right = left == right
  VString left == VString right = left == right
  VUnit == VUnit = True
  VFunction {} == VFunction {} = False
  VConstructor leftName leftValues == VConstructor rightName rightValues =
    leftName == rightName && leftValues == rightValues
  VConstructorFunction leftName leftArity == VConstructorFunction rightName rightArity =
    leftName == rightName && leftArity == rightArity
  _ == _ = False

instance Show Value where
  show (VInt value) = show value
  show (VFloat value) = show value
  show (VBool True) = "true"
  show (VBool False) = "false"
  show (VString value) = show value
  show VUnit = "unit"
  show VFunction {} = "<function>"
  show (VConstructor name []) = name
  show (VConstructor name values) = name ++ "(" ++ intercalate ", " (map show values) ++ ")"
  show (VConstructorFunction name _) = "<constructor " ++ name ++ ">"
