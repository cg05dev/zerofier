# Zerofier: Build Guide

Oct 11, 2026 · Christian

## Overview

Zerofier is a small blockchain written in pure Haskell. Every transfer is shielded and proven with a STARK, and nothing in it depends on elliptic curves or factoring, so it stays secure against quantum attacks. The name comes from the **zerofier**, the polynomial at the heart of every STARK constraint. It vanishes exactly where every rule holds, and a Zerofier transaction works the same way: everything checks out, and nothing shows.

By the end you will have:

- A STARK prover and verifier written from scratch: fields, polynomials, NTT, Merkle trees, FRI, and AIR.
- A shielded payment scheme where the sender, receiver, and amount are hidden.
- A small proof-of-work chain with a node, a mempool, and a wallet CLI.
- Tests, benchmarks, and a write-up explaining what it proves and what it does not.

### Goals and non-goals

Goals:

- Learn Haskell properly: typeclasses, type-level naturals, `ST`, `STM`, monad transformers, property testing, and performance tuning.
- Understand STARKs by building every layer yourself rather than calling a library.
- Be post-quantum by construction: hashes and field arithmetic only.

Non-goals:

- Production security, audits, or real money.
- Matching the speed of Rust provers.
- Full peer-to-peer networking or new consensus research.

### Why it survives a quantum computer

Shor's algorithm breaks anything based on discrete logs or factoring: ECDSA, Ed25519, ECDH, and the pairings behind Groth16 and KZG-based PLONK. Grover's algorithm only weakens hash functions, roughly halving their preimage security, so 256-bit outputs keep about 128 bits. STARK soundness rests on hash functions, which is why it is the post-quantum choice.

| Component | Typical choice (broken by Shor) | Zerofier choice |
| --- | --- | --- |
| Proof system | Groth16 or PLONK with KZG (pairings) | STARK (hashes and FRI) |
| Spending authorization | ECDSA or EdDSA signature | Knowledge of a secret key's hash preimage, proven inside the STARK |
| Note encryption to the receiver | ECDH (as in Zcash) | Out-of-band note files in v1; ML-KEM as a stretch goal |
| Block hashing and proof of work | SHA-256 (already safe) | SHA-256 or Blake2b-256 |
| Block producer identity | Signed blocks | Proof of work, so no signatures are needed |

### How to use this guide

Each phase lists its goal, what to read, what to build, the Haskell skills it teaches, a "done when" checklist, and common pitfalls. Phases build on each other, so finish each phase's tests before moving on. The function signatures are suggestions, so change them as your design develops.

## Why Haskell

Haskell was chosen because a STARK is algebra and a chain's consensus code must be deterministic, and Haskell enforces both in the type system. The cost is raw speed, which this section is honest about, along with how to close most of the gap.

### What Haskell gives this project

| Benefit | Where it shows up in the project |
| --- | --- |
| Determinism enforced by types | `verify` and `applyBlock` are pure, so the compiler guarantees they can't read the clock, network, or global state. Replaying the chain or switching forks is `foldM applyBlock genesis blocks`. |
| Code that reads like the math | Fields and polynomials are typeclass instances. A type-level modulus (`Fp p`) means elements of different fields can't be mixed by accident. |
| One constraint definition, three uses | AIR constraints are written once, generic over `Num`. At field elements they check a trace, on codewords they run the prover, and at the `Deg` type they compute degree bounds. The prover and verifier can't disagree about degrees, which is a real source of soundness bugs. |
| Shared prover and verifier transcript | Both sides run the same Fiat-Shamir code in a `State` monad, so challenge mismatches are hard to introduce. |
| Property-based testing | QuickCheck started in Haskell. Field laws, NTT round-trips, the FRI folding identity, and attacks like value overflow are tested as properties, not hand-picked cases. |
| Industry precedent | Cardano's node and the Plutus contract platform are written in Haskell, and Galois built its Cryptol cryptography language in Haskell. |

### Why Haskell over Rust for this project

The claim is that Haskell fits this project's goal (understanding the cryptography by building it from scratch), not that Haskell is better than Rust in general.

- **Less to manage that isn't cryptography.** Rust's ownership, borrowing, and lifetimes matter for production systems but have nothing to do with learning FRI.
- **Purity is guaranteed, not a convention.** Rust can perform side effects anywhere; Haskell's types prove the verifier has none.
- **More expressive abstractions.** Rust can do the `Num`-generic trick with traits, but with more ceremony, and it has no higher-kinded types, which makes the transcript monad clumsier.
- **Big integers built in.** `Integer` makes the 128-bit prime field trivial to start with.
- **A short path to Rust later.** Algebraic data types, typeclasses, and `Either` map closely onto Rust's enums, traits, and `Result`.

### What it costs in speed, and how to close the gap

The first version will prove much more slowly than an optimized Rust prover. The `Integer`-based 128-bit field is the main cause, not the language itself. Verification stays fast either way, because the verifier does only a small amount of work. Where the time goes and what fixes it:

| Fix | What it does | When |
| --- | --- | --- |
| Goldilocks field on `Word64` | Native 64-bit arithmetic instead of big integers; usually the largest single gain | Phase 9 |
| Unboxed mutable vectors in `ST` | The NTT and low-degree extension run in place, with no allocation per element | Phase 2, then Phase 9 |
| `INLINABLE` / `SPECIALIZE` pragmas and strict fields | Removes typeclass overhead and lazy thunks from hot loops | Phase 9 |
| `-fllvm` and `timesWord2#` | Better machine code, and 64×64 to 128-bit multiplies in one instruction | Phase 9 |
| Parallelism with `parallel` or `massiv` | Extends columns and hashes Merkle layers on every core | Phase 9 |
| Batch inversion | One field inverse for many values instead of one each | Phase 5 |
| Rust or C hot loops over FFI | NTT and field arithmetic run at native speed, while Haskell keeps the structure and the verifier | Stretch |

Hashing is already native: `crypton` implements Blake2b and SHA-256 in C. Measure before optimizing: `+RTS -s` and the profiler will show whether time is going to field multiplication, the NTT, or allocation.

With these fixes, Haskell can get reasonably close to straightforward Rust. It won't match the fastest Rust provers, which rely on SIMD and GPU work that GHC supports poorly, unless the hot loops move to Rust over FFI. The full-speed version is then a Haskell system with a native core, the same split many real systems use.

### The 30-second interview answer

> STARKs are mostly algebra, and consensus code has to be deterministic. Haskell enforces both: my verifier and state transition are pure by type, and the code reads like the math. I wrote the constraints once, generic over `Num`, and the same definition checks traces, drives the prover, and computes degree bounds, so the prover and verifier can't disagree. The trade-off is speed. I profiled it, moved to a 64-bit field, and parallelized the heavy steps. For a production prover I'd port the hot loops to Rust and keep the Haskell version as the reference.

## Architecture

Zerofier has three runtime parts (wallet, prover, node) sitting on a STARK library you build first. Only the wallet ever sees secrets. Nodes see a proof and a handful of public values, and they verify instead of re-executing anything.

```text
 Wallet (Phase 9)          Spend prover (Phase 7)          Node (Phase 8)
 keys: sk, address  --->   spend AIR (Rescue hashes) --->  mempool (STM)
 notes, Merkle paths       proves key/note/nullifier  tx   checks anchor, nf, proof
 builds the witness        balance + range checks          mines PoW blocks
                           emits ShieldedTx                state: tree, nullifiers
                                  ^ prove                        ^ verify
 +----------------------- STARK library (Phases 1-6) -------------------------+
 | Fields -> Poly/NTT -> Merkle/transcript -> FRI -> AIR + STARK -> Rescue     |
 |   P1        P2              P3              P4        P5           P6      |
 +-----------------------------------------------------------------------------+
```

A spend flows left to right across the top: the wallet assembles the witness, the prover turns it into a transaction with a STARK, and nodes check it and record it in a block. The library underneath is built bottom-up in Phases 1–6, and both the prover and the node depend on it. The module layout under Setup mirrors this picture.

## Setup

Install the toolchain once on openSUSE Tumbleweed, create one cabal project with a library, two executables, a test suite, and a benchmark suite, then turn on CI so every phase stays tested.

### Toolchain on openSUSE Tumbleweed

1. Install the system packages GHC needs:

```bash
sudo zypper refresh
sudo zypper install -y gcc gcc-c++ make curl git xz libffi-devel gmp-devel ncurses-devel pkgconf-pkg-config zlib-devel
```

2. Remove the distro's Haskell packages so they don't shadow GHCup's (optional, but it avoids "which ghc am I using?" confusion):

```bash
sudo zypper remove ghc-compiler cabal-install
```

3. Install GHCup (as your normal user, not root). Let it add itself to `~/.bashrc`, then pick the recommended versions:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
source ~/.bashrc
ghcup tui   # install and set the 'recommended' GHC, cabal and HLS
cabal update
```

4. Edit with VS Code (or any editor with LSP support) and the Haskell extension, set to use GHCup's HLS.
5. Keep the repo at `~/dev/zerofier`.

### Project skeleton

```text
zerofier/
  zerofier.cabal
  src/Zerofier/
    Field/Class.hs        -- Field typeclass
    Field/Prime128.hs     -- p = 1 + 407 * 2^119 (tutorial field)
    Field/Goldilocks.hs   -- p = 2^64 - 2^32 + 1
    Field/Ext2.hs         -- quadratic extension for soundness
    Poly.hs  NTT.hs
    Hash.hs  Merkle.hs  Transcript.hs
    FRI.hs
    AIR.hs
    Stark/Types.hs  Stark/Prover.hs  Stark/Verifier.hs
    Rescue.hs  Rescue/AIR.hs
    Shielded/Keys.hs  Shielded/Note.hs  Shielded/SpendAIR.hs  Shielded/Tx.hs
    Chain/Block.hs  Chain/State.hs  Chain/Validate.hs  Chain/PoW.hs  Chain/Mempool.hs
    Node.hs  Wire.hs
  app/node/Main.hs        -- zerofier-node
  app/wallet/Main.hs      -- zerofier-wallet
  test/                   -- one Spec module per src module
  bench/                  -- tasty-bench suites
  docs/                   -- design notes, write-up
```

The dependencies only point downward: fields, then polynomials, then hashing, then FRI, then the STARK, then the shielded layer, then the chain. Nothing below the chain knows about blocks.

### The cabal file

```cabal
cabal-version:   3.0
name:            zerofier
version:         0.1.0.0

common shared
  default-language:   GHC2021
  default-extensions: DataKinds DerivingStrategies OverloadedStrings
  ghc-options:        -Wall -O2
  build-depends:      base, bytestring, vector, containers, mtl

library
  import:          shared
  hs-source-dirs:  src
  build-depends:   crypton, memory, binary, stm, unordered-containers
  exposed-modules: Zerofier.Field.Class
                   -- add each module as you write it

executable zerofier-node
  import:         shared
  hs-source-dirs: app/node
  main-is:        Main.hs
  build-depends:  zerofier, network, async, optparse-applicative

executable zerofier-wallet
  import:         shared
  hs-source-dirs: app/wallet
  main-is:        Main.hs
  build-depends:  zerofier, optparse-applicative

test-suite spec
  import:         shared
  type:           exitcode-stdio-1.0
  hs-source-dirs: test
  main-is:        Main.hs
  build-depends:  zerofier, tasty, tasty-quickcheck, tasty-hunit, QuickCheck

benchmark bench
  import:         shared
  type:           exitcode-stdio-1.0
  hs-source-dirs: bench
  main-is:        Main.hs
  build-depends:  zerofier, tasty-bench
```

### Libraries and what each is for

| Package | Used for |
| --- | --- |
| `vector` | Unboxed arrays for evaluations and the NTT |
| `crypton`, `memory` | SHA-256, Blake2b, SHAKE-256, secure randomness |
| `mtl` | `State` for the Fiat-Shamir transcript, `ExceptT` for validation |
| `containers`, `unordered-containers` | Nullifier set, maps of chain state |
| `binary` | Serializing proofs, transactions, and blocks |
| `stm`, `async` | Concurrent mempool and node threads |
| `network` | TCP between local nodes |
| `optparse-applicative` | CLI parsing for the node and wallet |
| `tasty`, `QuickCheck`, `tasty-bench` | Tests, property tests, benchmarks |

### Habits that will save you

- Run `cabal build && cabal test` before every commit.
- Add a GitHub Actions workflow using `haskell-actions/setup` that runs the same commands on every push.
- Tag the end of each phase (`v0.1-fields`, `v0.2-ntt`, …) so you can always go back to a working state.
- Keep a `docs/notes.md` journal of what confused you. It becomes the write-up in Phase 9.

## Phase 1: Finite fields

**Goal:** a field typeclass with one main instance, the 128-bit prime p = 1 + 407 × 2^119 from *Anatomy of a STARK*, proven correct by property tests. Everything later is written against the typeclass, so changing fields is a one-line change.

**Read:** *Anatomy of a STARK*, Part 2 (Basic Tools), the finite field section.

### Build

Use a type-level modulus so the type carries the prime:

```haskell
newtype Fp (p :: Nat) = Fp Natural
  deriving stock (Eq, Ord)

instance KnownNat p => Num (Fp p)        -- (+), (*), negate, fromInteger (reduce mod p, handle negatives)
instance KnownNat p => Fractional (Fp p) -- recip via Fermat: a^(p-2), or extended Euclid

type F = Fp 270497897142230380135924736767050121217  -- 1 + 407 * 2^119
```

Then add a class for what a STARK needs beyond arithmetic:

```haskell
class (Eq a, Show a, Fractional a) => StarkField a where
  generator   :: a                    -- the tutorial's value; order 2^119 (not p - 1)
  twoAdicity  :: Int                  -- 119 for F: p - 1 = 407 * 2^119 (needs AllowAmbiguousTypes)
  rootOfUnity :: Int -> a             -- primitive 2^k-th root: generator ^ (2^(119-k))
  toBytes     :: a -> ByteString      -- canonical: 16 bytes, little-endian
  fromBytes   :: ByteString -> Maybe a  -- Nothing on wrong length or value >= p
```

Take the generator from the tutorial's code rather than computing one yourself. Note that it generates the order-2^119 subgroup, not the whole multiplicative group (3 does that); roots of unity and the FRI coset offset only need the 2-power subgroup. Turning hash output into a challenge is a separate function (reduce 32 bytes mod p) that belongs in Phase 3.

### Haskell skills

- Typeclasses and writing lawful `Num`/`Fractional` instances.
- `DataKinds`, `KnownNat`, and `natVal` (type-level naturals).
- `newtype` with `deriving stock` / `deriving newtype`.
- Writing `Arbitrary` instances for QuickCheck.

### Done when

- [x] Properties pass with 10,000 cases each: associativity, commutativity, distributivity, identities, `a * recip a == 1` for nonzero `a`, and `a ^ (p - 1) == 1`.
- [x] `rootOfUnity k ^ (2^k) == 1` and `rootOfUnity k ^ (2^(k-1)) /= 1` for several k.
- [x] `fromInteger (-1) == p - 1` and `fromBytes . toBytes == Just`.

### Pitfalls

- **Negative `fromInteger`:** use `mod`, not `rem`, so negative inputs reduce correctly.
- **`recip 0`:** decide now whether it errors or returns `Maybe`. Erroring is fine as long as tests never hit it by accident.
- **Weak generators:** make your `Arbitrary` instance produce 0, 1, and p − 1 often, since bugs hide at the edges.
- **Lazy folds:** use `foldl'` when summing many field elements, or thunks pile up.

### Stretch: Goldilocks (save for Phase 9)

The 128-bit field uses `Integer` arithmetic, which is simple but slow. Real provers use Goldilocks, p = 2^64 − 2^32 + 1, which fits in a `Word64`. It has a fast reduction because 2^64 ≡ 2^32 − 1 and 2^96 ≡ −1 (mod p), its generator is 7, and its two-adicity is 32. A 64-bit field is too small for random challenges on its own, so challenges come from the quadratic extension F\[X\]/(X² − 7) (7 is a non-residue). Inverse there is (a + bX)⁻¹ = (a − bX) / (a² − 7b²). Don't start here. Add it as a performance upgrade once the whole system works.

## Phase 2: Polynomials and the NTT

**Goal:** a polynomial type with arithmetic, division, interpolation, and a number-theoretic transform (an FFT over a finite field) for fast evaluation on power-of-two domains. A STARK is mostly polynomials moving between coefficient form and evaluation form, and this phase builds that.

**Read:** *Anatomy of a STARK*, Part 2 (the polynomial and multivariate sections) and Part 6 (NTT).

### Build

```haskell
newtype Poly f = Poly (Vector f)        -- coefficients, lowest degree first, no trailing zeros

degree      :: (Eq f, Num f) => Poly f -> Int        -- -1 for the zero polynomial
evaluate    :: Num f => Poly f -> f -> f              -- Horner's rule
instance (Eq f, Num f) => Num (Poly f)                -- add, subtract, multiply
polyDivMod  :: (Eq f, Fractional f) => Poly f -> Poly f -> (Poly f, Poly f)
interpolate :: (Eq f, Fractional f) => [(f, f)] -> Poly f   -- Lagrange
zerofier    :: (Eq f, Num f) => [f] -> Poly f              -- product of (x - d)
scalePoly   :: Num f => f -> Poly f -> Poly f              -- p(x) to p(c * x), for cosets

ntt  :: StarkField f => f -> Vector f -> Vector f   -- root of unity omega, length 2^k
intt :: StarkField f => f -> Vector f -> Vector f   -- inverse, includes the 1/n factor

evalOnCoset :: StarkField f => f -> Int -> Poly f -> Vector f  -- the low-degree extension
```

Write the NTT twice:

1. **Recursive and pure.** Split into even and odd coefficients, recurse with ω², then combine. It is short and obviously correct.
2. **Iterative in `ST`.** Bit-reversal permutation, then in-place butterflies on a mutable vector. This is the fast one.

Test that both always agree. The pure version is your reference implementation.

### Haskell skills

- `Data.Vector` and the boxed/unboxed distinction (`Natural` can't be unboxed, but `Word64` can later).
- The `ST` monad, `runST`, and `Data.Vector.Mutable` for safe local mutation.
- A `Num` instance for a non-number type, and smart constructors that normalize.

### Done when

- [ ] `intt w (ntt w v) == v` for random vectors of length 2^k.
- [ ] `ntt` matches `evaluate` at every domain point ω^i.
- [ ] Multiplying through the NTT matches schoolbook multiplication.
- [ ] For `(q, r) = polyDivMod a b`: `a == q * b + r` and `degree r < degree b`.
- [ ] `interpolate` then `evaluate` gives back the original points, and `zerofier ds` is zero on every `d`.

### Pitfalls

- **Wrong root order:** ω must be a primitive 2^k-th root for exactly that length. Use `rootOfUnity k`, never a hard-coded one.
- **Trailing zeros:** if `Poly` keeps them, `Eq` and `degree` give wrong answers. Normalize in every constructor.
- **Cosets:** to evaluate on {c · ω^i}, multiply coefficient i by c^i first, then run the NTT.
- **Forgetting 1/n** in the inverse transform.

## Phase 3: Hashing, Merkle trees, and the transcript

**Goal:** commit to a long vector of field elements with one 32-byte root, open any position with a short path, and turn an interactive protocol into a non-interactive one with a Fiat-Shamir transcript. These are the only cryptographic building blocks a STARK needs.

**Read:** *Anatomy of a STARK*, Part 2 (Merkle trees and the proof stream). The tutorial uses Blake2b for Merkle trees and SHAKE-256 for Fiat-Shamir. Copy that choice; `crypton` has both.

### Build

```haskell
newtype Digest = Digest ByteString                 -- 32 bytes, Blake2b-256

hashLeaf :: ByteString -> Digest                   -- H(0x00 || bytes)
hashNode :: Digest -> Digest -> Digest             -- H(0x01 || left || right)

data MerkleTree = MerkleTree (Vector (Vector Digest))  -- every layer, leaves first
commit     :: [ByteString] -> MerkleTree
root       :: MerkleTree -> Digest
openAt     :: Int -> MerkleTree -> [Digest]                    -- authentication path
verifyPath :: Digest -> Int -> ByteString -> [Digest] -> Bool
```

The transcript is a natural `State` monad. The prover and verifier run the same sequence of absorbs and squeezes, so they derive the same challenges:

```haskell
newtype Transcript = Transcript ByteString        -- running SHAKE-256 state or hash chain

absorb         :: ByteString -> State Transcript ()
squeezeField   :: StarkField f => State Transcript f
squeezeIndices :: Int -> Int -> State Transcript [Int]   -- n distinct indices below size
```

Wrap these in two monads: a prover monad that also records proof items, and a verifier monad (`StateT` over `Either VerifyError`) that reads proof items back and can fail.

### Haskell skills

- `State`, `StateT`, and `Either` from `mtl`, and why the prover and verifier share code.
- `ByteString` handling and the `crypton` hashing API (`hash`, `Digest Blake2b_256`, `SHAKE256`).
- Serialization with `binary`, so proof items have one canonical byte encoding.

### Done when

- [ ] For random trees of size 2^k, opening and verifying every index succeeds.
- [ ] Changing any byte of a leaf, path entry, index, or root makes verification fail.
- [ ] The same absorbs always produce the same challenges, and any change produces different ones.
- [ ] `squeezeIndices` returns distinct, in-range indices.

### Pitfalls

- **Leaf and node confusion:** without the 0x00/0x01 prefixes, an internal node can be passed off as a leaf.
- **Left/right order:** the low bit of the index at each level decides which side the sibling is on. Test odd and even indices.
- **Weak Fiat-Shamir:** absorb the public inputs and the statement *before* anything else. Leaving them out lets an attacker reuse or forge proofs. This class of bug is real and has hit production ZK libraries.
- **Non-canonical encodings:** if one field element can serialize two ways, hashes stop being binding.

## Phase 4: FRI

**Goal:** a prover and verifier for FRI, the protocol that convinces a verifier that a committed codeword is close to a low-degree polynomial while reading only a few dozen positions. FRI is the heart of a STARK and the hardest single phase, so plan the most time for it.

**Read:** *Anatomy of a STARK*, Part 3 (FRI). Read it twice, then work one round on paper with a degree-3 polynomial over a tiny field before writing code.

### The one idea to understand

Split any polynomial into even and odd parts, f(x) = fₑ(x²) + x · fₒ(x²). With a random challenge α, the next round's polynomial is fₑ + α · fₒ, with half the degree on a domain half the size. Each folded value comes from just two values of the previous codeword:

```latex
f_{i+1}(x^2) = \tfrac{1}{2}\left(1 + \tfrac{\alpha}{x}\right) f_i(x) + \tfrac{1}{2}\left(1 - \tfrac{\alpha}{x}\right) f_i(-x)
```

The verifier checks this with a colinearity test: the points (x, f(x)), (−x, f(−x)), and (α, fᵢ₊₁(x²)) must lie on one line. After the last round, the prover sends the small final codeword in the clear, and the verifier checks its degree directly.

### Build

```haskell
data FriParams f = FriParams
  { friOffset    :: f      -- coset offset (use the field generator)
  , friOmega     :: f      -- root of unity for the initial domain
  , friDomainLen :: Int
  , friExpansion :: Int    -- blowup factor = 1 / rate
  , friQueries   :: Int    -- number of colinearity tests
  }

fold      :: StarkField f => f -> f -> f -> Vector f -> Vector f   -- alpha, offset, omega
numRounds :: FriParams f -> Int
friProve  :: StarkField f => FriParams f -> Vector f -> ProverM f [Int]
friVerify :: StarkField f => FriParams f -> VerifierM f [(Int, f)]
```

`friProve` returns the top-layer indices it opened and `friVerify` returns the opened (index, value) pairs. The STARK in Phase 5 needs them to check that FRI was run on the right polynomial.

### Choosing parameters

The conjectured security rule is that each query adds log₂(expansion factor) bits. You also need a hash with at least 2λ output bits and a field with at least 2^λ elements, which your 128-bit field and Blake2b-256 satisfy.

| Expansion factor | Bits per query | Queries for \~128 bits (conjectured) |
| --- | --- | --- |
| 4 | 2 | 64 |
| 8 | 3 | 43 |
| 16 | 4 | 32 |

While developing, use small parameters (expansion 4, 8 queries) so tests run fast, and keep the real ones in one config value.

### Haskell skills

- Monadic loops: `forM`, `replicateM`, `foldM`, and `zipWithM_` across rounds.
- Keeping the prover and verifier structurally symmetric, so one reads like the other in reverse.
- Records, `Vector` slicing, and squaring the domain each round with `iterate`.

### Done when

- [ ] Property: folding the evaluations of p equals evaluating pₑ + α · pₒ on the squared domain.
- [ ] Honest codewords of several sizes are accepted.
- [ ] Random codewords are rejected, and so are codewords of degree just above the bound.
- [ ] A tampered final codeword, Merkle path, or root is rejected.

### Pitfalls

- **Skipping the final degree check:** without it, FRI proves nothing.
- **Domain drift:** square both the offset and ω each round. Index i in one round becomes i mod (half the length) in the next.
- **Wrong domain:** evaluate on a coset (offset = generator), not the subgroup itself. Phase 5 divides by polynomials that vanish on the subgroup, and those divisions break if the two domains overlap.

## Phase 5: AIR and the STARK

**Goal:** a general STARK prover and verifier for any computation written as an AIR (an execution trace plus polynomial constraints), with zero-knowledge randomizers. The first proofs are for a Fibonacci-style sequence. By the end you can prove "I ran this computation correctly" for any AIR you define.

**Read:** *Anatomy of a STARK*, Parts 1 and 4. Part 4 already includes zero-knowledge, so build it in from the start.

### How an AIR works

- **Trace:** a table with T rows (cycles) and w columns (registers), one row per step of the computation.
- **Transition constraints:** polynomials in the current row and the next row that equal zero on every valid step.
- **Boundary constraints:** (cycle, register, value) triples, such as the input in row 0 and the claimed output in the last row.

The prover turns each column into a polynomial, shows that each constraint divided by its zerofier is still a polynomial, and uses FRI to prove the result has low degree.

### The Haskell trick that makes this clean

Write constraints once as a function that works for *any* `Num` type, then run it at three types:

```haskell
{-# LANGUAGE RankNTypes #-}

data AIR f = AIR
  { airWidth       :: Int
  , airTraceLen    :: Int
  , airTransitions :: forall a. Num a => Vector a -> Vector a -> Vector a -> [a]
      -- periodic columns (round constants), current row, next row
  , airBoundary    :: [(Int, Int, f)]          -- (cycle, register, value)
  }

newtype Deg = Deg Int
instance Num Deg where
  Deg a + Deg b = Deg (max a b)
  Deg a * Deg b = Deg (a + b)
  fromInteger _ = Deg 0
  -- (-) is max like (+); negate and abs leave the degree unchanged
```

- At `a = f`, it checks that a concrete trace is valid. This is your test oracle.
- At `a = f` over the low-degree extension, the prover evaluates constraints point by point on codewords. This is faster than composing polynomials symbolically.
- At `a = Deg`, it computes each constraint's degree automatically, so degree bounds are never worked out by hand.

This is a good example of what Haskell does well, and it is worth a paragraph in your write-up.

### Build

```haskell
prove  :: StarkField f => StarkParams -> AIR f -> Trace f -> IO (Proof f)   -- IO only for randomness
verify :: StarkField f => StarkParams -> AIR f -> Proof f -> Either VerifyError ()
```

Prover steps, following the tutorial:

1. Run the computation to get the trace, then append random rows for zero-knowledge (the tutorial uses 4 × the number of queries).
2. Interpolate each column over the trace domain and extend it onto the larger FRI coset.
3. Compute the boundary quotients, commit them with Merkle trees, and absorb the roots.
4. Evaluate the transition constraints on the extended domain and divide by the transition zerofier, which vanishes on every row except the last.
5. Commit a random randomizer polynomial.
6. Squeeze weights, then degree-adjust and randomly combine all quotients with the randomizer.
7. Run FRI on the combined codeword.
8. At each FRI query index, open the quotient leaves at that point and at the "next row" point, plus the randomizer.

The verifier replays the transcript, rebuilds trace values from the quotient openings, re-evaluates the constraints, recombines with the same weights, and checks the result against FRI's opened values.

### Statements to prove

1. **Fibonacci:** two registers, transition (a, b) to (b, a + b), boundary at row 0 and the claimed output at the last row.
2. **Cube chain:** one register, xᵢ₊₁ = xᵢ³ + c. This is a degree-3 warm-up for Rescue-Prime in Phase 6.

### Haskell skills

- `RankNTypes` and records of polymorphic functions.
- Several `Num` instances giving one definition several meanings.
- A custom `VerifyError` type that says *which* check failed, which makes debugging much easier.

### Done when

- [ ] Honest proofs for both statements verify at several trace lengths.
- [ ] A wrong claimed output is rejected.
- [ ] A "cheating prover" test that corrupts one trace cell and proves anyway is rejected by the verifier.
- [ ] Proofs serialize and deserialize with `binary`, and you log proof size and proving time.

### Pitfalls

- **Transition zerofier over every row:** the last row has no "next" row, so it must be excluded.
- **Next-row offset:** in the extended codeword, the next row is `expansion` positions later, not 1.
- **Boundary rows after randomizing:** random rows are appended at the end, so the claimed-output row index must still point at the real last step.
- **Slow symbolic composition:** if proving takes minutes, you are composing polynomials instead of evaluating on codewords.

## Phase 6: Rescue-Prime and a post-quantum signature

**Goal:** implement the Rescue-Prime hash, write its AIR, and use your STARK to build a signature scheme with no elliptic curves. This is the bridge to privacy: proving "I know the preimage of this hash" is exactly how Zerofier authorizes a spend in Phase 7.

**Read:** *Anatomy of a STARK*, Part 5 (A Rescue-Prime STARK), then skim the Rescue-Prime paper for why the design is safe.

### Why a new hash

Blake2b costs thousands of constraints per call inside a STARK, because it is built from bit operations. Rescue-Prime is built from field operations (x³, its inverse, and a small matrix mix), so it is cheap to prove. Keep Blake2b for Merkle commitments *outside* the proof, and use Rescue-Prime for anything proven *inside* it.

The tutorial's parameters for your field: state width m = 2 (rate 1, capacity 1), N = 27 rounds, and α = 3.

### Build

```haskell
data RescueParams f = RescueParams
  { rpWidth, rpRounds :: Int
  , rpAlpha, rpAlphaInv :: Integer
  , rpMds, rpMdsInv :: [[f]]
  , rpRoundConstants :: [f]        -- 2 * m per round
  }

rescuePermute :: StarkField f => RescueParams f -> [f] -> [f]
rescueHash    :: StarkField f => RescueParams f -> [f] -> f     -- sponge, absorbs one element per permutation
rescueTrace   :: StarkField f => RescueParams f -> f -> Trace f
rescueAIR     :: StarkField f => RescueParams f -> f -> AIR f   -- public output as the boundary

newtype SecretKey f = SecretKey f
newtype PublicKey f = PublicKey f                     -- pk = rescueHash [sk]
keygen    :: IO (SecretKey F, PublicKey F)
sign      :: SecretKey F -> ByteString -> IO (Proof F)
verifySig :: PublicKey F -> ByteString -> Proof F -> Bool
```

The signature is a STARK proving knowledge of `sk` with `rescueHash [sk] == pk`. The message is absorbed into the transcript first, so the proof is bound to it.

### The AIR trick for the inverse S-box

x^(1/α) has huge degree, so you can't constrain it directly. Instead, each round's constraint runs the first half-round *forward* from the current row and the second half-round *backward* from the next row, and checks that they meet in the middle. Both sides have degree 3. Round constants differ per round, so supply them as periodic columns, which is why `airTransitions` takes that first argument.

### Zero-knowledge check

This is the first statement with a secret, so audit what a proof reveals:

- Every opened trace value should be masked by randomizer rows. There must be more random rows than opened positions, which is why the tutorial uses 4 × queries.
- Only the first state element is public. The tutorial notes that revealing the second one at the end would let anyone invert the permutation and recover `sk`.
- The tutorial omits Merkle leaf salts because the field is large. Write down that choice and why in your notes.

### Haskell skills

- Matrix and vector operations on lists, and modular exponentiation with large `Integer` exponents.
- Secure randomness from `crypton` (`getRandomBytes`), kept in `IO` and out of pure code.
- Generating test vectors from a reference implementation.

### Done when

- [ ] `rescueHash` matches test vectors generated by running the tutorial's Python code.
- [ ] The Rescue AIR accepts honest traces and rejects any corrupted cell.
- [ ] `sign` then `verifySig` succeeds, a signature on one message fails on another, and a wrong public key fails.
- [ ] You log signature size and signing time. Expect a large signature, which is normal for a STARK.

### Pitfalls

- **Forward/backward mix-up:** the MDS and inverse-MDS matrices and the S-box directions are easy to swap. Test each half-round separately.
- **Round-constant indexing:** each round uses 2m constants, half before the meet-in-the-middle point and half after.
- **Message not bound:** if the message is absorbed after any commitment, signatures can be replayed onto other messages.

## Phase 7: Shielded transactions

**Goal:** a Zcash-style private transfer built only from Rescue-Prime and your STARK. A transaction spends one hidden note and creates two hidden notes (payment and change). It reveals only a nullifier, two new commitments, a tree root, and the fee. The proof itself authorizes the spend, so no signature is needed.

**Read:** the Zcash protocol specification's sections on notes, note commitments, and nullifiers, to see the design you are simplifying. Skip the elliptic-curve parts. They are exactly what Zerofier replaces.

### The design

H is the Rescue-Prime sponge, and every use starts with a distinct domain tag so outputs from different roles can never collide.

| Object | Definition | Who knows it |
| --- | --- | --- |
| Spending key `sk` | Random field element | Owner only |
| Address `a` | H(ADDR, sk) | Anyone the owner gives it to |
| Note | (value v, address a, randomness r) | Sender and receiver |
| Note commitment `cm` | H(NOTE, v, a, r) | Public, as a leaf in the commitment tree |
| Commitment tree | Append-only Merkle tree of `cm`, nodes H(NODE, left, right) | Public |
| Nullifier `nf` | H(NF, sk, cm, position) | Public when spent; only the owner can compute it |

Spending reveals `nf`, never `cm`, so nobody can link a spend to the note it consumed. Each note has exactly one nullifier, so the chain rejects a second spend.

### What the spend proof proves

Public inputs: tree root (anchor), `nf`, `cm_out1`, `cm_out2`, fee. Private witness: `sk`, the input note, its position and Merkle path, and both output notes.

1. aᵢₙ = H(ADDR, sk), so you own the input note.
2. cmᵢₙ = H(NOTE, vᵢₙ, aᵢₙ, rᵢₙ).
3. The Merkle path from cmᵢₙ at its position hashes to the anchor, so the note exists.
4. nf = H(NF, sk, cmᵢₙ, position), so the nullifier is the correct one.
5. Each output commitment opens to its (v, a, r).
6. vᵢₙ = v₁ + v₂ + fee, so no value is created.
7. Every value is below 2^32, checked by bit decomposition.

All public inputs are absorbed into the transcript first, as with the signature in Phase 6. That binds the outputs and fee to the proof, so nobody can redirect the payment after it is made.

### Building the spend AIR

The trace is a sequence of Rescue permutations, 28 rows each, joined by wiring constraints. A periodic selector column marks where each permutation starts. Wiring constraints feed one hash's output into the next one's input. At each Merkle level a path bit b (constrained by b(b − 1) = 0) swaps left and right: left' = cur + b(sib − cur), right' = sib + b(cur − sib).

With the rate-1 sponge, depth 16 needs about 65 permutations, or roughly 1,800 rows padded to 2,048. Build it in three steps and finish each step's tests first:

1. **Membership only:** prove a public leaf is in a tree with a public root.
2. **Ownership:** hide the leaf, and add key derivation and the nullifier.
3. **Value:** add outputs, balance, and range checks.

Start at depth 4 for fast tests, and raise it to 16 once everything passes.

### Build

```haskell
newtype Value = Value Word32                     -- smart constructor: can't exceed 2^32 - 1
data Note = Note { noteValue :: Value, noteAddr :: F, noteRand :: F }

data IncTree = IncTree { itSize :: Int, itFrontier :: [Maybe F] }  -- incremental Merkle tree
appendLeaf :: F -> IncTree -> IncTree
treeRoot   :: IncTree -> F

data SpendWitness = SpendWitness { swKey :: SecretKey F, swNote :: Note, swPos :: Int
                                 , swPath :: [F], swOutputs :: (Note, Note) }
data ShieldedTx = ShieldedTx { txAnchor :: F, txNullifier :: F, txOutputs :: (F, F)
                             , txFee :: Value, txProof :: Proof F }

spendAIR    :: ShieldedTx -> AIR F                  -- public inputs come from the tx
proveSpend  :: SpendWitness -> F -> Value -> IO ShieldedTx   -- witness, anchor, fee
verifySpend :: ShieldedTx -> Either VerifyError ()
```

In v1, the wallet hands the receiver a note file (v, a, r, position) out of band. Encrypting it on-chain is a stretch goal (see Security notes).

### Haskell skills

- Algebraic data types and smart constructors that make invalid values unrepresentable.
- Persistent data structures: the incremental tree keeps every old root for free.
- Building an AIR from small combinators (`hashSegment`, `swapByBit`, `rangeCheck`) instead of one giant function.

### Done when

- [ ] An honest spend verifies, and the receiver can spend their output in a second transaction.
- [ ] Spending a note that is not in the tree fails.
- [ ] Spending with the wrong `sk` fails.
- [ ] Outputs worth more than the input fail.
- [ ] An overflow attack fails: an output of p − 5 that wraps around to look balanced.
- [ ] Changing any public field after proving fails.

### Pitfalls

- **Missing range checks:** the classic inflation bug. Field arithmetic wraps, so without range checks someone can mint coins.
- **Nullifier without position:** if two notes share a commitment, they share a nullifier and one becomes unspendable. Including the position prevents this.
- **Missing domain tags:** without them, an address could be passed off as a commitment or a tree node.
- **Proving against the newest root only:** the tree grows while the proof is generated, so the chain must accept recent roots too (Phase 8).

## Phase 8: The chain

**Goal:** wrap shielded transactions in a small proof-of-work chain. It needs blocks, a pure state-transition function, a mempool, and a few nodes on your machine that gossip blocks and agree on the tip. Most of the hard thinking is done by now, so this phase is mostly Haskell engineering.

### Data model

```haskell
data BlockHeader = BlockHeader
  { bhHeight :: Int, bhPrev :: Digest, bhTime :: Word64
  , bhTxRoot :: Digest            -- Blake2b Merkle root of transaction ids
  , bhNoteRoot :: F               -- commitment-tree root after this block
  , bhTarget :: Natural, bhNonce :: Word64 }

data Coinbase = Coinbase { cbNote :: Note }    -- reward + fees, opened publicly in v1
data Block = Block { blkHeader :: BlockHeader, blkCoinbase :: Coinbase, blkTxs :: [ShieldedTx] }

data ChainState = ChainState
  { csTree        :: IncTree
  , csRecentRoots :: Seq F          -- last K roots that proofs may use as anchors
  , csNullifiers  :: HashSet F
  , csTip         :: Digest
  , csHeight      :: Int }

validateTx :: ChainState -> ShieldedTx -> Either TxError ()
applyBlock :: ChainState -> Block -> Either BlockError ChainState   -- pure
```

Because `applyBlock` is pure, the whole chain state is `foldM applyBlock genesis blocks`. Replaying from disk, checking a fork, and testing are all that one line.

### Validation rules

A transaction is valid when:

- Its anchor is one of the last K roots.
- Its nullifier is not already in the set.
- Its STARK verifies.

A block is valid when:

- Its header hash is below the target, `bhPrev` is the tip, and its height is one more than the tip's.
- Every transaction is valid and no nullifier repeats within the block.
- The coinbase value is at most the block reward plus fees.
- `bhTxRoot` matches, and `bhNoteRoot` matches the tree after appending all output commitments in order.

### Proof of work

Hash the serialized header with Blake2b-256 and look for a nonce that puts it below the target. Use a fixed target in v1, then add retargeting every N blocks as a stretch goal. Grover's algorithm gives quantum miners a quadratic speedup, which is an advantage, not a break, and signature-free PoW has nothing for Shor to attack.

### The node

```haskell
data Node = Node
  { nState   :: TVar ChainState
  , nMempool :: TVar (Map F ShieldedTx)     -- keyed by nullifier, so conflicts are obvious
  , nPeers   :: TVar [Peer] }
```

- Run threads for the miner, a TCP listener, and peer handlers with `async`.
- Use length-prefixed `binary` messages: `Hello`, `NewTx`, `NewBlock`, and `GetBlocks fromHeight`.
- Fork choice: in v1, accept only blocks that extend the tip. In v2, keep competing branches and switch to the one with the most work by replaying from genesis.
- Persist blocks to an append-only file and replay it on startup.

### Haskell skills

- `STM`: `TVar`, `atomically`, and `retry`.
- `async`: `concurrently`, `race`, and `withAsync`.
- `ExceptT` for layered validation errors.
- Parallel proof verification with `Control.Parallel.Strategies` and `deepseq` (add both packages).
- Avoiding space leaks in long-running processes: strict fields and `StrictData`.

### Done when

- [ ] Three nodes on different ports mine and converge on the same tip.
- [ ] A transaction sent to one node lands in a block on all three.
- [ ] A double spend is rejected by the mempool and by block validation.
- [ ] A block with a tampered transaction, header, or root is rejected.
- [ ] A restarted node replays its file to the identical state.

### Pitfalls

- **Expensive work inside `atomically`:** STM transactions can retry, so verify proofs *before* entering the transaction, then do a cheap check-and-insert inside it.
- **Duplicate nullifiers within one block:** checking only against the old state misses them.
- **Anchor window too small:** honest transactions proven a few blocks ago start failing.
- **Memory creeping up over hours:** usually lazy fields in `ChainState`. Profile with `+RTS -s` and `-hT`.

## Phase 9: Wallet, demo, performance, and write-up

**Goal:** make Zerofier usable and explainable. That means a wallet CLI, a scripted three-person demo, benchmarks, one or two performance upgrades, and a README that someone else can follow.

### Wallet CLI

```text
zerofier-wallet new-key                       # writes sk and address to ~/.zerofier/wallet
zerofier-wallet address
zerofier-wallet import-note <file>            # receive a note handed over out of band
zerofier-wallet balance
zerofier-wallet send --to <addr> --amount 25 --fee 1 --node localhost:9001
                                              # proves the spend, submits it, writes the receiver's note file
```

The wallet needs the current Merkle path for each note. In v1, it asks the node for the path at spend time. That tells the node which note is being spent, so list it as a known privacy leak.

### The demo

Script it end to end, so one command shows the whole system working:

1. Start three nodes. Alice's node mines a few blocks and earns coinbase notes.
2. Alice sends 25 to Bob. Bob imports the note file and checks his balance.
3. Bob sends 10 to Carol.
4. Print what the chain shows: nullifiers, commitments, and fees, with no addresses or amounts.
5. Have Alice replay a spent note. Every node rejects it.

### Benchmarks

Measure with `tasty-bench` and record the numbers in the README:

- Field multiply and inverse.
- NTT at 2^10, 2^12, 2^14, and 2^16.
- Merkle commit for 2^16 leaves.
- FRI prove and verify.
- Spend proof: prove time, verify time, and proof size.

### Performance upgrades (pick one or two)

| Upgrade | What it buys | Difficulty |
| --- | --- | --- |
| Goldilocks field + quadratic extension | Native 64-bit arithmetic, unboxed vectors, likely the biggest speedup | Medium |
| Parallel low-degree extension | Uses every core through `parMap` over columns | Easy |
| Width-3 Rescue-Prime (2-to-1 hashing) | About a third of the Merkle-path permutations | Medium (generate new parameters with the reference script) |
| DEEP-ALI out-of-domain sampling | Better soundness per query, as in ethSTARK | Hard |
| Batched Merkle openings | Smaller proofs, since shared path nodes are sent once | Easy |
| Grinding (proof of work on the transcript) | Fewer FRI queries for the same security | Easy |

### Write-up

Your README should cover:

- What Zerofier is, in two sentences, plus the architecture diagram.
- How to build and run the demo.
- A design section: the threat model, what the spend proof proves, and why nothing depends on curves.
- The Haskell section: the polymorphic-constraint trick, the pure `applyBlock` fold, and the shared prover/verifier transcript.
- The benchmark table.
- Limitations, honestly stated (see Security notes).
- What you would do next.

Once it's done, a resume line could read: "Built Zerofier, a post-quantum private payment chain in Haskell with a from-scratch STARK prover (FRI, AIR, Rescue-Prime), shielded transactions, and proof-of-work consensus."

## Timeline

The plan runs 30 weeks, from Oct 12, 2026 to May 9, 2027. It assumes about 6–8 hours a week during the semester and more over winter break, so the whole project wraps before graduation.

| Phase / milestone | Dates |
| --- | --- |
| 1 · Setup and fields | Oct 12 – Oct 25, 2026 |
| 2 · Polynomials, NTT | Oct 26 – Nov 8 |
| 3 · Merkle, transcript | Nov 9 – Nov 22 |
| 4 · FRI | Nov 23, 2026 – Jan 3, 2027 |
| 5 · AIR and STARK | Jan 4 – Jan 31 |
| Milestone: first STARK proof verifies | Jan 31 |
| 6 · Rescue, signature | Feb 1 – Feb 28 |
| Milestone: signature verifies | Feb 28 |
| 7 · Shielded txs | Mar 1 – Apr 4 |
| 8 · Chain and nodes | Apr 5 – Apr 25 |
| 9 · Wallet, demo, write-up | Apr 26 – May 9 |
| Milestone: demo and write-up done | May 9, 2027 |

FRI gets the longest block because it is the hardest phase and it overlaps finals. Winter break is set aside for the STARK itself, since it needs long uninterrupted sessions.

If you fall behind, cut in this order and keep the core (Phases 4, 5, and 7) intact:

1. Phase 9 performance upgrades.
2. Fork handling in Phase 8: accept only blocks that extend the tip.
3. Real networking: run three nodes in one process connected by STM channels instead of TCP.
4. Tree depth: ship the spend proof at depth 8 instead of 16.

A weekly rhythm that works: one reading session, two build sessions, and `cabal test` before every commit.

## Security notes and honest limitations

Zerofier is a learning project, not a secure system. Put this list in the README so nobody mistakes it for one, and treat each item as a possible upgrade.

| Limitation | Why it matters | Upgrade path |
| --- | --- | --- |
| No audit, no formal analysis | Bugs in a proof system are soundness bugs: fake proofs, minted coins | Don't hold value; invite review once it works |
| Rescue-Prime with capacity 1 | A 128-bit capacity gives roughly 64-bit collision resistance, well below the rest of the system | Width-3 or wider parameters with more capacity |
| FRI query counts are conjectured | The "bits per query" rule is a conjecture; proven bounds need more queries | Use the proven-bound formulas from the ethSTARK documentation |
| Tutorial-level zero-knowledge | Randomizers without salted leaves, and no formal ZK analysis | Salted Merkle leaves, and follow ethSTARK's ZK treatment |
| Not constant-time | Haskell's `Integer` arithmetic and GC timing can leak secrets through side channels | Acceptable for a toy; real systems use constant-time native code |
| Notes delivered out of band | Receivers can't find payments on-chain | Encrypt notes with ML-KEM (FIPS 203) plus ChaCha20-Poly1305 from `crypton`. Implementing ML-KEM reuses your NTT skills (q = 3329) |
| Wallet asks the node for Merkle paths | The node learns which note is being spent | The wallet tracks its own paths as blocks arrive |
| Coinbase notes are public | Miner addresses and rewards are visible | Prove the coinbase commitment instead of opening it |
| Network metadata | IP addresses and timing can link transactions | Out of scope; real systems use Tor or Dandelion-style relaying |
| Three-node proof of work | Anyone can out-mine it | Fine for a demo |

Two rules apply no matter what:

- Generate keys and randomness with `crypton`'s system RNG, never `System.Random`.
- Never reuse a blinding factor `r` across notes.

## Reading list and glossary

### Reading list, in the order you'll need it

| Resource | Use it for | Phase |
| --- | --- | --- |
| [Anatomy of a STARK](https://aszepieniec.github.io/stark-anatomy/) (Szepieniec), Parts [1](https://aszepieniec.github.io/stark-anatomy/overview) and [2](https://aszepieniec.github.io/stark-anatomy/basic-tools) | The overview, fields, polynomials, Merkle trees, and the proof stream | 1–3 |
| [STARK 101](https://starkware.co/stark-101/) (StarkWare) | A shorter second explanation in Python notebooks, good when something doesn't click | 1–5 |
| [Anatomy of a STARK, Part 3: FRI](https://aszepieniec.github.io/stark-anatomy/fri) | Folding, colinearity tests, parameters | 4 |
| [Fast Reed-Solomon Interactive Oracle Proofs of Proximity](https://eccc.weizmann.ac.il/report/2017/134/) (Ben-Sasson, Bentov, Horesh, Riabzev) | The original FRI paper; read the intro, skim the rest | 4 |
| [Anatomy of a STARK, Part 4: The STARK Polynomial IOP](https://aszepieniec.github.io/stark-anatomy/stark) | AIR, zerofiers, quotients, randomizers | 5 |
| [ethSTARK Documentation](https://eprint.iacr.org/2021/582) (Ben-Sasson) | Real-world parameters, DEEP-ALI, proven security bounds | 5, 9 |
| [Anatomy of a STARK, Part 5: A Rescue-Prime STARK](https://aszepieniec.github.io/stark-anatomy/rescue-prime) | The Rescue AIR and the STARK signature | 6 |
| [Rescue-Prime: a Standard Specification (SoK)](https://eprint.iacr.org/2020/1143) (Szepieniec, Ashur, Dhooghe) | Hash design and parameter generation | 6, 9 |
| [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf), sections 3.2, 3.8, 3.9 | Notes, commitments, nullifiers, commitment trees, nullifier sets | 7 |
| [Anatomy of a STARK, Part 6: Speeding Things Up](https://aszepieniec.github.io/stark-anatomy/faster) | NTT-based arithmetic and prover speedups | 2, 9 |
| [Parallel and Concurrent Programming in Haskell](https://simonmar.github.io/pages/pcph.html) (Marlow) | `STM`, `async`, parallel strategies | 8, 9 |
| [FIPS 203: ML-KEM](https://csrc.nist.gov/pubs/fips/203/final) (NIST, Aug 2024) | Post-quantum note encryption stretch goal | Stretch |
| [GHCup](https://www.haskell.org/ghcup/) | Toolchain install | Setup |

### Glossary

| Term | Meaning |
| --- | --- |
| AIR | Algebraic Intermediate Representation: a computation written as an execution trace plus polynomial constraints between consecutive rows |
| Anchor | The commitment-tree root a spend proof is made against |
| Blowup / expansion factor | How much larger the evaluation domain is than the polynomial's degree; the inverse of the code rate |
| Codeword | A polynomial's values over a whole evaluation domain |
| Coset | A shifted subgroup {c · ω^i}, used so the FRI domain never overlaps the trace domain |
| Fiat-Shamir | Replacing the verifier's random challenges with hashes of the transcript, making a proof non-interactive |
| FRI | Fast Reed-Solomon IOP of Proximity: proves a codeword is close to a low-degree polynomial |
| LDE | Low-degree extension: evaluating a trace polynomial on a domain larger than the trace |
| Note | A hidden coin: (value, owner address, randomness) |
| Note commitment | A hash of a note, published on-chain as a tree leaf |
| Nullifier | A value derived from a note and its owner's key, published when the note is spent, so double spends are visible without revealing which note was spent |
| NTT | Number-theoretic transform: an FFT over a finite field |
| Periodic column | A public column, such as round constants, that repeats with a fixed pattern in the trace |
| Randomizer | Random trace rows and a random polynomial added so openings reveal nothing about the witness |
| Rescue-Prime | A hash function built from field operations, so it is cheap to prove inside a STARK |
| STARK | Scalable Transparent ARgument of Knowledge: a proof system using only hashes, with no trusted setup and conjectured post-quantum security |
| Zerofier | A polynomial that vanishes on a chosen set of points; dividing by it proves a constraint holds on those points |
