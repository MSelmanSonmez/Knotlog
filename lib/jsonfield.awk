# quipu — JSON string field reader.
# Contract (see PLAN 4.8, 4.11, 4.12):
#   * No regex. Manual character scan only.
#   * No literal backslash anywhere in this file. Backslash is produced with
#     sprintf("%c", 92) so no quoting layer (heredoc, shell, editor) can corrupt it.
#   * Never scans tool_response: callers use jsonfield_from() with a scope anchor.
#   * Missing field returns "" instead of failing.

function q_(   ) { return sprintf("%c", 34) }   # "
function bs_(  ) { return sprintf("%c", 92) }   # backslash
function nl_(  ) { return sprintf("%c", 10) }
function tab_( ) { return sprintf("%c",  9) }
function cr_(  ) { return sprintf("%c", 13) }

# Position just past the closing quote of "key". 0 if absent.
function jf_keyend(s, key, start,   k, i) {
  if (start < 1) start = 1
  k = q_() key q_()
  i = index(substr(s, start), k)
  if (i == 0) return 0
  return start + i - 1 + length(k)
}

# Position just past a JSON string's closing quote. 0 for an unterminated or
# non-string value. Braces and key names inside strings are data, not syntax.
function jf_string_end(s, p,   n, c, esc) {
  n = length(s)
  if (substr(s, p, 1) != q_()) return 0
  p++
  esc = 0
  while (p <= n) {
    c = substr(s, p, 1)
    if (esc) esc = 0
    else if (c == bs_()) esc = 1
    else if (c == q_()) return p + 1
    p++
  }
  return 0
}

# Four hex digits at s[p..p+3] -> number, -1 when they are not all hex.
function jf_hex4(s, p,   i, d, v) {
  v = 0
  for (i = 0; i < 4; i++) {
    d = index("0123456789abcdef", tolower(substr(s, p + i, 1)))
    if (d == 0) return -1
    v = v * 16 + d - 1
  }
  return v
}

# One code point as UTF-8. gawk in a UTF-8 locale makes %c a character, mawk
# and a C locale make it a byte; sprintf("%c", 256) == sprintf("%c", 0) only
# for byte-wise %c, so test that once and build the bytes by hand if needed.
function jf_utf8(cp,   b) {
  if (jf_mode == "") jf_mode = (sprintf("%c", 256) == sprintf("%c", 0)) ? "byte" : "char"
  if (jf_mode == "char") return sprintf("%c", cp)
  if (cp < 128) return sprintf("%c", cp)
  if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
  if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
  return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
}

# Decode the escape whose 'u' sits at s[p]. Sets jf_ulen to the number of
# characters after the 'u' that it consumed (4, or 10 for a surrogate pair).
# Lone surrogates become U+FFFD; malformed hex and U+0000 stay "?" (the old
# placeholder) so a NUL byte never reaches a shell string.
function jf_uni(s, p,   hi, lo) {
  jf_ulen = 4
  hi = jf_hex4(s, p + 1)
  if (hi < 0 || hi == 0) return "?"
  if (hi >= 55296 && hi < 56320) {                       # D800..DBFF
    lo = -1
    if (substr(s, p + 5, 2) == bs_() "u") lo = jf_hex4(s, p + 7)
    if (lo >= 56320 && lo < 57344) { jf_ulen = 10; return jf_utf8(65536 + (hi - 55296) * 1024 + (lo - 56320)) }
    return jf_utf8(65533)
  }
  if (hi >= 56320 && hi < 57344) return jf_utf8(65533)   # lone low surrogate
  return jf_utf8(hi)
}

# Read the string value that follows position p (expects optional ws, ':', ws, '"').
function jf_read(s, p,   n, c, out, esc) {
  n = length(s)
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == ":" || c == " " || c == tab_() || c == nl_() || c == cr_()) p++
    else break
  }
  if (substr(s, p, 1) != q_()) return ""   # not a string value (number/object/null)
  p++
  out = ""; esc = 0
  while (p <= n) {
    c = substr(s, p, 1)
    if (esc) {
      if      (c == "n") out = out nl_()
      else if (c == "t") out = out tab_()
      else if (c == "r") out = out cr_()
      else if (c == "b" || c == "f") { }        # dropped on purpose
      else if (c == "u") { out = out jf_uni(s, p); p += jf_ulen }   # uXXXX escape, UTF-8
      else out = out c                          # covers escaped quote, backslash, slash
      esc = 0
    }
    else if (c == bs_()) esc = 1
    else if (c == q_()) return out
    else out = out c
    p++
  }
  return out
}

# Whole-string lookup. Convenience only; prefer jsonfield_from for nested keys.
function jsonfield(s, key,   e) {
  e = jf_keyend(s, key, 1)
  if (e == 0) return ""
  return jf_read(s, e)
}

# Scoped lookup: find "key" only at/after position `start`.
function jsonfield_from(s, key, start,   e) {
  e = jf_keyend(s, key, start)
  if (e == 0) return ""
  return jf_read(s, e)
}

# Position of an anchor key, for scoping. e.g. jf_anchor(s, "tool_input")
function jf_anchor(s, key,   n, c, i, e, raw, depth, array) {
  # Find the requested key only among the root object's direct fields. This
  # prevents a tool_response/string value from becoming the scope anchor.
  n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == " " || c == tab_() || c == nl_() || c == cr_()) i++
    else break
  }
  if (substr(s, i, 1) != "{") return 0
  depth = 1; array = 0; i++
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == q_()) {
      e = jf_string_end(s, i)
      if (e == 0) return 0
      if (depth == 1 && array == 0) {
        raw = substr(s, i + 1, e - i - 2)
        if (raw == key) return e
      }
      i = e
      continue
    }
    if (c == "{") depth++
    else if (c == "}") {
      depth--
      if (depth == 0) return 0
    } else if (c == "[") array++
    else if (c == "]" && array > 0) array--
    i++
  }
  return 0
}

# Return the closing brace of the object whose opening brace is at p. Braces
# inside JSON strings are ignored. 0 means the anchor did not lead to an
# object or the object was truncated.
function jf_object_end(s, p,   n, c, depth, quoted, esc) {
  n = length(s)
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == " " || c == tab_() || c == nl_() || c == cr_() || c == ":") p++
    else break
  }
  if (substr(s, p, 1) != "{") return 0
  depth = 0; quoted = 0; esc = 0
  while (p <= n) {
    c = substr(s, p, 1)
    if (quoted) {
      if (esc) esc = 0
      else if (c == bs_()) esc = 1
      else if (c == q_()) quoted = 0
    } else {
      if (c == q_()) quoted = 1
      else if (c == "{") depth++
      else if (c == "}") {
        depth--
        if (depth == 0) return p
      }
    }
    p++
  }
  return 0
}

# Read a string field from the anchored JSON object only. The upper bound is
# important for hook payloads: a missing tool_input.command must never fall
# through to an attacker-controlled field in tool_response.
function jsonfield_scoped(s, anchor, key,   a, z, e, n, c, i, qend, raw, depth, array) {
  a = jf_anchor(s, anchor)
  if (a == 0) return ""
  z = jf_object_end(s, a)
  if (z == 0) return ""
  # Read only direct fields of the anchored object. A key-shaped fragment in
  # the command string or a nested response object must never be returned.
  n = z; i = a; depth = 0; array = 0
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == q_()) {
      qend = jf_string_end(s, i)
      if (qend == 0 || qend > n + 1) return ""
      if (depth == 1 && array == 0) {
        raw = substr(s, i + 1, qend - i - 2)
        e = qend
        while (e <= n && (substr(s, e, 1) == " " || substr(s, e, 1) == tab_() || substr(s, e, 1) == nl_() || substr(s, e, 1) == cr_())) e++
        if (substr(s, e, 1) == ":" && raw == key) return jf_read(s, qend)
      }
      i = qend
      continue
    }
    if (c == "{") depth++
    else if (c == "}") {
      depth--
      if (depth == 0) return ""
    } else if (c == "[") array++
    else if (c == "]" && array > 0) array--
    i++
  }
  return ""
}
