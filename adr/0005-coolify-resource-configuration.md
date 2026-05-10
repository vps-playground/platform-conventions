# ADR-0005: Coolify resource configuration recipe

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Each new workload on the vps-playground VPS gets its own Coolify resource. We want a standard configuration so:

1. Deploys are reproducible across workloads.
2. Volumes, env vars, and source connections don't drift into ad-hoc shapes.
3. Onboarding a new workload is mostly checking boxes, not making decisions.

## Decision

Every workload's Coolify resource is configured as follows:

- **Source.** A single GitHub App registered at the org level (e.g. `vps-playground` or a child org). The app is installed on each workload repo individually. Coolify mints short-lived auto-renewing installation tokens — no per-repo deploy keys to rotate.
- **Build pack.** Docker Compose. The compose file lives at the repo root (`docker-compose.yaml`) with a single primary service.
- **Persistent volume.** A named volume `<app>-data` mounted at `/data` inside the container. The volume name **must** be namespaced per app to prevent collisions on the shared Docker host; bare names like `data` are forbidden.
- **Environment variables.** Set in Coolify's Environment tab. The local `.env` is gitignored and `.dockerignore`'d; the runtime image never contains development credentials.
- **Auto-deploy on `main` push.** Enabled. Coolify registers the webhook automatically; the GitHub App handles auth.

## Consequences

- One template fits every workload — the deploy story for a new project is "create resource, point at repo, set env vars."
- Volumes survive rebuilds and are unambiguously owned by one app.
- A single GitHub App handles N repos: no per-repo deploy keys, no manual token rotation.
- **Trade-off:** a contributor adding a new repo needs access to the org-level GitHub App's installation page. Acceptable for a small team.
- **Constraint:** workloads that don't use Docker Compose must justify their build pack choice in their workload-local README.

## Alternatives considered

- **Per-repo deploy keys.** Works for one or two repos; doesn't scale, and rotation is manual. Coolify supports both — we chose the GitHub App path the moment we anticipated more than one workload.
- **Nixpacks / build-pack auto-detection.** Convenient for very simple apps but loses control of the build (no multi-stage, no easy non-root, no `HEALTHCHECK`). Out of scope for any workload that follows [ADR-0003](0003-container-image-build-conventions.md) and [ADR-0002](0002-healthcheck-endpoint.md).
- **Bind-mount host paths instead of named volumes.** Surfaces host filesystem details into the workload; the workload starts depending on a particular host layout. Named volumes keep that abstracted.
- **Env vars committed (encrypted) to the repo.** Increases velocity but loses Coolify's audit log of changes and requires a separate key-management story.
