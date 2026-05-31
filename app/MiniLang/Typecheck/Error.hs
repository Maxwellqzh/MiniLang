module MiniLang.Typecheck.Error
  ( TypeError (..)
  ) where

import MiniLang.Typecheck.Type

data TypeError
  = UnboundVariable String
  | ExpectedType String Type Type
  | ExpectedNumeric String Type
  | ExpectedFunction Type
  | ArityMismatch Int Int
  | ConstructorArityMismatch String Int Int
  | UnknownConstructor String
  | CannotCompareFunctions Type Type
  | ReturnOutsideFunction
  | NotAllPathsReturn
  | UnsupportedFeature String
  | InfiniteType Int Type
  deriving (Eq)

instance Show TypeError where
  show err =
    case err of
      UnboundVariable name ->
        "type error: unbound variable " ++ show name
      ExpectedType context expected actual ->
        "type error in "
          ++ context
          ++ ": expected "
          ++ show expected
          ++ ", but found "
          ++ show actual
      ExpectedNumeric context actual ->
        "type error in "
          ++ context
          ++ ": expected numeric operand, but found "
          ++ show actual
      ExpectedFunction actual ->
        "type error: expected a function, but found " ++ show actual
      ArityMismatch expected actual ->
        "type error: expected "
          ++ show expected
          ++ " argument(s), but got "
          ++ show actual
      ConstructorArityMismatch name expected actual ->
        "type error: constructor "
          ++ name
          ++ " expects "
          ++ show expected
          ++ " field(s), but got "
          ++ show actual
      UnknownConstructor name ->
        "type error: unknown constructor " ++ name
      CannotCompareFunctions left right ->
        "type error: function values cannot be compared: "
          ++ show left
          ++ " and "
          ++ show right
      ReturnOutsideFunction ->
        "type error: return used outside of a function"
      NotAllPathsReturn ->
        "type error: not all control-flow paths return a value"
      UnsupportedFeature message ->
        "type error: unsupported feature: " ++ message
      InfiniteType var ty ->
        "type error: cannot construct infinite type t"
          ++ show var
          ++ " ~ "
          ++ show ty
