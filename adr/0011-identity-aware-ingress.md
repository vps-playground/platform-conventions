# ADR-0011: Identity-aware ingress via Authentik forward-auth

- **Status**: Proposed
- **Date**: 2026-05-11
- **Decided by**: @a-grasso

## Context

Workloads on the vps-playground VPS span four access shapes:

| Shape | Examples | Who can reach it |
|---|---|---|
| **Public** | marketing pages, status pages | anyone, unauthenticated |
| **Authenticated** | small-team internal apps | any user known to the platform |
| **Admin-only** | ops dashboards, single-user tools | members of a named group |
| **Multi-tenant** | customer-facing apps with per-user data | any signed-in user; app filters data by user identity |

Doing authn/authz per-workload is the wild west: every service reinvents login, sessions, MFA, password reset, OAuth callbacks. The result is inconsistent rules, forgotten admin routes, drift across services, and a fan-out of auth code that has to be re-audited every time a workload is added or updated.

Workloads on this platform deploy via Coolify (Docker Compose) behind Coolify's bundled Traefik. We want **authentication to be platform infrastructure**, not per-workload application code.

## Decision

Use [Authentik](https://goauthentik.io/) as the platform identity provider, integrated via **Traefik forward-auth**. Every protected workload routes through a single forward-auth middleware that delegates each request to Authentik; on success, identity arrives at the workload as trusted HTTP headers; on failure, Authentik handles the login flow.

### Components

- **Authentik** runs as a Coolify-deployed Docker Compose application (see [`vps-playground/authentik`](https://github.com/vps-playground/authentik)). The embedded outpost in the `server` container serves the forward-auth endpoint at `/outpost.goauthentik.io/auth/traefik`.
- **Traefik file-provider dynamic config** defines two reusable middlewares — `authentik@file` (forward-auth) and `redirect-to-https@file` — managed by the `coolify_proxy_dynamic` Ansible role in [`vps-control-plane`](https://github.com/vps-playground/vps-control-plane).
- **External IdPs** (Google, Microsoft Entra, GitHub) federate into Authentik when the platform graduates beyond local users.

### Workload contract

Per protected workload:

1. **Compose file** (in the workload's repo) carries the full Traefik label set — host rule, HTTPS entrypoint, TLS cert resolver, port, and `middlewares=authentik@file`. Coolify Domain field per service is **left empty**; routing is workload-owned.

2. **Authentik configuration** — one **Proxy Provider** in *forward auth (single application)* mode (`external_host` = the workload's HTTPS URL), one **Application** referencing that Provider, bound to the embedded outpost. Provision via the blueprint template in [`vps-playground/authentik/blueprints/`](https://github.com/vps-playground/authentik/tree/main/blueprints).

3. **Per-host authorization** (when needed) is configured on the Application's **Bindings** tab — for example, a Group binding requiring membership in `admins`. The Bindings tab is the enforcement contract; nothing else.

4. **Workload code** reads identity from trusted headers, never re-validates credentials:

   | Header | Purpose |
   |---|---|
   | `X-Authentik-Uid` | Stable cryptographic identifier — **use for FK relations / tenant scoping** |
   | `X-Authentik-Username` | Display name; user-renameable, **not stable** |
   | `X-Authentik-Email` | Verified email when the upstream IdP verifies it |
   | `X-Authentik-Groups` | Pipe-separated group names, e.g. `"authentik Admins\|admins\|editors"` |
   | `X-Authentik-Jwt` | Signed JWT for service-to-service propagation when needed |

5. **Auth-exempt paths** (`/healthz`, `/.well-known/acme-challenge/`, etc.) get a second Traefik router with **higher priority**, matching only the exempt path, without the middleware label. Example:

   ```yaml
   # Protected default
   - "traefik.http.routers.app.rule=Host(`app.example.com`)"
   - traefik.http.routers.app.middlewares=authentik@file
   - traefik.http.routers.app.priority=10
   # Exempt /healthz
   - "traefik.http.routers.app-healthz.rule=Host(`app.example.com`) && Path(`/healthz`)"
   - traefik.http.routers.app-healthz.priority=100
   # no middleware → no auth
   ```

6. **Local development** — workload code falls back to a hardcoded dev identity only when `DEV_MODE=true`; otherwise the absence of identity headers is a hard 401. This protects against accidentally deploying a workload without forward-auth in place.

7. **Logout**. The Authentik session lives in a central cookie on the auth host (e.g. `auth.3eee17bc.nip.io`), not a per-workload cookie. Workloads expose a logout affordance (link or route) pointing at `/outpost.goauthentik.io/sign_out` on **their own hostname** — the embedded outpost intercepts that path on every protected hostname, invalidates the central session, and redirects to a post-logout page. Sign-out is therefore **platform-wide**: ending the session from one workload signs the user out of every workload protected by the same outpost. That matches the SSO model and is almost always what you want; workloads needing a local-only logout would have to mint and manage their own session cookie alongside Authentik's, outside this convention.

### Ownership

Platform owns identity infrastructure (Authentik deployment, Traefik middlewares, brand, outpost). Workload owns its image, its routing posture (labels in compose), and its row-level authorization (filtering by `X-Authentik-Uid` in code). Coolify owns runtime substrate.

## Consequences

**Upsides:**

- One identity system, one MFA system, one SSO session, one audit trail.
- Workloads carry zero auth code for the common case; adding a new workload doesn't add new login flows, OAuth callbacks, or password storage.
- Per-workload access policies live in Authentik UI where ops can see and audit them, not buried in application source.
- Federating to Google/Microsoft/GitHub later is a Provider-side change; workloads notice nothing.
- SSO across workloads works via Authentik's central session cookie on the auth host — single-app Provider mode gates per-host without sacrificing single sign-on.

**Trade-offs:**

- **Workload compose files contain Traefik labels.** We tested alternatives (Coolify-provided custom-label fields, `${COOLIFY_RESOURCE_UUID}` magic-var substitution in labels, file-provider routers with `traefik.enable=false`). Coolify magic vars don't substitute in `labels:` blocks — verified empirically. Coolify's documented "Raw Docker Compose Deployment" mode (workload owns full Traefik labels, Domain field left empty) is the supported path; nothing cleaner is available without inviting per-instance UUID leakage into workload repos.
- **Per-workload Authentik setup is ~3 minutes of UI clicks** (or one blueprint apply): Provider + Application + outpost binding + optional group binding. Acceptable for the spike's scale; revisit if it becomes friction.
- **Authentik is a critical-path dependency** for protected workloads. If Authentik is down, login redirects fail and protected workloads are unreachable. Mitigation today: Authentik runs on the same host as the workloads; if the host is up, both are up. High availability is a follow-up.
- **The Coolify control plane stays on its own login.** Putting Coolify behind Authentik would create a chicken-and-egg dependency — Coolify is what deploys Authentik. Operator access to the Coolify UI is via SSH tunnel; identity-aware ingress applies only to tenant workloads.

**Footguns to know:**

- **`authentik Admins` is the superuser group, but does NOT implicitly bypass Application-level policy bindings.** Members get Authentik UI admin rights only; they're subject to per-Application group bindings like any other user, and will hit "Request has been denied — Policy binding 'None' returned result 'False'" on workloads they aren't explicitly a member of. Reserve `authentik Admins` for platform-operator UI access; **never use it as a workload authz signal**, and add operators to per-workload groups explicitly when they need workload access. If you do want platform-operator bypass on a specific Application, bind an Expression Policy `return request.user.is_superuser` with `order: 0` and rely on `policy_engine_mode: any` — opt-in per workload, not implicit.
- **Group changes don't propagate to active sessions.** A user kept-in/removed-from a group sees the old set until they log out and back in. Kill sessions via Directory → Users → Sessions to force re-evaluation.
- **The Brand domain must match the parent hostname.** Without it, the outpost can't determine which brand a request belongs to and forward-auth fails with a "domain not configured" warning.
- **The Application form's "Groups" field is metadata, not authz.** Use the **Bindings** tab on the Application detail view to create policy bindings.
- **Direct container access bypasses Traefik entirely.** Anyone with Docker access on the VPS (or another container on the same Docker network) can reach the workload without auth headers. Workloads must treat missing identity headers as 401, not as "trusted internal traffic".
- **Coolify Domain field per service must stay empty** for workloads owning their Traefik labels — otherwise Coolify generates a parallel auto-router that conflicts with the compose-defined one.
- **Outpost re-evaluation lag.** Adding an Application to the embedded outpost takes a few seconds to propagate to the runtime; cache up to 30 seconds.

## Alternatives considered

- **Per-app OIDC** — every workload runs the OAuth flow itself against Authentik. Right shape for non-browser / cross-org clients; we keep the option open for those. For browser-driven workloads on a single platform it's strictly more code and more drift than forward-auth. Rejected as the default.
- **Authentik's "Forward auth (domain level)" mode** — one Provider serves an entire domain via the central host. Documented trade-off (verbatim from Authentik docs): "in [domain] mode you can't restrict individual applications to different users". We need per-host group gating, so single-application mode per workload is the right pick. SSO is preserved by Authentik's central session cookie on the auth host, not by a shared forward-auth cookie.
- **Authelia / Keycloak / Pomerium** — Authelia has a thinner policy DSL than we need for the multi-tenant case. Keycloak is heavier in ops cost and worse UX. Pomerium leans toward zero-trust-network shapes we don't have today.
- **Coolify's per-service Custom Labels UI with magic variables** — `${COOLIFY_RESOURCE_UUID}` doesn't substitute in compose `labels:` blocks per Coolify's docs and verified empirically. Coolify magic vars apply only to `environment:` blocks.
- **Hardcoding the Coolify-generated router UUID in compose labels** — works on one Coolify install but leaks per-instance identifiers into workload repos. Not portable. Rejected.
- **Skipping forward-auth and relying on app-level OIDC libraries** — punts identity into every workload's code path. The whole point of the convention is to remove that surface.
