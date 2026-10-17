module Main (main) where

import Test.Tasty.Bench (bench, bgroup, defaultMain, whnf)

-- | Benchmarks. Field multiply/inverse, NTT sizes, Merkle, FRI, and the
-- spend proof get added here as each phase lands.
main :: IO ()
main =
  defaultMain
    [ bgroup
        "baseline"
        [ bench "Integer mul mod p" $ whnf (\x -> (x * x) `mod` p) (p - 2)
        ]
    ]
  where
    p :: Integer
    p = 270497897142230380135924736767050121217
