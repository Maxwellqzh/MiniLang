module MiniLang.Lexer
  ( LexError (..)
  , lexProgram
  ) where

import Data.Char (chr, digitToInt, isAlpha, isAlphaNum, isDigit, isSpace, ord)
import MiniLang.Token

data LexError = LexError
  { lexErrorLine :: Int
  , lexErrorColumn :: Int
  , lexErrorMessage :: String
  }
  deriving (Eq)

instance Show LexError where
  show (LexError line column message) =
    "Lex error at line "
      ++ show line
      ++ ", column "
      ++ show column
      ++ ": "
      ++ message

lexProgram :: String -> Either LexError [Token]
lexProgram = go 1 1
  where
    go :: Int -> Int -> String -> Either LexError [Token]
    go line column input =
      case input of
        [] -> Right []
        current@(c : cs)
          | isSpace c ->
              let (nextLine, nextColumn) = advance c line column
               in go nextLine nextColumn cs
          | isAlpha c || c == '_' ->
              let (name, rest) = span isIdentChar current
                  token = keywordOrIdent name
               in (token :) <$> go line (column + length name) rest
          | isDigit c ->
              let (digits, rest) = span isDigit current
               in (TokInt (read digits) :) <$> go line (column + length digits) rest
          | c == '/' && startsLineComment cs ->
              let (rest, consumed) = skipLineComment cs
               in go line (column + consumed) rest
          | otherwise ->
              case c of
                '"' -> lexString line column cs
                '+' -> single cs TokPlus
                '-' -> single cs TokMinus
                '*' -> single cs TokStar
                '/' -> single cs TokSlash
                '(' -> single cs TokLParen
                ')' -> single cs TokRParen
                '{' -> single cs TokLBrace
                '}' -> single cs TokRBrace
                ';' -> single cs TokSemicolon
                ',' -> single cs TokComma
                '=' -> double cs '=' TokEq TokAssign
                '!' -> onlyDouble cs '=' TokNeq "unexpected character '!'"
                '<' -> double cs '=' TokLe TokLt
                '>' -> double cs '=' TokGe TokGt
                _ ->
                  Left
                    ( LexError
                        line
                        column
                        ("unexpected character " ++ show c)
                    )
      where
        single rest token = (token :) <$> go line (column + 1) rest

        double rest expected doubleToken singleToken =
          case rest of
            next : rest'
              | next == expected ->
                  (doubleToken :) <$> go line (column + 2) rest'
            _ -> (singleToken :) <$> go line (column + 1) rest

        onlyDouble rest expected token message =
          case rest of
            next : rest'
              | next == expected ->
                  (token :) <$> go line (column + 2) rest'
            _ -> Left (LexError line column message)

    lexString :: Int -> Int -> String -> Either LexError [Token]
    lexString startLine startColumn = collect startLine (startColumn + 1) []
      where
        collect :: Int -> Int -> String -> String -> Either LexError [Token]
        collect line column acc input =
          case input of
            [] ->
              Left
                ( LexError
                    startLine
                    startColumn
                    "unterminated string literal"
                )
            '"' : rest ->
              (TokString (reverse acc) :) <$> go line (column + 1) rest
            '\\' : rest -> lexEscape line column acc rest
            c : rest
              | c == '\n' || c == '\r' ->
                  Left
                    ( LexError
                        line
                        column
                        "newline in string literal"
                    )
              | otherwise ->
                  collect line (column + 1) (c : acc) rest

        lexEscape :: Int -> Int -> String -> String -> Either LexError [Token]
        lexEscape line column acc input =
          case input of
            [] ->
              Left
                ( LexError
                    line
                    column
                    "unterminated escape sequence"
                )
            esc : rest ->
              case decodeEscape esc of
                Just decoded ->
                  collect line (column + 2) (decoded : acc) rest
                Nothing ->
                  if esc == 'x'
                    then lexHexEscape line column acc rest
                    else
                      Left
                        ( LexError
                            line
                            column
                            ("invalid escape sequence \\" ++ [esc])
                        )

        lexHexEscape :: Int -> Int -> String -> String -> Either LexError [Token]
        lexHexEscape line column acc input =
          case input of
            a : b : rest
              | isHexDigit a && isHexDigit b ->
                  let value = hexValue a * 16 + hexValue b
                   in collect line (column + 4) (chr value : acc) rest
            _ ->
              Left
                ( LexError
                    line
                    column
                    "invalid hexadecimal escape, expected \\xHH"
                )

    isIdentChar :: Char -> Bool
    isIdentChar c = isAlphaNum c || c == '_'

    startsLineComment :: String -> Bool
    startsLineComment rest =
      case rest of
        '/' : _ -> True
        _ -> False

    skipLineComment :: String -> (String, Int)
    skipLineComment input = consume 2 (drop 1 input)
      where
        consume count rest =
          case rest of
            [] -> ([], count)
            '\n' : _ -> (rest, count)
            c : cs -> consume (count + advanceWidth c) cs

        advanceWidth c =
          case c of
            '\t' -> 4
            '\r' -> 0
            _ -> 1

    keywordOrIdent :: String -> Token
    keywordOrIdent name =
      case name of
        "let" -> TokLet
        "fn" -> TokFn
        "return" -> TokReturn
        "if" -> TokIf
        "else" -> TokElse
        "while" -> TokWhile
        "print" -> TokPrint
        "true" -> TokTrue
        "false" -> TokFalse
        _ -> TokIdent name

    advance :: Char -> Int -> Int -> (Int, Int)
    advance c line column =
      case c of
        '\n' -> (line + 1, 1)
        '\t' -> (line, column + 4)
        '\r' -> (line, column)
        _ -> (line, column + 1)

    decodeEscape :: Char -> Maybe Char
    decodeEscape esc =
      case esc of
        '"' -> Just '"'
        '\\' -> Just '\\'
        'n' -> Just '\n'
        't' -> Just '\t'
        'r' -> Just '\r'
        _ -> Nothing

    isHexDigit :: Char -> Bool
    isHexDigit c = isDigit c || c `elem` ['a' .. 'f'] || c `elem` ['A' .. 'F']

    hexValue :: Char -> Int
    hexValue c
      | isDigit c = digitToInt c
      | c >= 'a' && c <= 'f' = ord c - ord 'a' + 10
      | otherwise = ord c - ord 'A' + 10
