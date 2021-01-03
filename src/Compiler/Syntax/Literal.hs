module Compiler.Syntax.Literal where


data Lit
  = LitInt Int
  | LitBool Bool
  | LitDouble Double
  | LitChar Char
  | LitString String

instance Show Lit where
  show (LitInt i) = show i
  show (LitBool b) = show b
  show (LitDouble d) = show d
  show (LitChar ch) = show ch
  show (LitString s) = show s