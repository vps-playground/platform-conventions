# ADR-0006: Front-door defaults — auth, origin concealment, firewall

- **Status**: Proposed
- **Date**: 2026-05-10
- **Decided by**: @a-grasso

## Context

Coolify ([ADR-0005](0005-coolify-resource-configuration.md)) already gives every workload three things for free:

- A public hostname (auto-generated `*.sslip.io`, plus support for any custom domain).
- A valid Let's Encrypt TLS cert via Traefik.
- Routing from the public port to the container.

This ADR is **not** about any of those — they're settled by adopting Coolify.

What Coolify does **not** decide for us, and what this ADR settles platform-wide, is three things:

1. **Authentication for internal-facing surfaces.** Coolify routes traffic but does not authenticate users. Without a platform answer, each workload either writes its own login flow or ships unauthenticated.
2. **Origin IP concealment.** A direct A record to the VPS, or the default `sslip.io` hostname (which embeds the IP literally), exposes the box to anyone with `dig`. Direct-IP attacks land on the host rather than a proxy.
3. **Host-level inbound port policy.** Coolify configures Docker networking; the host firewall is a separate decision that needs a platform default.

## Decision

Default front-door for any internal-facing workload:

1. **Authentication via Cloudflare Access.** Self-hosted application protecting the workload's hostname. Identity providers: the organisation IdP (Google Workspace, GitHub, Microsoft Entra, …) plus One-Time PIN as a fallback for users without an org account. Allow-list policy by email or domain suffix. Workloads add **zero** auth code.
2. **Origin IP concealment via Cloudflare proxy.** The workload's domain is on Cloudflare with the proxy enabled (orange cloud). Public traffic terminates at Cloudflare's edge; the VPS IP is not in any public hostname. Coolify's Traefik continues to handle Let's Encrypt at the origin, so end-to-end the connection is Cloudflare's "Full (strict)" mode.
3. **Host firewall policy.** Inbound 22 (SSH), 80 (LE HTTP-01 challenge), 443 (traffic). Everything else denied by default at the VPS firewall (`ufw` or equivalent).
4. **Optional in-app audit.** Workloads that need per-user attribution read `Cf-Access-Authenticated-User-Email` from request headers and validate `Cf-Access-Jwt-Assertion` against Cloudflare's JWKS before trusting it.

## Costs and limits

Verified against Cloudflare's plan pages on 2026-05-10. Cloudflare can change these terms; revisit annually.

- **Cloudflare proxy / CDN — free plan.** Free for unlimited domains. The [Service-Specific Terms](https://www.cloudflare.com/service-specific-terms-application-services/) reserve Cloudflare's right to limit access if a workload serves "video or a disproportionate percentage of pictures, audio files, or other large files" through the free CDN; Cloudflare commits to attempting notification first. For HTML + small thumbnails this is a non-issue.
- **Cloudflare Access — free plan.** No hard user cap. Cloudflare recommends the free plan "for teams under 50 users or enterprise proof-of-concept tests"; beyond that, pay-as-you-go is **$7 per user per month** (annual billing). At our playground scale this stays in the free tier.
- **Cloudflare Tunnel.** Included in Zero Trust at no separate charge. Not part of this ADR's decision (we use CF proxy + Traefik instead) but available as a fallback path — see *Alternatives considered*.
- **Coolify, Let's Encrypt, the VPS firewall (`ufw`).** Free.

**Net:** the entire front-door stack is $0/month while the user count stays under ~50, with one well-defined upgrade trigger ($7/user/mo on Access) if we ever cross it.

## Consequences

- Zero authentication code per workload — Cloudflare Access handles login, sessions, MFA, password resets, and account lockout.
- The VPS IP is not in any public hostname; cold scans land on Cloudflare's edge.
- The host firewall is one decision per VPS, not per workload.
- **Trade-off:** Cloudflare terminates TLS at the edge and authenticates users — workloads must accept Cloudflare in their trust boundary. Not appropriate for workloads under regulatory constraints that forbid edge TLS termination; those need a separate edge story.
- **Constraint:** workloads must not assume requests carry a session of their own; Access-protected requests are pre-authenticated by the edge, and the workload's job is to *trust the headers* (after JWT verification, if it cares about audit).

## Alternatives considered

For authentication:

- **In-app OAuth (Authlib, NextAuth, Auth.js, etc.).** Full control; cost is writing and maintaining auth, sessions, password reset, MFA. Not worth it for internal tools without an external user model.
- **Tailscale or other mesh VPN.** Works for team-only tools where every user can install a client; bad for partners or stakeholders who can't.
- **Basic auth at Traefik.** Fine for one user; ungovernable past two; loses SSO.
- **No auth, hard-to-guess subdomain.** Leaks the moment any URL is shared, indexed, or linked.

For origin IP concealment:

- **Cloudflare Tunnel (`cloudflared`) instead of A-record + proxy.** Closes ports 80/443 on the VPS entirely; pairs naturally with Access. Strong option but adds a tunnel daemon per workload (or a shared one). The CF-proxy + firewall combo gets us most of the benefit at lower complexity; revisit if a workload needs the stronger isolation.
- **Direct A record (no proxy).** Simplest, but exposes the IP. Acceptable only for workloads that explicitly do not care.

For firewall:

- **Coolify-only port mediation.** Coolify can mediate published ports per resource but doesn't manage the host firewall. A `ufw` policy at the host level is independent of any orchestrator and survives orchestrator changes.
