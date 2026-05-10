# ADR-0002: Dedicated `/healthz` healthcheck endpoint

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Workloads on the vps-playground VPS run inside Docker containers managed by Coolify, which schedules a `HEALTHCHECK` against each container at a fixed interval (default 30s). The healthcheck signals liveness back to Coolify and Traefik for routing decisions.

Pointing the healthcheck at the application's public entry route (`/`) is a common antipattern across stacks: it triggers full request handling — template rendering, DB queries, upstream calls — every 30 seconds, forever. The result is a permanent low-grade load that isn't real user traffic, access logs polluted with orchestrator probes, and a probe signal that conflates "the HTTP listener is up" with "the entry route renders without error" — a stricter signal than liveness needs.

## Decision

Every HTTP workload exposes a route at `/healthz` that:

- Returns HTTP `200` with body `ok` and `Content-Type: text/plain; charset=utf-8`.
- Does **not** touch the database, render templates, or call upstream services.
- Is exempt from any auth gate (basic-auth middleware, session enforcement, etc.) so the orchestrator can probe it without credentials.
- Is exempt from rate-limiting middleware where present.

The container's `Dockerfile` `HEALTHCHECK` directive targets this path. Any HTTP client available in the image is fine — `curl`, `wget`, or a one-line snippet in the workload's runtime language. Examples:

```dockerfile
# curl (when present in the image)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/healthz" || exit 1

# wget (BusyBox/Alpine)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/healthz" || exit 1
```

## Consequences

- Healthcheck cost is negligible (one HTTP round-trip + plain-text response). No DB load, no template render.
- The signal is precise: the HTTP listener is up and responsive. Application-level health (DB reachability, upstream availability) is a separate concern, surfaced via observability rather than wedged into the liveness probe.
- Access logs no longer show 30-second-interval `GET /` entries from the orchestrator, making real user traffic readable.
- **Constraint:** workloads must add a public-by-default route at exactly `/healthz`. Workloads that gate every route through auth middleware must explicitly bypass this path.
- **Trade-off:** the probe doesn't catch "DB is down but HTTP is up" failure modes. That's intentional — readiness gating belongs in observability and auto-recovery, not in the liveness loop.

## Alternatives considered

- **Probe the entry route (`/`)** — too expensive (full request handling), conflates entry-route rendering with liveness. Rejected.
- **TCP probe only** (`HEALTHCHECK CMD nc -z 127.0.0.1 $PORT`) — doesn't catch a process that's listening but wedged at the application layer. Rejected.
- **`/healthz` with DB ping** (readiness probe) — useful, but a different concern. Workloads are free to add `/readyz` for that; this ADR is just about liveness.
- **Reuse Coolify's built-in HTTP probe instead of Dockerfile HEALTHCHECK** — works, but pinning the probe in the Dockerfile keeps the contract with the image (same behavior under any orchestrator).
