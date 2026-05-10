# ADR-0007: Two-tier backup strategy for VPS workloads

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Workloads on the VPS persist data in named Docker volumes. Two failure modes need different recovery tools:

- **Whole-VPS loss** — the host dies, the region has an issue, Coolify state is corrupted. Recovery requires the whole VM back.
- **App-level corruption** — a bad migration, user error, an accidental DELETE. Recovery requires rolling back one app's data without disturbing siblings.

A single backup mechanism doesn't cover both well, and any policy that depends on operator discipline at restore time will fail under pressure.

## Decision

Two layers, both default-on for any workload with persistent state:

1. **Hetzner snapshots** (whole-VM, ~€0.01/GB/month). Configured in the Hetzner Cloud Console; retention chosen per project. Recovery is a VM-level restore.
2. **App-level data dump** copied to the volume's `backups/` subdirectory, scheduled nightly. The exact command is engine-specific:
   - SQLite — `sqlite3 /data/<app>.db ".backup /data/backups/<app>-$(date +\%F).db"`
   - PostgreSQL — `pg_dump -Fc -f /data/backups/<app>-$(date +\%F).dump <db>`
   - Other — equivalent logical dump.

The dump should also be copied off the VPS at least weekly. Retention/rotation/off-host policy is workload-local; this ADR mandates only that the two layers exist.

## Consequences

- Two recovery modes available: VM-level rollback for catastrophic loss, app-level rollback for surgical recovery without disturbing siblings.
- Cheap insurance — both tiers cost cents per app per month.
- **Trade-off:** nightly dumps add a small load spike; SQLite `.backup` and `pg_dump` briefly add load on the writer. Negligible at our scale; revisit if a workload has strict latency SLOs.
- **Constraint:** workloads must reserve disk in their `/data` volume for the `backups/` subdir (a few × the live DB size).

## Alternatives considered

- **Snapshots only.** Catastrophic recovery works; surgical recovery requires booting an old snapshot in a sandbox and exporting one app's data. Painful enough that it would be skipped under pressure.
- **App dumps only.** Surgical recovery works; catastrophic recovery means rebuilding the VM from scratch and rehydrating each app one by one. Acceptable but slow.
- **Continuous WAL archiving (Litestream, pgBackRest, etc.).** Best-in-class for serious workloads with low-RPO requirements; over-engineered for the playground tier. Workloads are free to add this on top — it complements rather than replaces this ADR.
- **Off-host streaming backup (S3/B2/etc.) only.** Strong for catastrophic recovery; weak for surgical (restoring one row from an S3 archive is a chore).
