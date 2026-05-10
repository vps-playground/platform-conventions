# ADR-0009: Optional-secret design for split UI/backend workloads

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Some workloads have two surfaces:

- A **UI** that reads from persistent state (DB, files in the volume).
- A **backend** (pipeline, batch job, agent loop) that needs paid or sensitive credentials (LLM provider keys, third-party API keys, …) to do its work.

The default reflex — *require all credentials at startup* — couples the UI's deployability to the secret-handling readiness of every host that runs the image. If the prod credentials aren't ready yet, or the host shouldn't hold them at all, the UI can't start either.

The first workload on this VPS hit this in its initial deploy: it wanted to ship the UI to the VPS while the production LLM key was still being scoped, but the app refused to start without it. A small refactor split the requirement.

## Decision

For workloads with a UI ↔ backend split:

- Credentials are read from **optional** environment variables, never required at process startup.
- A small `require_<credential>()` helper raises a clear error **only at the call sites that actually need that credential** (the LLM call, the third-party API request).
- The UI must not call those helpers and must function fully against the persistent state alone.

This enables:

- **Read-only mode** — the UI runs on a host that doesn't hold the credentials; the backend runs elsewhere (or not yet).
- **Full mode** — everything on one host once the credentials arrive.

Both modes use **the same image**. Switching is an env-var change, not a code change.

## Consequences

- The UI can be deployed earlier than the backend; the time-to-first-deploy decouples from credential procurement.
- A less-trusted host can run the UI without ever seeing the secrets — a useful boundary for partner/stakeholder access.
- **Trade-off:** errors surface lazily. A misconfigured deployment looks fine until the first call site that needs the credential fires. **Mitigation:** log a clear startup banner listing which optional capabilities are disabled because their credentials are unset.
- **Constraint:** workloads following this pattern must not start health-affecting tasks (writers, agent loops) on import; everything secret-dependent must be lazy.

## Alternatives considered

- **Required-at-startup secrets.** Fails-fast and is the textbook default; loses the read-only-mode benefit and forces secret distribution to every host that runs the image.
- **Two separate images** (one UI, one backend). Correct for larger systems with independent release cadences; over-engineered when 90% of the code is shared.
- **Feature flag at startup** (`ENABLE_LLM=true|false`). Equivalent in effect but adds a second config knob that can drift from the actual key state. The optional-key approach makes the env var itself the flag.
- **Stub the secret with a placeholder.** Sometimes proposed as a quick fix; risks a real call going to a bogus credential and producing confusing 401s deep in the stack instead of a clear "not configured" error.
