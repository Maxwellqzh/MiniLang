module MiniLang.Typecheck.Type
  ( Type (..)
  , TypeEnv
  , emptyTypeEnv
  , applySubstType
  , applySubstEnv
  , maxTypeVarInEnv
  ) where

import qualified Data.Map as Map

data Type
  = TInt
  | TFloat
  | TBool
  | TString
  | TUnit
  | TData String
  | TFun [Type] Type
  | TVar Int
  deriving (Eq, Ord)

instance Show Type where
  show TInt = "Int"
  show TFloat = "Float"
  show TBool = "Bool"
  show TString = "String"
  show TUnit = "Unit"
  show (TData name) = name
  show (TVar var) = "t" ++ show var
  show (TFun args result) =
    let renderedArgs =
          case args of
            [] -> "()"
            [arg] -> showAtomic arg
            _ -> "(" ++ joinWith ", " (map showAtomic args) ++ ")"
     in renderedArgs ++ " -> " ++ show result

type TypeEnv = Map.Map String Type

emptyTypeEnv :: TypeEnv
emptyTypeEnv = Map.empty

applySubstType :: Map.Map Int Type -> Type -> Type
applySubstType subst ty =
  case ty of
    TInt -> TInt
    TFloat -> TFloat
    TBool -> TBool
    TString -> TString
    TUnit -> TUnit
    TData name -> TData name
    TVar var ->
      case Map.lookup var subst of
        Nothing -> TVar var
        Just resolved -> applySubstType subst resolved
    TFun args result ->
      TFun (map (applySubstType subst) args) (applySubstType subst result)

applySubstEnv :: Map.Map Int Type -> TypeEnv -> TypeEnv
applySubstEnv subst = Map.map (applySubstType subst)

maxTypeVarInEnv :: TypeEnv -> Int
maxTypeVarInEnv env =
  foldr max (-1) (map maxTypeVarInType (Map.elems env))

maxTypeVarInType :: Type -> Int
maxTypeVarInType ty =
  case ty of
    TInt -> -1
    TFloat -> -1
    TBool -> -1
    TString -> -1
    TUnit -> -1
    TData {} -> -1
    TVar var -> var
    TFun args result -> foldr max (maxTypeVarInType result) (map maxTypeVarInType args)

showAtomic :: Type -> String
showAtomic ty =
  case ty of
    TFun {} -> "(" ++ show ty ++ ")"
    _ -> show ty

joinWith :: String -> [String] -> String
joinWith separator items =
  case items of
    [] -> ""
    [item] -> item
    item : rest -> item ++ concatMap (separator ++) rest
