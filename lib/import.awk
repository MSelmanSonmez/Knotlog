# quipu — local conversation export reader.
# The shell joins a JSON export's physical lines before invoking this file.
# It accepts JSON objects carrying role/content pairs (Claude transcripts,
# ChatGPT conversations, and simple JSONL exports). Content arrays use the
# first text/parts string. Output is Markdown; no network or external parser.

function is_role(v) {
  return v == "system" || v == "user" || v == "assistant" || v == "tool"
}

function skip_json_ws(s, p,   c) {
  while (p <= length(s)) {
    c = substr(s, p, 1)
    if (c == " " || c == tab_() || c == nl_() || c == cr_()) p++
    else break
  }
  return p
}

function first_array_string(s, p) {
  p = skip_json_ws(s, p)
  if (substr(s, p, 1) != ":") return ""
  p = skip_json_ws(s, p + 1)
  if (substr(s, p, 1) != "[") return ""
  p = skip_json_ws(s, p + 1)
  if (substr(s, p, 1) != q_()) return ""
  return jf_read(s, p)
}

function content_after(s, p, end,   value, partsp, textp, nestedp) {
  if (end == 0) end = length(s) + 1
  # `content` is either a JSON string, an object with `parts`/`text`, or an
  # array of typed objects. Prefer parts before searching for text: a
  # content_type value of "text" is not itself a message.
  value = jf_read(s, p)
  if (value != "") return value
  partsp = jf_keyend(s, "parts", p)
  while (partsp != 0 && partsp < end) {
    value = first_array_string(s, partsp)
    if (value != "") return value
    partsp = jf_keyend(s, "parts", partsp + 1)
  }
  textp = jf_keyend(s, "text", p)
  while (textp != 0 && textp < end) {
    value = jf_read(s, textp)
    if (value != "") return value
    # jf_keyend is intentionally a small string scanner, so a content_type
    # value of "text" can be encountered before the actual text key.
    textp = jf_keyend(s, "text", textp + 1)
  }
  # Some exports use `content: [{...}]` and call the payload `content`
  # again inside the array item. This fallback remains scoped to the current
  # message because scan_messages bounds the initial content key by role.
  nestedp = jf_keyend(s, "content", p + 1)
  if (nestedp != 0 && nestedp < end) return content_after(s, nestedp, end)
  return ""
}

function emit_message(role, content) {
  if (content == "") return
  printf "### %s%c%c", role, nl_(), nl_()
  printf "%s%c%c", content, nl_(), nl_()
  found++
}

function scan_messages(s,   pos, rolep, contentp, nextrole, role, content) {
  pos = 1
  while (pos <= length(s)) {
    rolep = jf_keyend(s, "role", pos)
    if (rolep == 0) break
    role = jf_read(s, rolep)
    nextrole = jf_keyend(s, "role", rolep + 1)
    if (is_role(role)) {
      contentp = jf_keyend(s, "content", rolep)
      if (contentp != 0 && (nextrole == 0 || contentp < nextrole)) {
        content = content_after(s, contentp, nextrole)
        emit_message(role, content)
      }
    }
    pos = rolep + 1
  }
}

BEGIN {
  found = 0
  if (mode != "count") {
    print "---"
    print "title: Imported conversation"
    print "type: import"
    print "status: imported"
    print "---"
    printf "%s%c%c", "# Imported conversation", nl_(), nl_()
  }
}

{
  scan_messages($0)
}

END {
  if (mode == "count") print found + 0
}
