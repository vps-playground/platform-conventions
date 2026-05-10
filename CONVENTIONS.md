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
| [0004](adr/0004-constant-time-secret-compare.md) | Constant-time comparison for secrets | Proposed | Compare secrets with the stack's standard primitive (`crypto.timingSafeEqual`, `hmac.compare_digest`, `subtle.ConstantTimeCompare`). HMAC-normalize when length is sensitive. |

## Status values

- **Proposed** — open for discussion in a PR; not yet binding.
- **Accepted** — current standard; workloads must comply or justify deviation.
- **Superseded by ADR-NNNN** — replaced; kept for history.
- **Deprecated** — no longer applies; no replacement.

## Workload integration

Each workload repo should include the snippet from [`templates/workload-CLAUDE.md.snippet`](templates/workload-CLAUDE.md.snippet) at the top of its `CLAUDE.md`.

## Contributing

1. Copy `adr/ADR-template.md` → `adr/NNNN-short-title.md` with the next available number.
2. Fill it in. Keep ADRs small and focused — one decision per ADR.
3. Open a PR. Discussion happens on the PR.
4. On merge, update this index table.
