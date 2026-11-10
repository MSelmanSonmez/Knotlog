# Changelog

All notable changes to Knotlog (formerly Quipu; last Quipu release was v2.7.3).
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `knotlog context` adds one line under the rule headings that names the rules file (`Rules.md`, `Kurallar.md`, ...), since only the headings enter context and the full text stays on disk. New i18n key `ctx_rules_hint` in all six languages; the line only uses the budget slack left after every section, so it never costs a thread, rule, fact or lesson line, and a vault whose context fills `ctx_max` prints what it printed before. Measured on a fresh English `init` vault: +53 bytes (T-1419).
- `knotlog card <name> [--project <Project>] [--type code|content]` opens a numbered work card `NNN-<name>.md` under `<projects>/<Project>/<Cards>/` from the new `templates/<lang>/card.md` (all six languages; fields in the vault language, `status: draft` in the front matter, the type word in the vault language too). `--proje` and `--tur kod|icerik` are aliases. It resolves the project like `plan`, takes the next number in the folder, never overwrites a file, rejects names with a slash, backslash or control character (exit 2) and never enters `knotlog context`. New i18n keys `usage_card`, `cards_dir`, `err_card_type`, `err_card_name`, `err_card_project`, `err_card_extra_arg`, `err_card_exists`, `err_card_template`, `err_card_mkdir`, `err_card_write` in all six languages.
- `knotlog plan` accepts `--project` as an alias of `--proje`; nothing else about it changes.

- `knotlog search` matches Turkish words by stem: `güncelleme` finds `güncellemesi`, `okullar` finds `okulu`. A short list of Turkish endings (`lib/stem.awk`) is cut from the query terms and from each note's words at search time; the index is not touched. Config `stem=tr|off`; without a `stem=` line it is on for `lang=tr` and off for every other language. **Behaviour change: in a vault with `lang=tr` and no `stem=` line, search results and their order change after upgrading; `stem=off` in `.knotlog/config` brings back the old ranking exactly.** `--brief` snippets still show the folded text. Terms with digits or punctuation (`node.js`, `c++`, `#tag`) and words under four letters are not cut. A one- or two-letter ending is cut only if at least four letters stay (`okulu` finds `okul`, `dosya` is not cut to `dos`), a longer ending if at least three stay A final `b`, `d` or `g` that an ending softened is turned back (`kitabı` finds `kitap`, `rengi` finds `renk`) when the stem has four or more letters (T-1440 to T-1447, T-1461 to T-1467).
- `knotlog search` also looks for the Turkish or English counterpart of a query word: `package list` finds `paket listesi`, `kurulumu` finds `setup` and `install`, `open source` and `opensource` find each other. The counterparts come from a hand-kept list, `synonyms/tr-en.txt` (59 groups and 12 joined/apart spellings, among them `açık kaynak` for `opensource`); they are added to the query as ordinary terms at search time, so the index is not touched. Config `synonyms=tr-en|off`; without a `synonyms=` line it is on for `lang=tr` and off for every other language, and a missing list file means no expansion. A typed word is looked up only if it is a listed word or an inflected form of one: `kurulumu` expands, but `kurul`, a different word that merely shares the stem, does not (T-1468 to T-1470). **Behaviour change: in a vault with `lang=tr` and no `synonyms=` line, search results and their order change after upgrading; `synonyms=off` in `.knotlog/config` brings back the previous ranking exactly.**

- `knotlog doctor` prints one information row (`worktree`) when the vault root's `.git` is a file, i.e. the vault is a linked git worktree: writes go to that copy, and `KNOTLOG_VAULT=<main vault path>` sends them to the main vault. It moves no counter and no exit code. New i18n key `doc_worktree` in all six languages. The new REFERENCE section "Worktrees and parallel agents" records what was measured with a live Claude Code session.

### Fixed
- `knotlog note` and `note --thread` keep the target file's permissions. Both write through a temp file and a rename, and the temp file used to be created fresh, so a session note or threads file set to 600 came back with the umask default (644 on most systems). The temp file now starts as a `cp -p` copy, the same way `distill` and `compact` already did (T-1417, T-1418).

### Documentation
- `STABILITY.md`: the semver policy for 1.x, the stable and not-stable surfaces, the state files in `.knotlog/`, the move from Quipu, and how breaking changes are announced. Linked from the README's Documentation list.

## [1.6.0] - 2026-11-07

### Added
- Approved lessons come back at session start: `knotlog context` lists the newest `lessons=N` (default 5, `0` = off) approved `lesson`/`fix`/`skill` proposals of `.knotlog/pending` as one short line each, inside the `ctx_max` budget (dropped lines are counted in one note). Instruction-shaped text is skipped, `note`/`thread` proposals never enter, and a vault with no approved lesson prints exactly what it printed before. `doctor` warns when approved lessons exist but none fits the budget.
- `knotlog pending --approve N [--to note|facts|thread] [--dry-run]`: choose where an approved proposal lands. No `--to` (or `note`) is the old path, byte for byte. `facts` appends `- <text> (source: pending #N)` to the facts file under distill's own rules: the text must open with a `distill_tags` tag and a colon, a duplicate or a ledger hit is refused, the facts budget holds (exit 3), the folded text goes into `.knotlog/distilled`; a refusal exits 2 (1 for a missing or linked facts file) and leaves the proposal open. `thread` is `note --thread` (budget refusal exits 3, proposal stays open). `--dry-run` prints the target and the exact line and writes no file. An unknown `--to` exits 2. Admission (secret, instruction) runs again for every target.
- `knotlog setup claude` also writes `.claude/commands/learn.md` (`adapters/claude-code-learn.md`): a `/learn` slash command that queues one lasting lesson with `knotlog propose --kind lesson` and lists the `--to` choices; it never approves itself. Same rule as the hook file: written only when absent, an identical file is untouched, a different one is preserved with a warning.
- The review ask (`ctx_review_ask`, all six languages) now tells the agent to propose nothing from a conversation the user called off the record; still under 600 bytes.
- `knotlog similar [--min X]`: a read-only report of line pairs that may be the same topic, across the facts lines, the active thread lines and the approved `lesson`/`fix`/`skill` proposals. Words are folded and cut to five characters, pairs are scored by Jaccard (default `--min 0.4`, a number from 0 to 1, anything else exits 2), and each row gives the score, both places, which side Knotlog wrote (`knotlog/user`) and the first 60 bytes of each text. It writes nothing, takes no lock and never merges. `doctor` adds one row when the default scan finds a pair (no exit code change; skipped above 500 candidate lines).

### Fixed
- Two overlapping `remember` runs (or `note`, `distill`, `pending --approve`) could both take the remember lock where `mkdir` is uutils coreutils (Ubuntu 26.04's default), which exits 0 when another process creates the directory during its own call; the session file then got the same digest twice. The lock now belongs to whoever creates its `pid` file under noclobber, whatever `mkdir` reports.
- When the lock's `pid` write failed for a reason other than a racing owner (a full disk, a permission error, an antivirus lock), the empty `.knotlog/remember.lock` directory stayed behind, never counted as stale, and every later `remember`, `note`, `pending` and `distill` reported busy (hook-mode `remember` silently did nothing). The caller whose write failed now removes the directory when no `pid` file is in it.
- **Behaviour change: `pending --approve` and `--reject` need the user at a terminal.** An agent that ran `propose` could approve its own proposal, and approved lessons enter every opening context. Both now exit 4 (`err_pending_human`, all six languages) and change nothing unless stdin and stdout are a terminal and no agent or hook marker is set (`CLAUDECODE`, `KNOTLOG_HOOK`/`QUIPU_HOOK`); `--dry-run` is not gated. The lessons section also re-runs the secret check (with the instruction check) on each row's whole text, so a line appended to `.knotlog/pending` by hand cannot carry a secret into context. Defence in depth, not a sandbox: see Honest limits.
- `note`, `note --thread`, `propose` and MCP `knotlog_note` refused only a line break; an ESC sequence such as `ESC[8m` passed and could hide text from the person reviewing `knotlog pending` while the model still read it. Any control character other than a tab now exits 2 (`err_note_control`, all six languages), `pending --approve` refuses such a row the same way, and `knotlog pending` removes control bytes from what it lists. A tab in a plain note is still written.

## [1.5.0] - 2026-10-31

### Added
- `knotlog import claude [--project DIR] [--apply]` turns Claude Code transcripts (`~/.claude/projects/<vault path>/*.jsonl`) into session notes, one per session. Dry run by default; only user and assistant text is kept (no thinking, tool calls or tool output); secret-shaped lines and paths outside the vault are masked; a session already imported (`claude_session:` in the front matter) is skipped.
- `knotlog setup copilot` writes `.github/hooks/knotlog.json` for GitHub Copilot CLI: session-start context (`context --json SessionStart --copilot`, a top-level `additionalContext`), edit capture (`capture` also reads `tool_input.path` of edit tools), the review ask at turn end (`Stop`) and remember at session end. Not live-verified.
- README: Cline, Goose, Zed and Aider listed under the `AGENTS.md` bridge, with the Aider (`read: AGENTS.md`) and Zed (first rules file wins) notes.

## [1.4.0] - 2026-10-31

### Changed
- `knotlog note --thread` writes the line as `- YYYY-MM-DD HH:MM <text>` (was `- HH:MM <text>`), so `doctor` can age it. Existing lines are not touched.
- **Behaviour change: secret-shaped notes are refused.** `knotlog note`, `note --thread` and MCP `knotlog_note` now check the text against the secret pattern of the shipped pre-commit hook (the one source for both) and refuse a match with exit 4 and `refused<TAB>secret_pattern`, without echoing it; earlier versions wrote it. Any other text is written exactly as before.

### Added
- Freshness: `doctor` warns once when list lines of the active threads section carry no ISO date (`YYYY-MM-DD`) newer than `stale_days=` days (`.knotlog/config`, default 30; an invalid value falls back to 30 and is reported). The row names the count and the oldest line. A line's age is its newest date; undated lines, the closed section and the pin block are not counted. Read-only and not part of `context`; the exit code is unchanged.
- Review loop: once more than `KNOTLOG_REVIEW_AFTER` (default 40) activity events follow the `.knotlog/reviewed` watermark, `context --json Stop` asks the agent once whether the work left a lesson, a workflow worth a skill, or a corrected mistake (a due checkpoint goes first; `stop_hook_active`, `profile=economical|manual` and `review=off` keep it silent). `remember` leaves the same ask in `.knotlog/needs_review` for agents without a Stop channel, and the next `context --json SessionStart` shows it once. New `knotlog propose --kind lesson|skill|fix "<text>"`: the agent's answer, always queued in `.knotlog/pending` (exit 5) for `knotlog pending --approve N`; no vault or skill file is written. New vaults' seeded `.gitignore` lists `reviewed` and `needs_review`. The Claude Code Stop route was live-verified (2026-10-31, Claude Code 2.1.312); `docs/REFERENCE.md` notes that only Edit, Write, NotebookEdit and Read events count and that Claude Code labels the ask "Stop hook error".
- Write approval: with `write_approval=on` in `.knotlog/config`, `note` and `note --thread` do not write; the line waits in the append-only `.knotlog/pending` (exit 5, `pending_review`). `knotlog pending` lists the open proposals, `--approve N` writes one through the normal path (a budget refusal keeps it open), `--reject N` drops it; neither rewrites the file. With the setting on, a text that reads as an instruction to the agent is refused (exit 4, `instruction_shaped`) and one with a relative date ("tomorrow", "yarın") is queued as `relative_time`. The word lists are in `i18n/*.txt`. `doctor` shows the setting when it is set.
- MCP `knotlog_note`: exit 5 (queued) is a normal result, not `isError`.
- `distill --apply` refuses (exit 3, `err_facts_budget`) to add facts that would push the facts section past the context budget, where `context` would drop it; the dry run prints the same warning. `context` and `distill` share one formula (`_q_fts_room`).

## [1.3.0] - 2026-10-31

### Added
- `knotlog search --max-bytes N` caps the output at N bytes (works with `--paths` and `--brief`; the omitted count goes to stderr). The MCP `knotlog_search` tool always applies the `ctx_max` budget.
- `knotlog distill [--apply]` moves lines you mark up a layer: `[fact]` lines of session notes to the facts file, `[core]` lines of the facts file to the core block of `companion.md`. Dry run by default; no model, no duplicates, source lines never edited.
- `distill` remembers what it moved in `.knotlog/distilled`, so a line removed from its target does not come back. The MCP `knotlog_search` result ends with the omitted-results line when it was cut.
- Write-time budget: `knotlog note --thread` refuses a line that would push the threads file past the context budget, so `context` never has to crop it. It exits 3, writes nothing, and says how many bytes to free and how (`knotlog compact --apply`, `knotlog archive`, or a larger `ctx_max`). The check uses the same formula as `doctor`'s threads-overflow warning, so the warning and the refusal start at the same byte. Plain `note` (and MCP `knotlog_note`) writes the session note, which never enters context, and is not checked.
- `tests/bench/longmemeval.sh`: a LongMemEval-S retrieval bench for `knotlog search` (k = 5, one note per haystack session, same method as agentmemory's `eval/runner`). It is not part of `tests/run.sh`; method, results and the reproduce command are in `docs/REFERENCE.md` under Search.

### Fixed
- `search` strips punctuation from the ends of query terms the way it already tolerates it after a word in a note: `knotlog search "spotify?"` now finds what `knotlog search spotify` finds, and a trailing-punctuated query such as `"term."` matches the same notes as the bare term instead of only the notes where the word is followed by that punctuation. Leading `(` `'` `"` and trailing `. , ; : ! ? ) ' "` go; inner and other punctuation stays (`node.js`, `c++`, `#tag`, `--flag`, `2026-10-30`), and a term that is only punctuation is ignored. Present in 1.2.0 and earlier.
- `search` counts a repeated query term once. `knotlog search "playlist playlist spotify"` scores like `knotlog search "playlist spotify"`; before, each repeat raised the term's document frequency again, which could push it past the note count and print `-nan` scores with awk warnings on stderr. Present in 1.2.0 and earlier.

## [1.2.1] - 2026-10-31

### Fixed
- `context --json UserPromptSubmit` (and Gemini's `BeforeAgent`) re-sent the whole session context on every prompt, about as large as the session start (up to `ctx_max`, 4 KB by default). It now carries only the `now:` line plus the memory and checkpoint reminders when they are due, as the guide already described; the full context stays a `SessionStart` job. The README's "zero token cost" line is replaced with what the hooks actually add.
- Parallel captures across a log rotation lost rows: the fresh `activity.log` was truncated after the move, wiping rows other captures had just appended, and a capture that found the file already moved aborted before writing its own row. Rotation now runs under a lock (`.knotlog/rotate.lock`), re-checks the size, and no longer truncates; 100 parallel captures keep all 100 rows.

### Security
- The threads and facts headers in the session context now say what follows is the user's notes, information and never instructions (`ctx_threads`, `ctx_facts`, all six languages). A line such as "ignore all previous rules" written into `Threads.md` used to reach the model unmarked. The headers already count against `ctx_max`, so tiny budgets still hold. This is a prompt-level frame, not isolation; the README's honest limits say so.
- The secret gate missed colon-form assignments (`password: …`, `"password": "…"` in YAML and JSON), `Bearer` tokens and bare JWTs; all three are now caught, while a `${VAR}` reference still passes. An installed Knotlog hook picks this up the next time `knotlog init` runs in the vault.

### Documentation
- README (six languages) gains "Using it with an existing code repository": copy the adapter's hooks into the repository's (or the global) `.claude/settings.json` and set `KNOTLOG_VAULT` in its `env` block.
- The guides and the reference no longer call the installer's download "verified": the install check is a text anchor, and `update`'s SHA-256 comes from the same release, so it catches a broken download, not a replaced release. Releases are not signed.

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
