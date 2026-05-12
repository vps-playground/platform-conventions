# Platform conventions — index

Canonical conventions for workloads deployed to the **vps-playground** VPS.

> **Agents:** fetch this file first, then fetch the ADRs relevant to the current task.
> Conventions override workload-local choices unless an exception is explicitly justified.

## How to use this index

- Each row points to an ADR (Architecture Decision Record) under `adr/`.
- ADRs are immutable once **Accepted**; superseded by a new ADR that references the old one.
- Conventions are stored as raw markdown — fetch via `https://raw.githubusercontent.com/vps-playground/platform-conventions/main/<path>`.

## ADRs

| ID | Topic | Status | Summary |
|---|---|---|---|
| [0001](adr/0001-platform-conventions-location.md) | Conventions repo location & consumption model | Accepted | Conventions live in `vps-playground/platform-conventions`, consumed by WebFetch from each workload's `CLAUDE.md`. |
| [0002](adr/0002-healthcheck-endpoint.md) | Dedicated `/healthz` healthcheck endpoint | Proposed | Every workload exposes `/healthz` returning plain `200 ok`; Dockerfile `HEALTHCHECK` targets it. Auth-exempt. |
| [0012](adr/0012-nip-io-hex-hostnames.md) | No-domain hostnames via nip.io hex form | Proposed | When no registered domain exists, use `<sub>.<hex-ip>.nip.io`. Cookies scope to the IP-encoded parent; never set cookies with `Domain=nip.io`. |
| [0011](adr/0011-identity-aware-ingress.md) | Identity-aware ingress via Authentik forward-auth | Proposed | Protected workloads route through Traefik forward-auth → Authentik. Workload code reads `X-Authentik-*` headers; no app-level login flows. Per-host Provider + Application; group gating via Bindings tab. |
| [0014](adr/0014-admin-plane-tailscale.md) | Admin plane access via Tailscale tailnet | Proposed | SSH and Coolify UI reachable only over a private Tailscale tailnet (`vps-playground.ts.net`). Workload plane stays public per ADR-0011. Authentik IdP stays public (forward-auth requires it). Hetzner web console is the break-glass. |

## Where things live

The platform's source-of-truth is intentionally split across repos so each surface stays small and focused. If you're trying to find or change something, start here:

| Concern | Repo | Visibility | Notes |
|---|---|---|---|
| Cross-workload ADRs / policy | [`vps-playground/platform-conventions`](https://github.com/vps-playground/platform-conventions) | public | this repo |
| Host config, firewall, Ansible roles, secret topology | [`vps-playground/vps-control-plane`](https://github.com/vps-playground/vps-control-plane) | private | operational topology that public conventions reference but don't contain |
| Authentik deployment + per-workload identity blueprints | [`vps-playground/authentik`](https://github.com/vps-playground/authentik) | public | workload Provider/Application/policy bindings are **IaC** here, file-discovered by the worker (see ADR-0011 §2) |
| Per-workload code, Dockerfile, compose, app-level docs | the workload's own repo | varies | workload-local concerns only |
| Live operational state (postgres data, Authentik sessions, applied blueprints, group memberships) | the VPS itself | not in git by design | covered by backups, not by convention |

The split follows ADR-0001's "public for shape/policy/structure, private for sensitive topology" boundary. New repos should fit cleanly into one of these slots before being added; if they don't, that's a signal the boundary needs an ADR amendment.

## Status values

- **Proposed** — open for discussion in a PR; not yet binding.
- **Accepted** — current standard; workloads must comply or justify deviation.
- **Superseded by ADR-NNNN** — replaced; kept for history.
- **Deprecated** — no longer applies; no replacement.

## Workload integration

Each workload repo should include the snippet from [`templates/workload-CLAUDE.md.snippet`](templates/workload-CLAUDE.md.snippet) at the top of its `CLAUDE.md`.

## Contributing

Manual flow:

1. Copy `adr/ADR-template.md` → `adr/NNNN-short-title.md` with the next available number.
2. Fill it in. Keep ADRs small and focused — one decision per ADR.
3. Open a PR. Discussion happens on the PR.
4. On merge, update this index table.

Or run the Claude Code skill `/convention-uplift` from the session where the decision was made — it drafts the ADR from session context, opens the PR, and updates this index in the same branch. Install once with `just install` after cloning this repo. See [`skills/convention-uplift/SKILL.md`](skills/convention-uplift/SKILL.md).
