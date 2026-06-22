# Project guide for Claude Code — {{NAME}}

## Platform conventions (vps-playground)

This workload deploys to the shared **vps-playground** VPS. Before any infra,
deploy, CI, or cross-cutting platform task, fetch the conventions index:

```
https://raw.githubusercontent.com/vps-playground/platform-conventions/main/CONVENTIONS.md
```

That index links to ADRs (Architecture Decision Records). Fetch the ADRs
relevant to the task. Conventions **override** workload-local choices unless
the deviation is explicitly justified in the PR or a workload-local ADR.

To propose a new convention or amend one: open a PR against
[`vps-playground/platform-conventions`](https://github.com/vps-playground/platform-conventions),
or run `/convention-uplift` from the session where the decision was made.

## Workload at a glance

- **Stack:** {{STACK}}
- **Identity model:** {{IDENTITY_MODEL}} (per ADR-0011)
- **Hostname:** `https://{{HOSTNAME}}/` (nip.io hex form, ADR-0012)
- **Healthcheck:** `GET /healthz` → `200 ok` (ADR-0002)
- **Container port:** {{PORT}}
- **Persistence:** {{PERSISTENCE}}

## The loop

```
branch → red test → green test → smoke → commit → PR → user approves → merge
```

Conventional commit prefixes with scope: `feat(...)`, `fix(...)`, `chore(...)`,
`docs(...)`. Don't merge without explicit user approval. PR body covers
Summary, What's in the box, Verification (test/build numbers), Test plan,
Out of scope.

## What "done" looks like

`just preflight` green: lint + test + typecheck + build. UI work also gets a
hand-driven browser smoke. Anything not verifiable locally (prod-only paths,
external services): say so out loud.

## Where things live

| Thing | Where |
|---|---|
| Platform contracts | `vps-playground/platform-conventions` (fetch the index) |
| Deploy + env vars | [`README.md`](README.md) |
| Compose + Traefik wiring | [`compose.yml`](compose.yml) |
| Container build | [`Dockerfile`](Dockerfile) |
| Task runner | [`Justfile`](Justfile) |
