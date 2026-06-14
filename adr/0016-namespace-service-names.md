# ADR-0016: Namespace bundled service names on the shared Coolify network

- **Status**: Proposed
- **Date**: 2026-06-14
- **Decided by**: @a-grasso

## Context

Workloads deploy as Docker Compose stacks under Coolify and attach to the shared
`coolify` network so Traefik can route to them. That network is **shared across
every workload and Coolify's own services**, and Docker's embedded DNS resolves a
bare service name to whatever container claims it on a network the resolver is
attached to.

A workload bundled its own database as a compose service named `postgres` and
pointed the app at `DATABASE_HOST=postgres`. Because the app is also on the shared
`coolify` network — where another container already answers to `postgres` — the
name resolved to the **wrong** database. The app authenticated against a foreign
DB that doesn't know its role and crash-looped on `28P01 password authentication
failed`, despite the credentials and the app's own bundled DB being correct.
Confirmed live: `getent hosts postgres` on the `coolify` network resolved to a
foreign container, not the workload's DB. Generic names (`postgres`, `redis`,
`db`, `cache`, `mq`) are all exposed to this collision.

## Decision

Bundled backing services in a workload's compose **MUST use a workload-prefixed,
unique service name** (e.g. `closet-db`, not `postgres`), and the app's connection
host variables (`DATABASE_HOST`, `REDIS_HOST`, etc.) **MUST point at that unique
name**. Bundled services should also stay **off the `coolify` network** — on a
private per-workload `internal` network only — but the unique name is required
regardless, because the consuming app is necessarily on the shared network.

## Consequences

- No cross-workload DNS collisions; an app always resolves its own backing service.
- Compose files and host vars carry a workload prefix — marginally more verbose,
  but self-documenting.
- Existing workloads using bare names should rename on their next deploy. A rename
  keeps the volume name unchanged, so data and DB roles persist.
- Agents scaffolding workloads (e.g. `workload-bootstrap`) must emit prefixed
  service names by default.

## Alternatives considered

- **Keep generic names, rely on network ordering** — rejected: resolution is
  ambiguous and order-dependent; the failure is silent and intermittent-looking.
- **Don't attach the app to `coolify`** — rejected: Traefik ingress requires it.
- **Force every bundled service onto only the private network** — necessary but
  insufficient: the *app* is still on the shared network and does the resolving,
  so a unique name is what actually prevents the collision.
