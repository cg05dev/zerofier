module Zerofier.Field.Prime128Spec (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

-- | Field tests. The algebraic-law properties (10,000 cases each) go here
-- once 'Fp' exists; see the Phase 1 "Done when" checklist.
tests :: TestTree
tests =
  testGroup
    "Field"
    [ testCase "modulus literal is 1 + 407 * 2^119" $
        (270497897142230380135924736767050121217 :: Integer) @?= 1 + 407 * 2 ^ (119 :: Int)
    ]
