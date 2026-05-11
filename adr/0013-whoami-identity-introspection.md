# ADR-0013: Identity introspection via `/whoami`

- **Status**: Proposed
- **Date**: 2026-05-11
- **Decided by**: @a-grasso

## Context

[ADR-0011](0011-identity-aware-ingress.md) lands identity at the workload as a set of trusted HTTP headers — `X-Authentik-Uid`, `-Username`, `-Email`, `-Groups`, optionally `-Jwt`. Workloads are expected to read these and never re-validate.

In practice this creates an operational gap. Three concrete cases keep appearing across workloads:

1. **Diagnosing "every request 401s after deploy"** — is the Traefik forward-auth middleware applied? Is the embedded outpost binding active? Did the Authentik Brand domain match? Without a way to introspect what the workload actually received, the only tools are `journalctl` on Traefik, the Authentik Tasks view, or sprinkling `console.log(request.headers)` into application code.
2. **Bootstrapping per-user state from the CLI/API** — workloads sometimes need the operator's stable UID (eg. to attribute legacy data, to seed an admin group). Reading it from Authentik's UI works but is fiddly; reading it from the workload directly with one `curl` is much easier.
3. **Verifying a deploy end-to-end** — `/healthz` proves the listener is up, but not that auth is wired. A second endpoint that exercises the auth path proves both at once.

Per-workload bespoke debug endpoints diverge fast. Standardizing the path, response shape, and auth posture means a single `curl` works against every workload on the platform.

## Decision

Every workload that consumes identity from forward-auth (ADR-0011) **exposes a `/whoami` route** that:

- Returns HTTP `200` with `Content-Type: application/json`.
- Body is a JSON object with the stable shape:

  ```json
  {
    "uid": "<X-Authentik-Uid>",
    "username": "<X-Authentik-Username>",
    "email": "<X-Authentik-Email or null>",
    "groups": ["<group>", "..."]
  }
  ```

  Fields:
  - `uid` (string, required) — the value of `X-Authentik-Uid`. This is the canonical tenant identifier from ADR-0011 §"Workload contract".
  - `username` (string, required) — the value of `X-Authentik-Username`, or `uid` as the fallback when absent.
  - `email` (string | null, required) — the value of `X-Authentik-Email`, or `null` when the upstream IdP did not verify.
  - `groups` (string[], required) — parsed from `X-Authentik-Groups` by splitting on `|` and trimming. Empty array when the header is absent or empty.

- **Is subject to the workload's normal auth gate.** No special bypass. The hook resolves identity, runs its rate-limit + auth checks, and only then renders `/whoami`. Unauthenticated access is the same `401` every other gated route returns. Asymmetry vs `/healthz` is intentional — `/healthz` proves the listener; `/whoami` proves the identity layer.

- **Returns no fields the workload was not given by the trusted headers.** Workloads must not enrich `/whoami` with internal DB lookups, role flags computed from authorization logic, or per-tenant counts. The endpoint is a passthrough mirror of the forward-auth contract, not a profile API.

## Consequences

- A single `curl -i https://<workload>/whoami` confirms both that the listener is up AND that forward-auth is correctly injecting headers. Compared to the previous "tail Traefik logs" workflow, this is one round-trip and works from anywhere.
- Bootstrapping workflows (eg. "assign these legacy rows to my UID", "what group am I in") can read identity from any workload uniformly.
- Operators have a stable, predictable name to point at. No remembering each workload's bespoke `/debug/me` or `/api/v1/profile/self`.
- **Constraint:** workloads must keep `/whoami` aligned with whatever identity they expose downstream. If a workload starts trusting additional `X-Authentik-*` headers (eg. `-Jwt`), they should appear in `/whoami` too — otherwise the endpoint lies.
- **Constraint:** `/whoami` carries the user's email and group membership. The same auth gate that protects the rest of the workload protects this endpoint. Workloads that don't want their group list visible to authenticated peers (eg. shared-tenancy apps where users share a session realm but not data) must either restrict `/whoami` to a stricter group or omit `groups` from the response. Either deviation is a workload-local ADR.
- **Trade-off:** the endpoint is not standardized as part of the Authentik proxy itself (eg. as a built-in `/outpost.goauthentik.io/userinfo` mirror). That would centralize ownership but couple every workload to outpost behavior across Authentik upgrades. Per-workload implementation costs ~10 lines and keeps the introspection contract under workload control.

## Alternatives considered

- **Per-workload bespoke debug endpoints** (`/api/me`, `/debug/identity`, etc.) — what we have today by default. Diverges across workloads; a single operator can't write one diagnostic script that works against multiple workloads. Rejected.
- **Custom response header** (`X-Authentik-Echo: <json>`) — possible, but harder to inspect with standard tooling (browsers strip non-standard response headers from devtools display; `curl -i` shows them but JSON-in-header is painful to grep). Rejected.
- **Log-only** — workloads write resolved identity to a `console.log` on first request. Doesn't help live debugging from a laptop; requires shell access to the container. Rejected.
- **Authentik's own `/outpost.goauthentik.io/userinfo`** — exists at the outpost layer and works for some auth flows. It's a different surface (couples to outpost upgrades, returns Authentik-shaped data rather than what the workload actually trusts) and isn't reliably present in the forward-auth single-application mode chosen by ADR-0011. Out of scope; not in tension with this ADR.
- **Auth-exempt `/whoami`** — would mirror `/healthz`'s public posture. Rejected: an exempt `/whoami` returns no useful data (no identity headers, so all fields would be null/empty) and gives an unauthenticated probe a free, fingerprint-able platform-version signal. Gated `/whoami` is more useful and less leaky.
- **Combined `/healthz` that also returns identity** — conflates two unrelated probes. The platform's healthcheck path (ADR-0002) must answer unauthenticated for orchestrator probes; identity introspection inherently requires auth. Different audiences, different posture — keep them separate.
