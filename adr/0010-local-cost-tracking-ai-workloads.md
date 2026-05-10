# ADR-0010: Local cost tracking for AI-using workloads

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Workloads that call paid LLM or other AI APIs (Anthropic, OpenAI, Google, …) need visibility into per-call cost — for budget management, per-feature attribution, and tuning the model mix.

The natural reflex is to use the provider's admin or usage API. For some providers this is a dead end at our tier:

- **Anthropic** — the admin API requires an admin-tier key not provisioned on standard accounts; designing a workload's cost dashboard around it leads nowhere. Confirmed during the first AI workload's cost-dashboard work.
- **Other providers** — admin APIs exist but typically aggregate at the account or project level, with no per-feature attribution within a single workload.

Either way, "ask the provider" doesn't answer the questions a workload actually wants answered: *which feature in this app cost what last week?*

## Decision

Workloads that call paid AI APIs **track usage locally**, not via the provider's admin or usage API:

- Every API call records its tokens-in, tokens-out, model, and computed USD into a `<app>_costs` (or similar) table in the workload's own DB. The exact column set is workload-local; the column **set must include** at minimum: timestamp, model, input tokens, output tokens, USD, and a free-text `feature` tag identifying the call site.
- The cost computation uses model-specific rates kept in a small lookup file checked into the repo. Rate updates happen as commits, not as runtime config edits.
- A `/cost` page (or equivalent) in the workload surfaces per-model + per-feature + per-day totals.

## Consequences

- Cost data is portable and queryable in the same DB as the workload's domain data; per-feature cost analysis is a SQL query.
- No dependency on provider admin APIs that may not be available, may rate-limit, or may change shape.
- Rates live with the code, so a model swap that changes pricing is one commit.
- **Trade-off:** model-rate updates require a deploy. Acceptable — rates change infrequently and the deploy is `git push`.
- **Constraint:** every AI-call site in the workload must go through a single helper that records the call. Direct SDK calls that bypass it are a bug.

## Alternatives considered

- **Provider admin/usage APIs.** Often unavailable at our tier (Anthropic specifically); when available, aggregate at account or project level — no per-feature attribution within a workload.
- **Parse provider invoice CSVs.** Works for monthly billing reconciliation; useless for live per-feature attribution.
- **Third-party LLM observability platforms** (Langfuse, Helicone, Phoenix, …). Correct for serious ML systems with eval/replay needs; over-engineered for the playground tier and adds a cross-network hop on every API call. Workloads are free to add on top.
- **Log only, derive cost at query time.** Equivalent if the rate file is queryable; in practice writing a derived USD column at call time is simpler and lets the `/cost` page be a plain `SUM()` query.
