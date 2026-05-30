module MiniLang.Parsing.Parser where

import Data.Char (isUpper)
import MiniLang.Parsing.Lexer (lexProgram)
import MiniLang.Parsing.Syntax
import MiniLang.Parsing.Token

newtype ParseError = ParseError String
  deriving (Eq, Show)

parseProgram :: String -> Either ParseError Program
parseProgram source = do
  tokens <- mapLeft (ParseError . show) (lexProgram source)
  (program, rest) <- parseTokens tokens
  case rest of
    [] -> Right program
    token : _ -> Left (ParseError ("unexpected trailing token: " ++ show token))

parseTokens :: [Token] -> Either ParseError (Program, [Token])
parseTokens tokens = do
  (stmts, rest) <- parseStmtList tokens
  Right (Program stmts, rest)

parseStmtList :: [Token] -> Either ParseError ([Stmt], [Token])
parseStmtList tokens =
  case tokens of
    [] -> Right ([], [])
    TokRBrace : _ -> Right ([], tokens)
    _ -> do
      (stmt, rest) <- parseStmt tokens
      (stmts, finalRest) <- parseStmtList rest
      Right (stmt : stmts, finalRest)

parseStmt :: [Token] -> Either ParseError (Stmt, [Token])
parseStmt tokens =
  case tokens of
    TokData : TokIdent name : TokLBrace : rest -> do
      (constructors, rest1) <- parseConstructorDefs rest
      Right (SData name constructors, rest1)
    TokFn : TokIdent name : TokLParen : rest -> do
      (params, rest1) <- parseParamList rest
      (body, rest2) <- parseBlock rest1
      Right (SFun name params body, rest2)
    TokReturn : rest -> do
      (expr, rest1) <- parseExpr rest
      rest2 <- expect TokSemicolon rest1
      Right (SReturn expr, rest2)
    TokLet : TokIdent name : TokAssign : rest -> do
      (expr, rest1) <- parseExpr rest
      rest2 <- expect TokSemicolon rest1
      Right (SLet name expr, rest2)
    TokIdent name : TokAssign : rest -> do
      (expr, rest1) <- parseExpr rest
      rest2 <- expect TokSemicolon rest1
      Right (SAssign name expr, rest2)
    TokPrint : rest -> do
      (expr, rest1) <- parseExpr rest
      rest2 <- expect TokSemicolon rest1
      Right (SPrint expr, rest2)
    TokIf : TokLParen : rest -> do
      (condExpr, rest1) <- parseExpr rest
      rest2 <- expect TokRParen rest1
      (thenBranch, rest3) <- parseBlock rest2
      (elseBranch, rest4) <- parseOptionalElse rest3
      Right (SIf condExpr thenBranch elseBranch, rest4)
    TokWhile : TokLParen : rest -> do
      (condExpr, rest1) <- parseExpr rest
      rest2 <- expect TokRParen rest1
      (body, rest3) <- parseBlock rest2
      Right (SWhile condExpr body, rest3)
    [] -> Left (ParseError "unexpected end of input while parsing statement")
    token : _ -> Left (ParseError ("unexpected token while parsing statement: " ++ show token))

parseOptionalElse :: [Token] -> Either ParseError ([Stmt], [Token])
parseOptionalElse tokens =
  case tokens of
    TokElse : rest -> parseBlock rest
    _ -> Right ([], tokens)

parseBlock :: [Token] -> Either ParseError ([Stmt], [Token])
parseBlock tokens =
  case tokens of
    TokLBrace : rest -> do
      (stmts, rest1) <- parseStmtList rest
      rest2 <- expect TokRBrace rest1
      Right (stmts, rest2)
    _ -> Left (ParseError "expected '{' to start block")

parseParamList :: [Token] -> Either ParseError ([String], [Token])
parseParamList tokens =
  case tokens of
    TokRParen : rest -> Right ([], rest)
    TokIdent name : rest -> parseParamListTail [name] rest
    _ -> Left (ParseError "expected parameter name or ')' in function definition")
  where
    parseParamListTail params tokens' =
      case tokens' of
        TokComma : TokIdent name : rest -> parseParamListTail (params ++ [name]) rest
        TokRParen : rest -> Right (params, rest)
        TokComma : _ -> Left (ParseError "expected parameter name after ','")
        _ -> Left (ParseError "expected ',' or ')' in parameter list")

parseConstructorDefs :: [Token] -> Either ParseError ([ConstructorDef], [Token])
parseConstructorDefs tokens =
  case tokens of
    TokRBrace : rest -> Right ([], rest)
    TokIdent name : TokLParen : rest -> do
      (fields, rest1) <- parseParamList rest
      rest2 <- expect TokSemicolon rest1
      (constructors, rest3) <- parseConstructorDefs rest2
      Right (ConstructorDef name fields : constructors, rest3)
    TokIdent name : rest -> do
      rest1 <- expect TokSemicolon rest
      (constructors, rest2) <- parseConstructorDefs rest1
      Right (ConstructorDef name [] : constructors, rest2)
    [] -> Left (ParseError "unexpected end of input while parsing data declaration")
    token : _ -> Left (ParseError ("unexpected token in data declaration: " ++ show token))

parseExpr :: [Token] -> Either ParseError (Expr, [Token])
parseExpr = parseEquality

parseEquality :: [Token] -> Either ParseError (Expr, [Token])
parseEquality tokens = do
  (lhs, rest) <- parseComparison tokens
  parseEqualityTail lhs rest
  where
    parseEqualityTail lhs tokens' =
      case tokens' of
        TokEq : rest -> do
          (rhs, rest1) <- parseComparison rest
          parseEqualityTail (EEq lhs rhs) rest1
        TokNeq : rest -> do
          (rhs, rest1) <- parseComparison rest
          parseEqualityTail (ENeq lhs rhs) rest1
        _ -> Right (lhs, tokens')

parseComparison :: [Token] -> Either ParseError (Expr, [Token])
parseComparison tokens = do
  (lhs, rest) <- parseAdditive tokens
  parseComparisonTail lhs rest
  where
    parseComparisonTail lhs tokens' =
      case tokens' of
        TokLt : rest -> binary ELt lhs rest
        TokLe : rest -> binary ELe lhs rest
        TokGt : rest -> binary EGt lhs rest
        TokGe : rest -> binary EGe lhs rest
        _ -> Right (lhs, tokens')

    binary constructor lhs rest = do
      (rhs, rest1) <- parseAdditive rest
      parseComparisonTail (constructor lhs rhs) rest1

parseAdditive :: [Token] -> Either ParseError (Expr, [Token])
parseAdditive tokens = do
  (lhs, rest) <- parseMultiplicative tokens
  parseAdditiveTail lhs rest
  where
    parseAdditiveTail lhs tokens' =
      case tokens' of
        TokPlus : rest -> binary EAdd lhs rest
        TokMinus : rest -> binary ESub lhs rest
        _ -> Right (lhs, tokens')

    binary constructor lhs rest = do
      (rhs, rest1) <- parseMultiplicative rest
      parseAdditiveTail (constructor lhs rhs) rest1

parseMultiplicative :: [Token] -> Either ParseError (Expr, [Token])
parseMultiplicative tokens = do
  (lhs, rest) <- parsePostfix tokens
  parseMultiplicativeTail lhs rest
  where
    parseMultiplicativeTail lhs tokens' =
      case tokens' of
        TokStar : rest -> binary EMul lhs rest
        TokSlash : rest -> binary EDiv lhs rest
        _ -> Right (lhs, tokens')

    binary constructor lhs rest = do
      (rhs, rest1) <- parsePostfix rest
      parseMultiplicativeTail (constructor lhs rhs) rest1

parsePostfix :: [Token] -> Either ParseError (Expr, [Token])
parsePostfix tokens = do
  (expr, rest) <- parsePrimary tokens
  parseCallSuffix expr rest

parseCallSuffix :: Expr -> [Token] -> Either ParseError (Expr, [Token])
parseCallSuffix callee tokens =
  case tokens of
    TokLParen : rest -> do
      (args, rest1) <- parseArgumentList rest
      parseCallSuffix (ECall callee args) rest1
    _ -> Right (callee, tokens)

parsePrimary :: [Token] -> Either ParseError (Expr, [Token])
parsePrimary tokens =
  case tokens of
    TokMatch : rest -> do
      (scrutinee, rest1) <- parseExpr rest
      rest2 <- expect TokLBrace rest1
      (branches, rest3) <- parseMatchBranches rest2
      Right (EMatch scrutinee branches, rest3)
    TokFn : TokLParen : rest -> do
      (params, rest1) <- parseParamList rest
      (body, rest2) <- parseBlock rest1
      Right (ELambda params body, rest2)
    TokInt n : rest -> Right (EInt n, rest)
    TokString s : rest -> Right (EString s, rest)
    TokTrue : rest -> Right (EBool True, rest)
    TokFalse : rest -> Right (EBool False, rest)
    TokIdent name : rest -> Right (EVar name, rest)
    TokLParen : rest -> do
      (expr, rest1) <- parseExpr rest
      rest2 <- expect TokRParen rest1
      Right (expr, rest2)
    [] -> Left (ParseError "unexpected end of input while parsing expression")
    token : _ -> Left (ParseError ("unexpected token while parsing expression: " ++ show token))

parseMatchBranches :: [Token] -> Either ParseError ([(Pattern, Expr)], [Token])
parseMatchBranches tokens =
  case tokens of
    TokRBrace : rest -> Right ([], rest)
    [] -> Left (ParseError "unexpected end of input while parsing match expression")
    _ -> do
      (pattern_, rest) <- parsePattern tokens
      rest1 <- expect TokArrow rest
      (expr, rest2) <- parseExpr rest1
      rest3 <- expect TokSemicolon rest2
      (branches, rest4) <- parseMatchBranches rest3
      Right ((pattern_, expr) : branches, rest4)

parsePattern :: [Token] -> Either ParseError (Pattern, [Token])
parsePattern tokens =
  case tokens of
    TokUnderscore : rest -> Right (PWildcard, rest)
    TokIdent name : TokLParen : rest -> do
      (fields, rest1) <- parsePatternVarList rest
      Right (PConstructor name fields, rest1)
    TokIdent name : rest
      | isConstructorName name -> Right (PConstructor name [], rest)
      | otherwise -> Right (PVar name, rest)
    token : _ -> Left (ParseError ("unexpected token while parsing pattern: " ++ show token))
    [] -> Left (ParseError "unexpected end of input while parsing pattern")

parsePatternVarList :: [Token] -> Either ParseError ([String], [Token])
parsePatternVarList tokens =
  case tokens of
    TokRParen : rest -> Right ([], rest)
    TokIdent name : rest -> parsePatternVarListTail [name] rest
    _ -> Left (ParseError "expected pattern variable name or ')' in constructor pattern")
  where
    parsePatternVarListTail names tokens' =
      case tokens' of
        TokComma : TokIdent name : rest -> parsePatternVarListTail (names ++ [name]) rest
        TokRParen : rest -> Right (names, rest)
        TokComma : _ -> Left (ParseError "expected pattern variable name after ','")
        _ -> Left (ParseError "expected ',' or ')' in constructor pattern")

isConstructorName :: String -> Bool
isConstructorName name =
  case name of
    c : _ -> isUpper c
    [] -> False

parseArgumentList :: [Token] -> Either ParseError ([Expr], [Token])
parseArgumentList tokens =
  case tokens of
    TokRParen : rest -> Right ([], rest)
    _ -> do
      (arg, rest) <- parseExpr tokens
      parseArgumentListTail [arg] rest
  where
    parseArgumentListTail args tokens' =
      case tokens' of
        TokComma : rest -> do
          (arg, rest1) <- parseExpr rest
          parseArgumentListTail (args ++ [arg]) rest1
        TokRParen : rest -> Right (args, rest)
        _ -> Left (ParseError "expected ',' or ')' in argument list")

expect :: Token -> [Token] -> Either ParseError [Token]
expect expected tokens =
  case tokens of
    token : rest
      | token == expected -> Right rest
      | otherwise ->
          Left
            ( ParseError
                ( "expected "
                    ++ show expected
                    ++ ", but found "
                    ++ show token
                )
            )
    [] -> Left (ParseError ("expected " ++ show expected ++ ", but reached end of input"))

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f value =
  case value of
    Left err -> Left (f err)
    Right result -> Right result
