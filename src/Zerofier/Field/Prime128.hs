{-# LANGUAGE AllowAmbiguousTypes #-}

-- | Prime fields @Fp p@ with a type-level modulus, and the main field
-- @F = Fp 270497897142230380135924736767050121217@, where
-- p = 1 + 407 * 2^119 (the field from /Anatomy of a STARK/).
module Zerofier.Field.Prime128
  ( Fp -- constructor hidden to protect the [0, p) invariant
  , unFp
  , modulus
  , F
  ) where

import qualified Data.ByteString as BS
import Data.Proxy (Proxy (..))
import Data.Ratio (denominator, numerator)
import GHC.TypeLits (KnownNat, Nat, natVal)
import Numeric.Natural (Natural)

import Zerofier.Field.Class

-- | An element of the prime field Z/pZ.
--
-- Invariant: the stored 'Natural' is always in [0, p). The derived 'Eq'
-- is only correct because of this, so every function that builds an
-- 'Fp' must reduce mod p.
newtype Fp (p :: Nat) = Fp Natural
  deriving stock (Eq, Ord, Show)

-- | The canonical representative in [0, p).
unFp :: Fp p -> Natural
unFp (Fp a) = a

-- | The modulus p as an 'Integer'. Call it as @modulus \@p@.
modulus :: forall p. KnownNat p => Integer
modulus = natVal (Proxy @p)

-- | n mod p. `mod` (not `rem`) maps negatives into [0, p): mkFp (-1) == p - 1.
mkFp :: forall p. KnownNat p => Integer -> Fp p
mkFp n = Fp (fromInteger (n `mod` modulus @p))

toI :: Fp p -> Integer
toI (Fp a) = toInteger a

-- | Arithmetic mod p, done in 'Integer' so 'Natural' never underflows.
instance KnownNat p => Num (Fp p) where
  a + b = mkFp (toI a + toI b)
  a * b = mkFp (toI a * toI b)
  a - b = mkFp (toI a - toI b)
  negate a = mkFp (negate (toI a))
  fromInteger = mkFp

  -- Meaningless in a field; chosen so that abs x * signum x == x.
  abs = id
  signum (Fp 0) = Fp 0
  signum _ = Fp 1

instance KnownNat p => Fractional (Fp p) where
  -- | a^(-1) = a^(p-2) by Fermat. Zero is rejected, since 0^(p-2) = 0.
  recip (Fp 0) = error "Zerofier.Field.Prime128.recip: division by zero"
  recip a = a ^ (modulus @p - 2)

  fromRational r = fromInteger (numerator r) / fromInteger (denominator r)

-- | The field from /Anatomy of a STARK/: p = 1 + 407 * 2^119.
type F = Fp 270497897142230380135924736767050121217

instance StarkField F where
  -- From the tutorial's code. Its order is 2^119, not p - 1 (3 generates
  -- the whole group); the 2-power subgroup is all a STARK needs.
  generator = 85408008396924667383611388730472331217

  twoAdicity = 119

  -- | generator^(2^(119-k)): squaring halves a 2-power order.
  rootOfUnity k
    | k < 0 || k > twoAdicity @F =
        error ("Zerofier.Field.Prime128.rootOfUnity: no 2^k-th root for k = " <> show k)
    | otherwise = iterate (\x -> x * x) generator !! (twoAdicity @F - k)

  -- | 16 bytes, little-endian.
  toBytes a = BS.pack [fromIntegral (toI a `div` (256 ^ i)) | i <- [0 .. byteLen - 1 :: Int]]

  -- | Rejects values >= p instead of reducing them, keeping encodings canonical.
  fromBytes bs
    | BS.length bs /= byteLen = Nothing
    | n >= modulus @270497897142230380135924736767050121217 = Nothing
    | otherwise = Just (Fp (fromInteger n))
    where
      n = BS.foldr (\b acc -> fromIntegral b + 256 * acc) 0 bs :: Integer

byteLen :: Int
byteLen = 16
