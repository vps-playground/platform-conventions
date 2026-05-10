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

Copy [`templates/workload-CLAUDE.md.snippet`](templates/workload-CLAUDE.md.snippet) into the top of your repo's `CLAUDE.md`.

## Contributing

Open a PR. New decisions become numbered ADRs — copy [`adr/ADR-template.md`](adr/ADR-template.md), give it the next number, fill it in.

ADRs are immutable once **Accepted** — supersede with a new ADR rather than editing in place.

See [ADR-0001](adr/0001-platform-conventions-location.md) for the rationale behind this setup.
