{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable, FlexibleContexts, StandaloneDeriving, UndecidableInstances #-}
module Language.Typo.ASTs
  ( Value(..)
  , Op(..)
  , SingleBind(..)
  , BSurface(..)
  , Surface
  , Redex(..)
  , BANF(..)
  , ANF
  , Definition(..)
  , Program(..)
  , Anf         -- :: ContT ANF (State Int)
  , Gensym      -- :: State Int
  , runAnf      -- :: Anf Redex -> Gensym ANF
  , runGensym   -- :: Gensym a -> a
  , anormalize  -- :: Surface -> Anf Redex
  , gensym      -- :: (MonadState Int m) => String -> m String
  ) where

import Control.Monad.Cont
import Control.Monad.State

import Data.Word
import Data.Foldable ( Foldable )
import Data.Traversable ( Traversable )


data Value
  = Number Word
  | Boolean Bool
  | Id String
  deriving ( Eq, Ord, Show )

data Op
  = Add | Sub | Mul | Div | Rem
  | And | Or | Imp | Eq | Lt
  deriving ( Eq, Ord, Enum, Bounded, Show )

data SingleBind a = SingleBind String a
  deriving ( Eq, Ord, Show )

newtype Surface = Surface (BSurface SingleBind)

data BSurface b
  = Val Value
  | Let (b Surface) Surface
  | App String [Surface]
  | Bop Op Surface Surface
  | Cond Surface Surface Surface

deriving instance Eq (b Surface) => Eq (BSurface b)
deriving instance Ord (b Surface) => Ord (BSurface b)
deriving instance Show (b Surface) => Show (BSurface b)

data Redex
  = RVal Value
  | RApp String [Value]
  | RBop Op Value Value
  | RCond Value ANF ANF
  deriving ( Eq, Ord, Show )

type ANF = BANF SingleBind

data BANF b
  = ARed Redex
  | ALet (b Redex) ANF

deriving instance Eq (b Redex) => Eq (BANF b)
deriving instance Ord (b Redex) => Ord (BANF b)
deriving instance Show (b Redex) => Show (BANF b)

data Definition a
  = Definition { name :: String, args :: [String], body :: a }
  deriving ( Eq, Ord, Show, Functor, Foldable, Traversable )

data Program a
  = Program { definitions :: [Definition a], expr :: a }
  deriving ( Eq, Ord, Show, Functor, Foldable, Traversable )


type Gensym = State Int
type Anf = ContT ANF Gensym

runAnf :: Anf Redex -> Gensym ANF
runAnf m = runContT m (\r -> return (ARed r))

runGensym :: Gensym a -> a
runGensym m = evalState m 0

anormalize :: Surface -> Anf Redex
anormalize s =
  case s of
    Val v -> return (RVal v)
    Bop op l r -> do
      l' <- valued (anormalize l)
      r' <- valued (anormalize r)
      return (RBop op l' r')
    App f as -> do
      as' <- mapM (valued . anormalize) as
      return (RApp f as')
    Let (SingleBind x e) b -> do
      e' <- anormalize e
      mapContT ((ALet (SingleBind x e')) `fmap`)
        (anormalize b)
    Cond c t f -> do
      c' <- valued (anormalize c)
      t' <- lift $ runContT (anormalize t) (\r -> return (ARed r))
      f' <- lift $ runContT (anormalize f) (\r -> return (ARed r))
      return $ RCond c' t' f'

valued :: Anf Redex -> Anf Value
valued m = do
  redex <- m
  case redex of
    RVal v -> return v
    redex  -> do
      x <- gensym "gx"
      mapContT ((ALet (SingleBind x redex)) `fmap`)
        (return (Id x))

gensym :: (MonadState Int m) => String -> m String
gensym x = state (\s -> (x ++ (show s), s + 1))
