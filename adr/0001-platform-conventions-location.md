# ADR-0001: Platform conventions repo location & consumption model

- **Status**: Accepted
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Multiple workloads will be deployed to the single vps-playground VPS over time. We need a single source of truth for cross-workload conventions (deployment, DB strategy, networking, observability, etc.) that:

1. Is readable by humans browsing on GitHub.
2. Is consumable by AI coding agents (Claude Code primarily, but should not lock us into a single agent ecosystem).
3. Allows easy contribution from any workload repo without heavy tooling.

## Decision

- Conventions live in a dedicated public GitHub repo: `vps-playground/platform-conventions`.
- Decisions are recorded as numbered ADRs under `adr/`.
- A single index file `CONVENTIONS.md` lists all ADRs in a stable, parseable structure.
- Workloads consume conventions via **WebFetch** of `raw.githubusercontent.com` URLs. **No** git submodules, **no** scripted sync, **no** enforcement workflows.
- Each workload's `CLAUDE.md` carries the snippet from `templates/workload-CLAUDE.md.snippet`, instructing agents to fetch the index before any deploy/infra/CI task.

## Consequences

- Workloads stay clean — no vendored convention copies, no submodule headaches, no CI-enforced gates that block unrelated work.
- Agents always read the latest accepted conventions; no staleness window.
- **Trade-off:** discoverability depends on each workload remembering to include the `CLAUDE.md` snippet. Forgetting it once means an agent operates blind on that workload.
- **Trade-off:** WebFetch is a per-call tool invocation; long sessions may re-fetch the index. Acceptable cost for a small index file.
- **Constraint:** public repo means conventions cannot reference secrets, internal hostnames, or sensitive topology. Operational notes of that kind stay in the private `vps-control-plane` repo.

## Alternatives considered

- **Inside `vps-control-plane`** (`docs/conventions/`): conflates infra-as-code with cross-workload policy; workloads pulling from "the infra repo" feels wrong.
- **Org `.github` repo**: designed for templates and health files, not a knowledge base.
- **Wiki / Notion / Confluence**: hostile to agent consumption without a scraper.
- **Git submodules**: reliable but adds sync friction in every workload.
- **Claude Code plugin/skill**: best agent UX but locks into Claude Code only; revisit if the corpus grows or a workload-creation flow stabilizes.
- **MCP server**: overkill for the current scale (single-VPS playground, expected <50 ADRs).
