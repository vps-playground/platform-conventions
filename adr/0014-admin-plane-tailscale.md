# ADR-0014: Admin plane access via Tailscale tailnet

- **Status**: Proposed
- **Date**: 2026-05-12
- **Decided by**: @a-grasso

## Context

The vps-playground VPS exposes two distinct surfaces with very different threat models:

| Plane | Surfaces | Today's posture |
|---|---|---|
| **Workload** | Public apps on `:80` / `:443` via Coolify-bundled Traefik | Public ingress; protected per [ADR-0011](0011-identity-aware-ingress.md) by Authentik forward-auth. |
| **Admin** | SSH `:22`, Coolify UI `:8000`, Authentik admin UI | Mixed and ad-hoc — SSH public with key-only + fail2ban; Coolify UI firewalled off and reached via an SSH tunnel; Authentik UI public via Traefik. |

ADR-0011 deliberately scopes itself to workloads — it does not cover the infrastructure surfaces that operate the platform. The admin plane has therefore accumulated three separate access mechanisms (public SSH, SSH tunnel for Coolify, public IdP UI), each with its own ergonomics and audit story. Growing the admin set to two people compounds the cost: another set of SSH keys to rotate, another tunnel ceremony to teach, another browser tab to remember to log out of.

We want a single, coherent answer to "how do operators reach the admin plane" — distinct from how end users reach workloads — that scales to N admins without N rotations.

## Decision

**The admin plane is reachable only over a private Tailscale tailnet. The workload plane stays exactly as ADR-0011 defines it.**

### Tailscale account

- **Plan**: Tailscale Personal (free tier — 100 devices / 3 users covers current scope).
- **Tailnet name**: `vps-playground.ts.net`.
- **SSO**: Google. Deliberately a *different* IdP than the one federated into Authentik, so a compromise of either identity does not collapse both the network and application planes.
- **MFA**: required on every admin Google account.
- **MagicDNS**: enabled. **HTTPS certificates**: enabled (required for `tailscale serve`).

### VPS as tailnet node

- Host runs `tailscaled`, joined as `tag:vps` via a pre-auth key stored in the consuming repo's ansible-vault.
- After first join, key expiry is **disabled** for the VPS node so it cannot get logged out on a 180-day timer.
- ACL JSON — VPS is a pure receiver:

  ```jsonc
  {
    "tagOwners": { "tag:vps": ["autogroup:admin"] },
    "acls": [
      { "action": "accept", "src": ["autogroup:member"], "dst": ["tag:vps:*"] }
      // no reverse rule: the VPS does not initiate connections to admin devices
    ],
    "ssh": []  // openssh-on-tailnet, not Tailscale SSH (see Alternatives)
  }
  ```

### Per-surface mapping

| Surface | Public? | How it's reached |
|---|---|---|
| SSH | **No** | `sshd` bound to the `tailscale0` interface; firewall closes `:22` to the public Internet. Unix users (`agr`, `nbi`, …) unchanged; SSH key auth unchanged. |
| Coolify UI | **No** | `tailscale serve` exposes the local `:8000` listener at `https://coolify.vps-playground.ts.net` with a Let's Encrypt cert issued via Tailscale. SSH tunnel workaround retired. |
| Authentik IdP | **Yes** | Stays fully public via Traefik on its `nip.io` hex hostname. Required: every workload protected by ADR-0011 redirects users to Authentik for login; tailnet-gating would break public workload auth. Admin surface in Authentik is protected by Authentik's own login + the `admins` group binding + MFA. |
| Workload ingress | **Yes** | Unchanged — public on `:80` / `:443` per ADR-0011. |

### Break-glass

If the Tailscale control plane is unavailable, admins reach the VPS via the **Hetzner web console**. Public `:22` stays closed; we accept the lower-availability bet because Tailscale's control-plane uptime is high and Hetzner console is a genuine out-of-band path.

### Operator contract

- Adding an admin = invite their Google identity in the Tailscale admin console + ensure they have a Unix account on the VPS (managed via `vps_users` in the consuming repo).
- Removing an admin = remove their Tailscale user + remove their Unix account. No SSH-key rotation involved; revocation is one place.
- Audit trail is **split by design**: Tailscale logs which Google identity / device connected; `sshd` logs which Unix user the session ran as. The two are independent and may not correspond.

### Workload guidance (forward-looking)

This ADR is platform-side; it does not change ADR-0011 workloads. But it establishes the pattern for **any future workload that needs a non-public admin or management surface** (e.g. a database admin UI, an internal-only dashboard, an ops tool):

> Do not open a public port + add application-level access control. Bind the surface to `tailscale0` on the host, or expose it via `tailscale serve` at a `*.vps-playground.ts.net` hostname. Internal surfaces use the admin plane, not the workload plane.

## Consequences

**Upsides:**

- Public SSH brute-force surface eliminated; the VPS no longer answers `:22` from the Internet.
- Coolify UI becomes a normal HTTPS URL on the tailnet; no tunnel ceremony.
- Admin onboarding/offboarding centralises on Tailscale user management rather than SSH key distribution and `authorized_keys` rotation.
- Extends cleanly: future internal-only surfaces inherit the same posture for free.

**Trade-offs:**

- **New critical dependency** on Tailscale's control plane for normal admin access. Mitigated by the Hetzner-console break-glass.
- **Split audit trail** between Tailscale device logs and `sshd` user logs. Reading "who did X" requires correlating both.
- **Two SSO identities to manage** per admin (Google for Tailscale, plus whatever Authentik federates to). Acceptable cost; the alternative (single-IdP for both planes) collapses blast radius.
- **Free-tier limits** (100 devices / 3 users). Fine for current and projected scope; a real growth event would force the plan question.

## Alternatives considered

- **Cloudflare Access** ([open ADR-0006 PR](https://github.com/vps-playground/platform-conventions/pull/7)). Solves SSH and admin UIs as ZTNA without an extra agent. Rejected because we are not running Cloudflare in front of this VPS — [ADR-0012](0012-nip-io-hex-hostnames.md) deliberately uses `nip.io` hex hostnames, and ADR-0006 is not adopted.
- **Authentik forward-auth on the admin surfaces.** Technically works for HTTP surfaces (Coolify UI). Rejected because (a) it makes Authentik a self-recursive dependency for the admin plane that operates Authentik itself, and (b) `sshd` is not HTTP — forward-auth cannot gate it, so we would still need a second mechanism.
- **Tailscale SSH** (replaces `openssh` on the tailnet). Cleaner UX, tighter identity binding, optional session recording. Deferred — keeps `openssh`'s established audit / `PAM` / `sshd_config` posture for now. Worth revisiting as a follow-up ADR once this is in production.
- **WireGuard directly** (Headscale or hand-rolled). More self-managed, no third-party control plane. Rejected for ergonomics — Tailscale's pre-auth keys, MagicDNS, ACL JSON, and `tailscale serve` are exactly what this ADR needs; reproducing them on raw WireGuard is real work for no real win at this scale.
- **Bastion host.** A second VM whose only job is SSH proxy. Rejected as overkill for a single-VPS playground; adds a node to harden without removing any.
