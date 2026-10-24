# quipu - jsonemit driver: the `quipu context --json Stop` block envelope.
# stdin: the block reason text.
# Usage: awk -f lib/jsonemit.awk -f lib/emit_hookblock.awk
# Output: {"decision":"block","reason":...}
# No literal backslash (PLAN 4.11): record separator from code point.
{ if (NR == 1) buf = $0; else buf = buf sprintf("%c", 10) $0 }
END { print je_block(buf) }
