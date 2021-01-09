module Compiler.TypeChecker.Inference where

import qualified Data.Map.Strict as Map
import Data.List (elem, foldl)
import qualified Data.Set as Set
import Control.Monad.State
import Control.Monad.Except

import Compiler.Syntax 
  ( Bind(..)
  , Declaration(..), ConstrDecl(..)
  , Expression(..)
  , Lit(..)
  , MatchGroup(..), Match(..)
  , Pattern(..)
  , Sig(..)
  , Type(..), Scheme(..))

import Compiler.Syntax.Expression
import Compiler.TypeChecker.TypeError


type Infer a = ExceptT TypeError (State Int) a

newtype TypeEnv = Env (Map.Map String Scheme)

-- type substitution -- ordered mapping between name and type
newtype Subst = Sub [(String, Type)]


class Substitutable a where
  apply :: Subst -> a -> a
  ftv :: a -> Set.Set String

instance Substitutable Type where
  apply (Sub [(name, repl)]) var@(TyVar varname)
    | name == varname = repl
    | otherwise = var
  apply (Sub [(name, repl)]) (TyCon conname)
    = (TyCon conname)
  apply (Sub [(name, repl)]) (TyArr left right)
    = TyArr (apply (Sub [(name, repl)]) left) (apply (Sub [(name, repl)]) right)
  apply (Sub [(name, repl)]) (TyTuple types)
    = TyTuple $ map (\ t' -> apply (Sub [(name, repl)]) t') types
  apply (Sub [(name, repl)]) (TyList type') = case type' of
    TyVar var | name == var -> TyList repl
    TyVar _ -> TyList type'
    _ -> TyList $ apply (Sub [(name, repl)]) type'
  apply (Sub subst) type'
    = foldl
        (\ type' (name, repl) -> apply (Sub [(name, repl)]) type')
        type'
        subst

  ftv type' = case type' of
    TyVar name -> Set.singleton name
    TyCon name -> Set.empty
    TyTuple ts -> foldl (\ set' t' -> Set.union set' (ftv t')) Set.empty ts
    TyList t -> ftv t
    TyArr left right -> Set.union (ftv left) (ftv right)


instance Substitutable Scheme where
  apply (Sub [(name, replacement)]) (ForAll varnames type')
    | elem name varnames = ForAll varnames type'
    | otherwise = ForAll varnames $ apply (Sub [(name, replacement)]) type'
  apply (Sub subst) scheme
    = foldl
        (\ scheme (name, replacement)
          -> apply (Sub [(name, replacement)]) scheme)
        scheme
        subst

  ftv (ForAll vars type')
    = Set.difference (ftv type') (Set.fromList vars)


instance Substitutable Subst where
  apply subst'left (Sub subst'right)
    = Sub $ map
        (\ (name, type') -> (name, apply subst'left type'))
        subst'right

  ftv (Sub subst)
    = foldl
        (\ free'set (name, type') -> free'set `Set.union` ftv type')
        Set.empty
        subst


instance Substitutable TypeEnv where
  apply subst (Env type'env)
    = Env $ Map.map
        (\ scheme -> apply subst scheme)
        type'env

  ftv (Env type'env)
    = Map.foldr
        (\ scheme free'set -> free'set `Set.union` ftv scheme)
        Set.empty
        type'env


extend :: TypeEnv -> (String, Scheme) -> TypeEnv
extend (Env env) (ty'var, scheme) = Env $ Map.insert ty'var scheme env


runInfer :: Infer (Subst, Type) -> Either TypeError Scheme
runInfer m
 = case evalState (runExceptT m) 0 of
    Left err  -> Left err
    Right res -> Right $ closeOver res


closeOver :: (Subst, Type) -> Scheme
closeOver (subst, type')
  = normalize sc
  where sc = generalize (Env Map.empty) (apply subst type')  


normalize :: Scheme -> Scheme
normalize (ForAll type'args body) = ForAll (fmap snd ord) (normtype body)
  where
    ord = zip (Set.toList . ftv $ body) letters

    normtype (TyArr a b) = TyArr (normtype a) (normtype b)
    normtype (TyCon a) = TyCon a
    normtype (TyTuple ts) = TyTuple $ map normtype ts
    normtype (TyList t) = TyList $ normtype t
    normtype (TyVar a) =
      case lookup a ord of
        Just x -> TyVar x
        Nothing -> error $ "Type variable " ++ show a ++ " not in the signature." 


empty'subst :: Subst
empty'subst = Sub []


-- not really empty
empty'env :: TypeEnv
empty'env = Env $ Map.fromList
  [ ("#fst",  ForAll ["a", "b"] (TyArr (TyTuple [TyVar "a", TyVar "b"]) (TyVar "a")))
  , ("#snd",  ForAll ["a", "b"] (TyArr (TyTuple [TyVar "a", TyVar "b"]) (TyVar "b")))
  , ("#=",    ForAll ["a"]      ((TyTuple [TyVar "a", TyVar "a"]) `TyArr` (TyCon "Bool")))
  , ("#<",    ForAll []         ((TyTuple [TyCon "Int", TyCon "Int"]) `TyArr` (TyCon "Bool")))
  , ("#>",    ForAll []         ((TyTuple [TyCon "Int", TyCon "Int"]) `TyArr` (TyCon "Bool")))
  , ("#+",    ForAll []         ((TyTuple [TyCon "Int", TyCon "Int"]) `TyArr` (TyCon "Int")))
  , ("#*",    ForAll []         ((TyTuple [TyCon "Int", TyCon "Int"]) `TyArr` (TyCon "Int")))
  , ("#-",    ForAll []         ((TyTuple [TyCon "Int", TyCon "Int"]) `TyArr` (TyCon "Int")))
  , ("#/",    ForAll []         ((TyTuple [TyCon "Int", TyCon "Int"]) `TyArr` (TyCon "Int")))
  -- concat two strings
  , ("#.",    ForAll []         ((TyTuple [TyCon "String", TyCon "String"]) `TyArr` (TyCon "String")))
  , ("#++",   ForAll ["a"]      ((TyTuple [TyList (TyVar "a"), TyList (TyVar "a")]) `TyArr` (TyList (TyVar "a"))))
  , ("#!!",   ForAll ["a"]      ((TyTuple [TyCon "Int", TyList (TyVar "a")]) `TyArr` (TyVar "a")))
  -- prepend element to a list
  , ("#:",    ForAll ["a"]      ((TyTuple [TyVar "a", TyList (TyVar "a")]) `TyArr` (TyList (TyVar "a"))))
  -- prepend a char to a string
  , ("#;",    ForAll []         ((TyTuple [TyCon "Char", TyCon "String"]) `TyArr` (TyCon "String")))
  -- head of the list
  , ("#head", ForAll ["a"]      ((TyList (TyVar "a")) `TyArr` (TyVar "a")))
  , ("#tail", ForAll ["a"]      ((TyList (TyVar "a")) `TyArr` (TyList (TyVar "a"))))
  , ("#nil?", ForAll ["a"]      ((TyList (TyVar "a")) `TyArr` (TyCon "Bool")))
  ]


compose'subst :: Subst -> Subst -> Subst
compose'subst (Sub subst'left) subst'right
  = let (Sub subst'right') = apply (Sub subst'left) subst'right
    in Sub $ subst'left ++ subst'right'


occurs :: String -> Type -> Bool
occurs name (TyVar varname)
  = name == varname
occurs name (TyCon conname)
  = False
occurs name (TyTuple ts)
  = any (occurs $ name) ts
occurs name (TyList t)
  = occurs name t
occurs name (TyArr left right)
  = occurs name left || occurs name right


bind :: String -> Type -> Infer Subst
bind varname type'
  | type' == TyVar varname = return empty'subst
  | occurs varname type' = throwError $ InfiniteType varname type'
  | otherwise = return $ Sub [(varname, type')]


unify :: Type -> Type -> Infer Subst
unify (TyVar varname) type'
  = bind varname type'

unify type' (TyVar varname)
  = bind varname type'

unify (TyCon name'l) (TyCon name'r)
  | name'l == name'r = return empty'subst
  | otherwise = throwError $ UnifMismatch name'l name'r

unify (TyTuple ts'left) (TyTuple ts'right)
  = if length ts'left /= length ts'right
    then throwError $ UnifShapeMismatch (TyTuple ts'left) (TyTuple ts'right) 
    else foldM
      (\ subst' (t'left, t'right) -> do
        subst'new <- unify (apply subst' t'left) (apply subst' t'right)
        return (subst' `compose'subst` subst'new))
      empty'subst
      (zip ts'left ts'right)

unify (TyList t'left) (TyList t'right)
  = unify t'left t'right

unify (TyArr left'a right'a) (TyArr left'b right'b) = do
  subst'left <- unify left'a left'b
  subst'right <- unify (apply subst'left right'a) (apply subst'left right'b)
  return (subst'right `compose'subst` subst'left)

unify t'left t'right = do
  throwError $ UnifShapeMismatch t'left t'right


generalize :: TypeEnv -> Type -> Scheme
generalize env type'
  = ForAll type'args type'
    where
      fvt = ftv type'
      fve = ftv env
      type'args = Set.toList $ fvt `Set.difference` fve


letters :: [String]
letters = [1..] >>= flip replicateM ['a'..'z']


fresh :: Infer Type
fresh = do
  counter <- get
  put $ counter + 1
  return $ TyVar (letters !! counter)


instantiate :: Scheme -> Infer Type
instantiate (ForAll args type') = do
  args' <- mapM (const fresh) args
  let subst = zip args args'
  return $ apply (Sub subst) type'


infer :: TypeEnv -> Expression -> Infer (Subst, Type)
infer (Env env) expr = case expr of
  Var x ->
    case Map.lookup x env of
      Nothing -> throwError $ UnboundVariable x
      Just scheme -> do
        type' <- instantiate scheme
        return (empty'subst, type')

  Op x ->
    case Map.lookup x env of
      Nothing -> throwError $ UnboundVariable x
      Just scheme -> do
        type' <- instantiate scheme
        return (empty'subst, type')

  Lam x body -> do
    type'var <- fresh
    let env' = (Env env) `extend` (x, ForAll [] type'var)
    (subst', type') <- infer env' body
    return (subst', apply subst' (type'var `TyArr` type'))

  App left right -> do
    type'var <- fresh
    (subst'left, type'left) <- infer (Env env) left
    (subst'right, type'right) <- infer (apply subst'left (Env env)) right
    subst' <- unify (apply subst'right type'left) (type'right `TyArr` type'var)
    return (subst' `compose'subst` subst'right `compose'subst` subst'left, apply subst' type'var)

  If cond' then' else' -> do
    (subst'cond, type'cond) <- infer (Env env) cond'
    let env' = apply subst'cond (Env env)
    (subst'then', type'then') <- infer env' then'
    let env'' = apply subst'then' env'
    (subst'else', type'else') <- infer env'' else'

    let subst' = subst'cond `compose'subst` subst'then' `compose'subst` subst'else'

    let cond'type' = apply subst' type'cond
    let then'type' = apply subst' type'then'
    let else'type' = apply subst' type'else'

    unif'subst'1 <- unify cond'type' (TyCon "Bool")
    unif'subst'2 <- unify then'type' else'type'

    let final'subst = subst' `compose'subst` unif'subst'1 `compose'subst` unif'subst'2

    let final'type = apply final'subst then'type' -- or else'type' both should work I think
    return (final'subst, final'type)
  
  Let name value expression -> do
    (subst'val, type'val) <- infer (Env env) value
    let env' = apply subst'val (Env env)
    let type'val' = generalize env' type'val
    (subst'expr, type'expr) <- infer (env' `extend` (name, type'val')) expression
    return (subst'expr `compose'subst` subst'val, type'expr)

  Tuple exprs -> do
    (subst'fin, env'fin, types) <- foldM infer' (empty'subst, (Env env), []) exprs
    let types'fin = map (\ t -> apply subst'fin t) types
    return (subst'fin, TyTuple types'fin)
      where
        infer' (sub, env, ts) exp' = do
          (subst', type') <- infer env exp'
          let env' = apply subst' env
          return (sub `compose'subst` subst', env', ts ++ [type'])

  List exprs -> do
    (subst', env'fin, types) <- foldM infer' (empty'subst, (Env env), []) exprs
    let types' = map (\ t -> apply subst' t) types
    type'var <- fresh
    (subst'fin, type'fin) <- foldM unify' (empty'subst, type'var) types'
    return (subst'fin, TyList type'fin)
      where
        infer' (sub, env, ts) exp' = do
          (subst', type') <- infer env exp'
          let env' = apply subst' env
          return (sub `compose'subst` subst', env', ts ++ [type'])
        unify' (sub, t) t' = do
          sub' <- unify (apply sub t) (apply sub t') -- the first apply shouldn't be ncessary, but won't hurt
          return (sub `compose'subst` sub', apply sub' t)

  Fix expr -> do
    type'var <- fresh
    let t' = (type'var `TyArr` type'var) `TyArr` type'var
    (sub, t) <- infer (Env env) expr
    type'var' <- fresh
    sub' <- unify (t `TyArr` type'var') t'
    return (sub' `compose'subst` sub, apply sub' type'var')

  Lit (LitInt i) -> return (empty'subst, (TyCon "Int"))
  Lit (LitDouble d) -> return (empty'subst, (TyCon "Double"))
  Lit (LitChar ch) -> return (empty'subst, (TyCon "Char"))
  Lit (LitString s) -> return (empty'subst, (TyCon "String"))
  Lit (LitBool b) -> return (empty'subst, (TyCon "Bool"))
  Lit LitUnit -> return (empty'subst, (TyCon "Unit"))


inferExpression :: TypeEnv -> Expression -> Either TypeError Scheme
inferExpression env = runInfer . infer env


-- inferTop :: TypeEnv -> [(String, Expression)] -> Either TypeError TypeEnv
-- inferTop env [] = Right env
-- inferTop env ((name, ex):xs) = case inferExpression env ex of
--   Left err -> Left err
--   Right ty -> inferTop (extend env (name, ty)) xs


-- typeof :: TypeEnv -> String -> Maybe Scheme
-- typeof env name = Map.lookup name env
