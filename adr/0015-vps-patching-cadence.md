# ADR-0015: VPS patching cadence — nightly unattended-upgrades with auto-reboot

- **Status**: Proposed
- **Date**: 2026-05-17
- **Decided by**: @agr

## Context

vps-playground is a single shared Hetzner VPS hosting every workload deployed to the platform. Security patches reach the host through two channels:

1. **Ubuntu security pocket** — kernel, OpenSSH, libc, etc. Distributed through the standard `${distro_id}:${distro_codename}-security` archive.
2. **Docker's apt repo** (`download.docker.com`) — `docker-ce`, `docker-buildx-plugin`, `docker-ce-cli`, `docker-ce-rootless-extras`. Coolify uses these; the daemon hosts every workload's containers.

Until now, the `auto_updates` Ansible role enabled unattended-upgrades for the security pocket only, with `Automatic-Reboot "false"`. Consequences:

- Kernel updates installed but never activated — the host kept running an outdated kernel until a human SSHed in to reboot.
- Docker patches required manual intervention. The Coolify dashboard surfaces a "Manage Server Patches" notification, but acting on it still needs a human in the loop.
- Patch lag accumulated silently. The trigger for this ADR was a Coolify notification listing 5 pending patches, including a kernel bump (`6.8.0-111 → 6.8.0-117`) and four Docker components — none of which would have been applied by the existing automation.

The platform is a *playground*: brief planned downtime is acceptable. Every workload already runs under Coolify's reverse-proxy + container restart model, so individual container restarts are a non-event. A full reboot drops the host for ~30–60s.

## Decision

**Run unattended-upgrades nightly across both the Ubuntu security pocket and Docker's apt origin, with automatic reboot at 04:00 UTC when a kernel or library update demands it.**

Concretely, the `auto_updates` role's `/etc/apt/apt.conf.d/50unattended-upgrades` is set to:

```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
    "Docker:${distro_codename}";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::SyslogEnable "true";
```

Periodic timer config (`20auto-upgrades`) is unchanged — apt lists refresh daily, unattended-upgrade fires daily, autoclean weekly.

Non-security pocket updates (e.g. `linux-image-virtual` once it leaves `-security`) remain out of scope: those continue to apply via manual `apt upgrade` or the Coolify "Manage Server Patches" button when a human decides to take the broader update.

## Consequences

**Upsides:**
- Kernel and OpenSSH CVEs land within ~24h with no human action.
- Docker daemon CVEs land the same way — closes the gap that motivated this ADR.
- The 04:00 UTC reboot window is predictable; if a workload needs an explicit maintenance signal, it can hook to a `pre-reboot` script in a future iteration.
- CI re-asserts this config on every push to `vps-control-plane`'s `main` via the existing `harden.yml` workflow — no drift.

**Tradeoffs / what workloads must accept:**
- **Workloads must be reboot-safe.** Any container, database, or volume that doesn't survive a host reboot is a regression. This is already implicit in Coolify's model (containers are restarted on host boot), but ADR-0015 makes it explicit: *do not rely on long-lived in-memory state.*
- **Docker daemon restarts mid-week.** When `docker-ce` is upgraded, the daemon restarts and every container blips. The blip is short (seconds) and falls inside Coolify's normal restart-policy behavior, but anything that holds external long-lived connections (webhooks, websockets) will see a disconnect.
- **No staging.** Patches land on the same VPS that serves traffic. This is acceptable for a playground; if a workload graduates to needing pre-prod testing, that workload (not the platform) takes on the burden of canary or blue-green strategy.

**What this does *not* automate:**
- Distribution upgrades (`do-release-upgrade`).
- Non-security pocket bumps.
- Coolify's own version (handled by Coolify's autoupdate setting, not apt).
- Restarting individual services that need a config reload (`needrestart` reports these but unattended-upgrades doesn't act on them outside the reboot).

## Alternatives considered

- **Status quo (manual via Coolify UI).** Rejected — relies on a human noticing the notification. Kernel patches accumulated for weeks under this model.
- **Auto-apply security patches, never auto-reboot.** Rejected — kernel patches without a reboot are theatrical; the unpatched kernel keeps running.
- **CI-driven scheduled job with approval gate (PR comment / Slack ping).** Rejected for the security-pocket case — too much friction for routine CVE patching. Remains the right pattern *if* a workload ever needs gated patching (escalation path: workload-local ADR overriding this one).
- **Add non-security pocket to allowed origins.** Rejected — too aggressive for a shared host. Non-security updates can introduce behavioral changes that aren't worth absorbing without a human in the loop.
- **Different reboot window per workload.** Rejected — single shared VPS; the reboot is the host's, not a workload's. 04:00 UTC matches typical European low-traffic hours (06:00 CEST).
