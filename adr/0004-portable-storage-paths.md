# ADR-0004: Portable storage paths

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

A workload that persists data needs to behave the same in three environments:

- Local dev (`./data/...`)
- Container on the VPS (`/data/...`, mounted from a Coolify-managed named volume)
- A future migrated host (different absolute paths)

An early workload on this VPS hardcoded local-laptop paths into a database column (e.g. `/Users/.../output/run-...`), and migrating to the container volume required a one-shot helper to rewrite legacy rows. That migration was avoidable — and the next workload should not repeat the mistake.

## Decision

Two rules apply to every workload that persists state:

1. **Storage paths are env-overridable with sensible defaults.** Each writable path the app uses (DB file, output directory, cache directory, …) is read from an env var (e.g. `<APP>_DB_PATH`, `<APP>_OUTPUT_DIR`, `<APP>_CACHE_DIR`) with a project-root default for local dev. The `Dockerfile` sets these to `/data/*` so the same image runs identically locally and on the VPS.
2. **DB columns store basenames or relative paths, never absolute paths.** Resolvers join the persisted name against the configured root at read time. Anything that looks like `/Users/.../...` or `/home/.../...` in a database column is a bug.

## Consequences

- Same image, same code, runs identically on a laptop and inside the container — no local-dev branches in the source.
- Data is portable: a `<app>.db` written locally can be `docker cp`'d into the container's volume and just works.
- Volume-to-volume migrations (e.g. moving to a different VPS) become a `docker cp` rather than a SQL rewrite.
- **Trade-off:** requires a small resolver helper around path lookups instead of using stored paths verbatim. Trivial cost.

## Alternatives considered

- **Hardcoded paths** — simpler initially; breaks on every environment that isn't the original author's machine. The default mistake.
- **Absolute paths in DB columns** — works until the host changes; then needs a migration helper. The first workload on this VPS took this hit; future workloads should not.
- **OS-level symlinks bridging the local and container paths** — works but hides the abstraction in filesystem state outside the repo, which is fragile across hosts and invisible in code review.
- **Configuration via a checked-in YAML/TOML config file** — fine for non-secret config, but env vars compose better with Coolify's existing env tab and with `.env` for local dev.
