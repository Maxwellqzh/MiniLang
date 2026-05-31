module MiniLang.Typecheck.Checker
  ( typecheckProgram
  ) where

import Control.Monad (foldM, zipWithM_)
import Data.Char (isUpper)
import qualified Data.Map as Map
import MiniLang.Parsing.Syntax
import MiniLang.Typecheck.Error
import MiniLang.Typecheck.Type

type Subst = Map.Map Int Type

data TCState = TCState
  { tcNextVar :: Int
  , tcSubst :: Subst
  }

newtype TC a = TC {runTC :: TCState -> Either TypeError (a, TCState)}

instance Functor TC where
  fmap fn action =
    TC $ \state ->
      case runTC action state of
        Left err -> Left err
        Right (value, nextState) -> Right (fn value, nextState)

instance Applicative TC where
  pure value = TC $ \state -> Right (value, state)
  fnAction <*> valueAction = do
    fn <- fnAction
    value <- valueAction
    pure (fn value)

instance Monad TC where
  action >>= fn =
    TC $ \state ->
      case runTC action state of
        Left err -> Left err
        Right (value, nextState) -> runTC (fn value) nextState

data Outcome = Outcome
  { outcomeEnv :: TypeEnv
  , outcomeSawReturn :: Bool
  , outcomeDefiniteReturn :: Maybe Type
  }

typecheckProgram :: TypeEnv -> Program -> Either TypeError TypeEnv
typecheckProgram initialEnv (Program stmts) = do
  let initialState =
        TCState
          { tcNextVar = maxTypeVarInEnv initialEnv + 1
          , tcSubst = Map.empty
          }
  (outcome, finalState) <- runTC (checkBlock False initialEnv stmts) initialState
  pure (applySubstEnv (tcSubst finalState) (outcomeEnv outcome))

checkBlock :: Bool -> TypeEnv -> [Stmt] -> TC Outcome
checkBlock allowReturn env stmts =
  case stmts of
    [] -> pure (Outcome env False Nothing)
    stmt : rest -> do
      stmtOutcome <- checkStmt allowReturn env stmt
      case outcomeDefiniteReturn stmtOutcome of
        Just _ -> pure stmtOutcome
        Nothing -> do
          restOutcome <- checkBlock allowReturn (outcomeEnv stmtOutcome) rest
          pure
            ( Outcome
                (outcomeEnv restOutcome)
                (outcomeSawReturn stmtOutcome || outcomeSawReturn restOutcome)
                (outcomeDefiniteReturn restOutcome)
            )

checkStmt :: Bool -> TypeEnv -> Stmt -> TC Outcome
checkStmt allowReturn env stmt =
  case stmt of
    SLet name expr -> do
      exprType <- inferExpr env expr
      resolvedType <- resolveType exprType
      resolvedEnv <- normalizeEnv env
      pure (continueWith (Map.insert name resolvedType resolvedEnv))
    SAssign name expr -> do
      expectedType <- lookupType env name
      exprType <- inferExpr env expr
      unifyWith ("assignment to " ++ show name) expectedType exprType
      resolvedType <- resolveType expectedType
      resolvedEnv <- normalizeEnv env
      pure (continueWith (Map.insert name resolvedType resolvedEnv))
    SFun name params body -> do
      paramTypes <- mapM (const freshTypeVar) params
      returnType <- freshTypeVar
      let functionType = TFun paramTypes returnType
          closureEnv = Map.insert name functionType env
          paramsEnv = Map.fromList (zip params paramTypes)
          bodyEnv = paramsEnv `Map.union` closureEnv
      bodyType <- checkFunctionBody bodyEnv body
      unifyWith ("return type of function " ++ show name) returnType bodyType
      finalFunctionType <- resolveType functionType
      resolvedEnv <- normalizeEnv env
      pure (continueWith (Map.insert name finalFunctionType resolvedEnv))
    SReturn expr ->
      if allowReturn
        then do
          exprType <- inferExpr env expr
          resolvedType <- resolveType exprType
          pure (Outcome env True (Just resolvedType))
        else throwTC ReturnOutsideFunction
    SPrint expr -> do
      _ <- inferExpr env expr
      resolvedEnv <- normalizeEnv env
      pure (continueWith resolvedEnv)
    SIf cond thenBranch elseBranch -> do
      condType <- inferExpr env cond
      expectType "if condition" TBool condType
      resolvedEnv <- normalizeEnv env
      thenOutcome <- checkBlock allowReturn resolvedEnv thenBranch
      elseOutcome <- checkBlock allowReturn resolvedEnv elseBranch
      mergeIfOutcomes thenOutcome elseOutcome
    SWhile cond body -> do
      condType <- inferExpr env cond
      expectType "while condition" TBool condType
      resolvedEnv <- normalizeEnv env
      bodyOutcome <- checkBlock allowReturn resolvedEnv body
      nextEnv <- mergeCompatibleEnvs resolvedEnv (outcomeEnv bodyOutcome)
      pure (Outcome nextEnv (outcomeSawReturn bodyOutcome) Nothing)
    SData typeName constructors -> do
      nextEnv <- registerConstructorTypes env typeName constructors
      pure (continueWith nextEnv)

checkFunctionBody :: TypeEnv -> [Stmt] -> TC Type
checkFunctionBody env body = do
  outcome <- checkBlock True env body
  case (outcomeSawReturn outcome, outcomeDefiniteReturn outcome) of
    (False, Nothing) -> pure TUnit
    (_, Just returnType) -> resolveType returnType
    (True, Nothing) -> throwTC NotAllPathsReturn

mergeIfOutcomes :: Outcome -> Outcome -> TC Outcome
mergeIfOutcomes thenOutcome elseOutcome = do
  let sawReturn = outcomeSawReturn thenOutcome || outcomeSawReturn elseOutcome
  case (outcomeDefiniteReturn thenOutcome, outcomeDefiniteReturn elseOutcome) of
    (Just thenReturn, Just elseReturn) -> do
      unifyWith "if branch return type" thenReturn elseReturn
      returnType <- resolveType thenReturn
      nextEnv <- mergeCompatibleEnvs (outcomeEnv thenOutcome) (outcomeEnv elseOutcome)
      pure (Outcome nextEnv sawReturn (Just returnType))
    (Just _, Nothing) -> do
      nextEnv <- normalizeEnv (outcomeEnv elseOutcome)
      pure (Outcome nextEnv sawReturn Nothing)
    (Nothing, Just _) -> do
      nextEnv <- normalizeEnv (outcomeEnv thenOutcome)
      pure (Outcome nextEnv sawReturn Nothing)
    (Nothing, Nothing) -> do
      nextEnv <- mergeCompatibleEnvs (outcomeEnv thenOutcome) (outcomeEnv elseOutcome)
      pure (Outcome nextEnv sawReturn Nothing)

inferExpr :: TypeEnv -> Expr -> TC Type
inferExpr env expr =
  case expr of
    EInt {} -> pure TInt
    EFloat {} -> pure TFloat
    EBool {} -> pure TBool
    EString {} -> pure TString
    EVar name -> lookupType env name
    EAdd left right -> inferNumericBinary "operator +" env left right
    ESub left right -> inferNumericBinary "operator -" env left right
    EMul left right -> inferNumericBinary "operator *" env left right
    EDiv left right -> inferNumericDivision "operator /" env left right
    ELt left right -> inferNumericComparison "operator <" env left right
    ELe left right -> inferNumericComparison "operator <=" env left right
    EGt left right -> inferNumericComparison "operator >" env left right
    EGe left right -> inferNumericComparison "operator >=" env left right
    EEq left right -> inferEquality "operator ==" env left right
    ENeq left right -> inferEquality "operator !=" env left right
    ECall callee args -> inferCall env callee args
    ELambda params body -> inferLambda env params body
    EMatch scrutinee branches -> inferMatch env scrutinee branches

inferLambda :: TypeEnv -> [String] -> [Stmt] -> TC Type
inferLambda env params body = do
  paramTypes <- mapM (const freshTypeVar) params
  returnType <- freshTypeVar
  let functionType = TFun paramTypes returnType
      paramsEnv = Map.fromList (zip params paramTypes)
      bodyEnv = paramsEnv `Map.union` env
  bodyType <- checkFunctionBody bodyEnv body
  unifyWith "lambda return type" returnType bodyType
  resolveType functionType

inferMatch :: TypeEnv -> Expr -> [(Pattern, Expr)] -> TC Type
inferMatch _ _ [] =
  throwTC (UnsupportedFeature "empty match expression")
inferMatch env scrutinee branches = do
  scrutineeType <- inferExpr env scrutinee
  resultType <- freshTypeVar
  _ <- mapM (inferMatchBranch env scrutineeType resultType) branches
  resolveType resultType

inferMatchBranch :: TypeEnv -> Type -> Type -> (Pattern, Expr) -> TC ()
inferMatchBranch env scrutineeType resultType (pattern_, branchExpr) = do
  branchEnv <- inferPattern env scrutineeType pattern_
  branchType <- inferExpr branchEnv branchExpr
  unifyWith "match branch result" resultType branchType

registerConstructorTypes :: TypeEnv -> String -> [ConstructorDef] -> TC TypeEnv
registerConstructorTypes env typeName constructors = do
  resolvedEnv <- normalizeEnv env
  foldM register resolvedEnv constructors
  where
    register currentEnv (ConstructorDef constructorName fields) = do
      fieldTypes <- mapM (const freshTypeVar) fields
      let constructorType =
            case fieldTypes of
              [] -> TData typeName
              _ -> TFun fieldTypes (TData typeName)
      pure (Map.insert constructorName constructorType currentEnv)

inferPattern :: TypeEnv -> Type -> Pattern -> TC TypeEnv
inferPattern env scrutineeType pattern_ =
  case pattern_ of
    PWildcard ->
      normalizeEnv env
    PVar name -> do
      resolvedEnv <- normalizeEnv env
      resolvedScrutineeType <- resolveType scrutineeType
      pure (Map.insert name resolvedScrutineeType resolvedEnv)
    PConstructor name fieldNames -> do
      constructorType <- lookupType env name
      resolvedConstructorType <- resolveType constructorType
      case resolvedConstructorType of
        TData typeName -> do
          checkConstructorArity name 0 fieldNames
          unifyWith ("pattern " ++ name) scrutineeType (TData typeName)
          normalizeEnv env
        TFun fieldTypes (TData typeName) -> do
          checkConstructorArity name (length fieldTypes) fieldNames
          unifyWith ("pattern " ++ name) scrutineeType (TData typeName)
          resolvedEnv <- normalizeEnv env
          resolvedFieldTypes <- mapM resolveType fieldTypes
          pure (Map.fromList (zip fieldNames resolvedFieldTypes) `Map.union` resolvedEnv)
        _ -> throwTC (UnknownConstructor name)

checkConstructorArity :: String -> Int -> [String] -> TC ()
checkConstructorArity name expected fields =
  if expected == length fields
    then pure ()
    else throwTC (ConstructorArityMismatch name expected (length fields))

inferNumericBinary :: String -> TypeEnv -> Expr -> Expr -> TC Type
inferNumericBinary context env left right = do
  leftType <- inferExpr env left
  rightType <- inferExpr env right
  resolveNumericBinary context leftType rightType

inferNumericDivision :: String -> TypeEnv -> Expr -> Expr -> TC Type
inferNumericDivision context env left right = do
  leftType <- inferExpr env left
  rightType <- inferExpr env right
  resolveNumericBinary context leftType rightType

inferNumericComparison :: String -> TypeEnv -> Expr -> Expr -> TC Type
inferNumericComparison context env left right = do
  leftType <- inferExpr env left
  rightType <- inferExpr env right
  _ <- resolveNumericBinary context leftType rightType
  pure TBool

resolveNumericBinary :: String -> Type -> Type -> TC Type
resolveNumericBinary context left right = do
  leftResolved <- resolveType left
  rightResolved <- resolveType right
  case (leftResolved, rightResolved) of
    (TInt, TInt) -> pure TInt
    (TFloat, TFloat) -> pure TFloat
    (TInt, TFloat) -> pure TFloat
    (TFloat, TInt) -> pure TFloat
    (TVar var, TInt) -> bindTypeVar var TInt >> pure TInt
    (TVar var, TFloat) -> bindTypeVar var TFloat >> pure TFloat
    (TInt, TVar var) -> bindTypeVar var TInt >> pure TInt
    (TFloat, TVar var) -> bindTypeVar var TFloat >> pure TFloat
    (TVar varL, TVar varR) -> do
      bindTypeVar varL TInt
      bindTypeVar varR TInt
      pure TInt
    _ -> throwTC (ExpectedNumeric context (nonNumericOperand leftResolved rightResolved))

nonNumericOperand :: Type -> Type -> Type
nonNumericOperand left right =
  if canBeNumeric left then right else left

canBeNumeric :: Type -> Bool
canBeNumeric ty =
  case ty of
    TInt -> True
    TFloat -> True
    TVar {} -> True
    _ -> False

inferEquality :: String -> TypeEnv -> Expr -> Expr -> TC Type
inferEquality context env left right = do
  leftType <- inferExpr env left
  rightType <- inferExpr env right
  leftResolved <- resolveType leftType
  rightResolved <- resolveType rightType
  rejectFunctionComparison leftResolved rightResolved
  case (leftResolved, rightResolved) of
    (TInt, TFloat) -> pure ()
    (TFloat, TInt) -> pure ()
    _ -> unifyWith context leftResolved rightResolved
  pure TBool

inferCall :: TypeEnv -> Expr -> [Expr] -> TC Type
inferCall env callee args = do
  calleeType <- inferExpr env callee
  argTypes <- mapM (inferExpr env) args
  resolvedCalleeType <- resolveType calleeType
  case resolvedCalleeType of
    TFun paramTypes resultType -> do
      checkArity paramTypes argTypes
      zipWithM_ (unifyWith "function argument") paramTypes argTypes
      resolveType resultType
    TVar {} -> do
      resultType <- freshTypeVar
      unifyWith "function call" resolvedCalleeType (TFun argTypes resultType)
      resolveType resultType
    _ -> throwTC (ExpectedFunction resolvedCalleeType)

checkArity :: [Type] -> [Type] -> TC ()
checkArity paramTypes argTypes =
  if length paramTypes == length argTypes
    then pure ()
    else throwTC (ArityMismatch (length paramTypes) (length argTypes))

rejectFunctionComparison :: Type -> Type -> TC ()
rejectFunctionComparison left right =
  case (left, right) of
    (TFun {}, _) -> throwTC (CannotCompareFunctions left right)
    (_, TFun {}) -> throwTC (CannotCompareFunctions left right)
    _ -> pure ()

lookupType :: TypeEnv -> String -> TC Type
lookupType env name =
  case Map.lookup name env of
    Just ty -> resolveType ty
    Nothing
      | isConstructorName name -> throwTC (UnknownConstructor name)
      | otherwise -> throwTC (UnboundVariable name)

expectType :: String -> Type -> Type -> TC ()
expectType context expected actual =
  unifyWith context expected actual

unifyWith :: String -> Type -> Type -> TC ()
unifyWith context expected actual = do
  expectedResolved <- resolveType expected
  actualResolved <- resolveType actual
  case (expectedResolved, actualResolved) of
    (TVar var, ty) -> bindTypeVar var ty
    (ty, TVar var) -> bindTypeVar var ty
    (TInt, TInt) -> pure ()
    (TFloat, TFloat) -> pure ()
    (TBool, TBool) -> pure ()
    (TString, TString) -> pure ()
    (TUnit, TUnit) -> pure ()
    (TData expectedName, TData actualName)
      | expectedName == actualName -> pure ()
    (TFun expectedArgs expectedResult, TFun actualArgs actualResult) -> do
      checkArity expectedArgs actualArgs
      zipWithM_ (unifyWith context) expectedArgs actualArgs
      unifyWith context expectedResult actualResult
    _ -> throwTC (ExpectedType context expectedResolved actualResolved)

bindTypeVar :: Int -> Type -> TC ()
bindTypeVar var ty =
  case ty of
    TVar other
      | var == other -> pure ()
    _ ->
      if occursIn var ty
        then throwTC (InfiniteType var ty)
        else modifySubst (Map.insert var ty)

occursIn :: Int -> Type -> Bool
occursIn var ty =
  case ty of
    TInt -> False
    TFloat -> False
    TBool -> False
    TString -> False
    TUnit -> False
    TData {} -> False
    TVar other -> var == other
    TFun args result -> any (occursIn var) args || occursIn var result

isConstructorName :: String -> Bool
isConstructorName name =
  case name of
    c : _ -> isUpper c
    [] -> False

freshTypeVar :: TC Type
freshTypeVar = do
  state <- getState
  let var = tcNextVar state
  putState state {tcNextVar = var + 1}
  pure (TVar var)

resolveType :: Type -> TC Type
resolveType ty = do
  subst <- getSubst
  pure (applySubstType subst ty)

normalizeEnv :: TypeEnv -> TC TypeEnv
normalizeEnv env = do
  subst <- getSubst
  pure (applySubstEnv subst env)

mergeCompatibleEnvs :: TypeEnv -> TypeEnv -> TC TypeEnv
mergeCompatibleEnvs left right = do
  leftResolved <- normalizeEnv left
  rightResolved <- normalizeEnv right
  pure (Map.filterWithKey (\name ty -> Map.lookup name rightResolved == Just ty) leftResolved)

continueWith :: TypeEnv -> Outcome
continueWith env = Outcome env False Nothing

getState :: TC TCState
getState = TC $ \state -> Right (state, state)

putState :: TCState -> TC ()
putState state = TC $ \_ -> Right ((), state)

getSubst :: TC Subst
getSubst = tcSubst <$> getState

modifySubst :: (Subst -> Subst) -> TC ()
modifySubst fn = do
  state <- getState
  putState state {tcSubst = fn (tcSubst state)}

throwTC :: TypeError -> TC a
throwTC err = TC $ \_ -> Left err
