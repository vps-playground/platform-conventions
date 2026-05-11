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
