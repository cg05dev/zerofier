module Main (main) where

import Test.Tasty (defaultMain, testGroup)

import qualified Zerofier.Field.Prime128Spec

main :: IO ()
main =
  defaultMain $
    testGroup
      "Zerofier"
      [ Zerofier.Field.Prime128Spec.tests
      ]
