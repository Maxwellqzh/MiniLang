module Main where

import MiniLang.Lexer (lexProgram)
import MiniLang.Parser (parseProgram)

main :: IO ()
main = do
  let sampleFile = "examples/showcase.minilang"
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
      print (parseProgram source)
