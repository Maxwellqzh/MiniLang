module MiniLang.Parsing.Syntax where

newtype Program = Program [Stmt]
  deriving (Eq, Show)

data Stmt
  = SLet String Expr
  | SFun String [String] [Stmt]
  | SReturn Expr
  | SAssign String Expr
  | SPrint Expr
  | SIf Expr [Stmt] [Stmt]
  | SWhile Expr [Stmt]
  deriving (Eq, Show)

data Expr
  = EInt Int
  | EBool Bool
  | EString String
  | EVar String
  | EAdd Expr Expr
  | ESub Expr Expr
  | EMul Expr Expr
  | EDiv Expr Expr
  | ELt Expr Expr
  | ELe Expr Expr
  | EGt Expr Expr
  | EGe Expr Expr
  | EEq Expr Expr
  | ENeq Expr Expr
  | ECall Expr [Expr]
  deriving (Eq, Show)
