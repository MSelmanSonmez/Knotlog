# quipu — JSON string writer. Companion to jsonfield.awk.
# Contract (PLAN 4.5, 4.11): this file contains NO literal backslash. Every
# escape byte is produced from its code point, so no quoting layer can corrupt
# it. That includes line continuations -- expressions stay on one line.

function je_init(   i) {
  if (JE_READY) return
  for (i = 0; i < 256; i++) JE_ORD[sprintf("%c", i)] = i
  JE_BS = sprintf("%c", 92)
  JE_Q  = sprintf("%c", 34)
  JE_READY = 1
}

function je_esc(s,   n, i, c, o, code) {
  je_init()
  n = length(s); o = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if      (c == JE_BS)             o = o JE_BS JE_BS
    else if (c == JE_Q)              o = o JE_BS JE_Q
    else if (c == sprintf("%c", 10)) o = o JE_BS "n"
    else if (c == sprintf("%c", 13)) o = o JE_BS "r"
    else if (c == sprintf("%c",  9)) o = o JE_BS "t"
    else if (c == sprintf("%c",  8)) o = o JE_BS "b"
    else if (c == sprintf("%c", 12)) o = o JE_BS "f"
    else {
      code = JE_ORD[c]
      if (code != "" && code < 32) o = o JE_BS sprintf("u%04x", code)
      else                         o = o c
    }
  }
  return o
}

function je_str(s) { je_init(); return JE_Q je_esc(s) JE_Q }

# {"hookSpecificOutput":{"hookEventName":<ev>,"additionalContext":<ctx>}}
function je_hook_context(ev, ctx,   o) {
  o = "{" je_str("hookSpecificOutput") ":{"
  o = o je_str("hookEventName") ":" je_str(ev) ","
  o = o je_str("additionalContext") ":" je_str(ctx) "}}"
  return o
}

# Cursor hook output (cursor.com/docs/hooks): sessionStart takes additional_context. Copilot CLI
# takes a top-level additionalContext instead (JE_KEY=additionalContext).
function je_cursor_ctx(ev, ctx,   o) {
  return "{" je_str(JE_KEY != "" ? JE_KEY : "additional_context") ":" je_str(ctx) "}"
}

# {"decision":"block","reason":<reason>}
function je_block(reason,   o) {
  o = "{" je_str("decision") ":" je_str("block") ","
  o = o je_str("reason") ":" je_str(reason) "}"
  return o
}

# Antigravity SessionStart: {"injectSteps":[{"systemMessage":{"systemMessage":<ctx>}}]}
function je_ag_ctx(ctx,   o) {
  o = "{" je_str("injectSteps") ":[{" je_str("systemMessage") ":{"
  o = o je_str("systemMessage") ":" je_str(ctx) "}}]}"
  return o
}

# Antigravity Stop: {"decision":"continue","reason":<reason>} re-enters the loop.
function je_ag_continue(reason,   o) {
  o = "{" je_str("decision") ":" je_str("continue") ","
  o = o je_str("reason") ":" je_str(reason) "}"
  return o
}
