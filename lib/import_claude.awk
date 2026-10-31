# knotlog import claude: one Claude Code transcript (.jsonl, one event per
# line) -> one Markdown session note on stdout. Run with LC_ALL=C (byte
# positions; lines can be hundreds of KB) after lib/jsonfield.awk.
# Only user and assistant text is kept: thinking, tool_use, tool_result,
# isMeta and isSidechain events, harness tags (<system-reminder> ...) and
# every non-message event are left out. Absolute paths outside the vault
# become IC_PATHMASK. No literal backslash (PLAN 4.11).
# ENVIRON: IC_VAULTS (vault path spellings, TAB-separated), IC_PATHMASK,
# IC_UNTITLED (printf format, the short session id), IC_STATS (file that
# gets "id TAB YYYY-MM-DD TAB messages TAB lines with a masked path").
BEGIN {
  CR = sprintf("%c", 13)
  PM = ENVIRON["IC_PATHMASK"]
  nv = split(ENVIRON["IC_VAULTS"], vlt, sprintf("%c", 9))
  n = 0
}

function skip_ws(s, p,   c) {
  while (p <= length(s)) {
    c = substr(s, p, 1)
    if (c == " " || c == ":" || c == "," || c == tab_() || c == nl_() || c == cr_()) p++
    else break
  }
  return p
}

function is_true(s, key,   p) {
  p = jf_anchor(s, key)
  return p != 0 && substr(s, skip_ws(s, p), 4) == "true"
}

# Position just past "key" when it is a direct field of the object whose
# opening brace is at or after a (up to z); 0 otherwise.
function direct_key(s, a, z, key,   i, c, e, k, depth, array) {
  i = a; depth = 0; array = 0
  while (i <= z) {
    c = substr(s, i, 1)
    if (c == q_()) {
      e = jf_string_end(s, i)
      if (e == 0) return 0
      k = e
      while (substr(s, k, 1) == " ") k++
      if (depth == 1 && array == 0 && substr(s, k, 1) == ":" && substr(s, i + 1, e - i - 2) == key) return e
      i = e
      continue
    }
    if (c == "{") depth++
    else if (c == "}") { depth--; if (depth == 0) return 0 }
    else if (c == "[") array++
    else if (c == "]" && array > 0) array--
    i++
  }
  return 0
}

function field(s, a, z, key,   p) {
  p = direct_key(s, a, z, key)
  return p ? jf_read(s, p) : ""
}

# Harness-injected text (<system-reminder>, <command-name>, ...) is not
# something the user wrote.
function kept(v,   i, c) {
  i = 1
  while ((c = substr(v, i, 1)) == " " || c == tab_() || c == nl_() || c == cr_()) i++
  return !(c == "<" && substr(v, i + 1, 1) ~ /[a-z]/)
}

# The text of a message object: a string content, or the "text" items of a
# content array (tool_use, tool_result, thinking and images are skipped).
function msg_text(s, a, z,   p, c, e, out, v, ty) {
  p = direct_key(s, a, z, "content")
  if (!p) return ""
  p = skip_ws(s, p)
  c = substr(s, p, 1)
  if (c == q_()) { v = jf_read(s, p); return kept(v) ? v : "" }
  if (c != "[") return ""
  out = ""
  p++
  while (p <= z) {
    p = skip_ws(s, p)
    c = substr(s, p, 1)
    if (c == "]" || c == "") break
    if (c == "{") {
      e = jf_object_end(s, p)
      if (e == 0) break
      # A tool_result turn is the harness answering a tool call, never the user.
      if ((ty = field(s, p, e, "type")) == "tool_result") return ""
      if (ty == "text") {
        v = field(s, p, e, "text")
        if (v != "" && kept(v)) out = out (out == "" ? "" : nl_() nl_()) v
      }
      p = e + 1
    } else if (c == q_()) {
      e = jf_string_end(s, p)
      if (e == 0) break
      p = e
    } else p++
  }
  return out
}

function abs_path(c,   c1) {
  c1 = substr(c, 1, 1)
  if (c1 == "/") return substr(c, 2, 1) ~ /[A-Za-z0-9._~]/ && index(substr(c, 2), "/") > 0
  if (c1 == "~") return substr(c, 2, 1) == "/"
  return c1 ~ /[A-Za-z]/ && substr(c, 2, 1) == ":" && (substr(c, 3, 1) == "/" || substr(c, 3, 1) == bs_())
}

function in_vault(c,   i, lc) {
  lc = tolower(c)
  for (i = 1; i <= nv; i++)
    if (vlt[i] != "" && index(lc, tolower(vlt[i])) == 1) return 1
  return 0
}

function mask_tok(tok,   pre, core, post, c) {
  pre = ""; post = ""; core = tok
  while (core != "" && index("(<[`'" q_(), substr(core, 1, 1))) { pre = pre substr(core, 1, 1); core = substr(core, 2) }
  while (core != "" && index(".,;:)>]`'" q_(), substr(core, length(core), 1))) {
    post = substr(core, length(core), 1) post
    core = substr(core, 1, length(core) - 1)
  }
  if (abs_path(core) && !in_vault(core)) { hit = 1; return pre PM post }
  return tok
}

function mask_line(l,   out, sp) {
  out = ""
  while ((sp = index(l, " ")) > 0) { out = out mask_tok(substr(l, 1, sp - 1)) " "; l = substr(l, sp + 1) }
  return out mask_tok(l)
}

{
  if (substr($0, length($0), 1) == CR) $0 = substr($0, 1, length($0) - 1)
  # Cheap gate first: message events open with parentUuid, the others with
  # their type; an api-request blob is never scanned.
  head = substr($0, 1, 40)
  if (index(head, "{" q_() "parentUuid" q_()) != 1 && index(head, "{" q_() "type" q_() ":" q_() "custom-title" q_()) != 1) next
  t = jf_read($0, jf_anchor($0, "type"))
  if (t == "custom-title") { v = jf_read($0, jf_anchor($0, "customTitle")); if (v != "") title = v; next }
  if (t != "user" && t != "assistant") next
  if (is_true($0, "isMeta") || is_true($0, "isSidechain")) next
  a = jf_anchor($0, "message")
  if (!a) next
  z = jf_object_end($0, a)
  if (!z) next
  v = msg_text($0, a, z)
  if (v == "") next
  if (sid == "") sid = jf_read($0, jf_anchor($0, "sessionId"))
  n++; role[n] = t; when[n] = jf_read($0, jf_anchor($0, "timestamp")); body[n] = v
}

function stamp(ts) {
  return substr(ts, 1, 10) " " substr(ts, 12, 5) " UTC"
}

END {
  masked = 0
  if (n > 0) {
    if (title == "") title = sprintf(ENVIRON["IC_UNTITLED"], substr(sid, 1, 8))
    gsub(q_(), "'", title)
    print "---"
    print "title: " q_() title q_()
    print "type: import"
    print "source: claude"
    print "claude_session: " sid
    print "---"
    print ""
    print "# " title
    for (i = 1; i <= n; i++) {
      print ""
      print "### " role[i] " (" stamp(when[i]) ")"
      print ""
      k = split(body[i], ln, nl_())
      for (j = 1; j <= k; j++) {
        hit = 0
        print mask_line(ln[j])
        masked += hit
      }
    }
  }
  printf "%s%c%s%c%d%c%d%c", sid, 9, substr(when[1], 1, 10), 9, n, 9, masked, 10 > ENVIRON["IC_STATS"]
}
