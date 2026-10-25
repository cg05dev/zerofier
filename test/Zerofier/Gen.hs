{-# LANGUAGE AllowAmbiguousTypes #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | QuickCheck generators shared by the specs (orphan instances).
module Zerofier.Gen () where

import GHC.TypeLits (KnownNat)
import Test.QuickCheck (Arbitrary (..), choose, frequency)

import Zerofier.Field.Prime128 (Fp, modulus)

-- | Uniform elements, with the edge cases 0, 1 and p - 1 forced in often.
instance KnownNat p => Arbitrary (Fp p) where
  arbitrary =
    frequency
      [ (1, pure (fromInteger 0))
      , (1, pure (fromInteger 1))
      , (1, pure (fromInteger (p - 1)))
      , (7, fromInteger <$> choose (0, p - 1))
      ]
    where
      p = modulus @p
