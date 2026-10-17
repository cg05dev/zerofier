-- | Prime fields @Fp p@ with a type-level modulus, and the main field
-- @F = Fp 270497897142230380135924736767050121217@, where
-- p = 1 + 407 * 2^119 (the field from /Anatomy of a STARK/).
--
-- Phase 1. See docs/BUILD_GUIDE.md, "Phase 1: Finite fields".
module Zerofier.Field.Prime128 () where
