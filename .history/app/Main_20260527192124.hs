module Main where

import MiniLang.Syntax

main :: IO ()
main = do
  let program =
        Program
          [ SLet "x" (EInt 3)
          , SLet "y" (EAdd (EVar "x") (EInt 4))
          , SPrint (EVar "y")
          ]
  print program