# longmemeval.awk -- LongMemEval-S retrieval bench helpers (test code, not shipped).
# Load after lib/jsonfield.awk (uses jf_uni/jf_ulen for \uXXXX escapes).
#
#   mode=split    stdin/argv: longmemeval_s_cleaned.json
#                 vars: out=<dir> max=<questions, 0 = all>
#     Streams the JSON (any whitespace layout) and writes, per question i,
#     out/qNNNN/{meta.tsv,gold.txt,map.tsv} and out/qNNNN/vault/ (a vault with
#     .knotlog/config and one note per unique haystack session).
#     meta.tsv : question_id TAB abs(0/1) TAB question (TAB/CR/LF -> space)
#     gold.txt : answer session ids, one per line, unique
#     map.tsv  : note path (vault-relative, as `search --paths` prints it) TAB session id
#     Note text follows agentmemory eval/runner/load.ts + input.ts:
#       "[Source session date: D]" LF, then the turns "[role] content" joined
#       by a blank line. A session id seen twice with the same turns is one
#       note; each extra date is prepended as "[Additional source session
#       date: D]" LF. Same id, different turns -> error (exit 1).
#     Note names are s<NNN>.md in a per-question shuffled order (Park-Miller
#     LCG, same on every awk), so neither the name nor a score-tie order
#     follows the haystack order or tells gold from distractor.
#
#   mode=score    argv: search --paths output for one question
#                 vars: mapf=<map.tsv> goldf=<gold.txt> qid=<id> abs=<0/1>
#     Prints: question_id TAB abs TAB hits TAB gold TAB any TAB all
#     hits = distinct gold sessions among the returned paths. A path missing
#     from map.tsv is an error (exit 2): a silent miss would read as recall 0.
#
#   mode=summary  argv: score rows; vars: secs=<wall seconds>
#     recall_any / recall_all over the non-abstention rows only.

BEGIN {
  TAB = sprintf("%c", 9); LF = sprintf("%c", 10); CR = sprintf("%c", 13)
  BS = sprintf("%c", 92); DQ = sprintf("%c", 34); OFS = TAB
  if (mode == "split") {
    if (out == "" || index(out, "'")) { print "longmemeval: bad out dir" > "/dev/stderr"; exit 1 }
    RS = DQ
    instr = 0; buf = ""; depth = 0; nq = 0
  } else if (mode == "score") {
    FS = TAB
    while ((getline l < mapf) > 0) { split(l, f, TAB); sid[f[1]] = f[2] }
    close(mapf)
    ng = 0
    while ((getline l < goldf) > 0) if (l != "" && !(l in gold)) { gold[l] = 1; ng++ }
    close(goldf)
  } else if (mode == "summary") {
    FS = TAB
  } else { print "longmemeval: unknown mode" > "/dev/stderr"; exit 1 }
}

# ---- split -------------------------------------------------------------------

mode == "split" && instr {
  # The record ended at a quote; an odd run of backslashes before it means the
  # quote was escaped and the string goes on in the next record.
  i = length($0); nb = 0
  while (i > 0 && substr($0, i, 1) == BS) { nb++; i-- }
  if (nb % 2) { buf = buf $0 DQ; next }
  on_string(buf $0); buf = ""; instr = 0
  next
}

mode == "split" {
  s = $0
  gsub(/[ \t\r\n]+/, "", s)
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "{" || c == "[") {
      depth++; kind[depth] = (c == "{") ? "o" : "a"; wantkey[depth] = (c == "{"); key[depth] = ""
      if (c == "[" && depth == 4 && key[2] == "haystack_sessions") { ns++; stext[ns] = "" }
      if (c == "{" && depth == 5) { role = ""; content = "" }
      if (c == "{" && depth == 2) q_reset()
    } else if (c == "}" || c == "]") {
      if (c == "}" && depth == 5 && key[2] == "haystack_sessions")
        stext[ns] = stext[ns] ((stext[ns] == "") ? "" : LF LF) "[" role "] " content
      if (c == "}" && depth == 2) { q_emit(); if (max + 0 > 0 && nq >= max + 0) exit }
      depth--
    } else if (c == ",") {
      if (kind[depth] == "o") wantkey[depth] = 1
    } else if (c == ":") wantkey[depth] = 0
  }
  instr = 1
}

function on_string(raw) {
  if (kind[depth] == "o" && wantkey[depth]) { key[depth] = raw; return }
  if (depth == 2) {
    if (key[2] == "question_id") qid_ = dec(raw)
    else if (key[2] == "question") qtext = dec(raw)
  } else if (depth == 3) {
    if (key[2] == "haystack_session_ids") hid[++nh] = dec(raw)
    else if (key[2] == "haystack_dates") hdate[++nd] = dec(raw)
    else if (key[2] == "answer_session_ids") ans[++na] = dec(raw)
  } else if (depth == 5 && key[2] == "haystack_sessions") {
    if (key[5] == "role") role = dec(raw)
    else if (key[5] == "content") content = dec(raw)
  }
}

# JSON string body -> text. Fast path when there is no escape at all.
function dec(s,   o, p, c) {
  if (index(s, BS) == 0) return s
  o = ""
  while ((p = index(s, BS)) > 0) {
    o = o substr(s, 1, p - 1)
    c = substr(s, p + 1, 1)
    if (c == "u") { o = o jf_uni(s, p + 1); s = substr(s, p + 2 + jf_ulen); continue }
    if (c == "n") o = o LF
    else if (c == "t") o = o TAB
    else if (c == "r") o = o CR
    else if (c != "b" && c != "f") o = o c
    s = substr(s, p + 2)
  }
  return o s
}

function q_reset() {
  qid_ = ""; qtext = ""; nh = 0; nd = 0; na = 0; ns = 0
  delete hid; delete hdate; delete ans; delete stext
}

function q_emit(   d, v, i, j, k, t, u, nu, x, name, txt, q, g) {
  nq++
  if (nh != ns || nd != ns) {
    printf "longmemeval: %s: %d ids, %d dates, %d sessions\n", qid_, nh, nd, ns > "/dev/stderr"; exit 1
  }
  d = out "/q" sprintf("%04d", nq); v = d "/vault"
  if (system("mkdir -p '" v "/.knotlog'") != 0) exit 1
  print "fold=default" > (v "/.knotlog/config"); print "lang=en" > (v "/.knotlog/config")
  close(v "/.knotlog/config")
  # Unique sessions, first occurrence order; duplicates add a date line.
  nu = 0; delete pos; delete body; delete head; delete uid
  for (i = 1; i <= ns; i++) {
    if (hid[i] in pos) {
      u = pos[hid[i]]
      if (body[u] != stext[i]) { printf "longmemeval: %s: session %s repeats with other turns\n", qid_, hid[i] > "/dev/stderr"; exit 1 }
      head[u] = "[Additional source session date: " hdate[i] "]" LF head[u]
    } else {
      pos[hid[i]] = ++nu; uid[nu] = hid[i]; body[nu] = stext[i]
      head[nu] = "[Source session date: " hdate[i] "]" LF
    }
  }
  # Shuffle 1..nu (Fisher-Yates, Park-Miller LCG seeded by question number).
  delete perm
  for (i = 1; i <= nu; i++) perm[i] = i
  x = nq
  for (i = nu; i > 1; i--) {
    x = (x * 16807) % 2147483647
    j = 1 + x % i; t = perm[i]; perm[i] = perm[j]; perm[j] = t
  }
  for (i = 1; i <= nu; i++) {
    name = sprintf("s%03d.md", perm[i])
    printf "%s%s\n", head[i], body[i] > (v "/" name); close(v "/" name)
    print name TAB uid[i] > (d "/map.tsv")
  }
  close(d "/map.tsv")
  printf "" > (d "/gold.txt")
  delete g
  for (k = 1; k <= na; k++) if (!(ans[k] in g)) { g[ans[k]] = 1; print ans[k] > (d "/gold.txt") }
  close(d "/gold.txt")
  q = qtext; gsub(/[\t\r\n]/, " ", q)
  print qid_ TAB (substr(qid_, length(qid_) - 3) == "_abs" ? 1 : 0) TAB q > (d "/meta.tsv")
  close(d "/meta.tsv")
}

# ---- score -------------------------------------------------------------------

mode == "score" && $0 != "" {
  if (!($0 in sid)) { printf "longmemeval: %s: path not in map: %s\n", qid, $0 > "/dev/stderr"; bad = 1; exit 2 }
  s = sid[$0]
  if ((s in gold) && !(s in seen)) { seen[s] = 1; hits++ }
}

# ---- summary -----------------------------------------------------------------

mode == "summary" && substr($0, 1, 1) != "#" && NF == 6 {
  total++
  if ($2 == 1) { nabs++; next }
  scored++; sany += $5; sall += $6
}

END {
  if (mode == "score" && !bad)
    print qid, abs, hits + 0, ng, (hits > 0) ? 1 : 0, (hits == ng) ? 1 : 0
  if (mode == "summary") {
    d = (scored > 0) ? scored : 1
    printf "# questions\t%d\tabstention (excluded)\t%d\tscored\t%d\n", total, nabs, scored
    printf "# recall_any@5\t%d/%d\t%.1f%%\n", sany, scored, 100 * sany / d
    printf "# recall_all@5\t%d/%d\t%.1f%%\n", sall, scored, 100 * sall / d
    printf "# seconds\t%d\n", secs
  }
}
