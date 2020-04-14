{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}
import           Control.DeepSeq
import           Control.Monad
import           Control.Monad.Random
import           Data.Constraint              (Dict (..))
import           Data.List                    (foldl')
import           Data.Reflection              (reifyNat)
import           Data.Serialize
import           Data.Singletons
import           Data.Singletons.Prelude.List
import           Data.Typeable
import           GHC.TypeLits
import           System.IO
import           Unsafe.Coerce                (unsafeCoerce)

import qualified Data.ByteString              as B
import           Data.Semigroup               ((<>))
import           Data.Serialize

import           GHC.TypeLits

import qualified Numeric.LinearAlgebra.Static as SA

import           Options.Applicative

import           Grenade

import           Debug.Trace

-- | The definition for a feed forward network using the dynamic module. Note the nested networks. This network clearly is over-engeneered for this example!
netSpec :: SpecNet
netSpec = specFullyConnected 2 40 |=> specTanh1D 40 |=> netSpecInner |=> specFullyConnected 20 30 |=> specRelu1D 30 |=> specFullyConnected 30 20 |=> specRelu1D 20 |=> specFullyConnected 20 10 |=> specRelu1D 10 |=> specFullyConnected 10 1 |=> specLogit1D 1 |=> specNil1D 1
  where netSpecInner = specFullyConnected 40 30 |=> specRelu1D 30 |=> specFullyConnected 30 20 |=> specNil1D 20


netTrain ::
     (SingI (Last shapes), Show (Network layers shapes), MonadRandom m, KnownNat len1, KnownNat len2, Head shapes ~ 'D1 len1, Last shapes ~ 'D1 len2)
  => Network layers shapes
  -> LearningParameters
  -> Int
  -> m (Network layers shapes)
netTrain net0 rate n = do
    inps <- replicateM n $ do
      s  <- getRandom
      return $ S1D $ SA.randomVector s SA.Uniform * 2 - 1
    let outs = flip map inps $ \(S1D v) ->
                 if v `inCircle` (fromRational 0.50, 0.50)  || v `inCircle` (fromRational (-0.50), 0.50)
                   then S1D $ fromRational 1
                   else S1D $ fromRational 0

    let trained = foldl' trainEach net0 (zip inps outs)
    return trained

  where trainEach !network (i,o) = train rate network i o

renderClass :: IO ()
renderClass = do
  let testIns = [ [ (x,y)  | x <- [0..50] ]
                           | y <- [0..20] ]
  let outMat  = fmap (fmap (\(x,y) -> (render (x/25-1) (y/10-1)))) testIns
  putStrLn $ unlines outMat

  where
    render x y  | x == 0 && y == 0 = '+'
                | y == 0 = '-'
                | x == 0 = '|'
                | otherwise = let v = SA.vector [x,y] :: SA.R 2
                              in if v `inCircle` (fromRational 0.50, 0.50)  || v `inCircle` (fromRational (-0.50), 0.50)
                                 then '1'
                                 else ' '
-- netLoad :: FilePath -> IO FFNet
-- netLoad modelPath = do
--   modelData <- B.readFile modelPath
--   either fail return $ runGet (get :: Get FFNet) modelData

-- renderClass :: IO ()
-- renderClass = do
--   let testIns = [ [ (x,y)  | x <- [0..50] ]
--                            | y <- [0..20] ]
--   let outMat  = fmap (fmap (\(x,y) -> (render (x/25-1) (y/10-1)))) testIns
--   putStrLn $ unlines outMat

--   where
--     render x y  | x == 0 && y == 0 = '+'
--                 | y == 0 = '-'
--                 | x == 0 = '|'
--                 | otherwise = let v = SA.vector [x,y] :: SA.R 2
--                               in if v `inCircle` (fromRational 0.50, 0.50)  || v `inCircle` (fromRational (-0.50), 0.50)
--                                  then '1'
--                                  else ' '


netScore network = do
    let testIns = [ [ (x,y)  | x <- [0..50] ]
                             | y <- [0..20] ]
        outMat  = fmap (fmap (\(x,y) -> (render (x/25-1) (y/10-1) . normx) $ runNet network (S1D $ SA.vector [x / 25 - 1,y / 10 - 1]))) testIns
    putStrLn $ unlines outMat

  where
    render x y n'  | x == 0 && y == 0 = '+'
                   | y == 0 = '-'
                   | x == 0 = '|'
                   | n' <= 0.2  = ' '
                   | n' <= 0.4  = '.'
                   | n' <= 0.6  = '-'
                   | n' <= 0.8  = '='
                   | otherwise = '#'

normx :: S ('D1 1) -> Double
normx (S1D r) = SA.mean r

testValues :: (KnownNat len, Show (Network layers shapes), Head shapes ~ 'D1 len, Last shapes ~ 'D1 1) => Network layers shapes -> IO ()
testValues network = do
  inps <- replicateM 1000 $ do
      s  <- getRandom
      return $ S1D $ SA.randomVector s SA.Uniform * 2 - 1
  let outs = flip map inps $ \(S1D v) ->
                 if v `inCircle` (fromRational 0.50, 0.50)  || v `inCircle` (fromRational (-0.50), 0.50)
                   then 1 :: Integer
                   else 0
  let ress = zip outs (map (round . normx . runNet network) inps)
      correct = length $ filter id $ map (uncurry (==)) ress
      incorrect = length $ filter id $ map (uncurry (/=)) ress
      falsePositives = length $ filter id $ map (uncurry (\shd nn -> shd == 0 && nn == 1)) ress
      falseNegatives = length $ filter id $ map (uncurry (\shd nn -> shd == 1 && nn == 0)) ress
  putStr $ show correct  ++ " | "
  putStr $ show incorrect ++ " | "
  putStr $ show falsePositives ++ " | "
  putStrLn $ show falseNegatives ++ " | "


inCircle :: KnownNat n => SA.R n -> (SA.R n, Double) -> Bool
v `inCircle` (o, r) = SA.norm_2 (v - o) <= r


data FeedForwardOpts = FeedForwardOpts Int LearningParameters

feedForward' :: Parser FeedForwardOpts
feedForward' =
  FeedForwardOpts <$> option auto (long "examples" <> short 'e' <> value 1000)
                  <*> (LearningParameters
                       <$> option auto (long "train_rate" <> short 'r' <> value 0.005)
                       <*> option auto (long "momentum" <> value 0.0)
                       <*> option auto (long "l2" <> value 0.0005)
                      )


main :: IO ()
main = do
  FeedForwardOpts examples rate <- execParser (info (feedForward' <**> helper) idm)
  putStrLn "| Nr | Correct | Incorrect | FalsePositives | FalseNegatives |"
  putStrLn "--------------------------------------------------------------"
  let nr = 100 :: Int
  mapM_
    (\n -> do
       putStr $ "| " ++ show n ++ " | "
       SpecConcreteNetwork1D1D (net0 :: Network layers shapes) <- networkFromSpecificationWith HeEtAl netSpec
      -- We need to specify the actual number of output nodes, as our functions requiere that!
       case (unsafeCoerce (Dict :: Dict ()) :: Dict (('D1 1) ~ Last shapes)) of
         Dict -> do
           net <- netTrain net0 rate examples
           unsafeCoerce $ -- only needed as GADTs are enabled, which disallowes the type to escape and thus prevents the type inference to work. The result is not needed anyways.
             testValues net)
    [0 .. nr - 1]


  -- Features of dynamic networks:
  SpecConcreteNetwork1D1D (net' :: Network layers shapes) <- networkFromSpecificationWith HeEtAl netSpec
  net' <- netTrain net' rate examples
  let spec' = networkToSpecification net'
  putStrLn "String represenation of the network: "
  print spec'
  let serializedSpec = encode spec'   -- only the specification (not the weights) are serialized here! The weights can be serialized using the networks serialize instance!
  let weightsBs = encode net'         -- E.g. like this.
  case decode serializedSpec of
    Left err -> print err
    Right spec'' -> do
      SpecConcreteNetwork1D1D (net'' :: Network layers'' shapes'') <- networkFromSpecificationWith HeEtAl spec''
      net'' <- foldM (\n _ -> netTrain n rate examples) net'' [1..30]
      case (unsafeCoerce (Dict :: Dict ()) :: Dict (('D1 1) ~ Last shapes'')) of
        Dict -> netScore net''
