# quipu - idempotent marker-block injector (AGENTS.md bridge, PLAN Dilim 4).
# Reads the replacement body from stdin, one line per record, and joins the
# lines with sprintf("%c",10) so this file contains no literal backslash
# (PLAN 4.11, test 29).
#
# For every file argument:
#   * the span from "<!-- knotlog:start -->" through "<!-- knotlog:end -->"
#     inclusive is replaced by the marker pair with the new body between them;
#   * the legacy "quipu:" spelling of the same pair is recognized too: the
#     family found first in a file is the one rewritten (its markers are kept
#     as they were, no second block is added); a block of the other family in
#     the same file passes through untouched;
#   * when no marker is present, the block is appended at end of file with
#     the "knotlog:" markers;
#   * every other line passes through verbatim (user content is preserved).

BEGIN {
  if (start == "") start = "<!-- knotlog:start -->"
  if (end   == "") end   = "<!-- knotlog:end -->"
  # legacy spelling of the same markers (only the "knotlog:" prefix differs)
  lstart = start; sub(/knotlog:/, "quipu:", lstart)
  lend   = end;   sub(/knotlog:/, "quipu:", lend)
  body  = ""
  while ((getline line < "-") > 0) {
    if (body == "") body = line
    else body = body sprintf("%c", 10) line
  }
  close("-")
}

FNR == 1 {
  if (NR > 1 && !seen) {
    print start
    if (body != "") print body
    print end
  }
  inblk = 0
  seen  = 0
  cs = ""
  ce = ""
}

inblk {
  if ($0 == ce) inblk = 0
  next
}

# the first marker pair found fixes the family for this file
cs == "" && ($0 == start || $0 == lstart) {
  cs = $0
  ce = ($0 == start) ? end : lend
}

cs != "" && $0 == cs {
  print cs
  if (body != "") print body
  print ce
  seen  = 1
  inblk = 1
  next
}

{
  print
}

END {
  if (!seen) {
    print start
    if (body != "") print body
    print end
  }
}
