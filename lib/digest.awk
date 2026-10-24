# quipu — activity digest: per-path counts and last TOOL (default, mode unset),
# or fact lines RANGE/TOOL/FILE for the session digest writer (mode=digest).
# Reads TS | EVENT | TOOL | PATH log lines from a file argument or stdin.
# Parses only the first three " | " separators; PATH is everything after the
# third and may itself contain " | ". Lines with fewer than three separators,
# or an empty PATH, are skipped.
# No literal backslash anywhere in this file (PLAN 4.11): the output field
# separator is the TAB control byte, produced from code point 9.
BEGIN { OFS = sprintf("%c", 9); n = 0; ntool = 0; npath = 0 }
{
  s = $0
  p = index(s, " | ")
  if (p == 0) next
  ts = substr(s, 1, p - 1)
  s = substr(s, p + 3)
  p = index(s, " | ")
  if (p == 0) next
  s = substr(s, p + 3)
  p = index(s, " | ")
  if (p == 0) next
  tool = substr(s, 1, p - 1)
  path = substr(s, p + 3)
  if (path == "") next
  n++
  if (n == 1) first = ts
  last = ts
  cnt[path]++
  lasttool[path] = tool
  toolcnt[tool]++
  if (!(tool in toolseen)) { toolseen[tool] = 1; toolord[ntool] = tool; ntool++ }
  if (!(path in pathseen)) { pathseen[path] = 1; pathord[npath] = path; npath++ }
}
END {
  if (mode == "digest") {
    print "RANGE", first, last, n
    for (i = 0; i < ntool; i++) print "TOOL", toolord[i], toolcnt[toolord[i]]
    for (i = 0; i < npath; i++) print "FILE", pathord[i], cnt[pathord[i]]
  } else {
    for (path in cnt) print path, cnt[path], lasttool[path]
  }
}
