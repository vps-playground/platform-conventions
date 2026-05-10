# ADR-0003: Trust the reverse proxy for client IP

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Coolify routes external traffic to workload containers through a Traefik reverse proxy. The original client IP is preserved in the `X-Forwarded-For` request header; the TCP-level peer address that the workload sees is Traefik's, not the user's.

By default, most HTTP frameworks distrust forwarded headers (correctly — they're trivially spoofable when there's no proxy in front of the app). When the workload runs without telling its framework to trust the proxy, two things go wrong:

1. **Per-IP rate-limiting collapses to a single bucket.** Every request looks like it came from Traefik, so the limiter throttles all users together.
2. **Access logs and audit trails record the proxy IP**, not the actual client.

The fix is uniform across stacks but the configuration knob name varies. Without a platform-level convention, each workload solves it differently (or not at all), and the rate-limiter regressions discovered in one workload's review get re-discovered in the next.

## Decision

Every HTTP workload behind Traefik must:

- **Trust `X-Forwarded-For`** as the source of the client IP.
- **Limit trust to the exact number of proxy hops** between the public internet and the workload. For the standard vps-playground deploy that's `1` (Traefik only). When a workload sits behind an additional CDN/edge proxy, the count goes up.
- **Document the trust depth** alongside the workload's deploy config (env file, Helm values, `Dockerfile`, whatever the workload uses) so it's auditable without code reading.

The framework-specific knob is workload-level — typical names by stack:

| Stack | Trust knob |
|---|---|
| Node.js, SvelteKit (`@sveltejs/adapter-node`) | `ADDRESS_HEADER=x-forwarded-for` + `XFF_DEPTH=<hops>` env vars |
| Node.js, Express | `app.set('trust proxy', <hops>)` |
| Python, Django | `USE_X_FORWARDED_HOST = True` + `SECURE_PROXY_SSL_HEADER` |
| Python, FastAPI/Starlette | `ProxyHeadersMiddleware(trusted_hosts="*")` (or specific) |
| Go, net/http | manual `r.Header.Get("X-Forwarded-For")` parsing with hop-count discipline |
| Rust, Axum | `axum-client-ip` extractor configured for the proxy chain |

## Consequences

- Per-IP rate-limiters, per-IP feature flags, audit logs, and abuse-detection signals all see the real client IP.
- Workload-level decisions that key off "the request's address" (eg. `getClientAddress()` in adapter-node, `req.ip` in Express, `request.client.host` in Starlette) are accurate.
- **Constraint:** the trust depth must be correct. Trusting more hops than exist allows IP spoofing — an attacker can prepend `X-Forwarded-For: <victim>, <real>` and the framework will read the leftmost, attacker-controlled value. Trusting fewer breaks rate-limiting silently.
- **Constraint:** any change to the proxy topology (adding a CDN, fronting with Cloudflare, splitting Traefik into edge+app tiers) must update every workload's trust depth. This is platform-level coordination — track in this repo as a separate ADR if topology changes.

## Alternatives considered

- **Trust `X-Forwarded-For` unconditionally** (`trust proxy: true`, `XFF_DEPTH=99`, etc.) — accepts arbitrary spoofing. Rejected.
- **Use the PROXY protocol** (TCP-level peer-address forwarding) — eliminates the spoofing class entirely, but most app frameworks don't speak it natively, and Traefik would need explicit configuration. Revisit if a workload has stricter requirements.
- **Skip it; accept that rate-limiting and logs use the proxy IP** — silently degrades a security control. Rejected.
- **Read `X-Forwarded-For` manually in each workload** — works, but the framework-native knob is tested and handles edge cases (multi-value headers, IPv6 brackets). Rejected as the default.
