# Zerofier

A small, post-quantum, private blockchain written in pure Haskell. Every transfer is shielded and proven with a STARK built from scratch. Nothing in the system uses elliptic curves, pairings, or factoring; it relies only on hash functions and finite-field arithmetic.

The name comes from the **zerofier**, the STARK polynomial that vanishes exactly where every constraint holds. When this file says "Zerofier" (capitalized), it means the project; "zerofier" (lowercase) means the polynomial.

The full phase-by-phase plan lives in `docs/BUILD_GUIDE.md`. **Before helping with any phase, read that phase's section** (Goal, Build, Done when, Pitfalls).

This is a learning project: correctness and clarity matter more than speed. When reviewing, rank issues by severity: soundness bugs (an accepted false proof, minted coins, a broken Fiat-Shamir binding) first, then correctness, then Haskell style. Say so when unsure about a parameter or a security claim.

---

## Environment and commands

- GHC 9.10.3 and cabal 3.16.1.0 via GHCup, plus HLS. CI (`.github/workflows/ci.yml`) pins the same versions.

```bash
cabal build                                    # build everything
cabal test --test-show-details=direct          # all tests
cabal test --test-options='-p "/FRI/"'         # tests matching a tasty pattern
cabal bench                                    # tasty-bench suites
cabal run zerofier-node -- --port 9001         # a node (Phase 8+)
cabal run zerofier-wallet -- balance           # the wallet (Phase 9)
```

Run `cabal build && cabal test` before every commit. Tag the end of each phase: `v0.1-fields`, `v0.2-ntt`, and so on.

## Architecture

```text
 Wallet (P9) --witness--> Spend prover (P7) --tx--> Node (P8)
                               ^ prove                ^ verify
 STARK library: Fields(P1) -> Poly/NTT(P2) -> Merkle/Transcript(P3)
                -> FRI(P4) -> AIR + STARK(P5) -> Rescue-Prime(P6)
```

Dependencies only point downward. Nothing below `Chain/` knows about blocks.

```text
src/Zerofier/
  Field/Class.hs  Field/Prime128.hs  (later: Field/Goldilocks.hs  Field/Ext2.hs)
  Poly.hs  NTT.hs
  Hash.hs  Merkle.hs  Transcript.hs
  FRI.hs
  AIR.hs  Stark/Types.hs  Stark/Prover.hs  Stark/Verifier.hs
  Rescue.hs  Rescue/AIR.hs
  Shielded/Keys.hs  Shielded/Note.hs  Shielded/SpendAIR.hs  Shielded/Tx.hs
  Chain/Block.hs  Chain/State.hs  Chain/Validate.hs  Chain/PoW.hs  Chain/Mempool.hs
  Node.hs  Wire.hs
app/node/Main.hs  app/wallet/Main.hs  test/  bench/  docs/
```

## Design decisions (settled; don't change without asking)

**Field**
- `newtype Fp (p :: Nat) = Fp Natural` with `KnownNat`, plus `Num` and `Fractional` instances.
- Main field: `F = Fp 270497897142230380135924736767050121217`, which is p = 1 + 407·2^119, the field from *Anatomy of a STARK*.
- `generator` is the tutorial's 85408008396924667383611388730472331217. Its order is **2^119, not p − 1** (3 generates the whole group). `rootOfUnity k = generator^(2^(119−k))`, and it is also the FRI coset offset.
- `class StarkField` adds `generator`, `twoAdicity` (119), `rootOfUnity k`, `toBytes`, and `fromBytes`.
- Encoding: 16 bytes, little-endian. `fromBytes :: ByteString -> Maybe a` rejects the wrong length and values ≥ p (never reduces). Hash-to-field sampling is separate: reduce 32 bytes mod p (Phase 3).
- `recip 0` is an `error`. Inverse is by Fermat; batch inversion comes in Phase 5.
- Goldilocks (2^64 − 2^32 + 1) plus the quadratic extension X² − 7 is a **Phase 9 performance upgrade only**.

**Polynomials**
- `Poly f` stores coefficients lowest-degree first and is always normalized (no trailing zeros).
- The NTT has two versions: a pure recursive reference and an in-place version in `ST`. A test checks they agree.

**Hashing and the transcript**
- Merkle trees use Blake2b-256, with leaves hashed as H(0x00‖leaf) and nodes as H(0x01‖l‖r).
- Fiat-Shamir uses SHAKE-256 in a `State Transcript` monad that the prover and verifier share.
- **The public inputs and statement are absorbed before anything else.**

**FRI**
- Runs on a coset whose offset is the field generator.
- Development parameters: expansion 4 with 8 queries. Real parameters follow the conjectured rule of log₂(expansion) bits per query (for example, expansion 8 with 43 queries ≈ 128 bits).
- The verifier must check the final codeword's degree.

**AIR and STARK**
- Constraints are written once: `forall a. Num a => periodic -> cur -> next -> [a]`. They run at `f` (trace check), on codewords (prover), and at `Deg` (automatic degree bounds).
- The prover structure follows *Anatomy of a STARK*, Part 4, including zero-knowledge: random trace rows (4 × the number of queries) plus a randomizer polynomial.
- The transition zerofier excludes the last row.

**Rescue-Prime**
- State width m = 2 (rate 1, capacity 1), N = 27 rounds, α = 3, with parameters from *Anatomy*, Part 5.
- Used inside proofs only; Blake2b stays outside.
- Test vectors come from running the tutorial's Python code.

**Shielded transactions**
- H is a Rescue sponge, and every use starts with a domain tag:
  - address `a = H(ADDR, sk)`
  - note commitment `cm = H(NOTE, v, a, r)`
  - nullifier `nf = H(NF, sk, cm, position)`
  - tree node `H(NODE, l, r)`
- Each transaction spends 1 input and creates 2 outputs, plus a fee.
- Public inputs: anchor, nf, cm_out1, cm_out2, fee. The proof authorizes the spend, so there are no signatures.
- Values are `Word32` and range-checked inside the AIR, which prevents field-wraparound inflation.
- The spend AIR is a chain of 28-row Rescue permutations, wired with selector and periodic columns. Build it in order: membership, then ownership, then value. Start at tree depth 4; the target is depth 16.
- Notes go to the receiver out of band in v1. The wallet asks the node for Merkle paths, which is a known privacy leak.

**Chain**
- Proof of work over a Blake2b-256 header hash, with a fixed target in v1.
- `applyBlock :: ChainState -> Block -> Either BlockError ChainState` is pure, so the chain state is `foldM applyBlock genesis`.
- A proof may use any of the last K tree roots as its anchor.
- The nullifier set is a `HashSet`, and duplicates within a block are rejected too.
- The node keeps its state in `TVar`s. **Expensive verification happens outside `atomically`.**

## Invariants (never break these)

1. **No elliptic curves, pairings, RSA, or discrete-log crypto anywhere**, including as dependencies. This is the project's whole point.
2. `verify`, `validateTx`, and `applyBlock` stay pure. No `IO`, no `unsafePerformIO`.
3. Randomness comes only from `crypton`'s system RNG. Never use `System.Random` for keys, blinding, or randomizers.
4. Every value is range-checked. Never reuse a blinding factor `r`.
5. Serialization is canonical: one byte encoding per value.
6. Don't move to the next phase until the current phase's "Done when" checklist passes.

## Code conventions

- `GHC2021` plus `DataKinds`, `DerivingStrategies`, and `OverloadedStrings`. The code is `-Wall` clean.
- Use newtypes for distinct things: `Digest`, `Proof`, `Value`, `SecretKey`, `PublicKey`.
- Use strict fields in long-lived data, `foldl'` not `foldl`, and unboxed vectors wherever the element type allows.
- Every `src` module gets a matching spec in `test/`. Algebraic laws are QuickCheck properties, and `Arbitrary` generators deliberately hit 0, 1, and p − 1.
- Failures are typed: `VerifyError` and `BlockError` are sum types that name *which* check failed.
- Tests use small parameters. Real parameters live in one config value.
- Haddock comments on public functions state the math they implement, such as "folds f into f_e + α·f_o on the squared domain".

## Status

Update this table as phases finish.

| Phase | Topic | Status |
| --- | --- | --- |
| 1 | Finite fields | Done (`v0.1-fields`) |
| 2 | Polynomials, NTT | Not started |
| 3 | Merkle, transcript | Not started |
| 4 | FRI | Not started |
| 5 | AIR and STARK | Not started |
| 6 | Rescue-Prime, STARK signature | Not started |
| 7 | Shielded transactions | Not started |
| 8 | Chain and nodes | Not started |
| 9 | Wallet, demo, benchmarks, write-up | Not started |

The planned schedule runs Oct 2026 to May 2027 (see `docs/BUILD_GUIDE.md`, Timeline). If the schedule slips, cut Phase 9 upgrades first, then fork handling, then TCP networking, then tree depth. Never cut Phases 4, 5, or 7.

## Key references

- *Anatomy of a STARK*: https://aszepieniec.github.io/stark-anatomy/ (the primary reference; this design follows it)
- STARK 101: https://starkware.co/stark-101/
- ethSTARK documentation: https://eprint.iacr.org/2021/582
- Rescue-Prime specification: https://eprint.iacr.org/2020/1143
- Zcash protocol specification, sections 3.2, 3.8, and 3.9: https://zips.z.cash/protocol/protocol.pdf
