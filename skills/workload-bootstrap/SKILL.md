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
| Rust + Leptos | `~/Projects/private/personal-site/Dockerfile`, `compose.yml` — first deployed rust-leptos workload; uses cargo-chef + BuildKit cache mounts + cargo-binstall for tooling |
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

## 2. Gather workload profile (open-ended, 2-4 sentences)

Before the structured questions, ask **one** free-text question:

```
In 2-4 sentences, describe what this workload does, who uses it, and what
its dominant content / traffic / integration profile looks like. Mention
anything unusual — high-traffic, SEO-critical, heavy background jobs,
external API calls (LLM, payment, OAuth), large static assets, real-time
sockets, etc. The skill uses this to make judgment calls below.
```

The response becomes the **workload profile** — a piece of context the
skill carries through every subsequent decision. Examples of judgments the
profile informs:

- **CI shape** — SEO-critical → add a `pnpm exec lighthouse` step;
  background jobs → mention a `worker:` service in the generated compose;
  LLM API calls → list the relevant env vars in README's required-env table.
- **Dockerfile tuning** — low-traffic content site → looser `HEALTHCHECK
  --interval=60s`; high-traffic → tighter `--interval=10s --timeout=2s`.
- **SSR vs. SPA preference** — SEO-critical → enforce SSR in the framework
  config and call it out in CLAUDE.md.
- **Required env vars in README** — pre-list slots for the integrations
  the user mentioned (Anthropic key, Stripe key, OAuth client id, etc.).
- **Persistent volume contents** — if the profile mentions "uploaded
  files" or "user-generated content" → suggest a `volume:` even if the
  user picked `none` on the structured question.
- **Compose extras** — background-jobs profile → propose a second service
  for the worker; real-time sockets → ensure Traefik websocket settings.

If the profile is thin ("just a personal site"), do not pad — accept the
default judgments and move on.

### Profile → stack recommendation

Before asking the user to pick a stack, **derive a recommended stack from
the profile** and present it as the first option. Heuristics (non-exhaustive,
use judgment):

| Profile signal | Suggested stack | Reasoning |
|---|---|---|
| Content-heavy + SEO-critical + low traffic (blog, CV, docs) | `rust-leptos` (SSR) or `static` | Server-rendered HTML, no SPA hydration cost; static if no dynamic data. |
| Real-time sockets, high concurrency | `rust` or `go` | Per-connection memory + GC behavior. |
| LLM API orchestration, heavy text processing | `python` | Native SDK coverage (anthropic, openai, …); ecosystem of NLP libs. |
| CRUD + form-heavy + moderate JS interactivity | `node` (SvelteKit/Next) | Fastest path for full-stack form flows. |
| Pure pre-built marketing/docs site | `static` | nginx-alpine, zero runtime. |
| Background jobs + queues + cron | `python` or `go` | Stronger native scheduler/queue libs than Node by default. |

Present the recommendation in the stack `AskUserQuestion` as the first
(Recommended) option, with a one-line reason citing the profile signal
that triggered it. The user can still override.

### Profile → stack-file generation

The profile is **the primary input** to step 5 (generate stack files),
alongside the platform ADRs. Carry it forward verbatim. Concrete effects on
the generated code:

- **SSR vs. SPA**: SEO-critical → enforce SSR in the framework config
  (Leptos `Mode::Ssr`, SvelteKit adapter-node with SSR enabled, Next
  with `output: 'standalone'` SSR).
- **Hydration strategy**: low-interactivity content site → islands /
  selective hydration over full-page hydration; flag this in the generated
  framework config.
- **Background workers**: profile mentions cron / queues → generate a
  second `worker:` service in `compose.yml` and a minimal entrypoint stub.
- **Sitemap / robots**: profile mentions SEO → add `/sitemap.xml` and
  `/robots.txt` route stubs in the runtime entrypoint.
- **Database / migration scaffolding**: profile mentions a DB → generate
  a `migrations/` dir scaffold and a `db:` recipe in the Justfile, with
  TODO markers (no actual schema).
- **Required env vars**: profile mentions LLM / Stripe / OAuth → list
  those env vars in `README.md`'s required-env table and reference them
  as `${...}` placeholders in `compose.yml`'s `environment:` block.

When in doubt about whether a profile signal warrants a code change,
surface the decision to the user as a small AskUserQuestion before
generating — do not silently change shape.

## 3. Gather structured choices

Use `AskUserQuestion` to capture the remaining choices in a single batch:

1. **Stack** — open-ended; first option is the profile-derived
   recommendation (above) with a one-line reason. Other options:
   `rust-leptos` / `node` / `python` / `static` / `go` plus "Other
   (describe)". For "Other", follow up with a short free-text question
   on build + runtime.
2. **Identity model** — `protected` (Authentik forward-auth, ADR-0011) /
   `public` (no auth gate; suitable for personal sites, public APIs).
3. **Persistence** — `none` (stateless) / `volume:/data` (named Docker
   volume mounted at `/data`, survives redeploys). The skill may suggest
   overriding this default based on the workload profile (e.g., "the
   profile mentions uploaded files; recommending `volume`").
4. **Container port** — number the runtime listens on. Suggest a sensible
   default per stack (3000 for Node/Rust, 8000 for Python, 80 for static).

5. **Subdomain label** — the left-most label of the public hostname.
   Defaults to the workload name (e.g. `seriendex.3eee17bc.nip.io`), but
   may differ when the public identity is not the project name. Personal
   sites are the canonical case: workload name `personal-site` but
   subdomain `a-grasso` → `a-grasso.3eee17bc.nip.io`. Always ask, with the
   workload name pre-filled as the default.

Compute and surface for confirmation:

- **VPS IP** — read from `~/Projects/private/vps/static.md` if present, else
  ask. Compute hex parent with `printf "%02x%02x%02x%02x\n" a b c d`.
- **Full hostname** — `<subdomain>.<hex>.nip.io` (ADR-0012).

## 4. Render platform-contract files

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
| `{{NAME}}` | workload name (kebab-case) — used for repo, Coolify app, Traefik router ids |
| `{{NAME_UNDERSCORE}}` | workload name with `-` → `_` |
| `{{SUBDOMAIN}}` | left-most label of the public hostname; defaults to `{{NAME}}` but may differ (e.g. `a-grasso` for a `personal-site` workload) |
| `{{PORT}}` | container port |
| `{{HEX_PARENT}}` | hex-encoded VPS IP parent, e.g. `3eee17bc.nip.io` |
| `{{HOSTNAME}}` | `{{SUBDOMAIN}}.{{HEX_PARENT}}` |
| `{{STACK}}` | stack label chosen by user |
| `{{PERSISTENCE}}` | `none` or `volume` |
| `{{IDENTITY_MODEL}}` | `protected` or `public` |
| `{{DATE}}` | today's absolute date in `YYYY-MM-DD` |

## 5. Generate stack-specific files

Inputs for this step:

- **The workload profile** from step 2 — feed it into every judgment call.
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

## 6. Post-render checklist

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

## 7. Sanity-check rendered output

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
