# ADR-0002: Dedicated `/healthz` healthcheck endpoint

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Workloads on the vps-playground VPS run inside Docker containers managed by Coolify, which schedules a `HEALTHCHECK` against each container at a fixed interval (default 30s). The healthcheck signals liveness back to Coolify and Traefik for routing decisions.

Pointing the healthcheck at the application's public homepage (`/`) is a common antipattern: it triggers a full SSR render plus any data-fetching the homepage does — every 30 seconds, forever. For SvelteKit + DB workloads, that's a permanent low-grade load query and a permanent log line in the access log that doesn't represent real user traffic. It also conflates "the HTTP listener is up" with "the homepage renders without error", which is a stricter signal than liveness needs.

## Decision

Every workload exposes a route at `/healthz` that:

- Returns HTTP `200` with body `ok` and `Content-Type: text/plain; charset=utf-8`.
- Does **not** touch the database, render templates, or call upstream services.
- Is exempt from any auth gate (basic-auth middleware, session enforcement, etc.) so the orchestrator can probe it without credentials.

The container's `Dockerfile` `HEALTHCHECK` directive targets this path:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/healthz').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
```

## Consequences

- Healthcheck cost is negligible (one process + one HTTP round-trip + plain-text response). No DB load, no SSR cycle.
- The signal is precise: the HTTP listener is up and responsive. Application-level health (DB reachability, upstream availability) is a separate concern, surfaced via observability rather than wedged into the liveness probe.
- Access logs no longer show 30-second-interval `GET /` entries from the orchestrator, making real user traffic readable.
- **Constraint:** workloads must add a public-by-default route at exactly `/healthz`. Workloads that gate every route through auth middleware must explicitly bypass this path.
- **Trade-off:** the probe doesn't catch "DB is down but HTTP is up" failure modes. That's intentional — readiness gating belongs in observability and auto-recovery, not in the liveness loop.

## Alternatives considered

- **Probe `/`** — too expensive (full SSR + DB), conflates homepage rendering with liveness. Rejected.
- **TCP probe only** (`HEALTHCHECK CMD nc -z 127.0.0.1 $PORT`) — doesn't catch a process that's listening but wedged at the application layer. Rejected.
- **`/healthz` with DB ping** (readiness probe) — useful, but a different concern. Workloads are free to add `/readyz` for that; this ADR is just about liveness.
- **Reuse Coolify's built-in HTTP probe instead of Dockerfile HEALTHCHECK** — works, but pinning the probe in the Dockerfile keeps the contract with the image (same behavior under any orchestrator).
