# knotlog distill helper. No literal backslash (PLAN 4.11): TAB and CR come
# from code points. Values arrive through ENVIRON, never awk -v (escapes).
#   mode=cand      "- " lines carrying DS_MARK -> relpath TAB cleaned text
#   mode=key       every "- " line -> cleaned text
#   mode=blockkey  same, only inside the knotlog:core block
#   mode=plan      file 1 = folded target keys, file 2 = folded key TAB rel
#                  TAB text -> ADD|DUP|UNTAGGED TAB rel TAB text
#   mode=hasblock exit 0 when a core block opens and closes (knotlog: or
#                  quipu: spelling; the marker must open an HTML comment)
#   mode=insert    copy the file, adding the lines of DS_ADD before the core
#                  block's end marker
BEGIN {
  TAB = sprintf("%c", 9); CR = sprintf("%c", 13)
  M1 = ENVIRON["DS_FACT"]; M2 = ENVIRON["DS_CORE"]; MARK = ENVIRON["DS_MARK"]
  SRCW = ENVIRON["DS_SRC"]; PRE = ENVIRON["DS_PRE"]
  ntag = split(ENVIRON["DS_TAGS"], tag, "|")
  if (mode == "insert") {
    while ((getline l < ENVIRON["DS_ADD"]) > 0) add[++nadd] = l
    close(ENVIRON["DS_ADD"])
  }
}
function mk(s, name) {
  return substr(s, 1, 4) == "<!--" && (index(s, "knotlog:core:" name) || index(s, "quipu:core:" name))
}
function cut(s, m,   i) {
  if (m == "") return s
  while ((i = index(s, m)) > 0) s = substr(s, 1, i - 1) " " substr(s, i + length(m))
  return s
}
function clean(s,   i, j, last, t) {
  gsub(TAB, " ", s); gsub(CR, " ", s)
  s = cut(cut(s, M1), M2)
  gsub(/  +/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
  t = " (" SRCW ": "
  if (substr(s, length(s)) == ")") {
    last = 0
    for (i = 1; (j = index(substr(s, i), t)) > 0; i = last + 1) last = i + j - 1
    if (last > 0) s = substr(s, 1, last - 1)
  }
  return s
}
function tagged(t,   i, r) {
  for (i = 1; i <= ntag; i++)
    if (tag[i] != "" && index(t, tag[i]) == 1) {
      r = substr(t, length(tag[i]) + 1)
      if (index(r, ":") == 1 || index(r, "：") == 1) return 1
    }
  return 0
}
mode == "hasblock" {
  if (mk($0, "start")) st = 1
  else if (st && mk($0, "end")) ok = 1
  next
}
END {
  if (mode == "hasblock") exit !ok
  if (mode == "insert") print (done ? nadd : 0) > ENVIRON["DS_COUNT"]
}
mode == "plan" {
  if (FILENAME == ARGV[1]) { seen[$0] = 1; next }
  k = $0; p = index(k, TAB); r = substr(k, p + 1); k = substr(k, 1, p - 1)
  if (ENVIRON["DS_LABEL"] == 1 && !tagged(substr(r, index(r, TAB) + 1))) st = "UNTAGGED"
  else if (k in seen) st = "DUP"
  else { st = "ADD"; seen[k] = 1 }
  print st TAB r TAB k
  next
}
mode == "insert" {
  if (mk($0, "start")) ins = 1
  else if (ins && !done && mk($0, "end")) {
    cr = (substr($0, length($0), 1) == CR) ? CR : ""
    for (i = 1; i <= nadd; i++) print add[i] cr
    done = 1
  }
  print
  next
}
FNR == 1 { rel = FILENAME; if (PRE != "" && index(rel, PRE) == 1) rel = substr(rel, length(PRE) + 1) }
substr($0, 1, 2) != "- " && mode != "blockkey" { next }
mode == "blockkey" {
  if (mk($0, "start")) { inb = 1; next }
  if (mk($0, "end")) { inb = 0; next }
  if (inb && substr($0, 1, 2) == "- ") { t = clean(substr($0, 3)); if (t != "") print t }
  next
}
mode == "key" { t = clean(substr($0, 3)); if (t != "") print t; next }
mode == "cand" && index($0, MARK) {
  t = clean(substr($0, 3))
  # knotlog note writes "- HH:MM text": the clock stamp is not part of the fact.
  if (ENVIRON["DS_TIME"] == 1 && t ~ /^[0-9][0-9]:[0-9][0-9] /) t = substr(t, 7)
  if (t != "") print rel TAB t
}
