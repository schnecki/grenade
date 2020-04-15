{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE CPP                   #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}
{-|
Module      : Grenade.Core.Layer
Description : Defines the Layer Classes
Copyright   : (c) Huw Campbell, 2016-2017
License     : BSD2
Stability   : experimental

This module defines what a Layer is in a Grenade
neural network.

There are two classes of interest: `UpdateLayer` and `Layer`.

`UpdateLayer` is required for all types which are used as a layer
in a network. Having no shape information, this class is agnostic
to the input and output data of the layer.

An instance of `Layer` on the other hand is required for usage in
a neural network, but also specifies the shapes of data that the
network can transform. Multiple instance of `Layer` are permitted
for a single type, to transform different shapes. The `Reshape` layer
for example can act as a flattening layer, and its inverse, projecting
a 1D shape up to 2 or 3 dimensions.

Instances of `Layer` should be as strict as possible, and not emit
runtime errors.
-}
module Grenade.Core.Layer (
    Layer (..)
  , UpdateLayer (..)
  , LayerOptimizerData (..)
  , RandomLayer (..)
  , createRandom
  ) where

import           Control.Monad.Primitive           (PrimBase, PrimState)
import           System.Random.MWC

import           Data.List                         (foldl')

#if MIN_VERSION_base(4,9,0)
import           Data.Kind                         (Type)
#endif

-- import           Grenade.Core.LearningParameters
import           Grenade.Core.Optimizer
import           Grenade.Core.Shape
import           Grenade.Core.WeightInitialization

-- | Class for updating a layer. All layers implement this, as it
--   describes how to create and update the layer.
--
class UpdateLayer x where
  -- | The type for the gradient for this layer.
  --   Unit if there isn't a gradient to pass back.
  type Gradient x :: Type
  type MomentumStore x :: Type
  type MomentumStore x = ()

  -- | Update a layer with its gradient and learning parameters
  runUpdate   :: Optimizer opt -> x -> Gradient x -> x

  -- | Update a layer with many Gradientsx1
  runUpdates      :: Optimizer opt -> x -> [Gradient x] -> x
  runUpdates rate = foldl' (runUpdate rate)

  {-# MINIMAL runUpdate #-}

-- | This is the class which abstracts on how to store the data
--   in the learning process using the different optimizers. A layer
--   can implement it and use it as storage retrieval and setting,
--   however this is not a must. Fro a usefule storage see the
--   @ListStore@ type and the @FullyConnected@ layer for an example.
class LayerOptimizerData x optimizer where
  -- | A data structure that holds all the needed momentum vectors for
  --   the specied optimizer.
  type MomentumData x optimizer :: Type

  -- | Gets a momentum vector(s) for the specified optimizer.
  getData :: optimizer -> x -> MomentumStore x -> MomentumData x optimizer

  -- | Sets the momentum vector(s) for the specified optimizer.
  setData :: optimizer -> x -> MomentumStore x -> MomentumData x optimizer -> MomentumStore x

  -- | Create empty data instance with all values set to 0.
  newData :: optimizer -> x -> MomentumData x optimizer


-- | Class for a layer. All layers implement this, however, they don't
--   need to implement it for all shapes, only ones which are
--   appropriate.
--
class (UpdateLayer x) => Layer x (i :: Shape) (o :: Shape) where
  -- | The Wengert tape for this layer. Includes all that is required
  --   to generate the back propagated gradients efficiently. As a
  --   default, `S i` is fine.
  type Tape x i o :: Type

  -- | Used in training and scoring. Take the input from the previous
  --   layer, and give the output from this layer.
  runForwards    :: x -> S i -> (Tape x i o, S o)

  -- | Back propagate a step. Takes the current layer, the input that
  --   the layer gave from the input and the back propagated derivatives
  --   from the layer above.
  --
  --   Returns the gradient layer and the derivatives to push back
  --   further.
  runBackwards   :: x -> Tape x i o -> S o -> (Gradient x, S i)


-- | Class for random initialization of a layer. This enables to use
--   various initialization techniques for the networks. Every layer
--   needs to implement this. This is standalone class to prevent
--   code duplication for layers which use concrete types in their
--   @UpdateLayer@ instances.
class RandomLayer x where
  -- | Create a random layer according to given initialization method.
  createRandomWith    :: (PrimBase m) => WeightInitMethod -> Gen (PrimState m) -> m x


-- | Create a new random network. This uses the uniform initialization,
-- see @WeightInitMethod@ and @createRandomWith@.
createRandom :: (RandomLayer x)  => IO x
createRandom = withSystemRandom . asGenST $ \gen -> createRandomWith UniformInit gen


