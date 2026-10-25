# Knotlog reference

The full manual: install internals, every command, each agent adapter, the vault layout, search, and the honest limits. New here? Start with the [README](../README.md).

## Install

One line, no checkout (macOS/Linux; needs `curl`, or `wget` as a fallback):

```bash
curl -fsSL https://raw.githubusercontent.com/MSelmanSonmez/Knotlog/main/install.sh | sh
```

The script downloads the release tarball, verifies it against a version anchor before unpacking anything, and hands over to `knotlog install`. Note: the `main`-branch copy of `install.sh` is the development channel — it tracks the tip of `main` rather than a frozen release tag.

Or start from a local checkout — `install` itself is deliberately **not** a bootstrap downloader:

```bash
git clone https://github.com/MSelmanSonmez/Knotlog.git && cd Knotlog
./knotlog install
```

On a real interactive terminal, setup advances one clear screen at a time through this localized four-step flow:

1. **Language** — the first interaction is the `Language / Dil (<codes>):` question, listing every shipped language (`en/tr/es/pt-br/ja/zh-cn`); Enter selects English, and the answer is folded like `--lang` (`PT_BR` means `pt-br`).
2. **Vault location** — choose the parent directory, with your home directory shown as the default. Enter accepts it. Literal `~` and `~/…` expand to your home directory; relative input is resolved from the directory where `install` started.
3. **Identity** — provide the required user name, then optionally a companion name and vault purpose; Enter skips either optional answer.
4. **Install** — Knotlog creates or reuses the vault, wires the integrations, and prints a compact status summary plus one `knotlog doctor` next action.

Supplying a positional parent path skips the location question. `--lang`, `--user`, `--companion`, and `--purpose` likewise skip their corresponding questions. For automation and other non-interactive use, pass the required values explicitly:

```bash
./knotlog install "$HOME" --no-prompt --user "Ada" --companion "Kuz" --lang en
```

Without a positional path, **interactive** setup defaults to `$HOME`; non-interactive/`--no-prompt` setup preserves the original current-directory default. The vault folder is always named `<user>'s Knotlog`, independent of language. `install` also accepts `--plain` and `--git`; `--no-link` skips symlink creation for wrappers such as `install.ps1`. New Turkish and English installs use the localized number-free layouts; `--plain` selects the ASCII layout, while an existing vault's layout is never renamed or migrated.

**Agent wiring and icon.** A successful install copies `adapters/claude-code.json` byte-for-byte to `<vault>/.claude/settings.json`, installs the omp hook at `<vault>/.omp/hooks/pre/knotlog.ts`, and brands the vault with a folder icon derived from `icon/Knotlog.png`/`icon/Knotlog.ico`: KDE's `.directory` metadata on Linux, and `desktop.ini` on Windows, given the hidden/system attributes it needs — Explorer only honors a folder's `desktop.ini` when the folder itself carries the System attribute. Identical files are left untouched on reinstall. The omp hook and icon are tool-owned and refresh from the checkout when they differ. Claude settings are user-owned: if `.claude/settings.json` already differs, Knotlog preserves it byte-for-byte and prints both paths for a manual merge; it never overwrites or tries to merge arbitrary JSON. `.directory` is a KDE/Linux mechanism and is inert on Windows and macOS; `desktop.ini` is the Windows counterpart and is inert on Linux/macOS. Folder-icon metadata is cosmetic — nothing functional depends on it, and a failure here does not block the vault or the `knotlog` command; install reports it as a warning instead.

**Preflight and idempotence.** Shipped adapter assets, the vault target, and (unless `--no-link` is used) the command destination are checked before vault creation. A missing target or existing empty directory becomes a vault; an existing Knotlog vault is reused; a non-empty directory without `.knotlog/config` is rejected. The normal command is a symlink to this checkout's real `knotlog` script in the first non-empty existing writable `PATH` entry. A matching link is reported separately as already available—even when the vault itself was just created. Every other `knotlog` destination is rejected and never overwritten. Knotlog never creates a `PATH` directory or edits shell startup files.

`install` makes the new vault a **git repository by default** and closes it with one **baseline commit**, so the vault's starting state is already in history — the memory is only as safe as its history, and every other safety net here (the uncommitted-memory check in `doctor`, `capture --git`, `remember --git`) already assumes a repository. A `.gitignore` is seeded alongside it so the machine state Knotlog regenerates (`activity.log`, both derived indexes, folder-icon metadata) stays out of the history. Pass `--no-git` to skip the whole step; if `git` is not on `PATH` it is skipped and reported rather than failing the install. The default applies to a vault `install` **creates** — reinstalling over an existing vault that you kept outside git leaves it that way, and `--git` is how you ask for the conversion.

The baseline commit is made only when the repository has **no commits yet** — an existing history is yours, and Knotlog never writes into it. If no git identity resolves, the commit is skipped and reported; the vault is complete either way.

A vault under git also gets a `.githooks/pre-commit` **secret gate** that scans added staged lines for known secret shapes and rejects the commit — `git commit --no-verify` or `KNOTLOG_SKIP_SECRET_SCAN=1` stays your deliberate way around it. `init` keeps `--git` as an opt-in flag, so running `init` by hand in a plain folder behaves as it always did.

Prerequisites: POSIX sh plus `sed`, `awk`, `grep`, `tr`, and `git`.

**Vaults made before the rename.** A new vault keeps its machine state in `.knotlog/`. A vault created while the project was still called Quipu has `.quipu/` instead, and it keeps working as it is: the vault is found by the same walk-up, every command reads and writes its `.quipu/`, and `init` over it never adds a second state directory. If both exist, `.knotlog/` is used. To bring such a vault over, see `knotlog migrate` under Commands; until then `knotlog doctor` warns that the old name is still in use.

**Windows**: from Git Bash, `./knotlog install` still uses a symlink and normally requires Developer Mode. From PowerShell, run `.\install.ps1`; it discovers Git for Windows from `PATH` or the standard install locations/registry when a stale session omits Git, prompts for the required user name when `--user` is not supplied (PowerShell does not provide Bash with a POSIX tty), delegates vault setup to `knotlog install --no-link`, creates both `%LOCALAPPDATA%\Knotlog\bin\knotlog.cmd` and an executable POSIX `knotlog` shim for Bash hooks, and adds that directory to the user PATH without administrator rights. Restart the shell after installation.

## Setup

`knotlog setup <claude|codex|omp|gemini|cursor|antigravity|windsurf|opencode> [--dry-run]` writes one agent's hook file into the vault, the vault being found the same way every command finds it:

| Agent | Written to | Shipped from |
|---|---|---|
| `claude` | `<vault>/.claude/settings.json` | `adapters/claude-code.json` |
| `codex` | `<vault>/.codex/hooks.json` | `adapters/codex/hooks.json` |
| `omp` | `<vault>/.omp/hooks/pre/knotlog.ts` | `adapters/omp/hooks/pre/knotlog.ts` |
| `gemini` | `<vault>/.gemini/settings.json` | `adapters/gemini/settings.json` (SessionStart, BeforeAgent, AfterTool, SessionEnd; no AfterAgent: its output is not documented as reaching the model) |
| `cursor` | `<vault>/.cursor/hooks.json` | `adapters/cursor/hooks.json` (sessionStart with `context --json SessionStart --cursor`, afterFileEdit with `capture`; per-prompt context is not wired: the documented beforeSubmitPrompt output has no context field) |
| `antigravity` | `<vault>/.agents/hooks.json` | `adapters/antigravity/hooks.json` (see [Antigravity](#antigravity)) |
| `windsurf` (alias `devin`) | `<vault>/.devin/hooks.json` | `adapters/windsurf/hooks.json` (see [Windsurf / Devin Desktop](#windsurf--devin-desktop)) |
| `opencode` | `<vault>/.opencode/plugins/knotlog.js` | `adapters/opencode/knotlog.js` (see [OpenCode](#opencode)) |

Per target, exactly one of three results is printed:

- **written**: the target did not exist; the shipped file was copied there.
- **already up to date**: the target is byte-for-byte the shipped file; nothing is touched.
- **preserved**: the target exists and differs. Nothing is written, and the shipped source path is printed so you can merge it by hand.

A file that exists is never overwritten. `--dry-run` prints the same decisions and writes nothing. An unknown agent name prints the supported list and exits 2. `install` does its own copy and is unchanged by this command.

## Uninstall

Trying Knotlog should not be a one-way door. Uninstall removes only what install
put **outside** your vault, and never touches the vault itself — those are your
notes, and deleting them stays a deliberate, separate act.

```bash
knotlog uninstall --dry-run   # show what would be removed
knotlog uninstall             # remove the command from PATH
```

It scans every `PATH` entry — not just the one install happened to pick, since
`PATH` may have changed since — and removes a `knotlog` there only when it is a
symlink that resolves into a real Knotlog checkout. A plain file, or a symlink
pointing anywhere else, is reported and left alone: matching on the name alone
would delete a stranger's command. Afterwards it prints the vault path and the
Knotlog machinery still inside it (`.claude`, `.omp`, `.icon`, `.directory`,
`desktop.ini`, `repair-hooks`, `.githooks`, `.gitignore`), plus the exact
`rm -rf` line to remove the vault yourself if that is what you want. Your
`.git` directory is not on that list: the history is yours, not leftovers.

**Windows**: the shims and PATH entry come from `install.ps1`, which is not a
POSIX symlink, so the command above cannot see them. Run the matching remover
from PowerShell:

```powershell
.\uninstall.ps1 -DryRun
.\uninstall.ps1
```

It deletes `%LOCALAPPDATA%\Knotlog\bin\knotlog.cmd` and the POSIX `knotlog` shim only
when their contents match what `install.ps1` writes, removes that directory when
it is left empty, and drops the entry it added to the user `PATH`. Restart the
shell afterwards to refresh `PATH`.

## Update

`knotlog update` checks this checkout — the Knotlog program itself, not your
vault — against the latest GitHub release, and updates it in place when asked.
Two checkout shapes behave differently: a **git clone** (`.git` present)
updates with `git fetch` + checkout of the release tag; a **tarball
checkout** (installed via `install.sh`, no `.git`) downloads and verifies the
release tarball, then swaps it in atomically.

```bash
knotlog update --check   # compare shipped version against the latest release
knotlog update --apply   # actually update: git fetch+checkout, or tarball swap
```

`--check` only reaches out to the network to compare versions — it never
touches a file. `--apply` does the real update. A bare `knotlog update`, with
neither flag, is a deliberate error rather than a silent no-op or a silent
network-touching default: an update that reaches the network and rewrites
files is not something that should happen just because a flag was forgotten.

An interrupted `--apply` on a tarball checkout leaves a staging directory
behind instead of a half-swapped checkout; the next `update --apply` or
`knotlog doctor` reports it explicitly rather than reusing or ignoring it —
nothing here fixes itself silently. `--apply` also keeps prior copies of the
checkout so `knotlog rollback` can undo updates: up to three, newest first
(`.knotlog-previous`, `.knotlog-previous.2`, `.knotlog-previous.3`); the oldest is
dropped when a fourth is made. Backups made before the rename (`.quipu-previous`
and its `.2`/`.3`) are renamed to the new names the first time `update --apply` or
`rollback` runs.

A tarball `--apply` downloads `knotlog-<version>.tar.gz` from the release's
assets together with `knotlog-<version>.tar.gz.sha256` (`<hex>  <filename>`,
as `sha256sum` writes it). The hash is computed with `sha256sum`, else
`shasum -a 256`, else `openssl dgst -sha256`, and compared **before** anything
is extracted; a mismatch, a missing hash file, or a hash file that names a
different file stops the update and leaves the checkout untouched. With none of
those tools installed the update refuses; `--no-verify` skips the check
(use it only for an archive you made yourself). Before downloading, `--apply`
also refuses if the directory holding the checkout is not writable, if an
interrupted update (`….quipu-update-staging`) or rollback
(`….quipu-rollback-tmp`) left its tree behind, or if free space (`df -P`) is
below twice the checkout size. The release workflow builds both files from the tag.

The download address is never taken from the release reply: only its
`tag_name` is read, and it must be a plain version token (letters, digits and
`. _ + -`), otherwise the run stops before fetching anything. Versions are
compared as numbers, never by file content: a checkout whose
version string equals the latest release counts as up to date even if its files
came from a different commit. A tarball `--apply` replaces the whole checkout
directory, so a file you edited (or added) inside it is not carried into the
new copy; it survives in the backups above, and `knotlog rollback` brings it
back. Each `update --apply` moves the older copies one slot down, so a copy
made by the first update is dropped only by the fourth. A git checkout leaves git in charge: a local
edit to a file the release changes makes `--apply` fail instead of overwriting it.

**Update never touches your vault.** It only ever changes the Knotlog checkout
— the program's own files — the same boundary [Uninstall](#uninstall) keeps:
your notes stay exactly where they are.

Rollback to the previous version: `knotlog rollback` restores the checkout from
the newest backup (`.knotlog-previous`). Each rollback steps one copy further
back, so running it again goes to the next older version; when no backup is
left it says so and changes nothing.

## Commands

| Command | What it does |
|---|---|
| `knotlog help [--<code>]` | show English help by default; `--<code>` (e.g. `--tr`, `--ja`) prints it in any shipped language |
| `knotlog doctor` | environment diagnostics: tools present, agents installed, what's broken |
| `knotlog init` | create `.knotlog/` + ten layout folders + AGENTS.md/CLAUDE.md bridges (`--plain`: ASCII names; `--layout tr|en`: localized number-free names; repeated `--scope goals|money|body|mind`, or `full`, adds optional folders) |
| `knotlog migrate [--apply]` | bring a pre-rename (Quipu) vault over to Knotlog: renames `.quipu/` to `.knotlog/`, rewrites the `QUIPU_*` keys in the state folder's `config`, the `<!-- quipu:` block markers, the hook commands in `.claude/settings.json`, `.codex/hooks.json`, `.gemini/settings.json`, `.cursor/hooks.json` and `.agents/hooks.json`, the `.quipu` entries in `.gitignore`, the secret-gate hook and the old omp hook (replaced by `knotlog.ts`). Dry run unless `--apply`; safe to repeat. A bridge block in `AGENTS.md`/`CLAUDE.md` is refreshed only if unedited; a hand-edited one keeps its text, only its markers are renamed, and a warning says so. Stops if both `.quipu/` and `.knotlog/` exist |
| `knotlog setup <agent> [--dry-run]` | write one agent's hook file into the vault (`claude`, `codex`, `omp`, `gemini`, `cursor`, `antigravity`, `windsurf`, `opencode`); an existing, differing file is never overwritten; see Setup |
| `knotlog tui` | browse the newest session notes in the terminal; see Terminal browser |
| `knotlog mcp` | run a stdio MCP server exposing `knotlog_search`, `knotlog_context` and `knotlog_note`; takes no arguments; see MCP server |
| `knotlog uninstall` | remove the `knotlog` command from PATH; never touches your vault (`--dry-run` previews) |
| `knotlog capture` | append event line(s) to `activity.log` (stdin or `--event`/`--tool`/`--path`; `--git`: multi-line tree diff) |
| `knotlog index` | build/refresh `.knotlog/index.tsv` (incremental; `--full` rebuilds) |
| `knotlog compile` | manual, deterministic: writes one derived note per concept under the knowledge folder's `Compiled/` (first/last seen, occurrences, source pointers, co-mentioned concepts), built from `index.tsv`, wikilinks and Markdown headings; needs an existing `index.tsv` (run `knotlog index` first); takes no arguments; the notes are derived, not your memory, and never enter context |
| `knotlog search` | folded lexical search + BM25 (`--tag`/`--status`: narrow by frontmatter; `--all`: include `validity: rejected` notes) |
| `knotlog links` | print a note's outgoing/incoming `[[wikilinks]]` |
| `knotlog context` | recent-session context; `--json EVENT` emits the hook envelope; `--cursor` (with `--json`) emits Cursor's `additional_context` shape instead; `--antigravity` (with `--json SessionStart` or `Stop`) emits Antigravity's shapes; `--bridge` writes it to AGENTS.md |
| `knotlog remember` | mechanical digest: `activity.log` → `<sessions>/YYYY-MM-DD.md` + a pointer block in the session file doctor reads (`Last-Session.md`, `Son-Oturum.md` in a Turkish vault) (`--dry-run`/`--git`/`--limit`) |
| `knotlog note "<text>"` | appends one line (`- HH:MM <text>`) to today's session reflection block, after the existing lines of the first heading; never rewrites other lines; shares `remember`'s lock |
| `knotlog digest` | write/refresh a deterministic date-scoped digest under the layout's dump folder (`--date YYYY-MM-DD`, `--dry-run`, `--limit`; or `--since YYYY-MM-DD [--until YYYY-MM-DD]` to print a range to stdout) |
| `knotlog note --thread "<text>"` | appends one line (`- HH:MM <text>`) to the end of the active threads section (`Threads.md` / `Konular.md`) inside the threads block; never inside the pin block; exits 1 and writes nothing when the file or the active section is missing; shares `remember`'s lock |
| `knotlog import FILE` | convert a local JSON export with role/content messages (Claude transcript, ChatGPT export, or JSONL) into a session note (`--date YYYY-MM-DD`) |
| `knotlog plan <name> --proje <Project>` | open a plan note under `<projects>/<Project>/<Plans>/` from the localized front-matter template; a missing project folder is an error, never auto-created |
| `knotlog tone [--list\|<slug>]` | show which tone is active and why (preset or companion.md); `--list` browses the nine shipped presets; `<slug>` writes `tone=` to `.knotlog/config` (never touches companion.md) |
| `knotlog compact [--keep N] [--apply]` | move old `Closed threads` entries of `Threads.md` into the archive, losslessly; dry run unless `--apply`; the newest `--keep N` (default 20) stay; also trims the last-session file (newest 5 `## ` blocks stay, or `--keep N`); see Session reflection |
| `knotlog update --check` | compare this checkout's version against the latest GitHub release; network read only, touches no file |
| `knotlog update --apply [--no-verify]` | update this checkout in place (tarball checkout: download, SHA-256 check, atomic swap; git-clone checkout: `git fetch` + checkout `<tag>`); bare `knotlog update` errors on purpose |
| `knotlog rollback` | undo the last `update --apply`, restoring the checkout from its newest backup (`.knotlog-previous`); repeat to step back through up to three |

## Claude Code
The `adapters/claude-code.json` adapter wires Knotlog into Claude Code's local hooks. This is the first adapter **verified against a live session** and the most tested one; prefer it when you have the choice. It wires four hooks: `SessionStart` injects recent-session context, including: a `now: <date> <time> <weekday>` line (so the model writing memory later knows what time it is instead of guessing); an `identity: companion=…, user=…` line whenever `.knotlog/config` has those keys set (with a `purpose: …` line when `init --purpose` set one); a tone block — `.knotlog/config`'s `tone=<slug>` preset when one is set and shipped (`knotlog tone --list` shows the nine choices), otherwise companion.md's own Tone section (`## Üslup`/`## Tone`, resolved in either language) — closed with a one-line note that it never outranks the rules file; the localized rules file's headings (`Kurallar.md`/`Rules.md` — seeded by `init` with four sections: approval gates, zero-level protocols, the receipt rule, and record discipline); and the localized facts file's fact lines (`Gerçekler.md`/`Facts.md` — seeded once and silent in context until you add the first fact) — so the model sees who it and the user are, which behavior contract holds, and how to speak, without reading the rest of `companion.md` itself (only its Tone section reaches context) — plus `PostToolUse` capturing `Edit|Write|NotebookEdit|Read` events into `activity.log` (async, silent), `UserPromptSubmit` nudging the model to write memory o…

`knotlog install` places this adapter at `<vault>/.claude/settings.json`, making the hook configuration project-scoped and ready on a fresh vault. If that destination is already byte-identical, reinstall is a true no-op with no mtime churn. If it differs, Knotlog preserves the existing file byte-for-byte and prints a warning naming both the destination and `adapters/claude-code.json`; review and merge the adapter's `hooks` object manually. Knotlog never overwrites or automatically merges arbitrary Claude settings.

- `knotlog` must be on your `PATH` for the hooks; otherwise write its absolute path in each `command`.
- **Restart Claude Code after editing `settings.json`** — hook configuration is not loaded into a running session.
- On Windows, Git for Windows puts only `cmd/` on `PATH` — if a hook reports `Executable not found in $PATH: bash`, add `C:\Program Files\Git\bin` to `PATH` (or write the absolute bash path in the `shell` field).
- `knotlog remember --git` auto-commits the vault (`--git` is opt-in; the adapter never commits by itself).
- **Profiles.** `profile=` in `.knotlog/config` bundles how much context the hooks inject. `normal` (the default, also for an absent or unknown value; `doctor` warns on an unknown one) changes nothing. `economical` caps the session-start context at 4000 bytes and silences the per-turn output (the prompt nudge and the Stop reminder); `manual` injects nothing at session start or per turn. In both, `capture`, `remember` and `index` still run, and `knotlog context` run by hand prints normally. Precedence for the size cap: `KNOTLOG_CTX_MAX` (env) > `ctx_max=` > `economical` (4000) > default (4096). `doctor` prints a `profile` row only when the key is set.
- Languages: the supported set is the set of `i18n/<code>.txt` files; nothing else lists languages. Codes are lowercase file names — `en`, `tr`, `pt-br`, `zh-cn` — and `--lang`, `lang=`, `KNOTLOG_LANG` and `LANG` accept any case and `_` for `-` (`pt_BR.UTF-8` and `PT-BR` both mean `pt-br`; a region with no file of its own, such as `en_US`, means its language). An unsupported code works as English. The install wizard accepts the same spellings. Per-language assets (`persona/`, `templates/`, `tone/`, `layout/<code>.txt`, `layout/scope-<code>.txt`) are optional and fall back to English. The fold profile follows the language: `tr` → `tr`, `es`/`pt-br` → `latin`, every other language → `default`.
- Env knobs: `KNOTLOG_CTX_MAX`, `KNOTLOG_NUDGE_AFTER`, `KNOTLOG_CHECKPOINT_AFTER`, `KNOTLOG_LOG_MAX`, `KNOTLOG_HOOK`. `KNOTLOG_CTX_MAX` also has a vault-local fallback — `.knotlog/config`'s `ctx_max=` — so the setting survives moving the vault to another machine, where an env var would not; `doctor` reports which one is in effect. Each `KNOTLOG_*` setting (and `KNOTLOG_VAULT`, `KNOTLOG_LANG`, `KNOTLOG_HOME`) also answers to its pre-rename `QUIPU_*` name; when both are set, `KNOTLOG_*` wins.

## Handoff cards (parallel sessions, two machines)

When `remember` runs from a hook, it reads the hook payload on stdin and writes the pointer into the last-session file as a **card** of its own: `## <YYYY-MM-DD HH:MM> · <client> · <id8>`, where `id8` is the first 8 characters of `conversation_id` (Cursor), `trajectory_id` (Antigravity; Windsurf / Devin Desktop when the payload also has `agent_action_name`, labelled `devin`) or `session_id` (Claude Code, Codex, Gemini CLI; the client is read from `transcript_path`, otherwise `agent`). A hex or UUID id is cut to its first 8 characters; a word slug, such as Devin Desktop's `flax-drip`, is kept whole (up to 24 characters), because its first 8 characters would cut a word. A later `remember` from the same session replaces only that card and moves it to the bottom, so the last `## ` block is always the newest (doctor D3, `compact`); other sessions' cards are never touched. Without an id (CLI use, the omp hook, which has no payload) `remember` keeps updating the single marked block as before. An old marked block is left as it is when the first card is written.

`init`, `install` and `migrate --apply` add `merge=union` lines to the vault's `.gitattributes` (created if missing, never duplicated, your lines kept) for the files that only grow by appending: the last-session file and, if present, the journal. The threads file and the `AGENTS.md`/`CLAUDE.md` blocks are rewritten in place, so union would duplicate or resurrect lines there. If the same card was edited on both machines, a merge keeps both copies; the next `remember` of that session collapses them. `doctor` warns once when a git vault lacks the line.

## Checkpoint signal (mid-session memory guard)

When agents work across multiple turns without writing a session note, memory can be lost if a session ends abruptly. Knotlog includes a git-aware checkpoint signal:
- **Condition:** If the session note (`<sessions>/<today>.md` or `<yesterday>.md`) is older than `KNOTLOG_CHECKPOINT_AFTER` seconds (default: 1800s / 30 minutes) and there is work in the vault since the note was touched (a newer commit or a modified tracked file), a checkpoint is due. If the vault is not a git repository or git is unavailable, the signal remains silently inactive.
- **Nudge (`context --json UserPromptSubmit`):** When due, appends a localized reminder (`ctx_checkpoint_due`) asking the model to write a short note bullet. Rate-limited by `.knotlog/checkpoint_nudged` so it triggers at most once every `KNOTLOG_CHECKPOINT_AFTER` seconds.
- **Block (`context --json Stop`):** Intercepts turn completion. If stdin does not contain `"stop_hook_active": true` and a checkpoint is due (and not already nudged within the threshold), outputs `{"decision":"block","reason":"<checkpoint text>"}` to trigger a continuation turn, and updates `.knotlog/checkpoint_nudged`.
- **Adapters:**
  - **Claude Code:** `Stop` hook blocks turn once; `UserPromptSubmit` nudges.
  - **Codex:** `Stop` hook blocks turn once; `UserPromptSubmit` nudges.
  - **omp:** `agent_end` hook calls `context --json Stop` and injects only the checkpoint reason.
  - **Hook-less:** invoke `knotlog context --json Stop` or `UserPromptSubmit` programmatically.

## Codex

> **Live-verified on Codex CLI 0.153.0 (2026-09-03):** after the hook configuration is trusted, Codex dispatches `SessionStart`, `UserPromptSubmit`, `PreToolUse(apply_patch)`, `PostToolUse(apply_patch)`, `Stop`, and `SessionEnd`. The real `PostToolUse` payload puts the patch in `tool_input.command` using the native `*** Begin Patch` / `*** Add File:` / `*** Update File:` / `*** Delete File:` envelope (moves use `*** Move to:`), rather than the synthetic `+++ b/...` unified diff used by older fixtures. Knotlog parses both forms, preserves spaces and Unicode, strips line-breaking control bytes, and records every affected path. Codex hashes hook commands; approve the trust prompt once in the interactive TUI, then restart Codex after installing or changing the file. The trusted configuration also dispatches hooks from `codex exec`.

`adapters/codex/hooks.json` wires Knotlog into Codex CLI's local hooks: `SessionStart` chains `remember` + context injection, `UserPromptSubmit` nudges the model, `PostToolUse` synchronously captures native `apply_patch` events into `activity.log`, and `SessionEnd` chains `remember` + `index`. The parser accepts both Codex's native `*** Begin Patch` envelope and legacy `+++ b/...` unified-diff payloads. Copy it to `~/.codex/hooks.json` (global) or `.codex/hooks.json` (project-scoped) — there is no installer. Hooks are enabled by default; disable with `[features] hooks = false`. **Then start the interactive `codex` TUI once and approve the trust prompt** — until you do, the hooks are loaded and enabled but never run.

- `knotlog` must be on your `PATH`. **Restart Codex after installing the file** — hooks are read once at session setup; there is no watcher.
- Windows: `commandWindows` fields run under `cmd.exe /C` via `set KNOTLOG_HOOK=1&& knotlog …` (a POSIX env prefix is invalid there); the field is parsed and accepted, but the end-to-end run above was on Linux, so Windows remains unexercised.
- Codex clamps hook timeouts to 3s, so the adapter asks for 3 rather than declaring a number the runtime will not honour (it warns otherwise). The synchronous `capture` command records the affected paths before the next turn continues; a very large patch can still be bounded by the hook timeout.
- Honest limit: the adapter captures `apply_patch` events, not arbitrary shell edits. Native Add/Update/Delete paths are recorded; a move records both source and destination. The parser retains legacy `+++ b/...` payloads for older clients and fixtures, while malformed or truncated native envelopes are ignored. If hooks are disabled, untrusted, or unavailable, use `knotlog context --bridge` as the recovery path. See [One protocol, two bridge files](#one-protocol-two-bridge-files).
- **`codex exec` is supported after trust.** Hooks can run in both the interactive TUI and non-interactive `codex exec`; trust the installed commands once from the TUI first. The bridge remains useful when hooks are intentionally disabled or unavailable.

## omp

[omp (oh-my-pi)](https://github.com/can1357/oh-my-pi) is a TypeScript coding-agent harness with its own hook system. `adapters/omp/hooks/pre/knotlog.ts` wires Knotlog into its `session_start` hook: it runs `knotlog remember`, then `knotlog context --json SessionStart`, then feeds the parsed `additionalContext` back in as a silent (`display: false`) message so the model sees recent-session context without cluttering the transcript. Copy it into the vault's `.omp/hooks/pre/` directory (project-scoped) or `~/.omp/agent/hooks/pre/` (global) — or let `knotlog install` do exactly that for the vault it creates, keeping the repo copy as the source of truth on every reinstall.

> **Best-effort: verified once, against a single live install.** Unlike Codex, this one *has* been observed working in a real session (2026-08-24, companion identity injected correctly). One data point, not a suite: the adapter is not covered by `tests/run.sh` because omp needs a JS runtime and pulling one into CI would violate the zero-dependency principle. Between the two: stronger evidence than Codex, weaker than Claude Code.

`knotlog` must be on your `PATH` for the hook (see [Install](#install)).

## Antigravity

`knotlog setup antigravity` writes `adapters/antigravity/hooks.json` to `<vault>/.agents/hooks.json` (same written / already up to date / preserved rules as every other agent; `--dry-run` writes nothing). The file binds two hooks under a `knotlog` key, each running with `KNOTLOG_HOOK=1`:

- **`SessionStart`** (timeout 30 s) runs `knotlog remember`, then `knotlog context --json SessionStart --antigravity`. The context is returned as `{"injectSteps":[{"systemMessage":{"systemMessage":"<context>"}}]}`, so Antigravity injects it as a system message step.
- **`Stop`** (timeout 10 s) runs `knotlog context --json Stop --antigravity`, the [checkpoint signal](#checkpoint-signal-mid-session-memory-guard) as a save guard. Antigravity wants a decision every time, so the hook always answers one:
  - `{"decision":"continue","reason":"<checkpoint text>"}` when a checkpoint is due: the turn re-enters the loop so the model can write its note. At most once per `KNOTLOG_CHECKPOINT_AFTER` seconds (default 1800).
  - `{"decision":"allow"}` otherwise: inside that window, nothing to save, or when the payload says `"fullyIdle":false`.
- Any other event with `--antigravity` answers `{}`. There is no `stop_hook_active` field here; the 1800 s throttle is the loop guard.
- `knotlog migrate` also rewrites a pre-rename `.agents/hooks.json`.

Restart Antigravity after the file is written. This adapter is covered by `tests/run.sh` (T-840..T-853), not yet verified against a live session.

## Windsurf / Devin Desktop

`knotlog setup windsurf` (or `devin`) writes `adapters/windsurf/hooks.json` to `<vault>/.devin/hooks.json` (Windsurf is now Devin Desktop; the legacy `.windsurf/hooks.json` is only read when the new file is absent or empty). Context comes from the `AGENTS.md` bridge block, which Windsurf reads natively: no documented hook injects context into the model, so these hooks only record. Both exit 0 so they never block the user, and each has a `powershell` twin for Windows.

- **`post_write_code`** runs `knotlog capture`; the edited path is read from `tool_info.file_path` and logged as event `post_write_code`, tool `Write`.
- **`post_cascade_response`** runs `knotlog remember`, then `knotlog index`. Windsurf has no session-end event, so this runs after every response. That is safe: `remember` only appends what is new since its watermark (nothing new, nothing written) and replaces the session's own card (`trajectory_id`), and `index` is incremental.

Hooks run `knotlog` from the client's environment, and Devin Desktop takes it from your login shell: `knotlog` must be on the login-shell `PATH` (what `install` links), or the hook silently does nothing.

Live-verified on 2026-10-25, Linux, Devin Desktop 3.11.216: `post_write_code` captured an edit, `post_cascade_response` ran `remember` and `index`, and the card was written as `· devin · <slug>`. Not verified: Windows, and that `agent_action_name` is absent from Antigravity payloads (it is what separates the `devin` label from `antigravity`). Covered by `tests/run.sh` (T-975..T-982).

## OpenCode

`knotlog setup opencode` writes `adapters/opencode/knotlog.js` to `<vault>/.opencode/plugins/knotlog.js`, which OpenCode loads at start-up. It is a plain JS module run by OpenCode's own Bun, with no imports and nothing to install. Context comes from the `AGENTS.md` bridge block (OpenCode reads it natively); the plugin only records and never throws.

- **`file.edited`** runs `knotlog capture --event file.edited --tool Write --path <file>`.
- **`session.idle`** runs `knotlog remember`, then `knotlog index`.

The plugin runs `knotlog` from OpenCode's environment, so `knotlog` must be on the `PATH` OpenCode starts with, or it silently does nothing. OpenCode sends no session id, so `remember` keeps a single block.

Live-verified on 2026-10-25, Linux, OpenCode 1.19.4: `file.edited` captured an edit, and `session.idle` ran `remember` and `index`. Not verified: Windows. Covered by `tests/run.sh` (T-975..T-982) for the written file only; the JS is not executed in CI.

## Terminal browser

`knotlog tui` lists the newest 20 session notes (newest first) and takes no arguments. Keys are letters only:

| Key | Action |
|---|---|
| `j` / `k` | move down / up |
| `Enter` | open the note in a built-in pager (`Space` next page, `b` back, `q` back to the list) |
| `/` | prompt for a query, then list the results of `knotlog search --brief --limit 50`; `q` returns to the session list |
| `q` | quit |

The terminal is restored on every way out (`q`, Ctrl-C, errors). When stdin or stdout is not a terminal, or `TERM` is unset or `dumb`, it prints the session list once as plain text and exits 0, without touching terminal settings. Arrow keys are not supported yet.

## MCP server

`knotlog mcp` is a stdio [MCP](https://modelcontextprotocol.io) server: one JSON-RPC message per line on stdin, one reply per line on stdout. It takes no arguments (anything else exits 2) and, like the rest of Knotlog, needs only `sh` and `awk`. It exits on SIGINT, SIGTERM and SIGHUP (statuses 130, 143, 129), and on end of input.

Methods: `initialize`, `ping`, `server/discover`, `tools/list`, `tools/call`. Notifications get no reply; an unknown method is `-32601`.

| Tool | Arguments | Returns |
|---|---|---|
| `knotlog_search` | `query` (string, required), `limit` (integer, optional, at least 1) | the lines of `knotlog search --brief [--limit N] <query>` |
| `knotlog_context` | none | the output of `knotlog context` |
| `knotlog_note` | `text` (string, required; not empty, not starting with `-`) | runs `knotlog note <text>`: one line appended to today's session reflection block; the only tool that writes, and it writes nothing else |

A wrong argument shape or an unknown tool is a protocol error (`-32602`). A tool that ran and failed is a normal result with `isError: true` and the command's message as text.

**The vault.** Tool calls run `knotlog` itself, so the vault is found the usual way: the nearest ancestor of the server's working directory holding `.knotlog/config`, or `KNOTLOG_VAULT`. Register the server from inside the vault, or set `KNOTLOG_VAULT`. With no vault, tools return the "vault not found" message as an error result.

Claude Code (run from the vault; use the absolute path to `knotlog` if it is not on `PATH`). This registers it in local scope, for you in this folder only; add `-s project` to write a shared `.mcp.json` at the vault root instead:

```
claude mcp add knotlog -- knotlog mcp
```

or by hand in `.mcp.json` at the vault root:

```json
{ "mcpServers": { "knotlog": { "command": "knotlog", "args": ["mcp"], "env": { "KNOTLOG_VAULT": "/path/to/vault" } } } }
```

## Hook-less agents

Agents without a local hook surface get two fallbacks in the core — no config file required:

- **`knotlog capture --git`** — diff the working tree against the last commit and append one `gitdiff | git | <path>` line per changed Markdown file to `activity.log`. Silent on success. Run it manually before `knotlog remember`.
- `remember` serializes its append-and-watermark transaction. If another invocation still owns the lock after 5 seconds, it warns and skips without advancing `.knotlog/remembered`; standalone calls exit nonzero, while `KNOTLOG_HOOK=1` calls remain successful so the surrounding hook chain can continue. The activity log is therefore retried by the next `remember`, rather than discarded.
- **`knotlog context --bridge`** — write the recent-session context into a dedicated `<!-- knotlog:context:start -->` / `<!-- knotlog:context:end -->` block in **both** `AGENTS.md` and `CLAUDE.md`; the static `<!-- knotlog:start -->` block (created by `init`) is left untouched, and hand-written text outside the markers survives. The agent reads whichever of the two files it already reads, and sees the same memory.

`capture --git` is stateless (no `Read` events; re-runs without a commit duplicate lines) — see [Honest limits](#honest-limits).

## One protocol, two bridge files

Different agents read different files: Claude Code opens `CLAUDE.md`, most others (Codex included) open `AGENTS.md`. Knotlog writes the **same** content to both, so the choice of agent never decides how much of the vault an agent knows about:

- `init` writes the identical protocol body — layout, companion identity, append-only rule, session-end protocol — into the `<!-- knotlog:start -->` block of each file.
- `context --bridge` writes the identical recent-session context into the `<!-- knotlog:context:start -->` block of each file.

That symmetry is what lets a session in one agent pick up where a session in another left off: work done through Codex reaches Claude, and work done through Claude reaches Codex, without either being asked to open the other's file.

Duplicated text normally drifts apart. Here it cannot: both blocks are marker-delimited, tool-owned, and rewritten from one source on every run — so the fix for a stale copy is to run the command again, never to hand-edit. Everything **outside** the markers is yours and is never touched, which is why a hand-written `CLAUDE.md` can carry your own project instructions alongside Knotlog's block.

## Vault layout

`./knotlog install` — and `init --layout en|tr` directly — create ten folders using the localized, number-free names for the language you picked (English shown, Turkish in parentheses):

- **📥 Inbox** (`📥 Gelen Kutusu`) — capture point for quick, unprocessed notes
- **🗑️ Trash** (`🗑️ Çöp Kutusu`) — unsorted dump, its own top-level folder
- **🎯 Command Center** (`🎯 Komuta Merkezi`) — dashboard and daily entry point
- **🗂️ Projects** (`🗂️ Projeler`) — active work, one subfolder per project
- **🧠 Knowledge** (`🧠 Bilgi`) — long-lived notes and references
- **🛠️ Arsenal** (`🛠️ Aletler`) — tools, scripts and reusable snippets
- **📆 Sessions** (`📆 Oturumlar`) — per-session memory, written by `knotlog remember`
- **🔮 Companion** (`🔮 Asistan`) — companion persona and identity
- **📦 Archive** (`📦 Arşiv`) — finished or frozen material
- **📋 Templates** (`📋 Şablonlar`) — three note skeletons (note, project, session) to copy out; the folder was once left empty to keep seeds out of the index, and now the index excludes it instead

A bare `knotlog init` (no `--layout`, skipping `install` entirely) instead creates the older numbered emoji layout — `📥 000-Inbox`, `📥 000-Inbox/Dump`, `🎯 100-Command-Center`, `🏰 300-Projects`, `🧠 500-Knowledge`, `🛠️ 600-Arsenal`, `📆 700-Sessions`, `🔮 850-Companion`, `📦 900-Archive`, `📋 Templates` — and `init --plain` creates the same structure with ASCII-only names (`000-Inbox`, `000-Inbox/Dump`, `100-Command-Center`, …). Whichever layout is chosen is only applied when the folders are first created; existing vaults are never renamed or migrated to a different layout.

Optional scope folders are additive and persisted in `.knotlog/config`:
`init --scope goals|money|body|mind` may be repeated, and `--scope full`
adds all four localized folders (`⚔️ Hedefler`, `💰 Para`, `🫀 Beden`,
`🧘 Zihin` in Turkish; English equivalents in an English layout).
`core` records the core-only selection and adds no optional folder. Existing
folders and notes are never removed.

`knotlog digest --date YYYY-MM-DD` filters `activity.log` to that date and
refreshes `<dump>/YYYY-MM-DD-digest.md`; `--dry-run` prints without writing.
It is independent from `remember` and never advances `.knotlog/remembered`.

`knotlog digest --since YYYY-MM-DD [--until YYYY-MM-DD]` prints, to stdout only, the digest of each
day that has a `YYYY-MM-DD.md` session note in the sessions folder within the range (`--until`
defaults to today). Days are chosen by file name, not by activity; a day with no events prints the
`no activity events` line. Range mode never writes files. `--date` cannot be combined with it, and
`--until` requires `--since`; malformed dates exit 2.

`knotlog import FILE --date YYYY-MM-DD` parses a local Claude, ChatGPT, or
JSONL role/content export (including ChatGPT's `author.role` and
`content.parts`) and writes a Markdown session note under `<sessions>`.

**Repairing moved vaults.** Each installed vault includes `repair-hooks`
and `repair-hooks.ps1`. If the vault is renamed/moved or the Knotlog checkout
changes location, manually run `./repair-hooks --knotlog /path/to/knotlog` (or
PowerShell `.\repair-hooks.ps1 -Knotlog C:\path\to\Knotlog`). The entrypoint
rewrites only Knotlog-owned Claude command strings to the supplied absolute
checkout path and preserves unrelated user settings. Restart Claude Code and
the parent shell afterward. This explicit source argument is intentional:
hooks cannot reliably self-repair when their old launcher is already stale.

The same repair refreshes Linux `.directory` metadata and Windows
`desktop.ini` against `.icon/knotlog.png` and the valid `.icon/Knotlog.ico`
asset. Explorer may need a refresh or reopen after metadata changes.

`init` never renames or deletes. A vault from before this layout keeps its old folders (`📥 100-Inbox`, `🚧 300-Projects`, `📚 500-Knowledge`) and gains the new ones — moving notes is yours to do; there is no migration script. `Dashboard.md`, `Threads.md`, and `companion.md` are seeded only if absent and never touched again; `companion.md`'s seed includes an accumulating "never forget" block that survives `init` re-runs.

**Tone presets.** `knotlog tone --list` shows nine shipped presets — Default,
Professional, Friendly, Candid, Quirky, Efficient, Snarky, Teaching, Kaomoji — each a
data file under `tone/<lang>/<slug>.md`, not code. `knotlog tone <slug>` writes
`tone=<slug>` to `.knotlog/config`; a preset named there wins over
companion.md's own Tone section whenever the file actually ships for the
vault's language. Leave `tone=` unset (or point it at a slug that doesn't
exist) and context falls back to companion.md's Tone section exactly as
before presets existed — an invalid `tone=` is never a hard error, only a
`doctor` warning. `knotlog tone` (no arguments) prints which source is active
and why. `init --tone <slug>` and `install --tone <slug>` set the same key
without an interactive question — like `--purpose`, there is no prompt for
it, only the flag.

## Notes: frontmatter and wikilinks

`knotlog index` reads four frontmatter fields when present — `title:`, `tags:`, `status:`, `type:` — plus a `# Heading` title fallback and inline `#tag` words in the body. `status:`/`type:` have no fixed vocabulary; `search --status <durum>` matches whatever string is there exactly.

**Line endings.** A note saved with Windows (CRLF) line endings has its frontmatter read exactly like an LF note: the trailing carriage return is ignored on the `---` fence lines and on the `title:`/`tags:`/`status:`/`type:`/`aliases:` lines, and never reaches the index. The file itself is never rewritten.

**Aliases.** A frontmatter `aliases:` key makes a note findable under other names, wherever the key sits in the frontmatter: inline (`aliases: [ses ofseti, "audio offset"]`), as a YAML block list (`aliases:` with `- item` lines under it), or as a single value (`aliases: ses`). The words are folded like the note text (`açık` and `acik` match), and an alias weighs like the title: a note whose alias matches ranks above one that only mentions the word in its body. Only the frontmatter counts — an `aliases:` line further down the note is ordinary text. `search` output is unchanged. An index built by an older Knotlog upgrades itself on the next `knotlog index` (it notices the missing `.knotlog/index.schema` and rebuilds once).

**Status alphabet.** Knotlog renders no status mark itself — but if your notes follow the `🟢 active · 🟡 progress · 🔴 blocked · ⚪ paused` convention (the [avenoxbeyin](https://github.com/avenoxai/avenoxbeyin) template's alphabet), the slug-to-mark mapping lives in `layout/status.txt` (`slug<TAB>mark`) as DATA, not code — nothing hardcodes a status emoji.

`index` also scans each note body (frontmatter skipped) for `[[wikilink]]` targets and writes `.knotlog/links.tsv` (one row per occurrence — duplicates kept, the count is meaningful). All three Obsidian forms resolve to the same target: `[[Note Name]]`, `[[Note Name|shown text]]`, and `[[Note Name#Section]]` all extract `Note Name`.

`knotlog links <yol>` prints a note's outgoing and incoming links in two sections:

```
$ knotlog links taskbar.md
outgoing links
dpi.md
incoming links
dashboard.md
```

Resolution goes through three stages, stopping at the first match: literal vault-relative path (as written, or with `.md` appended — the Obsidian bare-name convention), then title (frontmatter `title:` or heading fallback), then filename stem searched vault-wide. A stage matching more than one candidate is reported as ambiguous rather than silently resolved. `doctor` warns `doc_links_broken` (exit stays 0) for targets matching nothing and `doc_links_ambiguous` for multi-matches; `links`'s incoming section only lists a link once its target resolves unambiguously.

## Search

`knotlog search <terms>` folds the query with the vault's fold profile, scores the index with BM25, and prints the best `--limit` rows (10 by default) as TAB-separated columns:

```
<score>  <path>  <title>  <tags>
```

- `--paths` — path column only, one per line: `knotlog search dpi --paths | xargs $EDITOR`.
- `--brief` — append a fifth column holding a 120-byte snippet (see [Large vaults](#large-vaults)). Mutually exclusive with `--paths` (exit 2).
- `--tag <etiket>` / `--status <durum>` — elimination filters on frontmatter, folded like the query, combined as AND: `knotlog search taskbar --tag ui --status active`. A non-matching note is dropped entirely, not just ranked lower.
- `validity: rejected` — a note whose frontmatter says `validity: rejected` (case-insensitive; spaces and quotes around the value are ignored) is a retired record: it stays on disk but is skipped by `search` (and so by the MCP `knotlog_search` tool) and by `compile`. `--all` brings rejected notes back into the results. Any other value, or no field, changes nothing.
- Unknown `-`-prefixed arguments are rejected (`unknown flag: --nope`, exit 2); bare words remain query terms.

**Long notes are searched in full.** The whole note is searchable, not just its first 2000 characters (see [Large vaults](#large-vaults), "Index size"). Results stay one row per note; the score is the best of the note's opening and its best-matching block, so a term that sits only in the tail of a long note finds the note. With `--brief`, when a block from further down the note is the best match, the snippet reads `[heading > path] text…` (folded, like every snippet) and starts just before the match, so you can see which section to open. The other columns are unchanged. A query with several terms scores each block on its own: terms that are spread over different sections of one long note do not add up across sections.

**Honest limit — `--tag` compares folded against raw.** The tags column in `index.tsv` stores frontmatter verbatim; `--tag`'s argument is folded. A tag written `#İstanbul` will not be found by `--tag istanbul`. `--status` has the same gap, rarely bitten because status values are conventionally short ASCII words. Not fixed in this release.

## Large vaults

The index is meant to be *read* by the agent, and an agent has a context budget. Once the vault outgrows a single read, the supported pattern is two-stage: **narrow with `--brief`, judge from the snippets, then read only the notes you picked.**

```
$ knotlog search taskbar --limit 50 --brief
0.706	taskbar.md	Taskbar overflow	windows,ui	# taskbar overflow  #windows #ui  the taskbar overflow chevron hides pinned apps whenever the dpi scale of the second
0.675	dpi.md	DPI notes	windows	# dpi notes  #windows  per-monitor dpi awareness, and how the taskbar reacts to it.
$ cat taskbar.md          # the agent opens the two or three it chose, not all fifty
```

Fifty snippets cost a fraction of fifty files, and choosing between them is exactly the judgement the model in the loop is already good at.

**Output shape.** The snippet is the first 120 bytes of the folded search field, cut back to the last word boundary — no ellipsis, nothing to strip. In a `fold=default` vault, whether 120 means characters or bytes depends on the platform's awk (gawk counts characters, mawk bytes); a multi-byte character can be split if those 120 bytes contain no space.

**Index size.** `.knotlog/index.tsv` is one line per note, seven TAB-separated columns: path, title, tags, mtime, the folded search field (capped at 2000 characters), status, type — the last two straight from frontmatter, empty when absent. That field is capped at 2000 characters, but the cap no longer hides the rest of a long note: a note that reaches it also gets rows in `.knotlog/blocks.tsv` (path, title, tags, heading path, folded block text of at most 2000 characters, status) that cover its whole text, cut at headings (`#`–`######`, outside fenced code), at line ends when a section is longer than 2000 characters, and at word boundaries when a single line is. `search` scores those rows like notes and reports the best one per note. Notes under the cap have no block rows and score exactly as before; the counts behind BM25 (note count, average length, document frequency) come from `index.tsv` alone. Cost: `blocks.tsv` is roughly the size of the folded text of the long notes (about 5.6 MB for 1000 notes of 6 KB), and the first `knotlog index` after upgrading rebuilds everything once. `blocks.tsv` follows the same incremental plan as `index.tsv` (a changed note gets fresh rows, a deleted note's rows drop out, an unchanged note is not reprocessed; `--full` rebuilds it) and is machine state like `index.tsv`: newly seeded vaults git-ignore it, an existing vault's `.gitignore` is yours to update. If `blocks.tsv` is missing beside a filled `index.tsv`, the next `knotlog index` rebuilds both without `--full`; `doctor` reports a missing or out-of-step `blocks.tsv` as an `info` row. The notes themselves are never modified and every hit still points at the complete file. An old-schema `index.tsv` (fewer than seven columns) is detected automatically on the next `knotlog index` (no `--full` needed) and fully rebuilt; `doctor` warns in the meantime.

**Extra folders to skip.** `index_exclude=` in `.knotlog/config` lists folder names, separated by spaces, that the index and search skip at any depth (for example `index_exclude=Drafts Archive`). The built-in skips (`.git`, `.knotlog`, `.quipu`, `node_modules`) stay in force. An entry containing `*`, `?`, `[`, `]`, `/` or `\` is not a single folder name and is ignored without a message. Changing the list takes effect on the next `knotlog index`: notes in newly excluded folders drop out of `index.tsv` and `blocks.tsv`, and notes in a folder that is no longer excluded are indexed again.

**Ceilings, past and present.** Earlier versions loaded the whole index into memory and spawned a child process per changed file — the first index of a 5000-note vault took ~36–39 minutes on Windows msys. Phase 12 replaced the scorer with a two-pass streaming mode whose memory is proportional to query terms, not documents, removing the practical vault-size ceiling; Phase 11 made indexing a batch pipeline flat in file count (same 5000-note vault: 3 s on Windows, 1 s on macOS, under a second on Linux). Searching still takes ~1 s and indexing stays incremental; these numbers come from `tests/run.sh` (T-85/T-86), printed on every run.

**Version stamp.** Each successful `knotlog index` also writes `.knotlog/index.version` with the Knotlog version that built the index. When the next run finds a different version, or no stamp file (an index built before the stamp existed), it rebuilds in full once, without `--full`, the same way a schema change does. `index.schema` is unchanged. Vaults seeded before this change do not list `index.version` in their `.gitignore`; add it there, as with `blocks.tsv`.

**`KNOTLOG_CTX_MAX` is a different limit.** It bounds the *context* output — the `activity.log` slice and `Threads.md` section emitted by `knotlog context` (4096 bytes by default) — not `.knotlog/index.tsv`. Set it in the environment for a one-off override, or write `ctx_max=` into `.knotlog/config` for a vault-local default that survives moving the vault to another machine (the env var still wins when both are set); `doctor` names which one is in effect.

## Session reflection

Knotlog keeps the mechanical ledger; the meaning comes from the model. `remember` gives it places to write meaning down, using marker scaffolds the model fills and Knotlog never touches again:

- Every session file gets a `<!-- knotlog:reflect:start -->` / `<!-- knotlog:reflect:end -->` block ("What changed in this session?", "Where did the work happen?", "Threads touched or continued"), appended **only when absent** — a second `remember` the same day cannot overwrite what the model wrote.
- `context --json SessionStart` asks the model to fill today's block while it is empty, naming the file and marker; if yesterday's block was left empty, the next `SessionStart` says so once and drops it. Both checks read the block's **contents**, never `mtime` — a touched file cannot fake a reflection.
- `Threads.md` gets the same treatment on the first `remember` in a vault: a scaffolded block ("Active threads" / "Closed threads") is **prepended** to the top, because `context`'s `KNOTLOG_CTX_MAX` budget drops whatever falls off the *bottom* of an overgrown `Threads.md` — putting the block first keeps it inside the budget longer. Pre-existing free-hand text survives unchanged, right after the block.
- `doctor` reports informationally when `Threads.md` (or a session reflection) is missing, unscaffolded, or scaffolded-but-empty; a filled block earns no line at all. It also warns when the file is larger than the context budget and says how much of it is dropped every session. When today's `activity.log` holds more events than `note_nudge_events=` in `.knotlog/config` (default 50; `0` turns the check off; a non-number falls back to 50) and today's reflection block is still empty, it adds one row pointing at `knotlog note "<what changed>"`; below the threshold it stays silent.
- When `context` does crop `Threads.md` it no longer does so silently: after the `… (truncated)` marker it adds one line with the number of bytes that never entered the context. A section that fits prints exactly what it printed before; when the budget is too small to spare the note (fewer bytes left for content than the note itself), only the plain marker appears.
- **`knotlog compact` — the one deliberate exception to "Knotlog never rewrites what you wrote".** It moves the oldest entries of the `Closed threads` section (inside the scaffolded block) into the same archive file `knotlog archive` uses. An entry is a list item at column 0 (`- ` or `* `) or a deeper heading, plus the lines under it up to the next entry; entries are assumed to be appended, so the first ones are the oldest. The newest `--keep N` (default 20) stay. It never runs from a hook or a timer and never commits. Without `--apply` it is a dry run: it prints what would move, how many bytes, and where to, and touches no file. `--apply` appends to the archive first (existing archive bytes are kept, a marker line precedes the entries), verifies the appended bytes against the source byte for byte, and only then cuts the entries out of `Threads.md` through a temp file and `mv`. If any step before the cut fails the source stays untouched and the exit code is non-zero. The `Active threads` section, the skeleton, the markers, the pin block and free text outside the section are never moved. To undo, copy the entries back from the archive by hand; they are stored verbatim.
- **Companion size limit.** The last-session file (`Last-Session.md`, `Son-Oturum.md` in a Turkish vault) and the journal only grow. `knotlog doctor` prints one warning when either is larger than `companion_max=` bytes (`.knotlog/config`, default 40000; a non-numeric value falls back to the default) and stays silent below it. `knotlog compact` also handles the last-session file: session blocks are `## ` sections appended at the bottom, so the first ones are the oldest. The newest 5 stay (`--keep N` sets both this and the threads count); older blocks move verbatim and in order to `Last-Session-Archive.md` (`Son-Oturum-Arsivi.md`) beside the threads archive, with the same dry run, append-verify-cut sequence and marker line. A file with 5 blocks or fewer is untouched. The journal is warned about but never rewritten.

Knotlog enforces the format, not the meaning.

## Honest limits

- **Folding is lossy**: `açık` and `acık` collapse together — a deliberate trade-off.
- **"Semantic" ≠ cosine similarity**: model judgment, better on meaning but weaker on exhaustive recall.
- **Wikilink target resolution is exact-string, not folded**: the path/title/filename staged resolution described under [Notes: frontmatter and wikilinks](#notes-frontmatter-and-wikilinks) is byte-for-byte at every stage, unlike search. A wikilink written `[[Beta Notu]]` will not match a title of `Beta notu` (case) or a folded/accented variant. Outgoing links are unaffected (they print raw wikilink text, never resolved). Not fixed in this release.
- **Index context limit**: comfortable up to a few thousand notes; beyond that, two-stage narrow-then-read with `--brief` — see [Large vaults](#large-vaults).
- **The Codex adapter was live-verified against CLI 0.153.0** (2026-09-03): after trust, `SessionStart`, `UserPromptSubmit`, `PreToolUse(apply_patch)`, `PostToolUse(apply_patch)`, `Stop`, `SessionEnd`, and `codex exec` all dispatched. `PostToolUse` carries Codex's native apply-patch envelope, which Knotlog parses alongside legacy unified-diff fixtures; the adapter captures synchronously per patch, while `SessionEnd` runs `remember` + `index`. Windows was not exercised. See [Codex](#codex). The Claude Code adapter was measured live and works; the omp adapter ran once live and worked.
- **Live install is verified on Windows and Linux; macOS is CI-only so far**: the test suite exercises `install` on Linux, macOS, and Windows in CI, and a real end-to-end setup into a real `$HOME` — PATH, shell, desktop environment, folder icon — has been done on Windows and on Arch Linux, including `knotlog uninstall` (v2.3.0). The two bugs fixed in v2.2.2 were both in an untested surface at the time and both survived hundreds of tests and three-platform CI, so treat macOS as plausible-but-unverified until someone runs it there. If you install on macOS and something is off, that is a report worth filing.
- **`capture --git` is stateless**: it diffs the tree, so it cannot see `Read` events (content unchanged), and two runs without a commit append the same files twice — commit (or `knotlog remember --git`) before re-running. Deletions are captured; the index later drops them.
- **Interactive `init`'s tty detection is not machine-verified**: questions appear only when `[ -t 0 ]` is true. The test suite proves the question/fill/skip mechanics under a forced-tty override, but whether a given OS's `isatty(0)` agrees with that POSIX check is not something a piped CI shell can prove. Manual check: run `knotlog init` in an empty folder from a real terminal and confirm the questions appear.
