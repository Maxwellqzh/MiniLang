module MiniLang.Backend.Error where

data RuntimeError
  = UndefinedVariable String
  | TypeMismatch String
  | DivisionByZero
  | ArityMismatch Int Int
  | ConstructorArityMismatch String Int Int
  | UnknownConstructor String
  | NotCallable String
  | MatchFailure
  | InvalidPattern String
  | ReturnOutsideFunction
  deriving (Eq, Show)
