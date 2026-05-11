# ADR-0012: No-domain hostnames via nip.io hex form

- **Status**: Proposed
- **Date**: 2026-05-11
- **Decided by**: @a-grasso

## Context

The vps-playground VPS hosts workloads for which a real registered domain may not yet exist — sandbox apps, pre-launch projects, the platform stack itself during bring-up. Coolify's Traefik issues Let's Encrypt certificates only for hostnames that publicly resolve to the VPS, which means we need *something* in DNS pointing at the VPS IP before TLS will work.

Buying a domain is the long-term answer (€10/yr, and it eliminates this entire category of decision), but the platform needs a working no-domain path that's:

- free, with no registrar setup
- TLS-issuable via Let's Encrypt
- safe for cookie scoping (so SSO and forward-auth work across our subdomains without leaking cookies to other tenants of the same wildcard-DNS service)
- aesthetically tolerable in URLs that may be shared in PRs, demos, and screenshots

[`nip.io`](https://nip.io) and [`sslip.io`](https://sslip.io) both offer wildcard DNS that resolves `<anything>.<ip>.<tld>` to that IP. Functionally interchangeable. The differences are aesthetic (hex form vs dotted IP) and a (false) belief in some documentation that one or both are on the [Public Suffix List](https://publicsuffix.org/).

## Decision

For workloads without a registered domain, use **nip.io's 8-character hex form**:

```
<workload-subdomain>.<hex-encoded-vps-ip>.nip.io
```

For the current VPS at `62.238.23.188`, that's `<workload>.3eee17bc.nip.io` (since `0x3e 0xee 0x17 0xbc` = `62.238.23.188`). Compute the hex with:

```sh
printf "%02x%02x%02x%02x\n" 62 238 23 188
```

This hostname is set in Coolify's per-service Domain field (or in workload-owned Traefik labels) exactly like any registered hostname; Let's Encrypt issues a real cert via HTTP-01 on first deploy.

### Cookie scoping is safe — verified

Both `nip.io` and `sslip.io` are **absent** from the Public Suffix List (verified by grepping `https://publicsuffix.org/list/public_suffix_list.dat` for either string; both return empty). That means:

- `.io` is the public suffix
- `nip.io` is the eTLD+1
- Browsers permit `Set-Cookie` with `Domain=3eee17bc.nip.io` (our specific parent)
- Cookies scoped to `3eee17bc.nip.io` are isolated to subdomains of *our* IP-encoded parent and do not leak to other users of nip.io

Browsers would *also* permit cookies with `Domain=nip.io`, which would leak across all nip.io users — so the convention is to **always scope cookies to the IP-encoded parent**, never the bare TLD. For the identity stack (Authentik), this means `AUTHENTIK_COOKIE_DOMAIN=3eee17bc.nip.io`, not `nip.io`. Workload-issued cookies follow the same rule.

## Consequences

**Upsides:**

- Zero cost, zero registrar, zero DNS records. Workloads come up with valid HTTPS on first deploy.
- Real Let's Encrypt certs (HTTP-01 challenge) — no self-signed pain, no browser warnings.
- nip.io's hex form is roughly half the length of dotted-IP wildcard-DNS hostnames (`3eee17bc.nip.io` vs `62.238.23.188.sslip.io`) — more readable in URLs, less awkward in screenshots.
- Migration to a real domain later is mechanical: swap the parent hostname in workload compose files, brand domain in Authentik, cookie domain env var. Workload code is unaffected.

**Trade-offs:**

- **Aesthetic.** URLs read as random hex; not what you want on a product launch page.
- **Coolify warns** when a sslip-style or nip-style hostname is used with HTTPS. The warning is conservative; the path works.
- **No DNS-level rate limit isolation.** Let's Encrypt rate limits apply per-hostname, which works in our favor (each `<workload>.3eee17bc.nip.io` is its own rate-limit bucket), but a misconfigured workload that repeatedly fails issuance can lock itself out for an hour per LE's *Failed Validations: 5/hour per hostname* rule. Use LE staging while iterating.
- **Implicit dependency on nip.io's uptime.** If nip.io's DNS goes down (rare in practice), our workloads' hostnames stop resolving. Buying a real domain removes this dependency.

**Footguns:**

- **Don't set cookies with `Domain=nip.io`** — they'd leak to every nip.io subdomain on the public internet. Always scope to your IP-encoded parent.
- **Per-app HTTP-01 means port 80 must stay open.** Standard LE concern, not specific to nip.io; documented in [`vps-control-plane/docs/https.md`](https://github.com/vps-playground/vps-control-plane/blob/main/docs/https.md).
- **Don't publish `AAAA` records pointing at nip.io hostnames unless v6 actually works** — ACME may attempt v6, fail, and burn a Failed Validation slot. nip.io natively resolves both v4 and v6 hex/dotted forms; stick with v4 unless you've explicitly tested v6 end-to-end.

## Alternatives considered

- **`sslip.io`** — functionally identical wildcard DNS service. We used it briefly during early spike work; switched to nip.io purely for hex-form aesthetics. Earlier docs claimed sslip.io was on the PSL; verified false. No technical reason to prefer one over the other for our use case.
- **nip.io dotted-IP form** (`<sub>.62.238.23.188.nip.io`) — longer, leaks the IP visually. Hex form is strictly shorter and more pleasant.
- **Buy a real domain (€10/yr)** — strictly better long-term. Eliminates this whole class of concern. The plan is to do this once the platform graduates beyond sandbox use; nip.io is the bridge until then.
- **Self-signed certs** — breaks the browser-trust experience, requires per-developer CA installation. Hard no.
- **DNS-01 challenge against a real DNS provider** — needs a real domain to begin with, so doesn't help in the no-domain case.
- **`.local` / `.test` / mDNS** — doesn't work for remote access; only useful inside a single network. Not what we need for VPS-hosted workloads.
