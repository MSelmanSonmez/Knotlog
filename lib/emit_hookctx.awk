# quipu - jsonemit driver: the `quipu context --json` envelope (PLAN Dilim 4).
# stdin: the plain context text. Unlike awk -v, stdin is read verbatim, so
# Windows paths (C:/Users/...) survive intact.
# Usage: awk -v JE_EV=EVENT -f lib/jsonemit.awk -f lib/emit_hookctx.awk
# Output: {"hookSpecificOutput":{"hookEventName":EVENT,"additionalContext":...}}
# (PLAN 4.5). No literal backslash (PLAN 4.11): the record separator comes
# from its code point.
{ if (NR == 1) buf = $0; else buf = buf sprintf("%c", 10) $0 }
END { if (JE_EV != "") print je_hook_context(JE_EV, buf) }
