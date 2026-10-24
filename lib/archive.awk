# lib/archive.awk -- B-K3 (`quipu archive`): locate a markdown heading and
# its section boundaries inside the threads file, honoring the pin block
# (<!-- knotlog:pin:start/end -->; legacy quipu: spelling too) as an archive-proof region. PLAN 4.11: no
# literal backslash byte anywhere in this file -- tab is built with
# sprintf("%c", 9), never a backslash-t escape, matching lib/block.awk's
# own newline-via-sprintf convention.
#
# Two modes, selected by -v mode=:
#   list    -- print every heading in the file, in order, one per line, as
#             "<pin-or-dash><TAB><heading text>". Used by `quipu archive
#             --list` so the user can see exactly what is archivable (and
#             which headings are protected by the pin block) without
#             opening the file. The first column is never empty -- see the
#             comment at the print site for why that matters to the shell
#             caller.
#   analyze -- find the heading whose trimmed text equals
#             ENVIRON["Q_AR_TARGET"] and report its section's line range,
#             or a STATUS error when the target is absent, ambiguous, or
#             sits inside the pin block. ENVIRON (not -v) carries the
#             target because a -v assignment interprets escape sequences
#             (POSIX) -- a heading containing an escape-like sequence
#             would be corrupted before comparison; ENVIRON does not (the
#             same reason quipu's plan command feeds its title/date
#             through ENVIRON rather than -v).
#
# A "section" is the heading line plus every line after it up to (but
# excluding) the next heading whose level is <= the matched heading's own
# level, or end of file. Heading-text comparison is plain string equality,
# not a pattern match -- a heading containing regex-special characters
# (parentheses, brackets, the user's own em-dashes) still matches exactly
# as typed, with nothing to escape.

function heading_level(s,    i, c) {
  c = 0
  i = 1
  while (substr(s, i, 1) == "#") { c++; i++ }
  if (c == 0) return 0
  if (substr(s, i, 1) != SP && substr(s, i, 1) != TAB) return 0
  return c
}

function is_blank(c) {
  return (c == SP || c == TAB)
}

function trim(s,    i, j) {
  i = 1
  while (i <= length(s) && is_blank(substr(s, i, 1))) i++
  j = length(s)
  while (j >= i && is_blank(substr(s, j, 1))) j--
  if (j < i) return ""
  return substr(s, i, j - i + 1)
}

function heading_text(s, lvl,    t) {
  # A CRLF file keeps its CR on the line end under some awks (GNU awk on
  # Linux, macOS awk) and drops it under others (MSYS awk on Windows). The
  # one trailing CR is not part of the heading text, so it is dropped here
  # and both kinds of awk compare the same string.
  t = s
  if (substr(t, length(t), 1) == CR) t = substr(t, 1, length(t) - 1)
  return trim(substr(t, lvl + 1))
}

BEGIN {
  SP = sprintf("%c", 32)
  TAB = sprintf("%c", 9)
  NL = sprintf("%c", 10)
  CR = sprintf("%c", 13)
  target = ENVIRON["Q_AR_TARGET"]
  pin = 0
  matches = 0
}

{
  if (index($0, "<!-- knotlog:pin:start -->") == 1 || index($0, "<!-- quipu:pin:start -->") == 1) { pin = 1 }
  inpin[NR] = pin
  if (index($0, "<!-- knotlog:pin:end -->") == 1 || index($0, "<!-- quipu:pin:end -->") == 1) { pin = 0 }
  lvl = heading_level($0)
  if (lvl > 0) {
    ishead[NR] = 1
    headlvl[NR] = lvl
    headtxt[NR] = heading_text($0, lvl)
    if (mode == "analyze" && headtxt[NR] == target) {
      matches++
      if (matches == 1) { mline = NR; mlvl = lvl }
    }
  }
}

END {
  total = NR
  if (mode == "list") {
    for (i = 1; i <= total; i++) {
      if (ishead[i]) {
        # The first column is "pin" or "-", never empty: POSIX `read` on
        # the shell side strips a LEADING IFS-whitespace field even when
        # IFS is set to a single custom character that happens to fall in
        # the "IFS whitespace" class (a tab does) -- an empty first column
        # would silently shift the heading text into the wrong shell
        # variable. "pin"/"-" are never confused with real heading text
        # because the caller only ever tests equality against "pin".
        printf "%s%s%s%s", (inpin[i] ? "pin" : "-"), TAB, headtxt[i], NL
      }
    }
    exit 0
  }
  # mode == "analyze"
  if (matches == 0) { print "STATUS" TAB "NOTFOUND"; exit 0 }
  if (matches > 1)  { print "STATUS" TAB "AMBIGUOUS" TAB matches; exit 0 }
  if (inpin[mline])  { print "STATUS" TAB "PINNED"; exit 0 }
  endline = total + 1
  for (i = mline + 1; i <= total; i++) {
    if (ishead[i] && headlvl[i] <= mlvl) { endline = i; break }
  }
  print "STATUS" TAB "OK" TAB mline TAB (endline - 1)
}
