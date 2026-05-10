# ADR-0008: Scheduled jobs via Coolify Scheduled Tasks

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Most workloads have at least one recurring job: a periodic data refresh, a digest email, an app-level backup dump, a cache warm-up. Without a default place to put those, each workload reinvents scheduling — usually as host-level crontab entries that drift from the workload that owns them.

We need one place app-level schedules live, owned by the same UI as the resource that runs them.

## Decision

App-level scheduled jobs run as **Coolify Scheduled Tasks** attached to the workload's resource — *not* in the host's `/etc/crontab` or `/etc/cron.d`.

Host-level cron remains the right tool for VPS-wide concerns: full-VPS backup scripts, log rotation, `docker system prune`, OS updates — anything that isn't owned by a single workload.

## Consequences

- The schedule lives next to the resource that owns it. Reading the Coolify resource page tells you what runs and when.
- Tasks restart cleanly when the resource redeploys; no orphan cron entries pointing at an old container name.
- Migrating the VPS is simpler — Coolify resources move; nothing important hides in `/etc/cron.d`.
- **Trade-off:** schedules are now Coolify-flavored, not POSIX. Switching orchestrators means re-creating tasks. Acceptable lock-in for the value of co-location with the resource.
- **Constraint:** workloads should not write app-level cron entries directly into the container or the host. The Coolify task is the only sanctioned place.

## Alternatives considered

- **Host crontab for everything.** Works but couples the schedule to a specific container name and host; brittle on redeploy or migration; invisible to anyone reading the workload's resource page.
- **In-app scheduler (APScheduler, Celery Beat, Sidekiq-cron, etc.).** Correct for tightly coupled scheduling logic that depends on application state mid-flight; overkill for "run this CLI command on Mondays."
- **GitHub Actions cron + remote trigger** (SSH, gh API, webhook). Works but introduces external dependencies, credentials to manage, and a network path that can fail independently.
- **systemd timers on the host.** More robust than cron, but moves us off Coolify's audit/restart story for app-level concerns. Still appropriate for host-wide tasks.
