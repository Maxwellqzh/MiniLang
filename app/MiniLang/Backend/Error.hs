module MiniLang.Backend.Error where

data RuntimeError
  = UndefinedVariable String
  | TypeMismatch String
  | DivisionByZero
  | ArityMismatch Int Int
  | NotCallable String
  | ReturnOutsideFunction
  deriving (Eq, Show)
