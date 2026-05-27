module MiniLang.Parser where

import MiniLang.Syntax

newtype ParseError = ParseError String
  deriving (Eq, Show)

parseProgram :: String -> Either ParseError Program
parseProgram _ =
  Left (ParseError "Parser not implemented yet")