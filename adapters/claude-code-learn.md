---
description: Capture one lasting lesson from this conversation as a Knotlog proposal
---

Look back over this conversation and pick the one thing worth remembering in a month: a fact about the project, a mistake that was corrected, or a workflow that worked. Do not ask the user what to write.

If there is nothing lasting, say so and stop. If the user said a conversation is off the record, never propose anything from it.

Write it as one line, as an observation and not an order ("the build needs X", not "always do X"), with absolute dates (2026-11-06, never "today"). Then queue it:

    knotlog propose --kind lesson "<text>"

Show the user the line you queued and the number Knotlog printed (#N). Do not approve it yourself. The user decides, with one of:

    knotlog pending --approve N --to note     (session note, with a [lesson] prefix)
    knotlog pending --approve N --to facts    (facts file; the text must open with Preference:, Decision: or Convention:)
    knotlog pending --approve N --to thread   (the active threads list)
    knotlog pending --reject N
