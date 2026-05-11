---
name: convention-uplift
description: "Propose a cross-workload convention as an ADR PR against vps-playground/platform-conventions. Scans the current session for promotable cross-cutting decisions, dedupes against the live index, drafts an ADR in a git worktree, and opens a PR. User-invoked only — never auto-trigger."
argument-hint: "[optional hint of what to uplift]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - WebFetch
  - AskUserQuestion
---


<objective>
Promote a cross-workload decision made in the current session into a numbered ADR
PR against `vps-playground/platform-conventions`. End-to-end:

1. Identify candidate(s) from the session — only cross-cutting concerns (deploy
   layout, auth model, observability, secret handling, naming, networking, CI
   shape, etc.). Workload-specific code/decisions are NOT candidates.
2. Fetch the live `CONVENTIONS.md` index and check for duplicates / supersessions.
3. Create or reuse a worktree of the conventions repo, draft the ADR from the
   template with the next available number, commit, push, open a PR via `gh`.

Selectivity is the success metric. If no candidate qualifies, say so and exit
cleanly — do not invent one.
</objective>

<repo_config>
Conventions repo:
- Slug: `vps-playground/platform-conventions`
- Default local clone path: `$HOME/Projects/private/platform-conventions`
- Raw index URL: `https://raw.githubusercontent.com/vps-playground/platform-conventions/main/CONVENTIONS.md`
- ADR template (in repo): `adr/ADR-template.md`
- ADRs live under: `adr/NNNN-short-title.md`

If the local clone is missing, run `gh repo clone vps-playground/platform-conventions <path>` only after confirming with the user.
</repo_config>

<candidate_criteria>
A session item qualifies as a platform convention candidate ONLY if it meets all of:

- **Cross-workload**: applies to >1 workload deployed to vps-playground (or clearly will).
- **Decision-shaped**: a chosen approach with rejected alternatives, not just a note or observation.
- **Stable**: not a one-off fix or short-lived experiment.
- **Not already covered**: no existing Accepted/Proposed ADR for the same topic.
- **Publishable**: contains no secrets, credentials, internal hostnames, or sensitive topology (the repo is public).

Reject candidates that are:
- Workload-internal code patterns or refactors.
- Library/version pins specific to one app.
- Tooling preferences with no platform impact.
- Aspirational / "we should probably…" without a concrete decision having been made.
</candidate_criteria>

<process>

## 1. Identify candidates

Review the current session (recent user turns and your own work) for decisions
matching `<candidate_criteria>`. Build a short internal list.

If `$ARGUMENTS` contains a hint, prefer candidates aligned with the hint but
still apply the criteria — the user's hint does not override gating.

If nothing qualifies: tell the user "No platform-convention candidates in this
session." with a one-line reason for each near-miss you considered, and stop.

## 2. Fetch the live index

WebFetch `https://raw.githubusercontent.com/vps-playground/platform-conventions/main/CONVENTIONS.md`
and parse the ADR table. Capture: highest ADR number, list of `(id, topic, status)`.

For each candidate, check the index for a same-topic ADR:
- **Accepted, same scope** → ask the user: draft a superseding ADR, or skip.
- **Proposed, same scope** → tell the user; offer to comment on that PR instead, then stop.
- **No match** → proceed.

## 3. Confirm with the user

Use AskUserQuestion to present the candidate(s) with a one-line summary each
(one option per candidate, plus "None — cancel"). Let the user pick one or cancel.

Then pre-fill from the session and ask only for gaps:
- Title (short, ADR-style — propose, let user edit)
- Status (default: Proposed)
- Context, Decision, Consequences, Alternatives — pre-fill from session, surface
  only the sections where session evidence is thin.

## 4. Locate / prepare the local conventions repo

Resolution order:
1. If the current working directory IS the conventions repo (check
   `git config --get remote.origin.url`), use it.
2. Else if `$HOME/Projects/private/platform-conventions` exists and points to
   the right remote, use it.
3. Else search: `find $HOME/Projects -maxdepth 4 -type d -name platform-conventions 2>/dev/null`.
4. Else, with explicit user confirmation, clone:
   `gh repo clone vps-playground/platform-conventions $HOME/Projects/private/platform-conventions`.

Confirm the resolved path with the user before any write.

Also capture, for the PR body, the *originating* workload context:
- Originating repo: `git config --get remote.origin.url` of the session's cwd
  if different from the conventions repo. Otherwise note "Authored directly in
  conventions repo session."

## 5. Create the worktree + branch

From the conventions repo root:

```bash
git fetch origin
git worktree add -b adr/NNNN-<slug> /tmp/platform-conventions-adr-NNNN-<slug> origin/main
```

Where:
- `NNNN` = max(filesystem ADR numbers under `adr/`, index ADR numbers) + 1, zero-padded to 4.
- `<slug>` = derived from the ADR title, kebab-case, ≤ 5 words.

Use the filesystem-derived max as authoritative; if it diverges from the index,
warn and propose fixing the index in this same PR.

## 6. Draft the ADR

In the worktree:

1. Copy `adr/ADR-template.md` → `adr/NNNN-<slug>.md`.
2. Fill in: Title (`# ADR-NNNN: <title>`), Status, Date (today's absolute date),
   Decided by (`gh api user --jq .login`, prefix with `@`), Context, Decision,
   Consequences, Alternatives.
3. Update `CONVENTIONS.md`: insert a new row into the ADRs table in
   ADR-number order. Keep the table well-formed (alignment is cosmetic; correctness
   is the column count).

Show the user the diff of both files before committing. Let them edit either.

## 7. Commit, push, open PR

After user approves the draft, run sequentially:

```bash
git add adr/NNNN-<slug>.md CONVENTIONS.md
git commit -m "ADR-NNNN: <title>"
```

Pushing and opening the PR are visible to others. **Confirm explicitly before
running** `git push` and `gh pr create`, even if prior session actions were
auto-approved. Then:

```bash
git push -u origin adr/NNNN-<slug>
gh pr create --title "ADR-NNNN: <title>" --body "$(cat <<'EOF'
## Summary

<one-paragraph summary of the decision>

## ADR

See `adr/NNNN-<slug>.md` in this branch.

## Originating context

<workload repo URL or "Authored directly in conventions repo session.">

## Discussion

Status is **Proposed**. ADRs become **Accepted** on merge. Please flag any
workload that would be forced to deviate.
EOF
)"
```

Return the PR URL to the user.

## 8. Cleanup hint

Leave the worktree in place (the branch lives there). Tell the user the
worktree path and the cleanup command: `git worktree remove <path>` after the
PR merges.

</process>

<failure_modes>

- **`gh` not installed or not authenticated** → stop. Instruct user to install
  `gh` or run `gh auth login`. Do not proceed.
- **Network failure on WebFetch of index** → retry once. If still failing, ask
  the user whether to proceed with a local copy (read directly from the local
  clone's `CONVENTIONS.md`) or abort.
- **Local clone is behind origin/main** → `git fetch origin` and base the
  worktree on `origin/main` (already in step 5). Warn if local `main` differs.
- **Index parsing yields a max ADR lower than the filesystem** → trust the
  filesystem. Warn the user; offer to also fix the index entry of the missing
  ADR in this same PR.
- **User cancels at any AskUserQuestion** → exit cleanly. The worktree is only
  created after step 4 confirmation, so cancellation before that requires no
  teardown. If cancelled after worktree creation, tell the user the worktree
  path and offer to remove it.
- **Multiple candidates** → present all via AskUserQuestion, one PR per
  invocation. Suggest re-running the skill for additional candidates.

</failure_modes>

<non_goals>

- This skill does NOT amend Accepted ADRs in place (they're immutable — use a
  superseding ADR instead).
- This skill does NOT merge PRs. Discussion and merge happen on GitHub.
- This skill does NOT enforce conventions on the originating workload — it only
  proposes them upstream.
- This skill does NOT auto-trigger. It is user-invoked only.

</non_goals>
