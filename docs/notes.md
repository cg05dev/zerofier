# Zerofier notes

A running journal of what confused me and how it got resolved. This becomes the Phase 9 write-up.

## 2026-10-17: Setup

- Toolchain: GHC 9.10.3, cabal 3.16.1.0, HLS via GHCup on openSUSE Tumbleweed.

## 2026-10-25: Phase 1, finite fields

- The tutorial's "generator" has order 2^119, not p − 1. It generates the 2-power subgroup, which is all the roots of unity and the FRI coset offset need. 3 is the smallest generator of the whole group.
- `Natural` subtraction and converting a negative `Integer` both throw, so all arithmetic runs in `Integer` and reduces with `mod` in one helper (`mkFp`).
- Fermat's inverse silently gives `recip 0 = 0`, so zero is rejected explicitly.
- `fromBytes` must reject values ≥ p instead of reducing them, or x and x + p would both decode to the same element and hashes stop binding.
- Reducing 16 hash bytes mod p for a challenge would be biased (2^128 / p ≈ 1.26); use 32 bytes in Phase 3.
- `twoAdicity :: Int` doesn't mention the class variable, so it needs `AllowAmbiguousTypes` and is called as `twoAdicity @F`.
- Benchmarks: F mul 88 ns (Integer baseline 77 ns), recip 25 μs.
