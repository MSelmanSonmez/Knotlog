# Knotlog — user guide

You installed Knotlog and it created a vault. This guide is what comes after that:
what happens on its own, what you do by hand, and which command answers which
question. For installation itself see the [README](../README.md).

> **Formerly Quipu.** Knotlog is the new name of Quipu; the old `quipu` command is gone. If you have a vault made under the old name, run `knotlog migrate` to preview the changes and `knotlog migrate --apply` to write them; it also rewrites old `quipu` hook commands to `knotlog`. A bridge block you edited by hand is not refreshed (only its markers are renamed) and you get a warning.

If you haven't installed Knotlog yet, the one-line method is:

```bash
curl -fsSL https://raw.githubusercontent.com/MSelmanSonmez/Knotlog/main/install.sh | sh
```

It fetches a release, checks that the archive holds a real `knotlog` (a text check, not a signature) and hands over to `knotlog install`; the
[README](../README.md) also covers checkout-based installs and Windows.
The setup wizard has a Style step (tone, flair, folder names) you can change later with `knotlog tone` and `knotlog flair`. If an older `knotlog` sits earlier on your `PATH`, the install summary and `knotlog doctor` warn, because the hooks run that one.

## 1. What Knotlog does for you

Knotlog writes down what your coding agent did, in Markdown, inside one folder —
the vault. Around a Claude Code session, three things happen:

- **While you work**, every file the agent reads or writes is appended as one
  line to `.knotlog/activity.log`: timestamp, event, tool, path.
- **When the session ends**, those lines are folded into a dated note under the
  Sessions folder, and the search index is refreshed.
- **When the next session starts**, Knotlog prints the recent activity, the open
  threads, and an identity line back into the model's context — so the agent
  opens knowing what happened last time. The very first line is always the
  current date, time, and weekday name (`now: 2026-09-02 20:15 Wednesday`) —
  without it, a model writing a session heading has to guess the time, and
  guesses drift.

There is no database and no network call. Every file is Markdown you can read,
edit, and commit to git. Knotlog only ever appends; it never rewrites your prose.

## 2. The daily loop

The part that confuses people first: some of the loop runs itself, and some of
it is yours. Here is the split.

**Runs on its own** (the Claude Code adapter, installed at
`<vault>/.claude/settings.json`):

| When | What runs | Effect |
|---|---|---|
| Session starts | `knotlog remember && knotlog context --json SessionStart` | pending log lines become a session note; recent memory is injected |
| Every prompt you send | `knotlog context --json UserPromptSubmit` | after enough new log lines, the model is reminded to write memory down |
| After `Edit`/`Write`/`NotebookEdit`/`Read` | `knotlog capture` | one line appended to `activity.log`, silently |
| Session ends | `knotlog remember && knotlog index` | the session note is written and the index refreshed |

Two conditions for this to work: `knotlog` must be on your `PATH`, and Claude Code
reads hook configuration once at startup — **restart it after any change to
`settings.json`**.

**Yours to do:**

1. Write notes into the vault folders as you go. Knotlog indexes what you put
   there; it does not invent notes.
2. At the end of a session, fill the reflection block in today's session note.
   The scaffold is already there, with three headings. The agent can fill it —
   the `SessionStart` context asks it to — but nobody checks that it did.
3. Keep the threads file (`Threads.md`) current: what is still open, what closed.
4. Run `knotlog search` when you need something from an earlier session, instead
   of retelling it.

Knotlog keeps the mechanical ledger. The meaning is written by you and the model.

## 3. The folders

`init` creates ten folders. The names below are the English layout; a Turkish
vault gets Turkish names, and `--plain` gets ASCII ones. Nothing here is
enforced — they are a habit, not a schema.

| Folder | Write here when… |
|---|---|
| `📥 Inbox` | a thought arrives and you do not want to decide where it belongs yet |
| `🗑️ Trash` | dumping raw material inside the inbox — pastes, fragments, transcripts |
| `🎯 Command Center` | it belongs on the dashboard: today's focus, entry links |
| `🗂️ Projects` | the note is about one active piece of work — one subfolder per project |
| `🧠 Knowledge` | you will want it again months from now, independent of any project |
| `🛠️ Arsenal` | it is a tool, a script, or a snippet to reuse |
| `📆 Sessions` | almost never by hand — `knotlog remember` writes here, one file per day |
| `🔮 Companion` | the companion's persona and the identity notes it carries |
| `📦 Archive` | the thing is finished or frozen, and you want it out of the way |
| `📋 Templates` | never edit in place — copy `note.md`, `project.md`, or `session.md` out |

The Templates folder ships with those three skeletons and is **excluded from the
search index**: they are shapes to copy, not content to find. A vault with three
notes and three templates indexes the notes, not the templates.

## 4. Commands you type

Everything below runs inside the vault (any subfolder works — Knotlog walks up to
find `.knotlog/`).

**`knotlog search <terms>`** — find a note.

```
$ knotlog search taskbar
0.934	🧠 Knowledge/taskbar.md	Taskbar overflow	windows,ui
0.673	🧠 Knowledge/dpi.md	DPI notes	windows
```

**`knotlog links <path>`** — see what a note connects to. Give it the
vault-relative path.

```
$ knotlog links "🧠 Knowledge/dpi.md"
outgoing links
incoming links
🧠 Knowledge/taskbar.md
```

Outgoing links are the `[[wikilinks]]` written in that note; incoming are the
notes pointing at it. Link targets resolve by exact string, not folded — write
`[[dpi]]` (the filename stem) or the full vault-relative path.

**`knotlog digest`** — summarize one day of activity without touching the session
watermark. `--dry-run` prints instead of writing, `--date YYYY-MM-DD` picks a
day, and the file lands in the dump folder.

```
$ knotlog digest --dry-run
---
Activity digest: 2026-08-30
type: digest
status: generated
---

Range: 2026-08-30T22:56 → 2026-08-30T22:56 (2 events)
Tools: Edit 1, Write 1
Touched files (top 10):
- 🧠 Knowledge/dpi.md (1)
- 🧠 Knowledge/taskbar.md (1)
```

**`knotlog doctor`** — the health check. See section 7.

**`knotlog import FILE`** — turn a saved conversation export (Claude transcript,
ChatGPT export, or JSONL with `role`/`content`) into a session note.

```
$ knotlog import /tmp/chat.jsonl --date 2026-08-29
wrote: 📆 Sessions/2026-08-29-import-chat.jsonl.md
```

**`knotlog plan <name> --proje <Project>`** — open a plan note where plans
belong: `<projects>/<Project>/<Plans>/<name>.md`, seeded from the localized
front-matter template and opened in `$EDITOR` when set. Plans are memory —
keeping them inside the vault is what makes the next session inherit them,
so a missing project folder is an error, never auto-created, and an
existing plan is never overwritten. Run it from inside a project folder and
`--proje` resolves itself.

```
$ knotlog plan roadmap --proje Knotlog
wrote: 🗂️ Projects/Knotlog/Plans/roadmap.md
```

**`knotlog tone [--list|<slug>]`** — show or set the tone preset. No arguments
prints which source is active and why (a preset slug, or companion.md's own
Tone section, or neither); `--list` browses the nine shipped presets
(Default, Professional, Friendly, Candid, Quirky, Efficient, Snarky,
Teaching, Kaomoji) and marks the active one; `<slug>` writes `tone=<slug>` to
`.knotlog/config` — it never touches companion.md.

```
$ knotlog tone --list
Tone presets:
  varsayilan   Default — The preset tone and voice
  profesyonel  Professional — Polished and clear
  ...
* etkili       Efficient — Brief, tight, clear
  ...
$ knotlog tone
active tone: Efficient (preset: etkili)
```

**`knotlog index`** — refresh the index by hand. The hooks do this at session end;
run it yourself after adding notes outside a session. `--full` rebuilds
everything.

```
$ knotlog index
# indexed 6 (reused 5, stale 1, dropped 0)
```

**`knotlog remember`** — write the session note now instead of at session end. Add
`--git` to commit the vault afterwards; without it, Knotlog never commits.

## 5. Searching your own memory

`search` folds the query, scores the index with BM25, and prints the best rows
as TAB-separated columns: score, path, title, tags. Ten rows by default.

- `--limit N` — how many rows.
- `--paths` — the path column only, one per line: `knotlog search dpi --paths`.
- `--brief` — one extra column holding a ~120-byte snippet of the note. Use it
  to choose which two notes to open instead of opening ten. Cannot be combined
  with `--paths`.
- `--tag ui` / `--status paused` — drop every note whose frontmatter does not
  match. These are filters, not ranking hints; combined, they are AND.

Scores are relative to your vault, not absolute — in a small vault a filtered
match can score below zero and still be the right note.

**Folding, and why it matters for Turkish.** Before indexing and before
searching, text goes through a fold profile recorded as `fold=` in
`.knotlog/config`. A Turkish vault gets `fold=tr`: `İ ı ğ ş ç ö ü` collapse to
their ASCII forms, so the query and the note meet in the middle.

```
$ knotlog search "acik kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
$ knotlog search "açık kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
```

Both spellings find the note. The `default` profile — what an English vault
gets — folds nothing beyond ASCII case, so there `acik` does not find `açık`. If
you write Turkish in an English-layout vault, set `fold=tr` in `.knotlog/config`
and run `knotlog index --full` once; the index has to be rebuilt with the new
profile.

Folding is lossy on purpose: `açık` and `acık` collapse to the same key. One
known gap: `--tag` folds its argument but compares it against the raw
frontmatter text, so `--tag istanbul` will not find a tag written `İstanbul`.

## 6. Threads and session notes

Four files carry the story between sessions.

**Today's session note** (`📆 Sessions/YYYY-MM-DD.md`) is written by `remember`.
The top is mechanical — time range, tool counts, touched files. Below it is a
scaffold Knotlog adds once and never touches again:

```
<!-- knotlog:reflect:start -->
### What changed in this session?

### Where did the work happen?

### Threads touched or continued

<!-- knotlog:reflect:end -->
```

Filling it is the job. A second `remember` on the same day will not overwrite
what is written there. While the block is empty, `SessionStart` asks the model
to fill it and names the file; if yesterday's block was left empty, the next
session is told once and then the notice is dropped.

**`Threads.md`** (`Konular.md` in a Turkish vault) sits at the vault root and holds the storylines that outlive a
day, under `### Active threads` and `### Closed threads`. `knotlog context` feeds
it back into every session, which makes it the highest-leverage file in the
vault — and the cheapest one to let rot. Keep it short; a thread that closed
should move down, not stay at the top.

`knotlog note --thread "<text>"` adds a line to the active section, but only
while the file still fits the context budget: a line that would make `context`
crop the section is refused (exit 3, nothing written), and the message says how
many bytes to free and how (`knotlog compact --apply`, `knotlog archive`, or a
larger `ctx_max`). What happened in a past session does not belong here; it
stays in the session notes, where `knotlog search` finds it.

The new line starts with today's date and time (`- YYYY-MM-DD HH:MM`), so
`doctor` can tell how old it is: when active lines carry no date newer than
`stale_days=` days (`.knotlog/config`, default 30), it prints one warning with
the count and the oldest line. Undated lines are not counted.

Both forms of `note` refuse a text that looks like a secret (an API key, a
token, a private key) with exit 4. If you want to see every line before it
lands, set `write_approval=on` in `.knotlog/config`: notes then wait in
`.knotlog/pending` until you run `knotlog pending --approve N` (or
`--reject N`); a line that reads as an order to the agent ("from now on you
must …") is refused, and one with "tomorrow" waits so you can give it a date.

After a busy stretch (more than 40 logged events), Knotlog asks the agent once,
at the end of a turn or at the next session start, whether the work left a
lesson, a workflow worth a skill, or a corrected mistake. The agent answers
with `knotlog propose --kind lesson|skill|fix "<text>"`; the finding waits in
`knotlog pending` for your `--approve N` and is never written on its own (no
skill file either). `review=off` in `.knotlog/config` turns the ask off.

### The rules file

`init` seeds **`Rules.md`** (`Kurallar.md` in a Turkish vault) at the vault
root — a behavior contract every agent working in the vault inherits. The
shipped default carries four blocks Knotlog considers non-negotiable:

- **Approval gates** — money movement, outbound messages, deletion and
  secrets are never crossed without approval; one yes covers one task in one
  session.
- **Zero-level protocols** — eleven baseline working habits (contract scope,
  a definition of done before starting, writing verification output to a
  file, the three things to report before saying "done," one commit per
  logical step, three lines at session end, and more), each with the reason
  it exists.
- **The receipt rule** — a commit, an updated file, output written to disk is
  a receipt; "done" is not. No trace, no work.
- **Record discipline** — when a new record supersedes an old one, retire the
  old: search the vault for the old name, close or update it; never leave two
  live copies of one subject.

Edit the file freely — it is yours; Knotlog never overwrites it (an existing
file wins even under the other language's name). `knotlog context` injects the
file's headings into every session, after the threads section; a squeezed
`ctx_max` drops this section whole before it ever cuts the threads block.
`doctor` checks the shipped templates among its product files. Until you edit
the seed, it is not counted as a hand-written memory file — so a fresh vault
still exits `doctor` clean; the moment you write into it, it joins the
mandatory narrative set described in section 7.

The bridge (`AGENTS.md`/`CLAUDE.md`) carries the checkpoint protocol that
keeps the story alive when sessions end badly: write the record the moment
work finishes, not at session end; when work stops midway, write where it
stopped and the next step; when the user hints they are leaving, finish the
record before closing.

None of these files is ever rewritten by Knotlog. All are append-only from its side.

### The facts file

`init` seeds **`Facts.md`** (`Gerçekler.md` in a Turkish vault) at the vault
root — the persistent-facts layer, kept without any external memory service.
The rule is **one line, one fact**: every bullet line opens with one of three
tags — `Decision:` (a made choice and its reason, valid until changed),
`Preference:` (how you like to work), `Convention:` (how things run in this
vault). The bar for entry: a line must still be both true and useful months
from now — **identity qualifies, news does not**; anything that goes stale
belongs in `Threads.md` or the session notes instead.

Edit the file freely — it is yours; Knotlog never overwrites it (an existing
file wins even under the other language's name). `knotlog context` injects the
fact lines into every session, after the rules section, under the same
`ctx_max` contract: a squeezed budget drops the section whole and never cuts
the threads block. An untouched seed is the skeleton, not a record — context
stays quiet about it until you write your first line. `doctor` prints one
`ok` row naming the fact-line count when the file exists and stays silent in
vaults that predate the layer.

### Moving lasting lines up: distill

A session note is the place for news; a line that will still be true in months belongs in the facts file, and the few you must never forget belong in the core block of `companion.md`. You decide which, and mark the line:

```
- Decision: the vault stays plain Markdown. [fact]
```

Run `knotlog distill` to see what would move (it writes nothing), then `knotlog distill --apply`. Marked lines in session notes go to the facts file, each with `(source: <note>)`; lines in the facts file marked `[core]` go to the core block. Lines that do not open with a Preference, Decision or Convention tag are listed but never added, and a line already there is skipped, so running it twice is safe. The marked lines themselves are never edited. A Turkish vault uses `[olgu]` and `[çekirdek]`.

## 7. When something looks wrong

`knotlog doctor` prints a section per area and a summary line. It exits 0 when
there are only warnings, and 1 only when something failed.

```
summary: 151 ok, 3 warn, 0 fail
```

**Which part of your memory is audited?** Not every file in a vault is held to
the same standard. **Live memory** — the AGENTS.md/CLAUDE.md bridges, the
threads file, the rules and core notes, and the newest `## ` block of
`Last-Session.md` — is the instruction the next session will stand on; every
path inside it must resolve. **Historical memory** — the older blocks of
`Last-Session.md`, the journal note, everything under the sessions folder — is
a record; it is entitled to mention folders that no longer exist, and the path
audit never reads it. Append a new session block and the old one turns into
history automatically.

Memory file names follow the vault's language (`Son-Oturum.md`/`Kurallar.md`/
`Çekirdek.md`/`Günlük.md` in a Turkish vault, `Last-Session.md`/`Rules.md`/
`Core.md`/`Journal.md` in an English one), and the other language's name is
accepted as a legacy fallback. The moment your vault carries a hand-written
memory file, that set becomes **mandatory**: one missing file is the only
memory finding that turns doctor's exit code to 1 — a half-migrated memory
layer is how sessions silently lose their injections.

How to read the lines that matter:

- `fail` under **tools** — `sh`, `sed`, `awk`, `grep`, `tr`, `git` are the whole
  dependency list. A missing one is the only kind of breakage that stops Knotlog.
- `warn index — index.tsv missing or stale (knotlog index)` — expected on a fresh
  vault, after editing notes outside a session, and right after `remember` —
  which writes a session note the index has not seen. Run `knotlog index`.
- `warn threads — Threads.md has not been updated yet` — the file is missing, or
  its `Active/Closed threads` block is still empty. The scaffold alone does not
  clear it; written content does. Expected on a new vault, a nudge later on.
- `warn links — N wikilink target(s) not found` — a `[[link]]` points at nothing.
  Resolution is exact-string, so a renamed note leaves a dangling link behind.
- `warn links — … resolve to more than one note` — two notes share a name and
  Knotlog refuses to guess which one you meant.
- `fail memory — Last-Session.md | Son-Oturum.md not found` — one of the
  mandatory memory files exists under neither its current nor its legacy name.
  Exit code 1; every other memory finding is a warning.
- `warn paths — N quoted path(s) not found` — a `` `quoted/path` `` in your live
  memory points at nothing in the vault. Each missing path is listed on its own
  row below the count. `~/`, absolute paths, URLs, drive letters, globs and
  shell snippets are never judged; a vault file followed by arguments
  (`./knotlog doctor`) is a command, and a bare folder name (`lib/`) counts as
  found if a folder of that name exists anywhere in the vault.
- `warn paths — … point inside git-ignored territory` — the path exists but git
  does not track it: it works on this machine and breaks the day the vault is
  cloned or moved.
- `warn memory — N memory file(s) with uncommitted changes` — your memory's
  safety net is git; edited-but-uncommitted memory has none. Commit.
- `warn last session — the newest session block does not mention today's date` —
  a commit from today exists, but the newest block of `Last-Session.md` was
  written earlier. Today's date is searched in the whole block, so a session
  that crossed midnight is not a false alarm.

- `ok claude hooks — installed (vault)` — the adapter is at
  `<vault>/.claude/settings.json`. This is what a normal install looks like.
  Plain `installed` means it was found in the global `~/.claude/settings.json`
  instead. `not installed` means neither exists, and the automatic loop in
  section 2 is not running.
- `warn path — path contains OneDrive` / `locale is not UTF-8` — environment
  risks for emoji folder names and for folding. Neither breaks a normal vault.

`doctor` modifies nothing. Everything it reports is a command for you to run.

## 8. Using Knotlog without hooks

For agents with no hook surface — or when you want the loop under your own hand
— two commands replace the automatic part:

- `knotlog capture --git` diffs the working tree against the last commit and
  appends one line per changed Markdown file. Run it before `remember`. It is
  stateless: run it twice without committing in between and the same files are
  logged twice.
- `knotlog context --bridge` writes the context the hooks would inject into a
  `<!-- knotlog:context:start -->` block in **both** `AGENTS.md` and `CLAUDE.md`.
  Any agent that reads either file sees the same memory — which is how a
  session in one agent picks up what a session in another one did.

A manual session is then: refresh the bridge files with `context --bridge` and
let the agent read one of them, work, then run
`knotlog capture --git && knotlog remember && knotlog index`.

### Antigravity

Antigravity has a hook surface, so it gets the automatic loop. From the vault:

```
knotlog setup antigravity --dry-run   # preview, writes nothing
knotlog setup antigravity             # writes .agents/hooks.json
```

At session start the hook runs `remember` and injects the recent context as a
system message. When the agent finishes a turn, a second hook checks whether
the session note has fallen behind (at most once every 30 minutes) and, if so,
sends the agent back to write it before the turn ends. An existing
`.agents/hooks.json` that differs is never overwritten; merge the shipped one
(`adapters/antigravity/hooks.json`) by hand. Restart Antigravity afterwards.
Details: [REFERENCE.md](REFERENCE.md#antigravity).

### Devin Desktop (Windsurf) and OpenCode

Both get a small recording hook; their context comes from the `AGENTS.md`
bridge. From the vault, run `knotlog setup windsurf` (or `devin`) and
`knotlog setup opencode`; `--dry-run` previews. They write
`.devin/hooks.json` and `.opencode/plugins/knotlog.js`, and never overwrite a
file that differs. The client runs `knotlog` from its own environment (Devin
Desktop uses your login shell), so `knotlog` must be on that `PATH` or the hook
silently does nothing. Live-verified on Linux on 2026-10-25 (Devin Desktop
3.11.216, OpenCode 1.19.4); Windows is not verified. Details:
[REFERENCE.md](REFERENCE.md#windsurf--devin-desktop).

### Connecting the MCP server

`knotlog mcp` lets an MCP client search the vault and read its context without
hooks. It offers three tools: `knotlog_search` (a query and an optional limit),
`knotlog_context`, and `knotlog_note` (one line into today's session note, the
same as `knotlog note`). It finds the vault from the folder it starts in, so
register it from inside the vault:

```
claude mcp add knotlog -- knotlog mcp
```

If `knotlog` is not on your `PATH`, give the absolute path instead. Another
client can run the same command with the argument `mcp`; for a server started
outside the vault, set `KNOTLOG_VAULT` to the vault folder. Details:
[REFERENCE.md](REFERENCE.md#mcp-server).

## 9. Knobs

Vault settings live in `.knotlog/config` as plain `key=value` lines: `layout`,
`lang`, `fold`, `user`, `companion`, `purpose`, `tone`, `flair`, `ctx_max`, `stale_days`, `write_approval`. Changing
`fold` requires `knotlog index --full` afterwards; the others take effect on
the next command. `ctx_max` is never written by `init` — it already has a
working default (4096), so add the line by hand only if you want to override
it; `doctor` reports where the value it's using came from (env/config/
default), and warns if a config `ctx_max=` isn't a positive integer
(ignored, not fatal).

**Choosing a language.** Knotlog speaks English, Türkçe, Español, Português
(Brasil), 日本語 and 简体中文. Pick one in the install wizard, with
`--lang <code>` (`en`, `tr`, `es`, `pt-br`, `ja`, `zh-cn`), or by setting
`lang=` in `.knotlog/config`; anything missing in your language falls back to
English. The non-English/Turkish translations are machine-assisted, and
corrections are welcome.

`tone` picks one of nine shipped tone presets (`knotlog tone --list` shows
name + description, `knotlog tone <slug>` sets it) — it wins over
companion.md's own `## Tone`/`## Üslup` section in the context Knotlog injects
whenever the named preset actually exists for the vault's language. Leave it
unset, or set it to a slug that doesn't ship, and Knotlog falls back to
companion.md's Tone section — the same behavior a vault had before presets
existed. Like `purpose`, there is no interactive question for `tone` during
`init`; only the `--tone <slug>` flag (also accepted by `install`).

`flair` adds a reply decoration on top of the tone: `none` (default), `kaomoji` or `emoji`. `knotlog flair` shows it, `knotlog flair --list` browses, `knotlog flair <value>` sets it; `--flair` is also accepted by `init` and `install`. The text ships in all six languages. Any flair other than `none` replaces the `kaomoji` tone preset.

Environment variables, when the defaults do not fit:

(The pre-rename `QUIPU_*` names still work; when both are set, `KNOTLOG_*` wins.)

- `KNOTLOG_CTX_MAX` (4096) — byte budget for the context Knotlog injects. Takes
  priority over `.knotlog/config`'s `ctx_max=`, which takes priority over the
  4096 default — use the env var for a one-off override, or `ctx_max=` in
  config for a setting that survives moving the vault to another machine.
- `KNOTLOG_NUDGE_AFTER` (50) — new log lines before the model is nudged to write
  memory.
- `KNOTLOG_CHECKPOINT_AFTER` (1800) — seconds before an unmodified session note
  with subsequent git activity triggers a checkpoint reminder or block.
- `KNOTLOG_LOG_MAX` (262144) — `activity.log` size before it rotates to `.log.1`.
- `KNOTLOG_HOOK=1` — set by the adapters. It makes errors exit 0, so a broken
  Knotlog never blocks your session.

### The secret gate (pre-commit)

`install` makes the vault a Git repository by default (`--no-git` opts out)
and adds one baseline commit plus a `.gitignore` for the regenerated machine
state; `init --git` does the same on demand. An existing history is never
committed into, an existing non-repository vault is never converted by the
default (pass `--git` to ask for it), and a missing git identity is reported,
not fatal. Whenever the vault is a repository,
Knotlog installs `.githooks/pre-commit` and points `core.hooksPath` at it. Every
commit then scans the *added* staged lines for well-known secret shapes — AWS
`AKIA…`, OpenAI `sk-…`, GitHub `ghp_…`/`github_pat_…`, Slack `xox…`, Google
`AIza…`, `PRIVATE KEY` blocks, `Bearer` tokens, JWTs, and generic
`api_key=`/`secret=`/`token=`/`password:` assignments (`=` or `:`) — and rejects the commit, naming the file it found. If an external
`sir-tara` scanner is on your `PATH`, the whole scan is delegated to it. A
hand-edited hook (one without Knotlog's marker) is never overwritten. To commit
anyway: `git commit --no-verify` skips all hooks, and
`KNOTLOG_SKIP_SECRET_SCAN=1 git commit …` skips just this gate for that one
commit.

`knotlog help` lists every command; `knotlog help --tr` prints the same list in
Turkish (the other shipped languages work the same way: `--es`, `--pt-br`, `--ja`, `--zh-cn`).

## 10. Leaving

If Knotlog is not for you, you should be able to get your machine back without
guesswork. Uninstall removes only what install put outside your vault:

```bash
knotlog uninstall --dry-run   # see what would go
knotlog uninstall             # remove the command from PATH
```

On Windows, run `.\uninstall.ps1` from PowerShell instead (or as well, if you
installed both ways) — it removes the shims under `%LOCALAPPDATA%\Knotlog\bin`
and the entry it added to your user `PATH`.

**Your notes are never deleted.** The vault stays exactly where it is, and the
command prints its path along with the Knotlog files still inside it. Those files
are inert without the command — the vault is just Markdown in folders at that
point, and you can keep it, move it, or delete it yourself. Uninstall shows you
the exact line to delete it if that is what you want.

Nothing else on your machine was changed: Knotlog never edits shell startup files,
never writes outside the vault and its own command shim, and never phones home.
