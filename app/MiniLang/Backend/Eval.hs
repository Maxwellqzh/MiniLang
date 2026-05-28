module MiniLang.Backend.Eval where

import qualified Data.Map as Map
import MiniLang.Backend.Error
import MiniLang.Backend.Value
import MiniLang.Parsing.Syntax

type Output = [String]

data ExecSignal
  = Continue
  | Returned Value

runProgram :: Program -> Either RuntimeError (Output, Env)
runProgram (Program stmts) = do
  (signal, env, output) <- execBlock False Map.empty [] stmts
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
    EBool value -> Right (VBool value, output)
    EString value -> Right (VString value, output)
    EVar name ->
      case Map.lookup name env of
        Just value -> Right (value, output)
        Nothing -> Left (UndefinedVariable name)
    EAdd left right -> evalIntBinary "+" (+) env output left right
    ESub left right -> evalIntBinary "-" (-) env output left right
    EMul left right -> evalIntBinary "*" (*) env output left right
    EDiv left right -> evalDiv env output left right
    ELt left right -> evalIntComparison "<" (<) env output left right
    ELe left right -> evalIntComparison "<=" (<=) env output left right
    EGt left right -> evalIntComparison ">" (>) env output left right
    EGe left right -> evalIntComparison ">=" (>=) env output left right
    EEq left right -> evalEquality True env output left right
    ENeq left right -> evalEquality False env output left right
    ECall callee args -> do
      (calleeValue, calleeOutput) <- evalExpr env output callee
      (argValues, argsOutput) <- evalArgs env calleeOutput args
      callValue calleeValue argValues argsOutput

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
    _ -> Left (NotCallable (show callee))

evalIntBinary :: String -> (Int -> Int -> Int) -> Env -> Output -> Expr -> Expr -> Either RuntimeError (Value, Output)
evalIntBinary op fn env output left right = do
  (leftValue, leftOutput) <- evalExpr env output left
  (rightValue, rightOutput) <- evalExpr env leftOutput right
  case (leftValue, rightValue) of
    (VInt leftInt, VInt rightInt) -> Right (VInt (fn leftInt rightInt), rightOutput)
    _ -> Left (TypeMismatch ("operator " ++ op ++ " expects integer operands"))

evalDiv :: Env -> Output -> Expr -> Expr -> Either RuntimeError (Value, Output)
evalDiv env output left right = do
  (leftValue, leftOutput) <- evalExpr env output left
  (rightValue, rightOutput) <- evalExpr env leftOutput right
  case (leftValue, rightValue) of
    (VInt _, VInt 0) -> Left DivisionByZero
    (VInt leftInt, VInt rightInt) -> Right (VInt (leftInt `div` rightInt), rightOutput)
    _ -> Left (TypeMismatch "operator / expects integer operands")

evalIntComparison :: String -> (Int -> Int -> Bool) -> Env -> Output -> Expr -> Expr -> Either RuntimeError (Value, Output)
evalIntComparison op fn env output left right = do
  (leftValue, leftOutput) <- evalExpr env output left
  (rightValue, rightOutput) <- evalExpr env leftOutput right
  case (leftValue, rightValue) of
    (VInt leftInt, VInt rightInt) -> Right (VBool (fn leftInt rightInt), rightOutput)
    _ -> Left (TypeMismatch ("operator " ++ op ++ " expects integer operands"))

evalEquality :: Bool -> Env -> Output -> Expr -> Expr -> Either RuntimeError (Value, Output)
evalEquality expectEqual env output left right = do
  (leftValue, leftOutput) <- evalExpr env output left
  (rightValue, rightOutput) <- evalExpr env leftOutput right
  case (leftValue, rightValue) of
    (VFunction {}, _) -> Left (TypeMismatch "function values cannot be compared")
    (_, VFunction {}) -> Left (TypeMismatch "function values cannot be compared")
    _ ->
      let result =
            if expectEqual
              then leftValue == rightValue
              else leftValue /= rightValue
       in Right (VBool result, rightOutput)

renderValue :: Value -> String
renderValue value =
  case value of
    VString text -> text
    VInt number -> show number
    VBool True -> "true"
    VBool False -> "false"
    VUnit -> "unit"
    VFunction {} -> "<function>"
