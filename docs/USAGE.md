# Knotlog Installation Runbook

> This document is an **agent runbook**: a coding agent reads it start to finish and follows
> it from an existing Knotlog checkout to a personalized vault wired into its own agent
> surface. All six phases run on platform-independent POSIX tools (`sh`, `sed`, `awk`,
> `grep`, `tr`, `git`); no macOS-specific tool, package manager, or scripting language is
> required. `knotlog install` is a local installer, **not** a bootstrap downloader: obtain the
> checkout first, then run its `./knotlog` script.

## Phase 0 — Prerequisite

Before starting the install, enter the Knotlog checkout and verify the environment:

```
./knotlog doctor
```

If the output has a `fail` line (e.g. `sh`/`sed`/`awk`/`grep`/`tr`/`git` not found), fix
that first — Knotlog's only requirement is POSIX sh plus these five tools, and there is no
other platform-specific setup step. At this stage vault-related `warn` lines are expected
because the vault does not exist yet.

## Phase 1 — Interview

Ask the user five questions, in their own language and in conversational tone:

1. What is the user's name?
2. What name should the AI companion have?
3. Which language should it operate in — Turkish (`tr`) or English (`en`)?
4. Should folder names be emoji-prefixed (default) or plain ASCII (`--plain`)?
5. Which **parent directory** should contain the vault? The generated child is always
   `<user>'s Knotlog`, in every language; omitting the parent defaults it to `$PWD`.

There is **no** question about an external service in this phase (e.g. an external semantic
memory service like mem0) — Knotlog's memory layer is already the agent in the loop itself, so
no additional service is needed.

## Phase 2 — Setup

```
./knotlog install [PARENT] --lang <tr|en> [--plain] [--no-git] [--no-link] [--no-prompt] \
  --user <name> [--companion <name>] [--purpose <text>]
```

`--no-link` skips every `PATH` and symlink probe. It is intended for wrappers
that provide their own command entry point, such as the PowerShell installer;
the vault and all integrations are still created normally.

PowerShell users should run `.\install.ps1` from the checkout. Because
PowerShell does not give the child `bash.exe` a POSIX tty, the wrapper prompts
for the required user name when `--user` is absent; `--no-prompt` still
requires an explicit `--user`. It checks for Git for Windows on `PATH`, then
falls back to standard install locations and registry entries when a stale
session omits Git. It delegates vault creation to `knotlog install --no-link`,
creates an idempotent `%LOCALAPPDATA%\Knotlog\bin\knotlog.cmd` plus an executable
POSIX `knotlog` shim for Bash hooks, and adds that directory to the user-level
`PATH` without administrator rights.

Example:

```
./knotlog install "$HOME" --lang tr --user "Ada" --companion "Kuz" \
  --purpose "Kalıcı çalışma hafızası"
cd "$HOME/Ada's Knotlog"
```

`PARENT` may appear before or after the flags; only one positional path is accepted. If
`--user` is omitted in an interactive terminal, Knotlog asks for it before deriving the
target. `--no-prompt` requires `--user`, because the folder name cannot otherwise be known.
The remaining flags are forwarded to `init`, which remains the single owner of
`.knotlog/config`, `index.tsv`, `activity.log`, the ten-folder tree, the
`AGENTS.md`/`CLAUDE.md` bridge blocks, and the personalized `companion.md` seed.

Before creating the vault or command link, `install` validates every collision. A missing
target is created; an existing empty target or a vault with `.knotlog/config` is accepted; a
non-empty non-vault target is rejected. In normal mode it scans `PATH` in order and links the
checkout's actual `knotlog` script into the first non-empty existing writable entry. The same
resolved symlink is idempotent; a regular file, directory, dangling link, or link to another
source is rejected and never overwritten. No `PATH` directory or shell startup file is created
or edited. With `--no-link`, all command-destination probing is skipped and only the vault
integrations are installed. These argument, target, and (when enabled) link checks happen
before either destination is changed; an unexpected failure inside `init` is returned honestly.
On Windows, run from Git Bash with Windows symbolic-link permission (normally provided by
Developer Mode, or equivalent process permission). Git Bash may otherwise emulate `ln -s`
with a copy or unusable placeholder. `install` verifies a real, executable same-source
symlink on the selected filesystem before initializing the vault; unsupported environments
fail clearly and the attempted command artifact is removed.

Running the same install again is safe: user-authored vault text is preserved and the
matching command link is reused.

## Phase 3 — Identity

Manually verify that identity was actually set:

- Does `.knotlog/config` have `user=<name>` and, when supplied, `companion=<name>` lines?
  (`grep user= .knotlog/config`, `grep companion= .knotlog/config`)
- Does `companion.md` in the companion folder contain both supplied names; is there **no**
  raw `%s` placeholder left? (If there is, Phase 2 ran incorrectly.)

`install` always records the user because that name determines the vault folder. If no
companion name was given, the seed uses the neutral i18n equivalent (`Companion` in English
and Turkish) without inventing a `companion=` config value. A later `knotlog init
--companion <name>` may fill a missing field; existing values and user-authored seed text are
never overwritten.

## Phase 4 — Agent wiring

Branch according to the user's agent:

- **Claude Code:** merge the `hooks` block from the "Claude Code" section of docs/REFERENCE.md into
  `~/.claude/settings.json` (four hooks: context injection at session start, a context
  reminder before each prompt, logging after tool use, and summary writing at session end).
  **Restart Claude Code after editing the settings** — hook configuration is not reloaded
  into a running session.
- **Codex:** copy `adapters/codex/hooks.json` to `~/.codex/hooks.json` (global) or
  `.codex/hooks.json` (project-scoped). **Restart Codex after setup** — hook configuration is
  only read at session setup.
- **Agents without a hook surface:** if you cannot install a local hook, follow the manual
  loop in the "Hook-less agents" section of docs/REFERENCE.md. At least two steps are always run manually:
  at session end,

  ```
  knotlog remember
  ```

  to write the mechanical summary into the current session file, and at session start,

  ```
  knotlog context --bridge
  ```

  to write the current context into `AGENTS.md`'s own block for the agent to read there.

## Phase 5 — First index and verification

1. Build the first index:

   ```
   knotlog index
   ```

   A cold (first) run can take a while on large vaults, but this is no longer a practical
   concern: Phase 11 replaced Knotlog's per-file child-process pipeline with a batch pipeline
   whose process count is flat in the number of files, cutting the first index of a
   5000-note test vault from 2150-2367 s down to roughly 3 s on Windows, 1 s on macOS, and
   under a second on Linux (see "Large vaults" in docs/REFERENCE.md). On a freshly created vault with a
   handful of notes, this takes a few seconds at most.

2. Try a search:

   ```
   knotlog search <a word>
   ```

3. View the context:

   ```
   knotlog context
   ```

4. Verify the setup again:

   ```
   knotlog doctor
   ```

   The summary line has the shape `summary: N ok, N warn, N fail`; the exit code is 0 once
   the fail count is 0.

5. Give a short report in the user's language: what was set up (vault path, language,
   layout, identity), how long the first index took, and finally do the "show the magic"
   step together — ask the user to say something, close and reopen the session, and observe
   together that the previous session's context appears in the new session.

## Optional scopes and local imports

The core layout is unchanged by default. Add optional, localized folders with
repeatable scope flags:

```
knotlog init --scope goals
knotlog init --scope money --scope body
knotlog init --scope full
```

Valid scopes are `core`, `goals`, `money`, `body`, `mind`, and `full`.
`core` adds no optional folders; `full` expands to all four. Scope selections
are persisted as a comma-separated `scope=` value in `.knotlog/config`, and
re-running `init` is additive and idempotent: it never removes folders or
changes existing notes. Turkish layouts use localized names such as
`⚔️ Hedefler`, while English layouts use `⚔️ Goals`.

`digest` summarizes only one activity date and never advances `remember`'s
watermark:

```
knotlog digest --date 2026-08-27 --limit 20
knotlog digest --date 2026-08-27 --dry-run
```

Without `--date`, today's date is used. The normal command refreshes the
deterministic `<dump>/YYYY-MM-DD-digest.md`; `--dry-run` prints the exact
Markdown without writing it.

Import a local JSON export without network access:

```
knotlog import conversation.json --date 2026-08-27
```

The reader accepts role/content messages (including JSONL), Claude-style
transcripts, and ChatGPT mapping exports whose messages use
`author.role` plus `content.parts`. It writes a Markdown note beneath the
layout's sessions folder and rejects missing, unreadable, or unsupported
exports without changing the vault.

## Repairing hooks after relocation

`install` copies two vault-local entrypoints: `repair-hooks` for POSIX shells
and `repair-hooks.ps1` for Windows PowerShell. If either the vault or the
Knotlog checkout has moved, launch the entrypoint manually with the current
checkout path:

```
./repair-hooks --knotlog /path/to/Knotlog
.\repair-hooks.ps1 -Knotlog C:\path\to\Knotlog
```

The repair updates only command strings beginning with `KNOTLOG_HOOK=1 knotlog`
(or the pre-rename `QUIPU_HOOK=1 quipu`)
in `.claude/settings.json`, replacing the bare command with the current
absolute checkout path. All unrelated Claude settings remain byte-for-byte
untouched, and repeated repairs are idempotent. The explicit checkout
argument is deliberate: a stale hook cannot discover or repair itself.

The same command refreshes `.directory` for Linux/KDE and `desktop.ini` for
Windows, using `.icon/knotlog.png` and the valid `.icon/Knotlog.ico` asset. Windows
Explorer may need a refresh or folder reopen before displaying a changed icon.
