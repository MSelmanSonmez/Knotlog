# Changelog

All notable changes to Knotlog (formerly Quipu; last Quipu release was v2.7.3).
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Write-time budget: `knotlog note --thread` refuses a line that would push the threads file past the context budget, so `context` never has to crop it. It exits 3, writes nothing, and says how many bytes to free and how (`knotlog compact --apply`, `knotlog archive`, or a larger `ctx_max`). The check uses the same formula as `doctor`'s threads-overflow warning, so the warning and the refusal start at the same byte. Plain `note` (and MCP `knotlog_note`) writes the session note, which never enters context, and is not checked.

## [1.2.0] - 2026-10-27

### Security
- A repository carrying symlinks inside `.knotlog/` could make hooks write outside the vault. Knotlog now refuses to run when the state directory is a symbolic link or holds one (hooks exit 0 silently, manual runs exit 1, `doctor` reports it), and refuses to write a vault file that is a link or whose folder resolves outside the vault. The vault root itself may still be a link. Present in 1.1.1 and earlier.
- `remember` and `note` ignore a `layout=` value that is not a shipped layout (falling back to `emoji`, as `context`, `import` and `digest` already did), and refuse a sessions folder that is absolute or contains `..`.
- `fold=`, `tone=` and `lang=` in a vault's config are names of shipped files, never paths: a value with `/` or `..` falls back to the default (`doctor` fails a bad `fold=`), so a cloned repository's config can no longer choose the sed script `index` and `search` run, or pull a file from outside the checkout into `context`. Present in 1.1.1 and earlier.
- `context` no longer reads a threads, rules, facts or `companion.md` file that is a symbolic link or resolves outside the vault; `compile`, `doctor` and `tui` read only the vault's own notes, whatever `index.tsv` lists. Present in 1.1.1 and earlier.
- `init`, `install`, `migrate`, `uninstall` and `repair-hooks` refuse to write or remove a file through a symbolic link in the vault, and `init` refuses a linked state directory. Present in 1.1.1 and earlier.
- The secret gate no longer sets `core.hooksPath` when `.githooks/` holds other hooks or a link: it reports it and leaves them inactive. Present in 1.1.1 and earlier.
- The vault walk-up never adopts a vault whose config another user owns (not checked under Git Bash).
- A `ctx_max=` or checkpoint value with a leading zero, a note named like an option (`-L.md`), and a hook event or tool name carrying a tab or newline no longer break `context`, `index` or `activity.log`. `init --lang` accepts only a language code.

### Fixed
- The arrow-key language menu no longer fails with "unknown layout" when you pick `es`, `ja`, `pt-br` or `zh-cn` (languages without their own folder layout); it falls back to English folders like every other install path. Present in 1.1.1.
- `knotlog tone` and `knotlog flair` also rewrite the `knotlog:context` block that `context --bridge` writes, so old style text no longer lingers beside the new one.
- The replace-the-link question in the install wizard shows the language's own yes/no letters (`[e/H]` Turkish, `[s/N]` Spanish and Portuguese) and accepts that language's yes along with `y`/`yes`.
- `install` makes `$HOME/.local/bin` when `PATH` names it but it is missing, and otherwise says exactly which folder to create and add to `PATH`.

### Changed
- `--version` reports `1.2.0`.
- The language menu shows Turkish as `Türkçe` in every interface language, and the install summary's first group is named in Spanish, Portuguese and Japanese instead of the English `Vault`.
- `knotlog uninstall` also removes the client hook files in the vault that are still identical to their shipped template, and lists those you changed as `Kept:`.

### Added
- `install` and `doctor` report a different `knotlog` earlier on PATH (hooks call plain `knotlog`, so that one runs): the install summary lists it under Skipped with its version and a `fix:` line, `doctor` warns when `knotlog` is missing from PATH or reports another version.
- `flair=none|kaomoji|emoji` config key and `knotlog flair [--list | none|kaomoji|emoji]`: a reply decoration independent of the tone preset, appended after the tone block in `knotlog context`. `init --flair` and `install --flair` set it. The text ships in all six languages under `flair/<lang>/`. `doctor` warns on an invalid value. `tone=kaomoji` is unchanged.
- Install wizard: a new Style step after Identity (tone preset, flair, folder names). Each menu is skipped by its flag (`--tone`, `--flair`, `--plain`) and the step is skipped in `--no-prompt` runs. The step counter reads `[n/5]` when the language is asked as a numbered page (`--lang` or the plain-text prompt) and `[n/4]` after the arrow-key language menu, which carries no counter of its own.
- The `AGENTS.md`/`CLAUDE.md` bridge block ends with a Style section (the active tone preset and flair text) when `tone=` or `flair=` is set, so agents with no context hook (OpenCode, Windsurf) see it; `knotlog tone` and `knotlog flair` rewrite the block in place. Unchanged when neither is set.
- A flair other than `none` replaces a `tone=kaomoji` preset in the context and the bridge, and each flair text says it overrides any emoji rule in the tone. The wizard's tone menu no longer lists `kaomoji` (`--tone kaomoji` still works).
- Install summary hint: when `opencode` or `windsurf`/`devin-desktop` is on PATH and the vault lacks its plugin or hook file, Skipped names `knotlog setup opencode` / `knotlog setup windsurf`. Nothing is wired automatically.
- Install summary: grouped under Vault, Hooks, Safety and Skipped, `✔` done / `!` skipped with a reason and a `fix:` line where one command fixes it; coloured only on a terminal (honours `NO_COLOR`). Fixed: `--no-link` on Linux/macOS no longer claims "use install.ps1 on Windows".

## [1.1.1] - 2026-10-25

### Fixed
- `install` no longer dead-ends on a `knotlog` symlink that already sits on PATH (for example one pointing at a developer checkout): an interactive install shows where it points and asks (default no); `--force` replaces the link without asking, and a non-interactive refusal now names `--force` and `--no-link`. The link's target is never touched, and a regular file or directory is never replaced. `install.ps1` gets the same rule for its shims (`-Force`).
- Install errors no longer print glued to the "Installing..." progress dots.

## [1.1.0] - 2026-10-25

### Added
- Six interface languages: English, Türkçe, Español (`es`), Português do Brasil (`pt-br`), 日本語 (`ja`) and 简体中文 (`zh-cn`). Messages live in `i18n/<code>.txt`; templates, tone presets and persona files are per language under `templates/`, `tone/` and `persona/`. The non-English/Turkish translations are machine-assisted; corrections are welcome.
- How languages are found: the supported set is the set of `i18n/*.txt` files (codes are lowercase file names); nothing else lists languages. `--lang`, `lang=` and the locale accept any case and `_` for `-` (`pt_BR` means `pt-br`; `en_US` means `en`). A language missing an asset (template, tone, persona, layout) falls back to English; an unsupported code works as English.
- Fold profile follows the language: `tr` uses `tr.sed`, `es` and `pt-br` use `latin.sed`, every other language uses `default.sed`.
- `knotlog help --<code>` prints help in any shipped language, and the help text says so.
- READMEs in all six languages; the guides and the reference describe how to choose a language.

### Changed
- The install wizard's language prompt accepts uppercase and underscore forms (`PT-BR`, `pt_BR`) the same way `--lang` does.
- `install.ps1` lists every shipped language, taken from the checkout's `i18n/*.txt` files, in its arrow-key menu and in its plain-text prompt. Not run on Windows before this entry was written.

### Fixed
- `install.sh` gives the wizard the terminal under `curl | sh` (reads from `/dev/tty` when stdin is not a terminal and `/dev/tty` opens); without a terminal nothing changes.
- The untouched-seed checks for `Rules.md` and `Facts.md` covered only the Turkish and English templates, so a fresh vault in another language failed `doctor`. They now walk every shipped language.

## [1.0.0] - 2026-10-25

### Renamed (from Quipu)
- The command is `knotlog`. The `quipu` command is gone. Users coming from Quipu install Knotlog and run `knotlog migrate`, which rewrites old `QUIPU_HOOK=1 quipu` hook commands to `knotlog`.
- New vaults keep their state in `.knotlog/`; a pre-rename `.quipu/` folder still works.
- Settings use `KNOTLOG_*` environment variables; the old `QUIPU_*` names are still read.
- Block markers are written as `<!-- knotlog: -->`; legacy `quipu:` markers are still read.
- User-facing messages, the vault folder (`<user>'s Knotlog`), the Windows install path (`%LOCALAPPDATA%\Knotlog`), the omp hook (`knotlog.ts`), icons, seed files and docs (English and Turkish) say Knotlog.
- `update` and `rollback` write backups as `<checkout>.knotlog-previous`, `.2`, `.3`; an old `.quipu-previous` chain is carried over.
- `repair-hooks` takes `--knotlog` (`--quipu` still works) and rewrites both the new and the pre-rename hook prefix.

### Added
- `knotlog tui`: browse the newest session notes in the terminal (`j`/`k`, `Enter` to open in a built-in pager, `/` to search, `q` to quit); prints a plain list when not on a terminal.
- `remember` writes one handoff card per hook session (`## date time · client · id8`) instead of overwriting a shared block, so parallel agents no longer erase each other's summary; `init`/`install`/`migrate` add `merge=union` for the last-session file and the journal to `.gitattributes`, and `doctor` warns when a git vault lacks it.
- Windsurf / Devin Desktop adapter (`knotlog setup windsurf`, alias `devin`, writes `.devin/hooks.json`: `post_write_code` captures, `post_cascade_response` runs `remember` and `index`) and OpenCode adapter (`knotlog setup opencode`, writes `.opencode/plugins/knotlog.js`: `file.edited` captures, `session.idle` runs `remember` and `index`). Both only record; context comes from the `AGENTS.md` bridge. Verified live on Linux on 2026-10-25 with Devin Desktop 3.11.216 and OpenCode 1.19.4; Windows is not verified. Hooks run `knotlog` from the client's environment, so it must be on the PATH the client sees (Devin Desktop uses the login shell's).
- Notes whose frontmatter says `validity: rejected` are skipped by `search` and `compile`; `search --all` includes them. The index schema moved to 3 (an `index.tsv` with an eighth column), so an older index rebuilds on the next `knotlog index`.
- `profile=normal|economical|manual` in `.knotlog/config` sets how much context the hooks inject.
- `doctor` warns when the last-session file or the journal exceeds `companion_max=` bytes (default 40000); `knotlog compact` also moves old session blocks of the last-session file to its archive, keeping the newest 5 (`--keep N`).
- Session ids that are word slugs, such as Devin's `trajectory_id`, are kept whole in handoff cards instead of cut to 8 characters; the client is also named from Windows transcript paths.
- `knotlog migrate` brings a pre-rename vault over: state folder, `QUIPU_*` settings, block markers, hook commands. Dry run by default, `--apply` writes, safe to repeat. The AGENTS.md/CLAUDE.md bridge block is refreshed only if it was not edited by hand.
- `knotlog setup <claude|codex|omp|gemini|cursor|antigravity|windsurf|opencode> [--dry-run]` writes one agent's hook file into the vault; a differing file is never overwritten.
- Antigravity adapter (`.agents/hooks.json`, `context --antigravity`). Covered by tests; not yet verified against a live Antigravity.
- Gemini adapter (`.gemini/settings.json`) and Cursor adapter (`.cursor/hooks.json`, `context --cursor`).
- `knotlog mcp`: stdio MCP server with the tools `knotlog_search`, `knotlog_context` and `knotlog_note` (append-only, the same as `knotlog note`). Verified live on Claude Code 2.1.309. Exits at once on SIGINT, SIGTERM and SIGHUP.
- Checkpoint signal: a reminder on `UserPromptSubmit` and a Stop hook (`agent_end` for omp) when work goes unrecorded; `KNOTLOG_CHECKPOINT_AFTER` sets the threshold.
- `knotlog note "text"` adds one line to today's reflection block; `note --thread` adds a line to the active threads section.
- `knotlog compile` builds deterministic derived concept notes (manual; never enters context).
- `knotlog archive` moves a closed heading out of Threads.md into the archive; `knotlog compact` moves old closed-thread entries there losslessly.
- `knotlog update --check` / `--apply` and `knotlog rollback`, with up to three rotated backups.
- `update --apply` (tarball checkout) downloads the release's `knotlog-<version>.tar.gz` and its `.sha256`, and refuses before extracting anything on a mismatch, a missing or wrong-named hash file, or when no SHA-256 tool (`sha256sum`, `shasum`, `openssl`) exists (`--no-verify` skips the check). It also refuses up front when the install directory is not writable, an interrupted update or rollback left its tree behind, or free space is clearly too small. A new release workflow (`.github/workflows/release.yml`) builds the archive and publishes both files when a `v*` tag is pushed.
- `knotlog tone` and nine tone presets (the last is `kaomoji`).
- `knotlog digest --since/--until` summarizes a date range.
- Search reads frontmatter `aliases` (weighted like the title) and a block index (`blocks.tsv`), so text past the 2000-character search field is searchable; results show one row per note.
- `index_exclude=` config key skips extra folder names when indexing.
- Zero-level protocols are printed in the AGENTS.md/CLAUDE.md bridge; `companion.md` tone is injected into context.
- Threads file: pinned block, and a note saying how many bytes were cropped; doctor warns when the file exceeds the injection budget.
- `doctor` warns when PATH's `bash` is the WSL one, and nudges when today has many events but an empty reflection block.

### Changed
- Installer and `update` now use github.com/MSelmanSonmez/Knotlog; default install dir is `~/.local/share/knotlog`. The banner moves to `icon/knotlog-banner.png`.
- README is now a landing page; the manual moved to `docs/REFERENCE.md`; Turkish README added.
- The index rebuilds in full when the Knotlog version changes.
- Capture skips temporary and scratchpad paths; the fixed activity section is capped at 20% of the context budget.
- JSON string fields decode `\uXXXX` escapes to UTF-8, including surrogate pairs.
- Start-up no longer needs an external `dirname`.

### Fixed
- `remember` printed to stdout in hook mode and broke the SessionStart JSON; it is now silent. Every adapter's SessionStart emits one JSON object.
- Antigravity runs `remember` before `context` at SessionStart (30 s timeout).
- `update` treats a `.git` file (worktree, submodule) as a git checkout.
- `update` runs a tarball `--apply` from a copy outside the checkout, keeps the checkout across an interrupted swap, and undoes the backup rotation if the first swap fails.
- `update` refuses a release `tag_name` that is not a plain version token.
- CRLF files: frontmatter is read like LF, and `archive` and `compact` keep CR bytes.
- `note` reports `err_note_write` and leaves the file unchanged when it cannot write.
- Doctor path scan runs under `LC_ALL=C` and skips command invocations; compile status marks no longer depend on the awk locale.
- `remember` writes the session file that `doctor` reads, in the vault's language.
- omp adapter imports `HookAPI` from the hooks subpath; its `agent_end` injects only the checkpoint reason.
- Gemini adapter drops `AfterAgent`, whose output is not documented to reach the model.

### Moving from Quipu
There is no update path from Quipu 2.7.3 (it has no `update` command, and Knotlog lives in a new repo). Install Knotlog from the new repo, then run in your vault:

```sh
knotlog migrate           # dry run: shows what would change
knotlog migrate --apply   # writes the changes
```

Old Quipu checkouts and vaults keep working until you migrate.

[1.0.0]: https://github.com/MSelmanSonmez/Knotlog
[1.1.0]: https://github.com/MSelmanSonmez/Knotlog
