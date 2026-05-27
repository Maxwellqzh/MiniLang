module MiniLang.Value where

data Value
  = VInt Int
  | VBool Bool
  | VString String
  | VUnit
  deriving (Eq, Show)