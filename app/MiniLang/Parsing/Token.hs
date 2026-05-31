module MiniLang.Parsing.Token where

data Token
  = TokLet
  | TokData
  | TokMatch
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
  | TokFloat Double
  | TokString String

  | TokPlus       -- +
  | TokMinus      -- -
  | TokArrow      -- ->
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
  | TokUnderscore -- _

  deriving (Eq, Show)
