# knotlog - jsonemit driver: the Antigravity Stop "continue" envelope.
# stdin: the reminder text.
# Usage: awk -f lib/jsonemit.awk -f lib/emit_agstop.awk
# Output: {"decision":"continue","reason":...}
{ if (NR == 1) buf = $0; else buf = buf sprintf("%c", 10) $0 }
END { print je_ag_continue(buf) }
