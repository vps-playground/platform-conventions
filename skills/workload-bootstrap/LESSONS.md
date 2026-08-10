# Hard-won lessons

Failures that reached a broken deploy on the VPS, and the checks that would
have caught them. **Read this before generating stack files.** Every entry cost
a debugging session; none of them are hypothetical.

Append to this file whenever a bootstrapped workload breaks in a way the
skeleton could have prevented. Keep entries symptom-first — the symptom is what
the next person will have in hand.

---

## Never bind-mount repo files into a container running as a non-root uid

**Symptom:** `ls: can't open '/docker-entrypoint-initdb.d/': Permission denied`,
repeated on every restart. Works perfectly on the developer's laptop.

**Cause:** Coolify clones the repo with ownership that the container's non-root
user (postgres is uid 999) cannot traverse. The mount is present and unreadable.

**Rule:** bake such files into an image and have a process that already runs
with the right identity apply them. For database bootstrapping, the migration
runner is that process — it connects as the owner and can be made idempotent,
which `/docker-entrypoint-initdb.d` cannot (that only ever runs against an
empty data directory, so any change needs hand-editing a live database).

## Everything the runtime CMD imports must be in `dependencies`

**Symptom:** logs show the app's own startup succeeding, then
`ERR_MODULE_NOT_FOUND`, then a restart loop. Traefik reports
`503 no available server` with nothing pointing at the cause.

**Cause:** a `--import` / `--require` preload copied from a sibling Dockerfile
without the sibling's `package.json` entries. The runtime stage installs
`--prod`, so a devDependency resolves locally and never in the image.

**Rule:** when reproducing a pattern from a sibling Dockerfile, copy the
dependency entries it relies on too. Generate a test that asserts every package
the CMD preloads is in `dependencies` — it is ~20 lines and catches the whole
class.

## Verify the CMD verbatim, never an approximation of it

Both bugs above survived a smoke test, because the smoke test ran
`node build/index.js` rather than the Dockerfile's actual `CMD` string. It
exercised every line except the broken one.

**Rule:** the final check runs the real `CMD`, in the real image, and asserts
`/healthz` answers from the running container. Structural greps ("does the
Dockerfile contain a HEALTHCHECK") verify that the contract is *written down*,
not that it *holds*.

## A generated skeleton that was never built is not known to work

Three toolchain breakages in one Node/SvelteKit run, none visible by reading:

- pnpm 10 denies build scripts by default, so `esbuild`'s postinstall is
  skipped and `vite build` fails. Name every package whose build script the
  stack needs in `onlyBuiltDependencies`.
- `onlyBuiltDependencies` moved from `package.json` to `pnpm-workspace.yaml`
  in pnpm 10; the old location is ignored with only a warning.
- Version-drift between a formatter and its plugin (prettier 3.9 vs
  prettier-plugin-svelte 3.5) crashes the lint gate outright.

**Rule:** end the skill by running the stack's own install, lint, test and
build, then report the results honestly. Caret ranges resolve to whatever is
current on the day, so this cannot be predicted from knowledge — only observed.

## `protected` workloads need three layers, not two

The post-render checklist ends at "deploy in Coolify → curl /healthz". For a
protected workload that is not enough to reach the app:

1. **Workload repo** — Traefik labels with `middlewares=authentik@file`, an
   auth-exempt `/healthz` router at higher priority, code reading
   `X-Authentik-*`. (The skill generates this.)
2. **`vps-playground/authentik` → `blueprints/<name>.yaml`** — Proxy Provider
   in `forward_single` mode + Application for that exact hostname. Copy the
   nearest sibling blueprint; a lowercase `sed` will miss the capitalised
   `name:` and the `meta_description`. Pushing this **redeploys Authentik and
   drops SSO platform-wide for about a minute.**
3. **Bind the Application to the embedded outpost** — Applications → Outposts →
   `authentik Embedded Outpost` → Edit → Applications → tick → Update.
   **Manual. A blueprint cannot append to the outpost's Application list
   without replacing it.**

Skip step 3 and the workload returns 404 from Authentik while being completely
healthy — `/healthz` answers 200, the container is up, the labels are right.

**Rule:** when identity model is `protected`, generate the blueprint (the skill
already knows the name and hostname) and end the checklist with the outpost
click called out as a required manual step.

## The diagnostic ladder belongs in every generated README

Three unrelated failures are indistinguishable from a browser:

| Symptom | Meaning |
|---|---|
| 404 with `x-powered-by: authentik` | Workload healthy; outpost binding missing |
| 503 `no available server` | Router registered, container down or crash-looping → `docker logs` |
| 404 plain `text/plain` | Traefik's default backend; no router matched at all |

Healthy protected workload: `/healthz` → `200 ok` unauthenticated, `/` → 302 to
Authentik. Those two requests prove the listener and the identity layer
separately — which is exactly why ADR-0002 and ADR-0013 have opposite auth
postures. A Let's Encrypt cert only issues after a route first resolves, so
`CN=TRAEFIK DEFAULT CERT` means nothing has routed successfully yet.

## Paths and questions the skill gets wrong

- Sibling references and `static.md` point at `~/Projects/private/<name>`;
  the workloads actually live in `~/Projects/private/vps-playground/<name>`.
- The persistence question offers only `none` / `volume:/data`, though
  `vps/docs/postgres.md` documents a real platform decision (Pattern A =
  Coolify Database resource, Pattern B = compose-bundled `db:`). Add
  `postgres` as an option and ask which pattern.
- Tenancy is never asked about, though it shapes the first migration and is
  near-impossible to retrofit. For anything `protected`, ask.
- A database kept correctly off the host makes local `just dev` impossible.
  Generate a `compose.dev.yml` overlay (explicit `-f`, never the auto-loaded
  `compose.override.yml`, port bound to `127.0.0.1`) plus `db-up` / `db-down` /
  `db-reset` recipes, and a `.env.example`.
- "Target dir non-empty → stop" breaks the normal docs-first workflow. Halt
  only when a file the skill would itself write already exists.
