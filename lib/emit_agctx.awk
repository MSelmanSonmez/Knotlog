# knotlog - jsonemit driver: the Antigravity SessionStart envelope.
# stdin: the plain context text, read verbatim.
# Usage: awk -f lib/jsonemit.awk -f lib/emit_agctx.awk
# Output: {"injectSteps":[{"systemMessage":{"systemMessage":...}}]}
{ if (NR == 1) buf = $0; else buf = buf sprintf("%c", 10) $0 }
END { print je_ag_ctx(buf) }
