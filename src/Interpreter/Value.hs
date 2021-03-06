module Interpreter.Value where

import Data.List
import qualified Data.Map.Strict as Map
import Control.Monad.State.Lazy

import Compiler.Syntax.Expression (Expression)
import Compiler.Syntax.Literal

import Interpreter.Address


type Env = Map.Map String Address


type Memory = Map.Map Address Value


data Stored
  = At Address Value

data Value
  = Op String
  | Lit Lit
  | Lam String Expression Env
  | Tuple [Value]
  | Thunk (Env -> State Memory (Either EvaluationError Value)) Env Address
  | Data String [Value] -- Name of the Constr and list of arguments


instance Show Value where
  show (Op name) = name
  show (Lit lit) = show lit
  show (Lam par body env) = "<lambda>"
  show (Tuple values) = "(" ++ intercalate ", " (map show values) ++ ")"
  show (Thunk force'f env addr) = "<thunk>"
  show (Data name [])
    = name
  show (Data name exprs)
    = "(" ++ name ++ " " ++ unwords (map show exprs) ++ ")"


data EvaluationError
  = UnboundVar String
  | BadOperatorApplication String Value
  | IndexOutOfBound Int
  | NilHeadException
  | NilTailException
  | EmptyStringException
  | DivisionByZero Int
  | Unexpected String

instance Show EvaluationError where
  show (UnboundVar name) =
    "Unknown variable " ++ name
  show (BadOperatorApplication name exp) =
    "Bad use of the operator " ++ name ++ "\n  in the expression \n    (" ++ name ++ ")" -- show exp ++
  show (IndexOutOfBound ind) =
    "Index out of the bound error. (" ++ show ind ++ ")"
  show NilHeadException =
    "Native function #head called on an empty list."
  show NilTailException =
    "Native function #tail called on an empty list."
  show EmptyStringException =
    "Operation called with an empty string."
  show (DivisionByZero left) =
    "Division by zero error. (" ++ show left ++ " / 0)"
  show (Unexpected message) =
    "Unexpected: " ++ message


empty'env :: Env
empty'env = Map.empty


empty'memory :: Memory
empty'memory = Map.empty


to'val'bool :: Bool -> Value
to'val'bool True = Data "True" []
to'val'bool False = Data "Fase" []


from'val'bool :: Value -> Bool
from'val'bool (Data "True" []) = True
from'val'bool (Data "Fase" []) = False
from'val'bool _ = error "Trying to convert non Boolean value to the Bool type!"


str'to'value :: String -> Value
str'to'value "" = Data "[]" []
str'to'value (ch : str) = Data ":" [Lit $ LitChar ch, rest]
  where rest = str'to'value str
