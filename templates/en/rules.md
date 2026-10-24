---
title: Rules
type: rules
status: active
tags: [knotlog, rules]
---

# Rules

This file is the behavior contract for every agent working in this vault. When
a new rule is learned it goes here — with its reason written under it; a rule
without a reason is a suggestion.

## Approval gates

Four gates are never crossed without approval:

1. Money movement: purchases, subscriptions, invoices, any payment.
2. Outbound messages: email, comments, PRs/issues, content sent to any platform.
3. Deletion: files, folders, records, branches — anything irreversible.
4. Secrets: sharing or placing keys, tokens and personal data.

An approval belongs to one task in one session: a yes at one gate never opens the next.

## Zero-level protocols

1. Your contract is the file list the operator gave at the start of the
   task. Do not read or roam beyond it.
   Reason: an unclear contract lets the agent invent its own scope.
2. Files you may touch: the given list; when none was given, the default
   scope is the project/folder the task runs in, and going beyond it
   requires asking first.
   Reason: if the agent widens its own scope, the damage lands outside the contract.
3. Take a task only with its definition of done: do not start before
   "when finished, the following will be true" is written down.
   Reason: work with no definition of done never finishes, it only stops.
4. Write the verification output to a file, then check the result on a
   separate line.
   Reason: looking at the terminal and calling it "passed" is an impression, not a measurement.
5. Before saying "done," give three things: what changed, which command
   ran, and where its output is.
   Reason: without these three, "done" is a claim that cannot be verified.
6. You cannot approve your own work; hand important work to a second,
   clean session to review.
   Reason: the eyes that wrote it systematically miss their own mistakes.
7. Do not stall on ambiguity: pick the reasonable choice, proceed, and
   list "what I assumed" at the end.
   Reason: stopping at every ambiguity does not do the work, it offloads the decision onto the operator.
8. When behavior changes, update the file that documents it in the same change.
   Reason: documentation debt that piles up never gets paid, and behavior drifts from the docs.
9. Add files one by one; a separate commit per logical step.
   Reason: a bulk commit makes it unreadable which change broke what.
10. Do not fix things outside the task's scope; report it, do not touch it.
    Reason: "fixing it while I'm here" is the most common door to out-of-contract damage.
11. At session end, three lines: what I did, what is half-done, what is next.
    Do not wait for the session end: right after a step is finished and committed, write it down at once with `knotlog note "<what changed>"`.
    Reason: without these three lines, the next session has to rediscover where it left off; an unexpected shutdown (crash, power cut) skips the session-end hook, and a line written at the moment survives it.
12. Never summarize from memory what the vault has on record: read the record
    first, then speak.
    Reason: a remembered summary degrades silently; getting it wrong while the
    record sits there is worse than not knowing, because it sounds certain.
13. When outward-facing work (a release, a profile, a share) is done, verify
    the result unauthenticated: the exit path, anonymous access, a control
    group.
    Reason: "success" as seen from your own session is not the state as seen
    from outside; the two can silently drift apart for months.

## Receipt rule

Proof of work lives in the trace: a commit, an updated file, output written to
disk is a receipt. "Done" is not a receipt — with no trace, the work did not happen.

## Record discipline

When adding a new record, retire the old one: search the vault for the old
name, close or update the live record; never leave two live copies of one subject.
