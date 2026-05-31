module Main where

import Control.Exception (SomeException, evaluate, try)
import MiniLang.Backend.Error
import MiniLang.Backend.Eval (runProgram)
import MiniLang.Backend.Value (Env)
import MiniLang.Parsing.Parser (parseProgram)
import System.Exit (exitFailure)

main :: IO ()
main = do
  results <-
    sequence
      [ testProgramOutput
          "anonymous function arguments"
          "fn apply(f, x) { return f(x); }\n\
          \let result = apply(fn(n) { return n + 1; }, 10);\n\
          \print result;\n"
          ["11"]
      , testProgramOutput
          "float output and arithmetic"
          "let pi = 3.14;\n\
          \let radius = 2.0;\n\
          \let area = pi * radius * radius;\n\
          \print area;\n\
          \print 5 + 0.5;\n\
          \print 5.0 / 2.0;\n"
          ["12.56", "5.5", "2.5"]
      , testProgramOutput
          "float comparisons"
          "print 2.5 > 2.0;\n\
          \print 2 == 2.0;\n\
          \print 2.0 != 3;\n"
          ["true", "true", "true"]
      , testProgramOutput
          "adt match recursive sum"
          "data List { Nil; Cons(head, tail); }\n\
          \fn sum(xs) {\n\
          \  return match xs {\n\
          \    Nil -> 0;\n\
          \    Cons(head, tail) -> head + sum(tail);\n\
          \  };\n\
          \}\n\
          \let xs = Cons(1, Cons(2, Cons(3, Nil)));\n\
          \print sum(xs);\n"
          ["6"]
      , testProgramOutput
          "match wildcard fallback"
          "data Maybe { None; Some(value); }\n\
          \fn defaultValue(value) {\n\
          \  return match value {\n\
          \    Some(inner) -> inner;\n\
          \    _ -> 0;\n\
          \  };\n\
          \}\n\
          \print defaultValue(None);\n"
          ["0"]
      , testRuntimeError
          "constructor arity mismatch"
          "data Maybe { None; Some(value); }\n\
          \print Some(1, 2);\n"
          (ConstructorArityMismatch "Some" 1 2)
      , testRuntimeError
          "unknown constructor"
          "print MissingConstructor(1);\n"
          (UnknownConstructor "MissingConstructor")
      , testRuntimeError
          "match failure"
          "data Maybe { None; Some(value); }\n\
          \let value = None;\n\
          \print match value {\n\
          \  Some(inner) -> inner;\n\
          \};\n"
          MatchFailure
      ]
  if and results then putStrLn "All tests passed" else exitFailure

testProgramOutput :: String -> String -> [String] -> IO Bool
testProgramOutput name source expected = do
  result <- runSource source
  case result of
    Right actual
      | actual == expected -> do
          putStrLn ("PASS " ++ name)
          pure True
      | otherwise -> do
          putStrLn ("FAIL " ++ name)
          putStrLn ("  expected: " ++ show expected)
          putStrLn ("  actual:   " ++ show actual)
          pure False
    Left err -> do
      putStrLn ("FAIL " ++ name)
      putStrLn ("  error: " ++ err)
      pure False

testRuntimeError :: String -> String -> RuntimeError -> IO Bool
testRuntimeError name source expected = do
  result <- runSourceError source
  case result of
    Right actual
      | actual == expected -> do
          putStrLn ("PASS " ++ name)
          pure True
      | otherwise -> do
          putStrLn ("FAIL " ++ name)
          putStrLn ("  expected error: " ++ show expected)
          putStrLn ("  actual error:   " ++ show actual)
          pure False
    Left err -> do
      putStrLn ("FAIL " ++ name)
      putStrLn ("  error: " ++ err)
      pure False

runSource :: String -> IO (Either String [String])
runSource source =
  case parseProgram source of
    Left err -> pure (Left ("parse error: " ++ show err))
    Right program -> do
      result <- try (evaluate (runProgram program)) :: IO (Either SomeException (Either RuntimeError ([String], Env)))
      case result of
        Left err -> pure (Left ("exception: " ++ show err))
        Right (Left err) -> pure (Left ("runtime error: " ++ show err))
        Right (Right (output, _env)) -> pure (Right output)

runSourceError :: String -> IO (Either String RuntimeError)
runSourceError source =
  case parseProgram source of
    Left err -> pure (Left ("parse error: " ++ show err))
    Right program -> do
      result <- try (evaluate (runProgram program)) :: IO (Either SomeException (Either RuntimeError ([String], Env)))
      case result of
        Left err -> pure (Left ("exception: " ++ show err))
        Right (Left err) -> pure (Right err)
        Right (Right (output, _env)) -> pure (Left ("expected runtime error, got output: " ++ show output))
