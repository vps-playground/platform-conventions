---
name: workload-bootstrap
description: "Scaffold a new workload repo targeting the vps-playground VPS. Renders the platform-contract files (compose.yml with Traefik labels + nip.io hostname per ADR-0012, healthz routing per ADR-0002, CLAUDE.md, Justfile, README, gitignores) from static templates, then generates the stack-specific files (Dockerfile + buildfile + minimal /healthz handler) using LLM knowledge of the chosen stack, constrained by the platform ADRs and a verified sibling workload as reference. User-invoked only — never auto-trigger."
argument-hint: "[optional target dir, e.g. ~/Projects/private/my-workload]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - AskUserQuestion
---


<objective>
Render a complete, convention-compliant skeleton for a new workload deploying
to the **vps-playground** VPS. After this skill exits, the target directory
contains everything needed to `git init && git push && let Coolify deploy`.

The skeleton is split into two layers:

1. **Platform contract** — static templates under `templates/_common/`,
   rendered via token substitution. These encode the cross-workload conventions
   (Traefik labels, nip.io hostname, healthz routing, the CLAUDE.md snippet,
   Justfile shape). They are stable, deterministic, and should not vary by stack.

2. **Stack-specific code** — `Dockerfile`, the language's buildfile (e.g.
   `Cargo.toml`, `package.json`, `pyproject.toml`), and a minimal `/healthz`
   handler. The skill **generates** these from LLM knowledge of the stack,
   constrained by the platform ADRs and (when one exists) a verified sibling
   workload's Dockerfile as a reference. This avoids the maintenance debt of
   static per-stack templates that go stale every time a runtime or
   build-tool conventions move.

Selectivity is the success metric: ask only what cannot be inferred. Provide
sensible defaults for everything else.
</objective>

<scope>
**In scope:** the structural skeleton — platform-contract files plus
generated stack files (Dockerfile + buildfile + minimal healthz handler).

**Out of scope:** business-logic code; auth wiring inside the app (workloads
consume `X-Authentik-*` headers per ADR-0011 §3 — generating the consumer
code is workload-specific and not part of bootstrap); database migration
tooling; secrets management; CI beyond a tiny skeleton.
</scope>

<stack_inference>
The skill is stack-agnostic. Common stacks the LLM should already know how to
render idiomatically:

- Rust + Leptos (cargo-leptos, SSR + hydration)
- Node + pnpm + SvelteKit / Next / plain HTTP server
- Python + uv + uvicorn (FastAPI / Starlette / plain ASGI)
- Static site (built artifacts served by nginx-alpine)
- Go + chi/echo/stdlib net/http

Any stack the LLM cannot generate confidently → ask the user to describe the
build/runtime model first, then proceed.

**Verified sibling references** (read on demand, do not duplicate logic):

| Stack | Sibling reference (read for verified patterns) |
|---|---|
| Node 22 + pnpm + SvelteKit | `~/Projects/private/seriendex/Dockerfile`, `compose.yml` |
| Python 3.13 + uv + FastAPI | `~/Projects/private/solar-panel-leads/Dockerfile`, `docker-compose.yaml` |
| Rust + Leptos | _no sibling yet — first one will become the reference_ |
| Static (nginx) | _no sibling yet_ |

When a sibling exists, **read its Dockerfile and compose.yml before generating
the new workload's**. Sibling files capture hard-won lessons (e.g.,
`pnpm.onlyBuiltDependencies` native-binding check; adapter-node trust-proxy
env vars; uv lockfile caching). Reproduce those patterns; only deviate when
the new workload's needs differ.

When no sibling exists, generate from general best practices but add a
comment in the Dockerfile noting: "First {{STACK}} workload on this platform —
revisit conventions once a second {{STACK}} workload exists."
</stack_inference>

<process>

## 1. Resolve target dir

If `$ARGUMENTS` is non-empty and looks like a path, treat it as the target dir.
Otherwise ask:

```
What is the workload name? (kebab-case, used for repo + subdomain)
```

Default target dir: `~/Projects/private/<name>` (matches sibling workloads).
Confirm with the user.

If the target dir exists and is non-empty: **stop** and report. Do not
overwrite.

## 2. Gather inputs

Use `AskUserQuestion` to capture the remaining choices in a single batch:

1. **Stack** — open-ended; suggest `rust-leptos` / `node` / `python` /
   `static` / `go` plus "Other (describe)". For "Other", follow up with a
   short free-text question on build + runtime.
2. **Identity model** — `protected` (Authentik forward-auth, ADR-0011) /
   `public` (no auth gate; suitable for personal sites, public APIs).
3. **Persistence** — `none` (stateless) / `volume:/data` (named Docker
   volume mounted at `/data`, survives redeploys).
4. **Container port** — number the runtime listens on. Suggest a sensible
   default per stack (3000 for Node/Rust, 8000 for Python, 80 for static).

Compute and surface for confirmation:

- **VPS IP** — read from `~/Projects/private/vps/static.md` if present, else
  ask. Compute hex parent with `printf "%02x%02x%02x%02x\n" a b c d`.
- **Full hostname** — `<name>.<hex>.nip.io` (ADR-0012).

## 3. Render platform-contract files

Templates under `templates/_common/`:

- `CLAUDE.md.tpl`
- `Justfile.tpl`
- `README.md.tpl`
- `.gitignore.tpl`
- `.dockerignore.tpl`
- `compose.public.yml.tpl` **OR** `compose.protected.yml.tpl` (pick one)
- `.github/workflows/ci.yml.tpl`

Render order: all `_common/` templates → token substitution → write into the
target dir (drop the `.tpl` suffix). The persistence `volumes:` block is
appended to `compose.yml` only when `PERSISTENCE=volume`.

### Tokens

| Token | Source |
|---|---|
| `{{NAME}}` | workload name (kebab-case) |
| `{{NAME_UNDERSCORE}}` | workload name with `-` → `_` |
| `{{PORT}}` | container port |
| `{{HEX_PARENT}}` | hex-encoded VPS IP parent, e.g. `3eee17bc.nip.io` |
| `{{HOSTNAME}}` | `{{NAME}}.{{HEX_PARENT}}` |
| `{{STACK}}` | stack label chosen by user |
| `{{PERSISTENCE}}` | `none` or `volume` |
| `{{IDENTITY_MODEL}}` | `protected` or `public` |
| `{{DATE}}` | today's absolute date in `YYYY-MM-DD` |

## 4. Generate stack-specific files

Inputs for this step:

- The platform ADRs (the skill **must fetch** ADR-0002 — `/healthz` contract —
  and read it before generating the runtime entrypoint).
- The chosen stack.
- The sibling reference Dockerfile if one exists (`<stack_inference>` table).

Files to generate (write directly; do not surface as templates):

- `Dockerfile` — multi-stage, non-root, `EXPOSE {{PORT}}`, `HEALTHCHECK`
  targeting `http://127.0.0.1:{{PORT}}/healthz`. Cache the dep-install layer.
- The language's buildfile (`Cargo.toml`, `package.json`, `pyproject.toml`, …).
- The minimum source files needed to: (a) start the runtime, (b) respond
  `200 ok` (plain text) at `GET /healthz`. Nothing else.

For each generated file, **show the user the proposed content via the
Read-then-Write sequence is unnecessary** — write directly, then list the
files. The user reviews via the post-run checklist below; corrections happen
in the next session if needed.

### Generation guardrails

- **Non-root user.** Every Dockerfile must `USER` to a non-root account
  before `CMD`.
- **Trust-proxy env vars** when the stack's HTTP server needs them (e.g.
  Node `adapter-node` requires `ADDRESS_HEADER=x-forwarded-for` +
  `XFF_DEPTH=1`; uvicorn needs `--proxy-headers --forwarded-allow-ips '*'`).
- **No DB pings in `/healthz`** (ADR-0002). It returns `200 ok`
  unconditionally.
- **Dockerfile and `compose.yml` env defaults must agree.** When the
  Dockerfile sets `ENV PORT=3000`, the compose `environment:` block lists
  the same value verbatim so Coolify's UI surfaces it.

## 5. Post-render checklist

Print:

```
✓ Workload scaffolded at <target-dir>.

Next steps (do NOT run automatically):

  1. cd <target-dir>
  2. Review Dockerfile, compose.yml, and the generated /healthz handler.
  3. git init && git add -A && git commit -m "feat: scaffold {{NAME}} workload"
  4. gh repo create <owner>/{{NAME}} --private --source=. --remote=origin --push
  5. In Coolify: "Docker Compose" application → point at the new GitHub repo
     → set required env vars (see README.md) → deploy.
  6. After first deploy: curl -fsS https://{{HOSTNAME}}/healthz   # → "ok"
```

## 6. Sanity-check rendered output

Before exiting, verify:

- `Dockerfile` contains a `HEALTHCHECK` targeting `/healthz`.
- `compose.yml` references `{{HOSTNAME}}` and includes the healthz exemption
  router at priority 100.
- `CLAUDE.md` starts with the platform-conventions snippet.
- The runtime entrypoint registers a `/healthz` route returning `200 ok`.

Report any failure as a skill bug, with the path of the offending file.

</process>

<failure_modes>

- **Target dir is non-empty** → stop. Tell the user. Do not overwrite.
- **No VPS IP available** → if `~/Projects/private/vps/static.md` is missing
  and the user has no IP to provide, fall back to the example `62.238.23.188`
  (`3eee17bc.nip.io`) and **warn loudly** that the rendered `compose.yml`
  will need editing before first deploy.
- **Stack the LLM cannot confidently render** → stop and ask the user to
  describe the build + runtime model in 2–3 sentences before proceeding.
- **AskUserQuestion cancelled** → exit cleanly. No files are written until
  every input is resolved.
- **Sibling reference path doesn't exist locally** → proceed without it; note
  in the Dockerfile comment that the conventional pattern was derived from
  general knowledge rather than a verified sibling.

</failure_modes>

<non_goals>

- **Not a Coolify-application creator.** The skill scaffolds the repo;
  Coolify's UI still owns the per-environment env vars and the application
  itself.
- **Not a CI bootstrapper beyond a skeleton.** Workload-specific CI is
  out of scope.
- **Not an authentication implementer.** Protected workloads consume
  `X-Authentik-*` headers per ADR-0011 §3 — that wiring is per-stack and
  out of scope here.
- **Does not auto-trigger.** User-invoked only.

</non_goals>
