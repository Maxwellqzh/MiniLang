module MiniLang.Eval where

import qualified Data.Map as Map
import MiniLang.Syntax
import MiniLang.Value
import MiniLang.Error

type Env = Map.Map String Value
type Output = [String]

runProgram :: Program -> Either RuntimeError (Output, Env)
runProgram _ =
  Right ([], Map.empty)