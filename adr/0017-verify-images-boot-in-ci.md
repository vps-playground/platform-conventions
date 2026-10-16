# ADR-0017: Verify images boot in CI, and treat empty env vars as unset

- **Status**: Proposed
- **Date**: 2026-08-27
- **Decided by**: @a-grasso

## Context

A workload on this platform went to production dead: Traefik answered `503 no available server`, no Let's Encrypt certificate was ever issued, and its routers were registered with no backend behind them. Its sibling service in the same compose file was healthy.

The cause was a single character of config semantics. Compose's default syntax

```yaml
KNOWLEDGE_ROOT: ${TENANT_KNOWLEDGE_ROOT:-}
```

supplies an **empty string**, not an absent variable. The application read it with JavaScript's `??`, which only falls back on `null`/`undefined`, so `''` passed straight through to a validating config schema (`z.string().min(1)`), which threw at module load. The process exited before it ever bound a port.

Two properties of that failure make it worth an ADR rather than a bugfix:

1. **It is invisible at the edge.** A container that dies parsing its config and a container that crashed under load are the same `503` to Traefik. There is no signal distinguishing "misconfigured" from "broken" without shelling into the host and reading container logs. The `/healthz` contract (ADR-0002) cannot help — the process never reached the point of serving it.

2. **It survived a green CI pipeline.** The workload's CI built both images successfully. Building an image proves it compiles; it proves nothing about whether the image *starts* under the environment its own compose file supplies. The gap between "builds" and "boots" is exactly where config-time death lives, and nothing on the platform was looking at it.

The empty-vs-unset trap is not exotic. Every workload here uses `${VAR:-}` defaults, and any workload validating its config at startup — a growing number, since fail-fast config is otherwise good practice — is one placeholder away from the same outage. Fail-fast config validation turns a *degraded* service into an *absent* one, which is the right trade only if something catches it before production.

## Decision

**Two rules, both binding on every workload.**

### 1. Config schemas treat an empty environment variable as unset

Reading a variable that compose may default to empty must fall back to the declared default, not propagate `''` into validation. Language-specific, same semantics:

```js
// JS/TS — `??` is wrong here; '' is not nullish
const read = (n) => { const v = process.env[n]; return v?.trim() ? v : undefined }
```

```python
# Python — os.environ.get returns '', not None
def read(n): return (os.environ.get(n) or "").strip() or None
```

Correspondingly, a compose file must not hand a service an empty value for a variable the service requires. Give it a **non-empty placeholder** that lets the container boot into a degraded-but-observable state:

```yaml
# Non-empty on purpose: '' would fail the config schema and kill the container
# at boot. The path need not exist — /healthz stays green, /readyz reports the
# real state until the value is configured.
KNOWLEDGE_ROOT: ${TENANT_KNOWLEDGE_ROOT:-/var/lib/app/unbootstrapped}
```

The principle: **a container must never fail to start because an optional dependency has not been configured yet.** Report it through readiness (ADR-0002's `/readyz`), where it is legible, rather than through process exit, where it is not.

### 2. CI runs every built image and asserts `/healthz`

Every workload's CI must, for each service image it builds:

- start the container with its **real `CMD`**, not a shell override or a simplified equivalent;
- supply the **environment its own compose file supplies** for a pre-bootstrap deploy — including variables that are empty at that stage, since that is the case being tested;
- poll `GET /healthz` until it answers `200 ok` per ADR-0002, with a bounded timeout;
- **dump container logs on failure**, so a red build names the bad variable instead of merely reporting a timeout.

A build step that only builds does not satisfy this rule.

## Consequences

**Upsides**

- The class of failure this ADR is named for cannot reach production silently. It fails on a pull request, with logs, next to the change that caused it.
- Config errors become legible. "Which variable?" is answered by CI output rather than by SSH plus `docker logs` against a running VPS.
- The `/healthz` contract gains teeth. ADR-0002 mandated the endpoint; nothing verified any image could actually serve it. This closes that gap for every workload at once.
- Degraded-but-up becomes the default posture for unconfigured optional dependencies, which composes with `/readyz` instead of fighting it.

**Trade-offs**

- CI gets slower — a container start and healthcheck poll per service, roughly 10–30 seconds each. Acceptable; it is strictly less than the time to diagnose one `503` on the VPS.
- CI must model the pre-bootstrap environment, which means the env block in CI and the env block in `compose.yml` can drift. Keeping them adjacent and commented is the mitigation; a workload wanting stronger coupling can parse `compose.yml` in CI rather than restating it.
- Workloads whose runtime genuinely cannot start without an external dependency (a database that must exist) will need a stub or a compose-based CI harness. That is a reasonable prompt to reconsider whether the dependency truly belongs in the startup path.
- Boot-time validation stays valuable and is **not** discouraged. The rule narrows it: fail fast on genuinely required configuration, degrade on the optional.

**What this does not cover**

- Runtime configuration changes after boot; this is a startup contract.
- Application correctness beyond "the listener came up and served `/healthz`". CI still needs the workload's own tests.
- Secrets management. Whether a value is *correct* is out of scope; whether its absence *kills the process* is not.

## Alternatives considered

- **Fix it per-workload as bugs arise.** Rejected — the trap is structural, not incidental. Every workload using compose defaults plus a validating schema has it latent, and each one discovers it the same expensive way: in production, as an opaque `503`.
- **Ban fail-fast config validation.** Rejected. Validating config at startup is good practice and catches real misconfiguration early. The problem is not validation; it is validating *optional* config as if it were required, with no gate in front.
- **Rely on Coolify's healthcheck or deployment status.** Rejected — Coolify does report the container as unhealthy, but only after the deploy, on the shared VPS, where diagnosis costs an SSH session. CI is the cheaper and earlier place, and it blocks the merge rather than reporting after it.
- **Require every variable to be explicitly set, forbidding `${VAR:-}` defaults.** Rejected — defaults are genuinely useful, and a workload with a two-phase bootstrap (deploy, then provision a tenant, then configure) legitimately cannot know some values at first deploy. The bootstrap sequence is the normal case, not an edge case.
- **Static analysis of compose files for empty defaults.** Rejected as the primary mechanism — it catches one syntactic shape of a semantic problem, and says nothing about whether the image boots. Running the image subsumes it. Could be added later as a cheap pre-filter.
- **Smoke-test after deploy instead of in CI.** Rejected as a replacement, reasonable as an addition. Post-deploy verification finds the problem after it is already live and after the certificate-issuance window has been burned; ADR-0012 notes Let's Encrypt's failed-validation rate limit makes repeated broken deploys costly.
