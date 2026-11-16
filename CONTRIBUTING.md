# How work is tracked

## Issues

- **Every task is an issue**, filed when it is found. If it is plainly part of an issue that is already open, update that issue instead (its task list or a comment). If that issue is closed, open a new one and link back.
- **Large issues are split into sub-issues** of a main issue. Each sub-issue body explains its scope, why it matters, what it needs, and when it is done.
- **The main issue has a table of its sub-issues** with exactly these columns, in this order: `Step | Issue | What it is | Needs | State`.
  - **Step:** the sub-issue's step name (see titles below).
  - **Issue:** the link, `#n`.
  - **What it is:** one or two sentences.
  - **Needs:** empty if nothing; otherwise the issues it depends on, as `#n` links.
  - **State:** open / in progress (say what is left) / done. Keep it current.
- **Titles:** `X1a - Title (part of #n)`.
  - `X` is a letter for the master issue. The roadmap uses `M`, so milestone steps are `M1`, `M2`, and so on.
  - The number is the position in the main issue's table. A lowercase letter marks a part of a step (`M3a`, `M3b`).
  - The title ends with `(part of #n)`, naming the main issue. Only a master issue (one with no parent) has no step and no suffix.
- **Tick boxes in both the parent and the sub-issue** when the work is verified, not before.

### Labels

Every issue gets one label from each family when it is created:

| Family | Labels |
|---|---|
| issue | `issue: main` (has sub-issues), `issue: sub` (has a parent); both if both |
| area | `area: world` (terrain, rivers, plants, weather, day and night), `area: gameplay` (gold, panning, machines, base, economy), `area: vehicles`, `area: ui` (HUD, map, menus), `area: tooling` (tests, harness, launchers, docs tooling) |
| type | `type: feature`, `type: bug`, `type: chore`, `type: docs`, `type: testing`, `type: breaking` |
| priority | `priority: high`, `priority: medium`, `priority: low` |
| who | `who: agent` (can be done in code), `who: human` (needs the owner: decisions, playtesting, merges) |

## Pull requests

- One branch per feature or concern. Never commit straight to `main`.
- The PR body has **Summary**, **Details**, **Testing** and **Notes** sections, and `Closes #n` for each issue it finishes.
- Run the checks in the README before opening or updating a PR, and say in **Testing** what was run and what it showed.
- The owner playtests and merges. After a merge, close each linked issue with a comment naming the PR and what was verified; move anything unfinished to another issue first.
- Review comments: after fixing one, reply on that thread with the commit hash, what changed and any test added. If declining, say why.

## Privacy

This repository is public. Never put local paths, machine names, usernames, hardware or setup details in commits, issues, PRs, comments or docs. Describe problems generically.
