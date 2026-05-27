module MiniLang.Error where

data RuntimeError
  = UndefinedVariable String
  | TypeMismatch String
  | DivisionByZero
  deriving (Eq, Show)