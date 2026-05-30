module Main where

import MiniLang.Backend.Eval (runProgram)
import MiniLang.Repl (repl)
import MiniLang.Parsing.Lexer (lexProgram)
import MiniLang.Parsing.Parser (parseProgram)
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [] -> runFile "examples/showcase.minilang"
    ["repl"] -> repl
    ["--repl"] -> repl
    [sampleFile] -> runFile sampleFile
    _ -> putStrLn "Usage: MiniLang [repl|--repl|FILE]"

runFile :: FilePath -> IO ()
runFile sampleFile = do
  source <- readFile sampleFile
  putStrLn ("Source file: " ++ sampleFile)
  putStrLn ""
  putStrLn "=== Source ==="
  putStrLn source
  putStrLn "=== Lexer Output ==="

  case lexProgram source of
    Left err -> print err
    Right tokens -> do
      mapM_ print tokens
      putStrLn "=== Parser Output ==="
      case parseProgram source of
        Left err -> print err
        Right program -> do
          print program
          putStrLn "=== Eval Output ==="
          case runProgram program of
            Left err -> print err
            Right (output, env) -> do
              mapM_ putStrLn output
              putStrLn "=== Final Env ==="
              print env
