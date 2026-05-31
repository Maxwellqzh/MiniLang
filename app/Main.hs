module Main where

import MiniLang.Backend.Eval (runProgram)
import MiniLang.Repl (repl)
import MiniLang.Parsing.Lexer (lexProgram)
import MiniLang.Parsing.Parser (parseProgram)
import System.Environment (getArgs)
import System.Exit (exitFailure)

data Mode
  = Run
  | Debug
  | Tokens
  | Ast
  | Repl

main :: IO ()
main = do
  args <- getArgs
  case parseArgs args of
    Left message -> failWith message
    Right (Repl, _) -> repl
    Right (mode, sourceFile) -> do
      source <- readFile sourceFile
      runMode mode sourceFile source

parseArgs :: [String] -> Either String (Mode, FilePath)
parseArgs args =
  case args of
    [] -> Right (Debug, "examples/showcase.minilang")
    ["repl"] -> Right (Repl, "")
    ["--repl"] -> Right (Repl, "")
    [sourceFile] -> Right (Run, sourceFile)
    ["--debug", sourceFile] -> Right (Debug, sourceFile)
    ["--tokens", sourceFile] -> Right (Tokens, sourceFile)
    ["--ast", sourceFile] -> Right (Ast, sourceFile)
    _ -> Left usage

usage :: String
usage =
  unlines
    [ "Usage:"
    , "  MiniLang"
    , "  MiniLang FILE"
    , "  MiniLang --debug FILE"
    , "  MiniLang --tokens FILE"
    , "  MiniLang --ast FILE"
    , "  MiniLang repl"
    , "  MiniLang --repl"
    ]

runMode :: Mode -> FilePath -> String -> IO ()
runMode mode sourceFile source =
  case mode of
    Run -> runProgramOnly source
    Debug -> runDebug sourceFile source
    Tokens -> printTokens source
    Ast -> printAst source
    Repl -> repl

runProgramOnly :: String -> IO ()
runProgramOnly source =
  case parseProgram source of
    Left err -> failWith (show err)
    Right program ->
      case runProgram program of
        Left err -> failWith (show err)
        Right (output, _env) -> mapM_ putStrLn output

printTokens :: String -> IO ()
printTokens source =
  case lexProgram source of
    Left err -> failWith (show err)
    Right tokens -> mapM_ print tokens

printAst :: String -> IO ()
printAst source =
  case parseProgram source of
    Left err -> failWith (show err)
    Right program -> print program

runDebug :: FilePath -> String -> IO ()
runDebug sourceFile source = do
  putStrLn ("Source file: " ++ sourceFile)
  putStrLn ""
  putStrLn "=== Source ==="
  putStrLn source
  putStrLn "=== Lexer Output ==="

  case lexProgram source of
    Left err -> failWith (show err)
    Right tokens -> do
      mapM_ print tokens
      putStrLn "=== Parser Output ==="
      case parseProgram source of
        Left err -> failWith (show err)
        Right program -> do
          print program
          putStrLn "=== Eval Output ==="
          case runProgram program of
            Left err -> failWith (show err)
            Right (output, env) -> do
              mapM_ putStrLn output
              putStrLn "=== Final Env ==="
              print env

failWith :: String -> IO ()
failWith message = do
  putStrLn message
  exitFailure
