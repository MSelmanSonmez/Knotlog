# quipu - jsonemit driver: the Cursor hook envelope for `quipu context --json <Ev> --cursor`.
# stdin: the plain context text. Unlike awk -v, stdin is read verbatim, so
# Windows paths (C:/Users/...) survive intact.
# Usage: awk -v JE_EV=EVENT [-v JE_KEY=additionalContext] -f lib/jsonemit.awk -f lib/emit_cursorctx.awk
# Output: {"additional_context":...} (sessionStart); see je_cursor_ctx.
# No literal backslash (PLAN 4.11): the record separator comes from its code point.
{ if (NR == 1) buf = $0; else buf = buf sprintf("%c", 10) $0 }
END { if (JE_EV != "") print je_cursor_ctx(JE_EV, buf) }
