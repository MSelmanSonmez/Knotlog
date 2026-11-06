# knotlog similar helper. No literal backslash (PLAN 4.11): TAB and CR come
# from code points. Values arrive through ENVIRON, never awk -v (escapes).
#   mode=facts    "- " lines of the facts file -> candidate rows
#   mode=threads  list lines of the active threads section (pin block skipped)
#   mode=pending  approved, not rejected lesson/fix/skill proposals
#   mode=score    file 1 = distilled ledger, file 2 = candidate rows with a
#                 folded text column -> scored pairs (Jaccard on stems)
# Candidate row: kind TAB path TAB line TAB source TAB ref TAB text [TAB folded]
BEGIN {
  TAB = sprintf("%c", 9); CR = sprintf("%c", 13)
  REL = ENVIRON["SM_REL"]
  for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
  nw = split(ENVIRON["SM_WORDS"], wd, "|")
  STEM = ENVIRON["SM_STEM"] + 0
  ng = split(ENVIRON["SM_TAGS"], tg, "|")
  for (i = 1; i <= ng; i++) if (tg[i] != "") tagset[tg[i]] = 1
  if (mode == "pending") FS = TAB
}
function clean(s) {
  gsub(TAB, " ", s); gsub(CR, " ", s); gsub(/[[:cntrl:]]/, " ", s)
  gsub(/  +/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
  return s
}
# Trailing "(source: X)" -> sets SRC to X and returns the text without it.
function strip(s,   i, j, last, t, k, p) {
  SRC = ""
  if (substr(s, length(s)) != ")") return s
  for (k = 1; k <= nw; k++) {
    t = " (" wd[k] ": "
    last = 0
    for (i = 1; (j = index(substr(s, i), t)) > 0; i = last + 1) last = i + j - 1
    if (last > 0) {
      p = last + length(t)
      SRC = substr(s, p, length(s) - p)
      return substr(s, 1, last - 1)
    }
  }
  return s
}
function emit(kind, ln, ref, s,   t) {
  s = clean(s)
  t = strip(s)
  if (t == "") return
  print kind TAB REL TAB ln TAB SRC TAB ref TAB t
}
mode == "facts" && /^- / { t = $0; sub(/^- /, "", t); emit("f", FNR, "", t) }
mode == "threads" {
  t = $0; sub(/\r$/, "", t)
  if (!blk) { if (index(t, "knotlog:threads:start") || index(t, "quipu:threads:start")) blk = 1; next }
  if (index(t, "knotlog:threads:end") || index(t, "quipu:threads:end")) exit
  if (index(t, "knotlog:pin:start") || index(t, "quipu:pin:start")) { pin = 1; next }
  if (pin) { if (index(t, "knotlog:pin:end") || index(t, "quipu:pin:end")) pin = 0; next }
  if (t == ENVIRON["SM_HEAD"]) { act = 1; next }
  if (t ~ /^#/) { act = 0; next }
  if (act && t ~ /^[ \t]*[-*+] /) { sub(/^[ \t]*[-*+] /, "", t); emit("t", FNR, "", t) }
}
mode == "pending" {
  if ($1 == "P") { n++; id[n] = $2; kd[n] = $4; ln[n] = NR; t = $0; for (j = 0; j < 5; j++) sub(/^[^\t]*\t/, "", t); tx[n] = t }
  else if ($1 == "A") ok[$2] = 1
  else if ($1 == "R") no[$2] = 1
}
function cut(s, m,   r) {
  if (length(s) <= m) return s
  r = substr(s, 1, m)
  if (ord[substr(s, m + 1, 1)] >= 128 && ord[substr(s, m + 1, 1)] < 192) {
    while (length(r) > 0 && ord[substr(r, length(r), 1)] < 192) r = substr(r, 1, length(r) - 1)
    r = substr(r, 1, length(r) - 1)
  }
  return r
}
# Folded text -> token set tok[row, k], count nt[row]. Drops a leading
# [bracket] prefix, a leading distill tag, words under 3 bytes and numbers,
# then keeps the first STEM characters of each word.
function tokenize(r, s,   i, c, w, p, u, seen, nn) {
  while (s ~ /^[[][^]]*[]]/) { sub(/^[[][^]]*[]]/, "", s); sub(/^ +/, "", s) }
  p = index(s, ":")
  if (p > 1 && (substr(s, 1, p - 1) in tagset)) s = substr(s, p + 1)
  s = s " "
  w = ""; nn = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if ((c >= "a" && c <= "z") || (c >= "0" && c <= "9") || ord[c] >= 128) { w = w c; continue }
    if (length(w) >= 3 && w !~ /^[0-9]+$/) {
      u = stem(w)
      if (!((r, u) in seen)) { seen[r, u] = 1; tok[r, ++nn] = u }
    }
    w = ""
  }
  nt[r] = nn
}
function stem(w,   i, k, o, c) {
  if (STEM <= 0) return w
  k = 0; o = ""
  for (i = 1; i <= length(w); i++) {
    c = substr(w, i, 1)
    if (ord[c] < 128 || ord[c] >= 192) { if (++k > STEM) break }
    o = o c
  }
  return o
}
mode == "score" && FILENAME == ARGV[1] { if ($0 != "") { split($0, lf, TAB); if (lf[1] == "facts") led[lf[2]] = 1 }; next }
mode == "score" {
  split($0, f, TAB)
  nr++
  kind[nr] = f[1]; pth[nr] = f[2]; lno[nr] = f[3]; src[nr] = f[4]; ref[nr] = f[5]; txt[nr] = f[6]
  fz = f[7]; gsub(/  +/, " ", fz); sub(/^ /, "", fz); sub(/ $/, "", fz)
  org[nr] = (f[1] == "p" || f[4] != "" || (f[1] == "f" && (fz in led))) ? "knotlog" : "user"
  tokenize(nr, fz)
}
END {
  if (mode == "pending") {
    for (i = 1; i <= n; i++) {
      if (!(kd[i] == "lesson" || kd[i] == "fix" || kd[i] == "skill") || !(id[i] in ok) || (id[i] in no)) continue
      emit("p", ln[i], "pending #" id[i], tx[i])
    }
  }
  if (mode != "score") exit
  min = ENVIRON["SM_MIN"] + 0
  for (i = 1; i <= nr; i++) {
    nc = 0
    for (a = 1; a <= nt[i]; a++) {
      t = tok[i, a]
      for (b = 1; b <= pn[t]; b++) { j = post[t, b]; if (!(j in cnt)) { cnt[j] = 0; touched[++nc] = j }; cnt[j]++ }
    }
    for (b = 1; b <= nc; b++) {
      j = touched[b]; x = cnt[j]
      sc = x / (nt[i] + nt[j] - x)
      # A proposal approved into the facts file is the same item as the fact that cites it.
      dupe = (ref[j] != "" && src[i] == ref[j]) || (ref[i] != "" && src[j] == ref[i])
      if (sc >= min && !dupe)
        printf "%.6f\t%.2f\t%s:%s\t%s:%s\t%s/%s\t%s\t%s\n", sc, sc, pth[j], lno[j], pth[i], lno[i], org[j], org[i], cut(txt[j], 60), cut(txt[i], 60)
    }
    delete cnt; delete touched
    for (a = 1; a <= nt[i]; a++) { t = tok[i, a]; post[t, ++pn[t]] = i }
  }
}
