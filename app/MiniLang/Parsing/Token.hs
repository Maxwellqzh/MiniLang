module MiniLang.Parsing.Token where

data Token
  = TokLet
  | TokFn
  | TokReturn
  | TokIf
  | TokElse
  | TokWhile
  | TokPrint

  | TokTrue
  | TokFalse

  | TokIdent String
  | TokInt Int
  | TokString String

  | TokPlus       -- +
  | TokMinus      -- -
  | TokStar       -- *
  | TokSlash      -- /

  | TokAssign     -- =
  | TokEq         -- ==
  | TokNeq        -- !=
  | TokLt         -- <
  | TokGt         -- >
  | TokLe         -- <=
  | TokGe         -- >=

  | TokLParen     -- (
  | TokRParen     -- )
  | TokLBrace     -- {
  | TokRBrace     -- }
  | TokSemicolon  -- ;
  | TokComma      -- ,

  deriving (Eq, Show)
