# ADR-0003: Container image build conventions

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Workloads on the vps-playground VPS run as containers. We need a baseline image-build shape that:

1. Keeps redeploys (`git push` → Coolify rebuild) fast.
2. Doesn't ship build-time tooling or development credentials in the runtime image.
3. Doesn't hand a privileged shell to anyone who exploits the app.
4. Matches what solarscout already adopted, so the next workload doesn't reinvent the same shape.

The healthcheck side of the image contract is covered separately in [ADR-0002](0002-healthcheck-endpoint.md).

## Decision

Every workload image:

- **Multi-stage build.** A separate builder stage installs/compiles dependencies; the runtime stage copies only the artifacts. The toolchain (compilers, lockfile resolvers, dev libs) does not ship in the runtime image.
- **Non-root user.** The runtime stage creates a dedicated unprivileged user (e.g. `app`, `spl`) and the `USER` directive switches to it before `CMD`. Writable directories (`/data`, log paths) are explicitly `chown`'d to that user.

## Consequences

- Smaller, more reproducible runtime images; faster cold redeploys.
- Container exploits land on a non-root user; lateral movement requires a kernel/Docker escape.
- Volume writes happen as the non-root UID, so future volume migrations don't have to deal with mixed-ownership trees.
- **Trade-off:** non-root requires explicit `chown` of writable directories in the Dockerfile, and care if the app wants to bind a port < 1024 (Traefik's reverse-proxying makes this a non-issue in practice).

## Alternatives considered

- **Single-stage build** — simpler, but ships toolchains in the runtime image, bloats redeploys, and can leak build-time secrets via Docker history.
- **Run as root** — works, but every container exploit becomes a root-shell exploit on the container's namespace, and volume writes-as-root complicate later non-root migrations.
- **Distroless / `FROM scratch` runtime stage** — strictly smaller and more secure; valid choice but adds friction (no shell for debugging, no `curl`/`wget` for the [ADR-0002](0002-healthcheck-endpoint.md) healthcheck). Workloads are free to use distroless once comfortable.
