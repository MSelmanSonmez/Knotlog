# knotlog migrate: rewrite what Knotlog itself wrote before the rename, and
# nothing else. One mode per run (-v mode=hook|marker|ignore|config); the
# result goes to stdout and the caller decides whether to write it back.
# No literal backslash or quote byte in this file (PLAN 4.11): both come from
# code points.
BEGIN { dq = sprintf("%c", 34); bs = sprintf("%c", 92) }

function isword(c) {
  return c != "" && index("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-/", c) > 0
}

function rep(s, a, b,   out, p) {
  out = ""
  while ((p = index(s, a)) > 0) { out = out substr(s, 1, p - 1) b; s = substr(s, p + length(a)) }
  return out s
}

# A hook command line: QUIPU_HOOK=1 [&& ]quipu ... or the quoted checkout path
# repair-hooks wrote (".../quipu"). Anything else after QUIPU_HOOK=1 is the
# user's own command and is left exactly as it was.
function hookline(s,   out, p, sep, n, tok) {
  out = ""
  while ((p = index(s, "QUIPU_HOOK=1")) > 0) {
    out = out substr(s, 1, p - 1)
    s = substr(s, p + 12)
    sep = ""
    while (substr(s, 1, 1) == " " || substr(s, 1, 1) == "&") { sep = sep substr(s, 1, 1); s = substr(s, 2) }
    if (substr(s, 1, 5) == "quipu" && !isword(substr(s, 6, 1))) {
      out = out "KNOTLOG_HOOK=1" sep "knotlog"
      s = substr(s, 6)
    } else if ((n = quotedquipu(s)) > 0) {
      out = out "KNOTLOG_HOOK=1" sep bs dq home "/knotlog" bs dq
      s = substr(s, n + 4)
    } else {
      out = out "QUIPU_HOOK=1" sep
    }
  }
  return out s
}

# Length-index of the closing bs-dq when s opens with a quoted path ending in
# /quipu and home can be written back into JSON unescaped; else 0.
function quotedquipu(s,   n) {
  if (substr(s, 1, 2) != bs dq || home == "" || index(home, bs) > 0 || index(home, dq) > 0) return 0
  n = index(substr(s, 3), bs dq)
  if (n > 0 && substr(s, n - 4, 6) == "/quipu") return n
  return 0
}

function ownedmarker(t) {
  if (t == "start" || t == "end" || t == "archived" || t == "compacted") return 1
  return t ~ /^(context|reflect|threads|pin|core):(start|end)$/
}

mode == "hook" {
  if (index($0, dq "command") > 0) print hookline($0)
  else if (index($0, dq "name" dq) > 0) print rep($0, dq "quipu-", dq "knotlog-")
  else if (index($0, dq "description" dq) > 0) print rep($0, dq "quipu memory hooks", dq "knotlog memory hooks")
  else print
  next
}

# Only whole marker lines the tool writes, outside code fences; a mention of
# quipu: inside prose or a fenced example is the user's text.
mode == "marker" {
  if (substr($0, 1, 3) == "```" || substr($0, 1, 3) == "~~~") fence = !fence
  if (!fence && substr($0, 1, 11) == "<!-- quipu:" && substr($0, length($0) - 2) == "-->") {
    t = substr($0, 12)
    sub(/ .*$/, "", t)
    sub(/-->$/, "", t)
    if (ownedmarker(t)) { print "<!-- knotlog:" substr($0, 12); next }
  }
  print
  next
}

mode == "ignore" {
  if ($0 == "# quipu: machine state, regenerated -- not memory.") print "# knotlog: machine state, regenerated -- not memory."
  else if (substr($0, 1, 6) == ".quipu" && (length($0) == 6 || substr($0, 7, 1) == "/")) print ".knotlog" substr($0, 7)
  else print
  next
}

# Two passes over the same file: first the KNOTLOG_ keys already present, then
# the rewrite. An old key whose KNOTLOG_ twin exists is kept as a comment (the
# twin wins, nothing is lost) and its name goes to dupfile for the report.
mode == "config" && NR == FNR {
  if ($0 ~ /^KNOTLOG_[A-Z_]+=/) { k = $0; sub(/=.*/, "", k); have[k] = 1 }
  next
}
mode == "config" {
  if ($0 ~ /^QUIPU_[A-Z_]+=/) {
    k = $0; sub(/=.*/, "", k)
    nk = "KNOTLOG_" substr(k, 7)
    if (nk in have) { print "# migrated, " nk " wins: " $0; print nk > dupfile }
    else print nk substr($0, length(k) + 1)
  } else print
}
