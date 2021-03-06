module ParserSpec where

import Test.Hspec
import System.Exit

import Compiler.Parser.Parser (parse'expr)
import Compiler.Syntax.Expression
import Compiler.Syntax.Literal


-- TODO:  test assume

spec :: Spec
spec = describe "Test the parser" $ do
  it "Parses a single integer" $ do
    "23" <=> Lit (LitInt 23)
  it "Parses a single double" $ do
    "24.42" <=> Lit (LitDouble 24.42)
  it "Parses a single char" $ do
    "'c'" <=> Lit (LitChar 'c')
  it "Parses a single string" $ do
    "\"h\"" <=> App (App (Var ":") (Lit $ LitChar 'h')) (Var "[]")
  it "Parses a single boolean (True)" $ do
    "True" <=> Var "True"
  it "Parses a single boolean (False)" $ do
    "False" <=> Var "False"
  it "Parses a single unit" $ do
    "()" <=> Var "()"
  it "Parses a single empty list" $ do
    "[]" <=> Var "[]"
  it "Parses a single short list" $ do
    "[1, 2]" <=> App (App (Var ":") (Lit (LitInt 1))) (App (App (Var ":") (Lit (LitInt 2))) (Var "[]"))
  it "Parses a single tuple (Pair) of values" $ do
    "(23, True)" <=> Tuple [Lit (LitInt 23), Var "True"]
  
  it "Parses a lambda function" $ do
    "\\ a b -> a" <=>
      Lam "a" (Lam "b" (Var "a"))

  it "Parses an if expression" $ do
    "if True then 23 else 42" <=>
      If (Var "True") (Lit (LitInt 23)) (Lit (LitInt 42))

  it "Parses a simple application" $ do
    "a b c" <=>
      App (App (Var "a") (Var "b")) (Var "c")

  it "Parses a nested application" $ do
    "(a b) c" <=>
      App (App (Var "a") (Var "b")) (Var "c")

  it "Parse an infix constructor application" $ do
    "a : b" <=>
      App (App (Var ":") (Var "a")) (Var "b")

  it "Parses an infix operation" $ do
    "a ++ b" <=>
      App (App (Var "++") (Var "a")) (Var "b")

  it "Parses parenthesized infix operation" $ do
    "(ix - 1)" <=>
      App (App (Var "-") (Var "ix")) (Lit (LitInt 1))

  it "Parses a simple infix operation" $ do
    "(t !! 0)" <=>
      App (App (Var "!!") (Var "t")) (Lit $ LitInt 0)

  it "Parses a simple nested infix operation" $ do
    "(t !! (ix - 1))" <=>
      App (App (Var "!!") (Var "t")) (App (App (Var "-") (Var "ix")) (Lit (LitInt 1)))

  it "Parses a simple let expression" $ do
    "let { a = 23 } in a" <=>
      Let [("a", (Lit (LitInt 23)))] (Var "a")
  it "Parses a multi let expression" $ do
    "let { a = 23 ; b = 42 } in a" <=>
      Let [("a", (Lit (LitInt 23))), ("b", (Lit (LitInt 42)))] (Var "a")
  it "Parses a multi let with operators" $ do
    "let { (+) = 23 ; (<=>) = 42 } in a" <=>
      Let [("+", (Lit (LitInt 23))), ("<=>", (Lit (LitInt 42)))] (Var "a")
  it "Parses a multi let with cross-level references" $ do
    "let { (+) = 23 ; (++) = (+) } in a" <=>
      Let [("+", (Lit (LitInt 23))), ("++", (Var "+"))] (Var "a")
  it "Parses a let function" $ do
    "let { f a b = b } in x" <=>
      Let [("f", (Lam "a" (Lam "b" (Var "b"))))] (Var "x")
  it "Parses a let prefix operator" $ do
    "let { (+) a b = b } in x" <=>
      Let [("+", (Lam "a" (Lam "b" (Var "b"))))] (Var "x")
  it "Parses a let infix operator" $ do
    "let { a + b = b } in x" <=>
      Let [("+", (Lam "a" (Lam "b" (Var "b"))))] (Var "x")
  it "Parses a let infix operator" $ do
    "let { a + b = b } in x" <=>
      Let [("+", (Lam "a" (Lam "b" (Var "b"))))] (Var "x")

  it "Parses an operator in infix let" $ do
    "let { a + b = b } in x" <=>
      Let [("+", (Lam "a" (Lam "b" (Var "b"))))] (Var "x")

  it "Parses a function in infix let" $ do
    "let { a `plus` b = b } in x" <=>
      Let [("plus", (Lam "a" (Lam "b" (Var "b"))))] (Var "x")

  it "Parses a multi let" $ do
    "let { n = 23 ; f m = m } in (f n)" <=>
      Let [("n", (Lit (LitInt 23))), ("f", (Lam "m" (Var "m") ))] (App (Var "f") (Var "n"))

  -- it "Parses a fix expression" $ do
  --   "fix (\\ fn n -> (fn n))" <=>
  --     Fix (Lam "fn" (Lam "n" (App (Var "fn") (Var "n"))))

  it "Parses a recursive let expression" $ do
    "let { fn n = (fn n) } in (fn 2)" <=>
      Let
        [ ("fn", (Lam "n" (App (Var "fn") (Var "n")))) ]
        (App (Var "fn") (Lit (LitInt 2)))

  it "Parses a simple arithmetic expression equivalent to 23 + 42" $ do
    "(#+) (23, 42)" <=>
      App (Op "#+") (Tuple [Lit (LitInt 23), Lit (LitInt 42)])
  
  it "Parses a simple arithmetic expression (#+ (23, 42))" $ do
    "(#+ (23, 42))" <=>
      App (Op "#+") (Tuple [(Lit (LitInt 23)), (Lit (LitInt 42))])
  -- NOTE: This is just a parser tests, this is not a valid expression in the language's evaluation semantisc.
  it "Parses a simple arithmetic expression [prefix] ((#+) 23 42)" $ do
    "((#+) 23 42)" <=>
      App (App (Op "#+") (Lit (LitInt 23))) (Lit (LitInt 42))
  -- NOTE: This is just a parser tests, this is not a valid expression in the language's evaluation semantisc.

  it "Parses a simple infix function expression (23 `plus` 42)" $ do
    "(23 `plus` 42)" <=>
      App (App (Var "plus") (Lit (LitInt 23))) (Lit (LitInt 42))
  it "Parses a let-in expression with simple infix function expression (let plus = plus in (23 `plus` 42))" $ do
    "let { plus = plus } in (23 `plus` 42)" <=>
      Let [("plus", (Var "plus"))] (App (App (Var "plus") (Lit (LitInt 23))) (Lit (LitInt 42)))
  it "Parses a let-in expression with simple infix function expression (let plus = (\\ a b -> ((#+) (a, b))) in (23 `plus` 42))" $ do
    "let { plus = \\ a b -> ((#+) (a, b)) } in (23 `plus` 42)" <=>
      Let
        [ ("plus", (Lam "a" (Lam "b" (App (Op "#+") (Tuple [Var "a", Var "b"]))))) ]
        (App (App (Var "plus") (Lit (LitInt 23))) (Lit (LitInt 42)))


infix 4 <=>

(<=>) :: String -> Expression -> IO ()
(<=>) expr ast = do
  case parse'expr expr of
    Left cmd -> exitFailure
    Right ast' -> ast' `shouldBe` ast
