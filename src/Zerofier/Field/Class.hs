{-# LANGUAGE AllowAmbiguousTypes #-}

-- | The 'StarkField' class: what a STARK needs from a field beyond
-- 'Num' and 'Fractional' (a generator, two-adicity, roots of unity,
-- and a canonical byte encoding).
module Zerofier.Field.Class
  ( StarkField (..)
  ) where

import Data.ByteString (ByteString)

-- | A prime field with large power-of-two subgroups. 'twoAdicity' does not
-- mention @a@ (hence AllowAmbiguousTypes), so call it as @twoAdicity \@F@.
class (Eq a, Show a, Fractional a) => StarkField a where
  -- | Source of the roots of unity and the FRI coset offset. Its order need
  -- not be p - 1; each instance states it.
  generator :: a

  -- | The largest k with 2^k dividing p - 1.
  twoAdicity :: Int

  -- | A primitive 2^k-th root of unity: ω^(2^k) = 1 and ω^(2^(k-1)) ≠ 1.
  -- Errors for k < 0 or k > 'twoAdicity'.
  rootOfUnity :: Int -> a

  -- | Canonical fixed-width encoding: exactly one byte string per element.
  toBytes :: a -> ByteString

  -- | Inverse of 'toBytes'. Returns 'Nothing' on the wrong length or on an
  -- encoded integer ≥ p, so every element has exactly one valid encoding.
  fromBytes :: ByteString -> Maybe a
