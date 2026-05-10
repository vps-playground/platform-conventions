# ADR-0006: Edge stack — Cloudflare + Traefik + Cloudflare Access

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Workloads need a public hostname, valid TLS, and authentication for non-public surfaces — without each app reinventing auth code or each operator hand-rolling nginx + certbot. We also want to avoid exposing the VPS IP directly to the public internet.

A standard front-door recipe means any new workload gets the same posture for free.

## Decision

Default front-door stack for any internal-facing workload:

1. **DNS on Cloudflare with proxy ON** (orange cloud). The custom domain (`<app>.<zone>`) hides the VPS IP behind Cloudflare's edge. Coolify's auto-generated `*.sslip.io` URLs are *not* a long-term hostname — they embed the VPS IP in the hostname itself.
2. **TLS terminates twice.** Cloudflare presents the edge cert to the browser; Coolify's Traefik presents a Let's Encrypt cert to Cloudflare. End-to-end is Cloudflare's "Full (strict)" mode.
3. **Authentication via Cloudflare Access.** Self-hosted application protecting the domain. Identity providers: organisation IdP (e.g. Google Workspace, GitHub, Microsoft Entra) plus One-Time PIN as a fallback for users without an org account. Allow-list policy by email or domain suffix.
4. **VPS firewall.** Inbound 22 (SSH), 80 (LE HTTP-01 challenge), 443 (traffic). Everything else denied.
5. **In-app audit (optional).** Workloads that need per-user attribution read `Cf-Access-Authenticated-User-Email` from the request headers and validate the `Cf-Access-Jwt-Assertion` JWT against Cloudflare's JWKS before trusting it.

## Consequences

- Zero authentication code in any workload — Cloudflare Access handles login, sessions, MFA, password resets, and account lockout.
- The VPS IP is not in any public hostname; cold scans land on Cloudflare's edge.
- One stack to learn for every workload; the recipe is the same whether it's a static site, an API, or a full app.
- **Trade-off:** Cloudflare terminates TLS and authenticates users — workloads must accept Cloudflare in their trust boundary. Not appropriate for workloads with regulatory constraints that forbid edge TLS termination; those need a separate edge story.
- **Constraint:** the workload must not assume requests carry a session of its own; Access-protected requests are pre-authenticated by the edge.

## Alternatives considered

- **Cloudflare Tunnel (`cloudflared`) instead of Traefik exposure.** Closes ports 80/443 on the VPS entirely; pairs naturally with Access. Strong option but adds a tunnel daemon per workload (or a shared one). Coolify's Traefik plus the firewall already meets our needs at this scale; this ADR may be revisited if the VPS hosts more sensitive workloads.
- **In-app OAuth (Authlib, NextAuth, etc.).** Full control; cost is writing and maintaining auth, sessions, password reset, MFA. Not worth it for internal tools.
- **Tailscale or other mesh VPN.** Works for team-only tools where every user can install a client; bad for partners/stakeholders who can't.
- **Basic auth at Traefik.** Fine for one user; ungovernable past two.
- **No auth, hard-to-guess subdomain.** Leaks the moment any URL is shared, indexed, or linked. Not acceptable for any workload with non-public data.
