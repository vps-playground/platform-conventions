# ADR-0017: `/readyz` reports the running build's commit

- **Status**: Proposed
- **Date**: 2026-08-27
- **Decided by**: @a-grasso

## Context

Workloads on the VPS deploy by pushing to `main`: the orchestrator pulls, builds, and restarts the container. Nothing in that chain tells anyone afterwards *which* build is actually serving traffic.

This surfaced concretely. A workload's CI ran fully green, its `/healthz` returned `200`, and the container was still serving an image built before the change - the deploy trigger had silently never fired. Both signals that exist today were working exactly as designed, and neither could have caught it:

- **CI** attests that a commit builds and passes tests. It says nothing about whether that commit shipped. Wiring deploys outside CI (orchestrator webhooks, manual redeploys) is normal here, so green CI and a stale container are entirely compatible states.
- **`/healthz`** (ADR-0002) attests that the HTTP listener is up. It deliberately says nothing about application identity, and its body is fixed to `ok`.

The gap was only found by probing for an API route that existed solely in the new code - a trick that requires writing a new probe for every change and is unavailable to anyone who does not already know the diff.

ADR-0002 scoped itself to liveness and explicitly left readiness to workloads: *"Workloads are free to add `/readyz` for that; this ADR is just about liveness."* That is the natural home for build identity, and several workloads already expose `/readyz` informally with no agreed shape.

## Decision

Every HTTP workload exposes a route at `/readyz` that:

- Returns HTTP `200` with a JSON body containing at least a **`commit`** field: the git SHA (full or abbreviated, consistently) of the revision the running image was built from.
- Is **auth-exempt**, like `/healthz` - verification must not require a session or an API credential. Under ADR-0011 this means an auth-exempt router for the path.
- Derives `commit` from a **build-time** injection (build arg or baked env var), never by reading a `.git` directory at runtime. Runtime images do not ship git metadata, and a value computed at runtime attests the filesystem rather than the build.

Recommended shape, with additional fields left free:

```json
{"commit": "9f3c1ab", "version": "0.4.2"}
```

Returning a non-`200` while the workload is genuinely not ready (dependencies unavailable) remains valid and is orthogonal to this ADR.

## Consequences

- **"Is my push live?" becomes one unauthenticated `curl`**, identically shaped across every workload, and equally usable by a human, an agent, or a script.
- **Deploy pipelines can verify instead of assume.** After triggering a deploy, CI can poll `/readyz` until `commit` matches the pushed SHA and fail loudly otherwise. This closes the failure mode above at its root: a deploy that did not happen stops looking like a success.
- **Constraint:** builds must thread the SHA into the image, and the path must be exempted from the auth perimeter. For workloads that already exempt `/healthz`, this is one more entry on the same list.
- **Trade-off - the commit SHA becomes public.** Accepted: a bare SHA discloses no repository content, and the operational value of external verifiability outweighs it. A workload that objects may gate `/readyz` behind the perimeter, accepting that it forfeits external verification.
- Does not replace CI or `/healthz`. The three answer different questions: *does it build*, *is it up*, *what is it*.

## Alternatives considered

- **Put the version in `/healthz`** - ADR-0002 fixes that body to `ok` with `text/plain`, and overloading a liveness probe with identity muddies a deliberately narrow signal. Rejected.
- **Read the image tag or digest in the orchestrator dashboard** - requires dashboard access, is not scriptable by agents, and reports what was *deployed* rather than what is *serving*. Rejected.
- **A response header (e.g. `X-Build-Commit`) on every response** - workable and cheap to check, but adds bytes to every response and offers no single discoverable place to look. Rejected as the primary mechanism; workloads may add it alongside.
- **Log the SHA at boot and read container logs** - needs host or dashboard access, so it is unavailable to the agents and CI jobs that most need the answer. Rejected.
- **Record the deployed SHA in CI only** - does not survive deploys triggered outside CI, including manual redeploys, which is precisely how the original gap arose. Rejected.
