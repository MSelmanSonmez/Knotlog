# Why Knotlog

## The problem

Open a terminal agent today, and it knows nothing about yesterday.

You spent three hours with it last night. You explained the project. You
rejected two approaches and said why. You settled on a third. This morning you
open the same agent in the same folder, and none of that is there. So you
explain it again. Shorter this time, because you are tired of explaining, which
means it gets the worse version.

That is the whole problem. Not that the model is weak — the model is fine. It
just starts every session at zero, and you are the one carrying the context
across the gap.

After a few weeks of this you notice what you have started doing. You keep a
scratch file of things to paste at the beginning. You avoid long sessions
because restarting is expensive. You stop asking "why did we do it this way"
because nobody remembers, including you.

## What Knotlog does instead

Knotlog writes down what happened, in Markdown, in one folder.

While the agent works, every file it reads or writes gets appended as one line
to a log. When the session ends, those lines become a dated note. When the next
session starts, the recent activity and the open threads are printed back into
the model's context before you type anything.

So tomorrow morning the agent opens knowing what you did last night and why.
Not because it remembers — because it reads.

That is the entire idea. The rest of this page is why it is built the way it
is.

## Why it costs nothing

This is the part people ask about first, because most memory tools for coding
agents charge for infrastructure.

They charge for a reason. A tool like claude-mem runs a separate worker process
to decide what a session meant. That worker has no model inside it, so it needs
one from somewhere: a vector database for retrieval, embeddings to fill it,
an API key to generate them. Real infrastructure, real cost, passed on to you.

Knotlog does not have that problem, because it never needed a second brain. The
agent is already running. You are already paying for it. So the part that
understands meaning is the model you already have in the loop — Knotlog just gives
it a place to write things down and reads them back at the right moment.

No database. No embeddings. No API key. Nothing to bill you for, because there
is nothing running that could cost money.

## The files are yours

Your memory is Markdown files in a folder you chose.

Open them in any editor. Read them without any tool at all. Put them in git and
watch your own thinking change over the months. Move them into Obsidian, or a
different memory tool, or a plain text editor five years from now.

There is nothing to export, because nothing was ever imported into a format only
one program can read. Knotlog appends to these files; it never rewrites what you
wrote. If you delete Knotlog tomorrow, everything it recorded is still sitting
there, still readable.

## Offline, and local

Knotlog makes no network calls. There is no `curl` in it, no upload, no telemetry,
no account.

Your notes are on your disk. What your agent touched at 2 a.m. is on your disk.
That matters if you work on client code, on anything under an NDA, or on a plane.
It also means Knotlog cannot break because a service went down, changed its
pricing, or shut off its free tier.

## Zero dependencies

Knotlog is one POSIX shell script. It uses `sed`, `awk`, `grep`, `tr`, and `git` —
tools your machine already has.

No Python. No Node. No `jq`. Nothing to `npm install`, nothing to keep in sync
with a runtime version, nothing that breaks when you upgrade something unrelated
six months from now.

This is not a boast about minimalism. It is the reason installation works. There
is no dependency tree to resolve, so there is nothing for the install to fail on.
The test suite runs on Linux, macOS, and Windows on every commit, because
the same script runs on all three.

## Turkish and English, both properly

Most tools treat non-English as a translation layer bolted on at the end. Here
it goes deeper than the interface strings.

Search folds text before indexing and before querying. In a Turkish vault,
`İ ı ğ ş ç ö ü` collapse to their ASCII forms on both sides, so `acik kaynak` and
`açık kaynak` find the same note. That fold is a real character map, written out
rule by rule — not a hopeful `lowercase()` call that mangles the dotted İ and
calls it done.

The interface, the folder layout, the help text, the seeded templates and the
companion persona all exist in both languages. You pick one at install and the
vault is built in it.

## What it is not

Knotlog is not a search engine that understands your prose. Its search is lexical
and ranked with BM25 — good at finding a note you half-remember, not at
answering a question about it. The understanding happens where it should: in the
model reading the results.

Knotlog also does not write your reflections for you. It records what happened
mechanically — files, times, tools — and leaves a scaffold in each session note
for the part only you or the model can supply: what changed, and why. If nobody
fills it, nobody fills it. Knotlog enforces the format, not the meaning.

And it does not read your mind about structure. It indexes the notes you write.
It does not invent them.

## The honest summary

If you use a coding agent daily, you already have a memory problem. You are
already solving it by hand, badly, with pasted context and a scratch file.

Knotlog is a small script that does that part for you, into files you own, on a
machine that stays yours, for nothing.

Start here: [README](../README.md) to install, [the user guide](GUIDE.md) for
the daily loop.
