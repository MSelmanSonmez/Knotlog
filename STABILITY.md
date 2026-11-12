# Stability

What you can rely on across Knotlog 1.x releases, what may still move, and how changes are announced.
This page describes the policy from 1.6.0 on; [CHANGELOG.md](CHANGELOG.md) is the record of what each
release actually changed.

## Versioning

Knotlog uses semantic versioning. `knotlog --version` prints the version of the checkout, and
`knotlog update --check` compares it with the latest release as numbers.

- **Patch (1.7.x):** fixes. No command, flag or file format changes.
- **Minor (1.x.0):** new commands, flags, config keys and adapters. Existing ones keep working.
- **Major (2.0.0):** anything in the stable list below may be removed or change meaning.

One exception: a security fix may change behaviour in any release when keeping the old behaviour would
leave a hole. Examples: a linked `.knotlog/` is refused since 1.2.0, secret-shaped notes are refused since
1.4.0, and `pending --approve`/`--reject` need the user at a terminal since 1.6.0. Since 1.4.0 an entry
that changes what you see starts with **Behaviour change:** in the changelog.

The one breaking release so far was 1.0.0, the rename from Quipu (see [Moving from Quipu](#moving-from-quipu)).

## Stable in 1.x

These do not change meaning, lose a flag or change an exit code without a major release:

- **Commands and their flags** as listed in `knotlog help` and the [Commands](docs/REFERENCE.md#commands)
  table: `help`, `doctor`, `init`, `install`, `setup`, `migrate`, `uninstall`, `capture`, `index`,
  `compile`, `search`, `links`, `context`, `remember`, `note`, `note --thread`, `pending`, `propose`,
  `digest`, `import`, `plan`, `card`, `board`, `tone`, `flair`, `archive`, `compact`, `distill`,
  `similar`, `tui`, `mcp`, `update`, `rollback`.
- **The work card format** that `card` writes and `board` reads: the `status:` line in the front
  matter, the six `status:` values `draft`, `ready`, `running`, `review`, `done`, `stuck` (English in
  every language), and the field names of the bold lines in each shipped language: Type (`Type`,
  `Tür`, `Tipo`, `種別`, `类型`), Waiting on (`Waiting on`, `Bekliyor`, `Esperando a`, `Aguardando`,
  `待機中`, `等待`) and Project (`Project`, `Proje`, `Proyecto`, `Projeto`, `プロジェクト`, `项目`).
  `board` takes its PROJECT column from the card's folder and does not read the Project line.
- **Documented exit codes**, for example `note` exit 4 (refused) and 5 (queued for review), `note --thread`
  exit 3 (over the context budget), `pending --approve` exit 4 without a terminal.
- **Dry run first:** `migrate`, `compact`, `distill` and `import claude` write nothing without `--apply`.
- **The MCP tools** `knotlog_search`, `knotlog_context` and `knotlog_note` and their input schemas.
- **Vault files Knotlog reads and appends to:** the threads, rules and facts files (`Threads.md`,
  `Rules.md`, `Facts.md` and their localized names), `companion.md`, the session notes, the last-session
  file, and the `<!-- knotlog:... -->` block markers in `AGENTS.md`/`CLAUDE.md`. Knotlog appends to
  them; only `archive` and `compact --apply` move lines out, into the archive, when you run them.
- **Config keys** in `.knotlog/config` (`lang=`, `layout=`, `fold=`, `ctx_max=`, `profile=`, `tone=`,
  `flair=`, `lessons=`, `write_approval=`, `review=`, ...) and the `KNOTLOG_*` environment variables in
  the [Reference](docs/REFERENCE.md), with their pre-rename `QUIPU_*` names.
- **The context budget:** `knotlog context` never prints more than `ctx_max` bytes.

## Not stable

These can change in any minor release:

- **The text of `context`.** It is written for a model, not for a parser: section order, headings and
  wording may change (they are i18n data). The `ctx_max` cap above still holds. Use `--json EVENT` for
  the hook envelopes; the envelope shape each agent needs is stable, the text inside it is not.
- **The look of `board`.** Column text, padding, and the wording of the summary and attention lines.
  The flags and the card format above are stable.
- **Human-facing messages and `doctor` rows**, in every language.
- **Derived state** in `.knotlog/`: `index.tsv`, `blocks.tsv`, `links.tsv` and their schema. They are
  rebuilt from the vault, never edited by hand. An index built by another version or with another schema
  is rebuilt in full on the next `knotlog index`.
- **Adapters not verified against a live session.** Claude Code, Codex, Windsurf/Devin and OpenCode have
  been run live; omp was seen working once; Antigravity, Gemini CLI, Cursor and GitHub Copilot CLI are
  covered by tests and written from each agent's docs, but not live-verified. A change in the agent can
  require a change in the adapter. See [Setup](docs/REFERENCE.md#setup) and the per-agent sections.
- **`knotlog compile` output** under the knowledge folder's `Compiled/`: derived notes, regenerated on
  each run, never part of your memory.

## State in `.knotlog/`

Two kinds of files live there:

- **Your state:** `config`, `activity.log`, `pending` (append-only), `distilled`, and the watermarks
  (`remembered`, `reviewed`). These are kept across updates and read by later 1.x versions.
- **Derived state:** the index files above (with `index.schema` and `index.version`), locks, `*.tmp`
  files and signal flags such as `nudged` and `needs_review`. Knotlog rebuilds or recreates them; they are
  not meant to be edited by hand.

`knotlog update` changes only the Knotlog checkout, never the vault. `knotlog rollback` restores up to
three earlier checkouts.

## Moving from Quipu

Knotlog 1.0.0 renamed Quipu (last release 2.7.3). There is no update path from Quipu: install Knotlog,
then run `knotlog migrate` in the vault (dry run) and `knotlog migrate --apply` to write. It renames
`.quipu/` to `.knotlog/`, rewrites `QUIPU_*` config keys, block markers and hook commands, and is safe to
repeat. Until then the old names keep working: `.quipu/`, `QUIPU_*` variables and `<!-- quipu: -->`
markers are still read in 1.x.

## How breaking changes are announced

- Every release has a [CHANGELOG.md](CHANGELOG.md) entry in the Keep a Changelog format.
- A change that needs you to act (a security behaviour change, a rename, a new requirement) starts with
  **Behaviour change:** and says what to do.
- A major release lists each removed or changed stable item and the replacement, and keeps a migration
  path such as `knotlog migrate` where files on disk change.
