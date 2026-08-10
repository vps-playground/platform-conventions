# {{NAME}}

> One-line description goes here.

Deployed at **https://{{HOSTNAME}}/** (nip.io hex form per ADR-0012).

## Stack

{{STACK}}, containerized, deployed to the **vps-playground** VPS via Coolify.

## Local dev

```sh
just            # list recipes
just dev        # boot the local dev server
just test       # run the test suite
just preflight  # full pre-deploy gate (lint + test + build)
```

## Deploy

```sh
just deploy     # preflight + push main; Coolify auto-deploys
just healthz    # verify the deployed /healthz endpoint
```

Required env vars (set in Coolify's UI before first deploy):

| Variable | Purpose |
|---|---|
| _(none required for the default skeleton)_ | — |

## Identity model

**{{IDENTITY_MODEL}}.** See [`compose.yml`](compose.yml) for Traefik wiring.

- `public` → no auth gate; the workload is reachable directly.
- `protected` → every non-`/healthz` request goes through Authentik
  forward-auth per ADR-0011. The workload reads `X-Authentik-Username` and
  related headers from the proxied request — never run the auth flow itself.

## Healthcheck

`GET /healthz` returns `200 ok` (plain text) without touching DB / upstreams.
Auth-exempt at the Traefik layer (separate router with priority 100). See
ADR-0002 for the contract.

## When it looks broken

Three unrelated failures are indistinguishable from a browser. The response
tells you which one you have:

| Symptom | Meaning |
|---|---|
| 404 with `x-powered-by: authentik` | Workload is healthy; the Application is not bound to the embedded outpost |
| 503 `no available server` | Router registered but no backend — container down or crash-looping. `docker logs` |
| 404 plain, `content-type: text/plain` | Traefik's default backend; no router matched at all |

Healthy protected workload: `/healthz` → `200 ok` without credentials, `/` →
302 to Authentik. Those two requests prove the listener and the identity layer
separately. A Let's Encrypt cert only issues after a route first resolves, so
`CN=TRAEFIK DEFAULT CERT` means nothing has routed successfully yet.

## Conventions

This workload follows
[`vps-playground/platform-conventions`](https://github.com/vps-playground/platform-conventions).
Cross-cutting decisions live there as ADRs; workload-local code conventions
live in [`CLAUDE.md`](CLAUDE.md).
