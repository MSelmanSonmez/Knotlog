# knotlog mcp -- stdio MCP server loop. One JSON-RPC message per line in, one
# per line out; stdout carries MCP messages only. Run after jsonfield.awk and
# jsonemit.awk (-v ver=<knotlog version> -v maxline=<byte cap per line>).
# No literal backslash here: strings go through je_str.

function mc_ws(c) { return c == " " || c == tab_() || c == cr_() || c == nl_() }

# One complete JSON-looking object: braces/brackets balance outside strings and
# the first "{" closes on the last character. shortcut: not a full JSON
# validator (bad literals inside a balanced object pass), upgrade if a client needs it.
function mc_object(s,   n, i, c, e, depth) {
  n = length(s)
  if (substr(s, 1, 1) != "{" || substr(s, n, 1) != "}") return 0
  depth = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == q_()) {
      e = jf_string_end(s, i)
      if (e == 0) return 0
      i = e - 1
    } else if (c == "{" || c == "[") depth++
    else if (c == "}" || c == "]") {
      depth--
      if (depth < 0 || (depth == 0 && i < n)) return 0
    }
  }
  return depth == 0
}

# Position just past the closing quote of root-level key `key` (0 if absent).
# Strings inside nested values and string VALUES equal to the key are skipped.
function mc_keypos(s, key,   n, i, c, e, depth, j) {
  n = length(s); depth = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == q_()) {
      e = jf_string_end(s, i)
      if (e == 0) return 0
      if (depth == 1) {
        j = e
        while (j <= n && mc_ws(substr(s, j, 1))) j++
        if (substr(s, j, 1) == ":" && substr(s, i + 1, e - i - 2) == key) return e
      }
      i = e - 1
    } else if (c == "{" || c == "[") depth++
    else if (c == "}" || c == "]") depth--
  }
  return 0
}

# Raw value token of a root-level key, byte for byte (quotes kept); "" if absent.
function mc_raw(s, key,   p, n, e, c, o) {
  p = mc_keypos(s, key)
  if (p == 0) return ""
  n = length(s)
  while (p <= n && (substr(s, p, 1) == ":" || mc_ws(substr(s, p, 1)))) p++
  if (substr(s, p, 1) == q_()) {
    e = jf_string_end(s, p)
    return e ? substr(s, p, e - p) : ""
  }
  o = ""
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == "," || c == "}" || c == "]" || mc_ws(c)) break
    o = o c; p++
  }
  return o
}

function mc_send(s) { print s; fflush() }

function mc_err(id, code, msg, data) {
  mc_send("{" je_str("jsonrpc") ":" je_str("2.0") "," je_str("id") ":" (id == "" ? "null" : id)     "," je_str("error") ":{" je_str("code") ":" code "," je_str("message") ":" je_str(msg)     (data == "" ? "" : "," je_str("data") ":" data) "}}")
}

function mc_ok(id, result) {
  mc_send("{" je_str("jsonrpc") ":" je_str("2.0") "," je_str("id") ":" id "," je_str("result") ":" result "}")
}

function mc_info() { return "{" je_str("name") ":" je_str("knotlog") "," je_str("version") ":" je_str(ver) "}" }

function mc_prop(name, type, desc) {
  return je_str(name) ":{" je_str("type") ":" je_str(type) "," je_str("description") ":" je_str(desc) "}"
}

function mc_tools(   s, c, n) {
  s = "{" je_str("type") ":" je_str("object") "," je_str("properties") ":{"
  s = s mc_prop("query", "string", "Search terms") "," mc_prop("limit", "integer", "Maximum number of results") "}"
  s = s "," je_str("required") ":[" je_str("query") "]}"
  c = "{" je_str("type") ":" je_str("object") "," je_str("additionalProperties") ":false}"
  n = "{" je_str("type") ":" je_str("object") "," je_str("properties") ":{" mc_prop("text", "string", "One line to add") "}"
  n = n "," je_str("required") ":[" je_str("text") "]," je_str("additionalProperties") ":false}"
  return "[{" je_str("name") ":" je_str("knotlog_search") ","     je_str("description") ":" je_str("Search the Knotlog vault notes (folded lexical plus BM25 ranking); returns matching notes with short snippets.")     "," je_str("inputSchema") ":" s "},"     "{" je_str("name") ":" je_str("knotlog_context") ","     je_str("description") ":" je_str("Return the session memory context of the current Knotlog vault.")     "," je_str("inputSchema") ":" c "},"     "{" je_str("name") ":" je_str("knotlog_note") ","     je_str("description") ":" je_str("Append one line to today's session reflection note in the Knotlog vault (append-only, the same as knotlog note); writes nothing else.")     "," je_str("inputSchema") ":" n "}]"
}

# Root-level key whose value is an object -> that object's text, else "".
function mc_obj(s, key,   p, n, e) {
  p = mc_keypos(s, key)
  if (p == 0) return ""
  n = length(s)
  while (p <= n && (substr(s, p, 1) == ":" || mc_ws(substr(s, p, 1)))) p++
  e = jf_object_end(s, p)
  return e ? substr(s, p, e - p + 1) : ""
}

function mc_isint(t,   i, n, c) {
  n = length(t); i = 1
  if (substr(t, 1, 1) == "-") i = 2
  if (i > n) return 0
  for (; i <= n; i++) { c = substr(t, i, 1); if (c < "0" || c > "9") return 0 }
  return 1
}

# Wrap s in single quotes for sh. Inside single quotes nothing is special, so
# the only character to handle is the single quote itself: close, add an
# escaped quote, reopen. Built with index/substr, not gsub, so that neither
# "&" nor a backslash in the replacement can misbehave.
function mc_sq(s,   o, i, sq) {
  sq = sprintf("%c", 39)
  o = ""
  while ((i = index(s, sq)) > 0) {
    o = o substr(s, 1, i - 1) sq bs_() sq sq
    s = substr(s, i + 1)
  }
  return sq o s sq
}

# Run `sh knotlog <args>` with stdin closed and stderr in a scratch file.
# Sets mc_rc and mc_out (stdout) and mc_msg (stderr text, or a fallback).
# shortcut: the child's stdout is read whole; fine for search and context
# (both bounded), upgrade if a tool with unbounded output is added.
function mc_run(args,   cmd, line, rcline) {
  cmd = "{ sh " mc_sq(ENVIRON["KNOTLOG_MCP_SELF"]) " " args " 2>" mc_sq(ENVIRON["KNOTLOG_MCP_ERR"]) " </dev/null; rc=$?; echo; echo rc=$rc; }"
  mc_out = ""
  while ((cmd | getline line) > 0) mc_out = mc_out line nl_()
  close(cmd)
  # The trailer is a newline, rc=N, a newline: drop it and the newline the echo added.
  mc_rc = 1
  if (match_rc(mc_out)) { mc_rc = mc_rcval; mc_out = mc_body }
  mc_msg = ""
  while ((getline line < ENVIRON["KNOTLOG_MCP_ERR"]) > 0) mc_msg = mc_msg line nl_()
  close(ENVIRON["KNOTLOG_MCP_ERR"])
}

# Split mc_out into body and exit code without regex.
function match_rc(s,   n, i, tail) {
  n = length(s)
  if (substr(s, n, 1) != nl_()) return 0
  i = n - 1
  while (i > 0 && substr(s, i, 1) != nl_()) i--
  tail = substr(s, i + 1, n - i - 1)
  if (substr(tail, 1, 3) != "rc=" || !mc_isint(substr(tail, 4))) return 0
  mc_rcval = substr(tail, 4) + 0
  mc_body = (i > 1) ? substr(s, 1, i - 1) : ""
  return 1
}

function mc_tool_result(id, r, text, bad) {
  mc_ok(id, "{" r je_str("content") ":[{" je_str("type") ":" je_str("text") "," je_str("text") ":" je_str(text) "}]," je_str("isError") ":" (bad ? "true" : "false") "}")
}

# tools/call. Wrong shape (unknown tool, missing or mistyped argument) is a
# protocol error, -32602; a tool that ran and failed is a result with isError.
function mc_call(id, s, r,   p, name, args, qtok, ltok, query, lim, a, ttok, text) {
  p = mc_obj(s, "params")
  if (p == "" || mc_raw(p, "name") == "" || substr(mc_raw(p, "name"), 1, 1) != q_()) { mc_err(id, -32602, "Invalid params"); return }
  name = jf_read(p, mc_keypos(p, "name"))
  args = mc_obj(p, "arguments")
  if (name == "knotlog_context") {
    mc_run("context")
  } else if (name == "knotlog_search") {
    qtok = mc_raw(args, "query"); ltok = mc_raw(args, "limit")
    if (substr(qtok, 1, 1) != q_()) { mc_err(id, -32602, "Invalid params: query (string) is required"); return }
    if (ltok != "" && !mc_isint(ltok)) { mc_err(id, -32602, "Invalid params: limit must be an integer"); return }
    query = jf_read(args, mc_keypos(args, "query"))
    if (substr(query, 1, 1) == "-") { mc_tool_result(id, r, "query must not start with a dash", 1); return }
    a = "search --brief"
    if (ltok != "") {
      if (ltok + 0 < 1) { mc_tool_result(id, r, "limit must be at least 1", 1); return }
      a = a " --limit " (ltok + 0)
    }
    mc_run(a " " mc_sq(query))
  } else if (name == "knotlog_note") {
    ttok = mc_raw(args, "text")
    if (substr(ttok, 1, 1) != q_()) { mc_err(id, -32602, "Invalid params: text (string) is required"); return }
    text = jf_read(args, mc_keypos(args, "text"))
    if (text == "") { mc_tool_result(id, r, "text must not be empty", 1); return }
    if (substr(text, 1, 1) == "-") { mc_tool_result(id, r, "text must not start with a dash", 1); return }
    mc_run("note " mc_sq(text))
  } else { mc_err(id, -32602, "Unknown tool: " name); return }
  if (mc_rc == 0) mc_tool_result(id, r, mc_out, 0)
  else mc_tool_result(id, r, (mc_msg != "" ? mc_msg : "knotlog exited with status " mc_rc), 1)
}

function mc_known(v) { return v == "2024-11-05" || v == "2025-03-26" || v == "2025-06-18" || v == "2025-11-25" }

function mc_line(s,   id, m, v, meta, r) {
  if (length(s) > maxline) { mc_err("", -32600, "Request too large"); return }
  if (substr(s, 1, 1) == "[") { mc_err("", -32600, "Invalid Request"); return }
  if (!mc_object(s)) { mc_err("", -32700, "Parse error"); return }
  id = mc_raw(s, "id")
  if (mc_keypos(s, "method") == 0) {
    if (id == "") mc_err("", -32600, "Invalid Request")   # a client response (id, no method) is ignored
    return
  }
  if (id == "") return                                     # notification: never answered
  m = jf_read(s, mc_keypos(s, "method"))
  if (m == "") { mc_err(id, -32600, "Invalid Request"); return }
  if (m == "initialize") {
    v = jsonfield_scoped(s, "params", "protocolVersion")
    if (!mc_known(v)) v = "2025-11-25"
    mc_ok(id, "{" je_str("protocolVersion") ":" je_str(v) "," je_str("capabilities") ":{" je_str("tools") ":{}},"       je_str("serverInfo") ":" mc_info() "}")
    return
  }
  meta = jsonfield(s, "io.modelcontextprotocol/protocolVersion")   # modern era: version rides on every request
  if (meta != "" && meta != "2026-07-28") {
    mc_err(id, -32022, "Unsupported protocol version", "{" je_str("supported") ":[" je_str("2026-07-28") "]," je_str("requested") ":" je_str(meta) "}")
    return
  }
  r = (meta != "") ? je_str("resultType") ":" je_str("complete") "," : ""
  if (m == "ping") mc_ok(id, "{" (meta != "" ? je_str("resultType") ":" je_str("complete") : "") "}")
  else if (m == "server/discover")
    mc_ok(id, "{" je_str("resultType") ":" je_str("complete") "," je_str("supportedVersions") ":[" je_str("2026-07-28") "],"       je_str("capabilities") ":{" je_str("tools") ":{}}," je_str("_meta") ":{" je_str("io.modelcontextprotocol/serverInfo") ":" mc_info() "},"       je_str("ttlMs") ":3600000," je_str("cacheScope") ":" je_str("public") "}")
  else if (m == "tools/list")
    mc_ok(id, "{" r je_str("tools") ":" mc_tools() (meta != "" ? "," je_str("ttlMs") ":3600000," je_str("cacheScope") ":" je_str("public") : "") "}")
  else if (m == "tools/call") mc_call(id, s, r)
  else mc_err(id, -32601, "Method not found")
}

{ if (substr($0, length($0), 1) == cr_()) $0 = substr($0, 1, length($0) - 1); if ($0 != "") mc_line($0) }
