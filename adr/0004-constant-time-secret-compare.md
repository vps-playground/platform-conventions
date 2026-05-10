# ADR-0004: Constant-time comparison for secrets

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Workloads frequently need to compare a presented secret against an expected value: API keys, basic-auth passwords, HMAC signatures, session tokens, webhook payload digests, CSRF tokens, etc. The naïve approach is the language's normal equality operator (`===`, `==`, `equals()`, `==`).

Naïve equality short-circuits on the first mismatching byte. The time taken to return `false` is a function of how many leading bytes match. Over enough samples, an attacker can recover a secret one byte at a time by timing repeated guesses — a textbook side-channel attack. The exact feasibility depends on network jitter and the secret's length, but the defense is cheap and uniform: use a comparison that takes the same time for every input pair.

A second, related leak: many naïve comparisons fail fast on a length mismatch *before* comparing any bytes, leaking the expected length.

These bugs aren't framework-specific — they appear in every stack, are easy to write, and easy to miss in review. Standardizing the rule once across all workloads catches them by reflex.

## Decision

Workloads compare secrets in constant time, using the platform's standard library primitive. Implementations must not leak length or content via timing.

The standard library primitives across our common stacks:

| Stack | Primitive |
|---|---|
| Node.js | [`crypto.timingSafeEqual(a, b)`](https://nodejs.org/api/crypto.html#cryptotimingsafeequala-b) over `Buffer` of equal length |
| Web Crypto / Deno / Bun | the Node primitive above (Bun, Deno) or a `subtle.timingSafeEqual` shim where available |
| Python | [`hmac.compare_digest(a, b)`](https://docs.python.org/3/library/hmac.html#hmac.compare_digest) |
| Go | [`crypto/subtle.ConstantTimeCompare(a, b)`](https://pkg.go.dev/crypto/subtle#ConstantTimeCompare) |
| Rust | [`subtle::ConstantTimeEq`](https://docs.rs/subtle/) (or a constant-time HMAC comparison if available) |
| Java | [`MessageDigest.isEqual(a, b)`](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/security/MessageDigest.html#isEqual(byte%5B%5D,byte%5B%5D)) (constant-time as of Java 7) |

Most of these primitives still throw or short-circuit on length mismatch, leaking the expected length. The recommended pattern for inputs whose length is itself sensitive (passwords, free-form tokens):

1. Hash both inputs with HMAC-SHA-256 using a per-process random key.
2. Compare the resulting fixed-length digests with the constant-time primitive.

This normalizes both inputs to the digest length and makes the comparison time independent of the original lengths.

## Consequences

- Every secret comparison in every workload is constant-time and length-stable. A reviewer skimming for `if (provided === expected)` against a secret variable knows it's a finding without further analysis.
- Writing a new auth helper is mechanical: the primitive has the same shape across stacks, and the HMAC-then-compare pattern is the same regardless of language.
- **Constraint:** the per-process HMAC key must be generated at process start (eg. `crypto.randomBytes(32)`) and never logged or persisted. Reusing a fixed key across processes defeats length normalization.
- **Trade-off:** the HMAC step costs two SHA-256 invocations per comparison. Negligible for auth — single-digit microseconds — and avoided entirely when the secret length is itself a public constant (eg. an HMAC signature is always the digest length).

## Alternatives considered

- **Plain `===` / `==`** — leaks timing per byte and length per length-check. Rejected.
- **Use `crypto.timingSafeEqual` directly without HMAC normalization** — fine when both inputs are guaranteed to be the same fixed length (eg. comparing two HMAC outputs). The primitive throws on length mismatch otherwise, which itself leaks the expected length. The HMAC step is the standard cure.
- **Hash with a non-keyed digest (plain SHA-256)** instead of HMAC — works for length normalization but invites comparison-of-public-hashes attacks if the secret has low entropy. HMAC-with-secret-key is the correct primitive.
- **Custom constant-time loop** — easy to get wrong (the JIT can re-introduce branches, optimizers can short-circuit). Rejected; use the standard library.
