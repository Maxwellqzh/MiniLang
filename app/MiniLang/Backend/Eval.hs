module MiniLang.Backend.Eval where

import Data.Char (isUpper)
import qualified Data.Map as Map
import MiniLang.Backend.Error
import MiniLang.Backend.Value
import MiniLang.Parsing.Syntax

type Output = [String]

data ExecSignal
  = Continue
  | Returned Value

runProgram :: Program -> Either RuntimeError (Output, Env)
runProgram = runProgramWithEnv Map.empty

runProgramWithEnv :: Env -> Program -> Either RuntimeError (Output, Env)
runProgramWithEnv initialEnv (Program stmts) = do
  (signal, env, output) <- execBlock False initialEnv [] stmts
  case signal of
    Continue -> Right (output, env)
    Returned _ -> Left ReturnOutsideFunction

execBlock :: Bool -> Env -> Output -> [Stmt] -> Either RuntimeError (ExecSignal, Env, Output)
execBlock allowReturn env output stmts =
  case stmts of
    [] -> Right (Continue, env, output)
    stmt : rest -> do
      (signal, nextEnv, nextOutput) <- execStmt allowReturn env output stmt
      case signal of
        Continue -> execBlock allowReturn nextEnv nextOutput rest
        -- Return is a control-flow signal, not a value stored in the environment.
        Returned value -> Right (Returned value, nextEnv, nextOutput)

execStmt :: Bool -> Env -> Output -> Stmt -> Either RuntimeError (ExecSignal, Env, Output)
execStmt allowReturn env output stmt =
  case stmt of
    SLet name expr -> do
      (value, nextOutput) <- evalExpr env output expr
      Right (Continue, Map.insert name value env, nextOutput)
    SData _ constructors ->
      Right (Continue, registerConstructors constructors env, output)
    SFun name params body ->
      -- Haskell's lazy binding lets the closure environment contain the
      -- function itself, which gives named functions recursive visibility.
      let closure = VFunction params body recursiveEnv
          recursiveEnv = Map.insert name closure env
       in Right (Continue, recursiveEnv, output)
    SReturn expr ->
      if allowReturn
        then do
          (value, nextOutput) <- evalExpr env output expr
          Right (Returned value, env, nextOutput)
        else Left ReturnOutsideFunction
    SAssign name expr ->
      if Map.member name env
        then do
          (value, nextOutput) <- evalExpr env output expr
          Right (Continue, Map.insert name value env, nextOutput)
        else Left (UndefinedVariable name)
    SPrint expr -> do
      (value, nextOutput) <- evalExpr env output expr
      Right (Continue, env, nextOutput ++ [renderValue value])
    SIf cond thenBranch elseBranch -> do
      (condValue, nextOutput) <- evalExpr env output cond
      case condValue of
        VBool True -> execBlock allowReturn env nextOutput thenBranch
        VBool False -> execBlock allowReturn env nextOutput elseBranch
        _ -> Left (TypeMismatch "if condition must be boolean")
    SWhile cond body -> loop env output
      where
        loop currentEnv currentOutput = do
          (condValue, condOutput) <- evalExpr currentEnv currentOutput cond
          case condValue of
            VBool True -> do
              (signal, bodyEnv, bodyOutput) <- execBlock allowReturn currentEnv condOutput body
              case signal of
                Continue -> loop bodyEnv bodyOutput
                Returned value -> Right (Returned value, bodyEnv, bodyOutput)
            VBool False -> Right (Continue, currentEnv, condOutput)
            _ -> Left (TypeMismatch "while condition must be boolean")

evalExpr :: Env -> Output -> Expr -> Either RuntimeError (Value, Output)
evalExpr env output expr =
  case expr of
    EInt value -> Right (VInt value, output)
    EFloat value -> Right (VFloat value, output)
    EBool value -> Right (VBool value, output)
    EString value -> Right (VString value, output)
    EVar name ->
      case Map.lookup name env of
        Just value -> Right (value, output)
        Nothing -> Left (UndefinedVariable name)
    EAdd left right -> evalIntBinary "+" (+) (+) env output left right
    ESub left right -> evalIntBinary "-" (-) (-) env output left right
    EMul left right -> evalIntBinary "*" (*) (*) env output left right
    EDiv left right -> evalDiv env output left right
    ELt left right -> evalIntComparison "<" (<) env output left right
    ELe left right -> evalIntComparison "<=" (<=) env output left right
    EGt left right -> evalIntComparison ">" (>) env output left right
    EGe left right -> evalIntComparison ">=" (>=) env output left right
    EEq left right -> evalEquality True env output left right
    ENeq left right -> evalEquality False env output left right
    ECall (EVar name) args -> do
      case Map.lookup name env of
        Nothing
          | isConstructorName name -> Left (UnknownConstructor name)
          | otherwise -> Left (UndefinedVariable name)
        Just calleeValue -> do
          (argValues, argsOutput) <- evalArgs env output args
          callValue calleeValue argValues argsOutput
    ECall callee args -> do
      (calleeValue, calleeOutput) <- evalExpr env output callee
      (argValues, argsOutput) <- evalArgs env calleeOutput args
      callValue calleeValue argValues argsOutput
    ELambda params body -> Right (VFunction params body env, output)
    EMatch scrutinee branches -> do
      (scrutineeValue, scrutineeOutput) <- evalExpr env output scrutinee
      evalMatch env scrutineeOutput scrutineeValue branches

registerConstructors :: [ConstructorDef] -> Env -> Env
registerConstructors constructors env =
  foldl register env constructors
  where
    register currentEnv (ConstructorDef name fields) =
      let value =
            case fields of
              [] -> VConstructor name []
              _ -> VConstructorFunction name (length fields)
       in Map.insert name value currentEnv

evalArgs :: Env -> Output -> [Expr] -> Either RuntimeError ([Value], Output)
evalArgs env output args =
  case args of
    [] -> Right ([], output)
    arg : rest -> do
      (value, nextOutput) <- evalExpr env output arg
      (values, finalOutput) <- evalArgs env nextOutput rest
      Right (value : values, finalOutput)

callValue :: Value -> [Value] -> Output -> Either RuntimeError (Value, Output)
callValue callee args output =
  case callee of
    VFunction params body closureEnv ->
      if length params /= length args
        then Left (ArityMismatch (length params) (length args))
        else do
          -- Function calls run in a fresh local environment built from the
          -- captured closure plus argument bindings; local assignments do not
          -- write back into the caller environment.
          let localEnv = Map.fromList (zip params args) `Map.union` closureEnv
          (signal, _localFinalEnv, finalOutput) <- execBlock True localEnv output body
          case signal of
            Continue -> Right (VUnit, finalOutput)
            Returned value -> Right (value, finalOutput)
    VConstructorFunction name arity ->
      if length args == arity
        then Right (VConstructor name args, output)
        else Left (ConstructorArityMismatch name arity (length args))
    _ -> Left (NotCallable (show callee))

evalMatch :: Env -> Output -> Value -> [(Pattern, Expr)] -> Either RuntimeError (Value, Output)
evalMatch env output scrutinee branches =
  case branches of
    [] -> Left MatchFailure
    (pattern_, expr) : rest -> do
      matchResult <- matchPattern pattern_ scrutinee
      case matchResult of
        Nothing -> evalMatch env output scrutinee rest
        Just bindings -> evalExpr (bindings `Map.union` env) output expr

matchPattern :: Pattern -> Value -> Either RuntimeError (Maybe Env)
matchPattern pattern_ value =
  case pattern_ of
    PWildcard -> Right (Just Map.empty)
    PVar name -> Right (Just (Map.singleton name value))
    PConstructor name fields ->
      case value of
        VConstructor valueName values
          | name /= valueName -> Right Nothing
          | length fields == length values -> Right (Just (Map.fromList (zip fields values)))
          | otherwise ->
              Left
                ( InvalidPattern
                    ( "constructor pattern "
                        ++ name
                        ++ " expects "
                        ++ show (length values)
                        ++ " fields, got "
                        ++ show (length fields)
                    )
                )
        _ -> Right Nothing

evalIntBinary :: String -> (Int -> Int -> Int) -> (Double -> Double -> Double) -> Env -> Output -> Expr -> Expr -> Either RuntimeError (Value, Output)
evalIntBinary op intFn floatFn env output left right = do
  (leftValue, leftOutput) <- evalExpr env output left
  (rightValue, rightOutput) <- evalExpr env leftOutput right
  case (leftValue, rightValue) of
    (VInt leftInt, VInt rightInt) -> Right (VInt (intFn leftInt rightInt), rightOutput)
    (leftNumber, rightNumber) ->
      case (toDouble leftNumber, toDouble rightNumber) of
        (Just leftFloat, Just rightFloat) -> Right (VFloat (floatFn leftFloat rightFloat), rightOutput)
        _ -> Left (TypeMismatch ("operator " ++ op ++ " expects numeric operands"))

evalDiv :: Env -> Output -> Expr -> Expr -> Either RuntimeError (Value, Output)
evalDiv env output left right = do
  (leftValue, leftOutput) <- evalExpr env output left
  (rightValue, rightOutput) <- evalExpr env leftOutput right
  case (leftValue, rightValue) of
    (VInt _, VInt 0) -> Left DivisionByZero
    (VInt leftInt, VInt rightInt) -> Right (VInt (leftInt `div` rightInt), rightOutput)
    (leftNumber, rightNumber) ->
      case (toDouble leftNumber, toDouble rightNumber) of
        (Just _, Just 0.0) -> Left DivisionByZero
        (Just leftFloat, Just rightFloat) -> Right (VFloat (leftFloat / rightFloat), rightOutput)
        _ -> Left (TypeMismatch "operator / expects numeric operands")

evalIntComparison :: String -> (Double -> Double -> Bool) -> Env -> Output -> Expr -> Expr -> Either RuntimeError (Value, Output)
evalIntComparison op fn env output left right = do
  (leftValue, leftOutput) <- evalExpr env output left
  (rightValue, rightOutput) <- evalExpr env leftOutput right
  case (toDouble leftValue, toDouble rightValue) of
    (Just leftNumber, Just rightNumber) -> Right (VBool (fn leftNumber rightNumber), rightOutput)
    _ -> Left (TypeMismatch ("operator " ++ op ++ " expects numeric operands"))

evalEquality :: Bool -> Env -> Output -> Expr -> Expr -> Either RuntimeError (Value, Output)
evalEquality expectEqual env output left right = do
  (leftValue, leftOutput) <- evalExpr env output left
  (rightValue, rightOutput) <- evalExpr env leftOutput right
  case (leftValue, rightValue) of
    (VFunction {}, _) -> Left (TypeMismatch "function values cannot be compared")
    (_, VFunction {}) -> Left (TypeMismatch "function values cannot be compared")
    (VConstructorFunction {}, _) -> Left (TypeMismatch "constructor functions cannot be compared")
    (_, VConstructorFunction {}) -> Left (TypeMismatch "constructor functions cannot be compared")
    _ ->
      let areEqual = numericOrValueEqual leftValue rightValue
       in Right (VBool (if expectEqual then areEqual else not areEqual), rightOutput)

toDouble :: Value -> Maybe Double
toDouble value =
  case value of
    VInt number -> Just (fromIntegral number)
    VFloat number -> Just number
    _ -> Nothing

numericOrValueEqual :: Value -> Value -> Bool
numericOrValueEqual left right =
  case (toDouble left, toDouble right) of
    (Just leftNumber, Just rightNumber) -> leftNumber == rightNumber
    _ -> left == right

isConstructorName :: String -> Bool
isConstructorName name =
  case name of
    c : _ -> isUpper c
    [] -> False

renderValue :: Value -> String
renderValue value =
  case value of
    VString text -> text
    VInt number -> show number
    VFloat number -> show number
    VBool True -> "true"
    VBool False -> "false"
    VUnit -> "unit"
    VFunction {} -> "<function>"
    VConstructor name values -> show (VConstructor name values)
    VConstructorFunction name arity -> show (VConstructorFunction name arity)
