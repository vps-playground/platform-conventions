# ADR-0018: Shared web analytics via one self-hosted Umami

- **Status**: Proposed (deferred: implement once a third public site wants analytics)
- **Date**: 2026-10-25
- **Decided by**: @a-grasso

## Context

Public workloads have no way to answer "is anyone visiting this?". The personal
site (`a-grasso.dev`) and telemetrix (`telemetrix.3eee17bc.nip.io`) both want
visitor counts, top pages and referrers. Neither logs requests, and Coolify's
Traefik has access logs off.

Constraints:

- Small shared VPS: whatever we run must be light on RAM.
- No cookie banners: the tool must be cookieless and store no personal data.
- Workloads ship strict CSPs (`default-src 'self'`, nonce-based `script-src`),
  so any tracker is an explicit, reviewed exception per workload.
- Only the operator may read the stats.

With two interested sites the setup cost (new repo, Coolify resource, Authentik
wiring, per-workload CSP change) isn't worth it yet. This ADR records the
design so it isn't re-derived when a third site shows up.

## Decision

Run **one shared [Umami](https://umami.is/) instance** for every public
workload on the VPS. Each workload is registered as its own *website* in Umami
and gets its own website ID.

- **Deployment**: a dedicated repo `vps-playground/umami` (same shape as
  `vps-playground/authentik`) holding the compose file and `.env.example`,
  deployed as a Coolify Docker Compose resource. The bundled Postgres is named
  `umami-db` (ADR-0016).
- **Hostname**: `stats.<parent>`, on the registered domain if one is available,
  else the nip.io hex form (ADR-0012).
- **Access**: the whole host sits behind Authentik forward-auth (ADR-0011),
  with a higher-priority router **without** the middleware for the two tracker
  paths, `/script.js` and `/api/send`. Those must stay public or visitors can't
  be counted. Umami's own login stays on as a second layer; its default
  `admin` / `umami` credentials are changed on first boot.
- **Workload integration**: a workload opts in by adding
  `<script defer src="https://stats.<parent>/script.js" data-website-id="…">`
  to its HTML shell and adding the stats origin to `script-src` and
  `connect-src` in its CSP. Nothing else changes in the workload.
- **Scope**: public workloads only. Authentik-protected workloads don't get the
  tracker unless they have real multi-user traffic worth measuring.

## Consequences

- One dashboard, one database, one thing to update for all sites.
- Each opted-in workload carries a third-party origin in its CSP.
- Ad blockers will hide some visits; numbers are a lower bound. Umami's
  `TRACKER_SCRIPT_NAME` / `COLLECT_API_ENDPOINT` can rename the endpoints if
  that becomes a problem (update the Authentik exemptions to match).
- The stats host becomes a dependency of page loads, but the script is `defer`
  and a failure only loses analytics, never breaks a page.

## Alternatives considered

- **Traefik access logs + GoAccess**: no workload changes, but bots and
  scanners dominate the counts, and enabling logs is host-level config.
- **Plausible CE**: similar features, but needs ClickHouse, which is too heavy
  for a shared small VPS.
- **Request logging inside each workload**: gives no aggregation or dashboard,
  and logs disappear on redeploy.
- **One analytics instance per workload**: multiplies the Postgres and update
  burden for no isolation benefit; analytics data isn't sensitive across sites.
- **Hosted SaaS (Umami Cloud, Plausible.io)**: works, but sends visitor data off
  the VPS and costs money for what self-hosting covers.
