# Working in this repository

Guidance for any coding agent (Claude Code, Codex, omp, …) asked to change
Knotlog. Human contributors: see `README.md` and `docs/GUIDE.md`.

## Behaviour contract

The behaviour rules live in the product itself, not here:

    templates/en/rules.md      (Turkish: templates/tr/rules.md)

**Read that file first.** It carries the approval gates and the zero-level
protocols Knotlog seeds into every vault — scope, definition of done, measuring
instead of guessing, one commit per logical step, session-end handoff. They
apply to work on Knotlog too.

This file is deliberately short and points at that one. Two copies of the same
rules drift apart; the pointer cannot.

## What this project will not accept

- **New runtime dependencies.** Knotlog is POSIX sh + awk + sed, nothing else.
  No Python, no Node, no network calls at runtime. This is why it installs in
  one line and runs identically on Linux, macOS and Git Bash.
- **Strings hardcoded in code.** All user-facing text comes from `i18n/en.txt`
  and `i18n/tr.txt`. Both languages change together.
- **Rewriting a user's memory files.** Vault notes are append-only. `knotlog`
  never overwrites what a user wrote.

## Before you say it works

- `sh tests/run.sh` — the suite takes about two minutes. Run it in the
  background and read the summary line; do not judge by scrollback.
- `sh -n knotlog` and `shellcheck -s sh knotlog` must both stay clean.
- **Prove the test can fail.** Revert your fix and re-run: only your own tests
  may turn red. A test that passes with and without the change proves nothing.
- A red suite is not committed. Green → commit → (only then) tag or push.

## Scope

Touch what the task names. If you spot an unrelated defect, report it — do not
fix it in the same change. Say plainly what you could not verify; "not
verified" is worth more than a confident guess.
