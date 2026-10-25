module Main (main) where

import Test.Tasty.Bench (bench, bgroup, defaultMain, whnf)

import Zerofier.Field.Prime128 (F)

main :: IO ()
main =
  defaultMain
    [ bgroup
        "field"
        [ bench "Integer mul mod p (baseline)" $ whnf (\x -> (x * x) `mod` p) (p - 2)
        , bench "F mul" $ whnf (\x -> x * x) a
        , bench "F add" $ whnf (\x -> x + x) a
        , bench "F recip (Fermat)" $ whnf recip a
        ]
    ]
  where
    p :: Integer
    p = 270497897142230380135924736767050121217

    a :: F
    a = fromInteger (p - 2)
