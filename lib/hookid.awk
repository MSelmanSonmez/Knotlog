# knotlog - session identity from one hook payload (stdin).
# Loaded alongside jsonfield.awk. Prints "<id8><TAB><client>", or nothing when
# the payload carries no usable id. The id is reduced to letters, digits and
# "-" so it is safe inside a heading; a hex/UUID id keeps its first 8
# characters (id8), a word slug such as Devin's "flax-drip" stays whole (up to
# 24), since its first 8 characters would cut a word and collide.
# Id keys by client: conversation_id (Cursor), trajectory_id (Antigravity; Devin/Windsurf when agent_action_name is present),
# session_id (Claude Code, Codex, Gemini CLI; told apart by transcript_path).
# No regex, no literal backslash.
function clean(v,   i, c, o, hex) {
  o = ""; hex = 1
  for (i = 1; i <= length(v) && length(o) < 24; i++) {
    c = substr(v, i, 1)
    if (index("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-", c)) {
      o = o c
      if (!index("0123456789abcdefABCDEF-", c)) hex = 0
    }
  }
  return hex ? substr(o, 1, 8) : o
}
{ s = s $0 }
END {
  client = "cursor"
  id = clean(jsonfield(s, "conversation_id"))
  if (id == "") {
    client = "antigravity"; id = clean(jsonfield(s, "trajectory_id"))
    # Windsurf / Devin payloads also carry agent_action_name; assumed absent from Antigravity's.
    if (jsonfield(s, "agent_action_name") != "") client = "devin"
  }
  if (id == "") {
    client = "agent"
    id = clean(jsonfield(s, "session_id"))
    tp = jsonfield(s, "transcript_path")
    # Windows paths: the payload spells the separator as a backslash.
    t2 = ""; for (i = 1; i <= length(tp); i++) { c = substr(tp, i, 1); t2 = t2 ((c == sprintf("%c", 92)) ? "/" : c) }; tp = t2
    if (index(tp, "/.claude/")) client = "claude-code"
    else if (index(tp, "/.codex/")) client = "codex"
    else if (index(tp, "/.gemini/")) client = "gemini"
  }
  if (id != "") print id sprintf("%c", 9) client
}
