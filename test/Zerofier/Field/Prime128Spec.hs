{-# LANGUAGE AllowAmbiguousTypes #-}

module Zerofier.Field.Prime128Spec (tests) where

import qualified Data.ByteString as BS
import GHC.TypeLits (KnownNat)
import Test.QuickCheck (Gen, Property, chooseInt, forAll, vectorOf, (==>))
import Test.Tasty (TestTree, localOption, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (QuickCheckTests (..), testProperty)

import Zerofier.Field.Class
import Zerofier.Field.Prime128
import Zerofier.Gen ()

tests :: TestTree
tests =
  testGroup
    "Field"
    [ testCase "modulus literal is 1 + 407 * 2^119" $
        modulus @270497897142230380135924736767050121217 @?= 1 + 407 * 2 ^ (119 :: Int)
    , fieldLaws @17 "F17"
    , fieldLaws @270497897142230380135924736767050121217 "F"
    , starkFieldF
    ]

-- | The field axioms and reduction edge cases, for any prime p.
fieldLaws :: forall p. KnownNat p => String -> TestTree
fieldLaws name =
  localOption (QuickCheckTests 10000) $
    testGroup
      name
      [ testGroup
          "addition"
          [ testProperty "associative" $ \a b c -> (a + b) + c == a + (b + c :: Fp p)
          , testProperty "commutative" $ \a b -> a + b == b + (a :: Fp p)
          , testProperty "identity" $ \a -> a + 0 == (a :: Fp p)
          , testProperty "inverse" $ \a -> a + negate a == (0 :: Fp p)
          , testProperty "subtraction is adding the negation" $ \a b -> a - b == a + negate (b :: Fp p)
          ]
      , testGroup
          "multiplication"
          [ testProperty "associative" $ \a b c -> (a * b) * c == a * (b * c :: Fp p)
          , testProperty "commutative" $ \a b -> a * b == b * (a :: Fp p)
          , testProperty "identity" $ \a -> a * 1 == (a :: Fp p)
          , testProperty "distributes over addition" $ \a b c -> a * (b + c) == a * b + a * (c :: Fp p)
          , testProperty "a * recip a == 1 for a /= 0" $ \a -> a /= 0 ==> a * recip a == (1 :: Fp p)
          , testProperty "a ^ (p - 1) == 1 for a /= 0 (Fermat)" $ \a -> a /= 0 ==> a ^ (p - 1) == (1 :: Fp p)
          ]
      , testGroup
          "reduction"
          [ testCase "fromInteger (-1) == p - 1" $ unFp (fromInteger (-1) :: Fp p) @?= fromInteger (p - 1)
          , testCase "fromInteger p == 0" $ (fromInteger p :: Fp p) @?= 0
          , testProperty "fromInteger n == fromInteger (n + k * p)" $ \n k ->
              (fromInteger n :: Fp p) == fromInteger (n + k * p)
          , testProperty "representative is in [0, p)" $ \a -> toInteger (unFp (a :: Fp p)) < p
          ]
      ]
  where
    p = modulus @p

-- | The 'StarkField' instance for the main field.
starkFieldF :: TestTree
starkFieldF =
  testGroup
    "StarkField F"
    [ testCase "generator has order exactly 2^119" $ do
        assertBool "g^(2^119) == 1" (generator ^ (2 ^ (119 :: Int) :: Integer) == (1 :: F))
        assertBool "g^(2^118) /= 1" (generator ^ (2 ^ (118 :: Int) :: Integer) /= (1 :: F))
    , testCase "rootOfUnity k is a primitive 2^k-th root for every k in [1, 119]" $
        mapM_ checkRoot [1 .. twoAdicity @F]
    , testCase "rootOfUnity 0 == 1" $ rootOfUnity 0 @?= (1 :: F)
    , localOption (QuickCheckTests 10000) $
        testGroup
          "encoding"
          [ testProperty "toBytes is 16 bytes" $ \a -> BS.length (toBytes (a :: F)) == 16
          , testProperty "fromBytes (toBytes a) == Just a" $ \a -> fromBytes (toBytes a) == Just (a :: F)
          , testProperty "canonical: a decoded string re-encodes to itself" canonical
          , testCase "rejects 2^128 - 1 (>= p)" $ fromBytes (BS.replicate 16 0xff) @?= (Nothing :: Maybe F)
          , testCase "rejects the wrong length" $ do
              fromBytes (BS.replicate 15 0) @?= (Nothing :: Maybe F)
              fromBytes (BS.replicate 17 0) @?= (Nothing :: Maybe F)
          ]
    ]
  where
    checkRoot k = do
      let w = rootOfUnity k :: F
      assertBool ("w^(2^k) == 1, k = " <> show k) (w ^ (2 ^ k :: Integer) == 1)
      assertBool ("w^(2^(k-1)) == -1, k = " <> show k) (w ^ (2 ^ (k - 1) :: Integer) == -1)

-- | Any 16-byte string that decodes re-encodes to itself. About 79% of
-- random 16-byte strings are below p, so most cases decode.
canonical :: Property
canonical = forAll bytes16 $ \bs -> case fromBytes bs :: Maybe F of
  Nothing -> True
  Just a -> toBytes a == bs
  where
    bytes16 :: Gen BS.ByteString
    bytes16 = BS.pack <$> vectorOf 16 (fromIntegral <$> chooseInt (0, 255))
