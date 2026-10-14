# platform-conventions

Cross-workload conventions for projects deployed to the **vps-playground** VPS.

Lives separately from infrastructure-as-code ([`vps-control-plane`](https://github.com/vps-playground/vps-control-plane)) so individual workload repos can pull conventions without dragging in infra concerns.

## For humans

Browse [`CONVENTIONS.md`](CONVENTIONS.md) for the index, then read individual ADRs under [`adr/`](adr/).

## For AI agents

Fetch the index first:

```
https://raw.githubusercontent.com/vps-playground/platform-conventions/main/CONVENTIONS.md
```

Then fetch the ADRs relevant to the current task. Conventions override workload-local choices unless an exception is explicitly justified in the workload's PR or ADR.

## For workload repos

Two ways to start a new workload aligned with these conventions:

- **From scratch:** run the [`workload-bootstrap`](skills/workload-bootstrap/SKILL.md) Claude skill — it renders the compose + Traefik labels + nip.io hostname + healthz routing + CLAUDE.md/Justfile/README/gitignore from static templates, then generates the stack-specific Dockerfile and `/healthz` handler informed by the ADRs and any verified sibling workload.
- **Retrofit an existing repo:** copy [`templates/workload-CLAUDE.md.snippet`](templates/workload-CLAUDE.md.snippet) into the top of your repo's `CLAUDE.md` so future sessions pull the conventions index automatically.

## Claude skills shipped from this repo

| Skill | Purpose |
|---|---|
| [`convention-uplift`](skills/convention-uplift/SKILL.md) | Promote a cross-workload decision from the current session into a numbered ADR PR against this repo. |
| [`workload-bootstrap`](skills/workload-bootstrap/SKILL.md) | Scaffold a new workload repo targeting the vps-playground VPS (see above). |

To enable every skill on a machine, clone this repo and run:

```sh
just install
```

This symlinks each skill under `skills/` into `~/.claude/skills/`. `just status` shows install state; `just uninstall` removes the symlinks; `just reinstall` forces a clean replace.

## Contributing

New decisions become numbered ADRs. Two paths:

- **Manual:** copy [`adr/ADR-template.md`](adr/ADR-template.md), give it the next number, fill it in, open a PR.
- **Claude Code skill:** run `/convention-uplift` in the session where the decision was made. The skill drafts the ADR from session context, creates a worktree on a new branch, and opens the PR.

ADRs are immutable once **Accepted** — supersede with a new ADR rather than editing in place.

See [ADR-0001](adr/0001-platform-conventions-location.md) for the rationale behind this setup.
