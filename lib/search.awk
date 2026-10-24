# quipu — search.awk: lexical BM25 ranker over .quipu/index.tsv (Katman 3).
#
# FAZ 12: streamed two-pass engine. The pre-FAZ12 design read index.tsv ONCE
# into four parallel in-memory arrays (path[]/title[]/tags[]/folded[], one
# slot per document) and ran both BM25 passes over those arrays. Memory then
# grew linearly with the DOCUMENT count. BM25 genuinely needs two passes (one
# for df/avgdl, one for scoring), but neither pass needs the array — each can
# read index.tsv straight off disk if the two passes are split into two awk
# invocations that hand a small summary between them. This file now offers
# two modes instead of one:
#
#   mode=bm25count  args: <index.tsv>
#     vars: terms=<folded query>  tagf=/statf=<FAZ 10 filters>
#           idxfile=<same index.tsv path, for the fallback re-read below>
#           dfout=<path to write the small df/avgdl/n/fallback summary to>
#     Streams index.tsv once, applying the SAME --tag/--status elimination
#     filter search always had, and accumulates only: n (surviving document
#     count), sumlen (-> avgdl), and df[term] for each QUERY term (one array
#     slot per query term, not per document). No document's path/title/tags/
#     folded text is ever kept past the row it came from. If no query term
#     word-matched any surviving document (total == 0), the END block
#     re-reads idxfile a SECOND time via getline (this is the "geri düşüş",
#     matching the pre-FAZ12 substring fallback) to compute a substring-based
#     df instead. Writes dfout as TAB-separated summary rows:
#       df TAB <term> TAB <count>      (one per non-empty query term)
#       avgdl TAB <value>
#       n TAB <value>
#       fallback TAB 0-or-1
#
#   Block rows (2026-09-30): an optional extra argv file, vars blocksfile=<its
#   path> (and blocks=1 for bm25score), holds .quipu/blocks.tsv -- the parts of
#   over-cap notes that index.tsv's 2000-character search field cuts off. Same
#   column positions as index.tsv for path/title/tags/folded/status; $4 is the
#   heading path. bm25count reads it only to decide the substring fallback
#   (n, avgdl, df stay note-only, so notes under the cap score exactly as
#   before). bm25score scores each block like a note (same df/n/avgdl, its own
#   length) and appends an internal 0/1 column; the caller sorts, keeps the
#   best row per path and drops that column.
#
#   mode=bm25score  args: <dfout from bm25count> <index.tsv> [<blocks.tsv>]
#     vars: terms=<same folded query>  tagf=/statf=<same filters>
#           brief=<0/1>  snip=<byte budget, default 120>
#     Reads the FIRST argv file (bm25count's dfout) with the FNR==NR idiom
#     already used elsewhere in this repo (lib/index.awk's mode=plan
#     oldfile/allfile join, mode=assemble's joinfile join) to fill df[]/
#     avgdl/n/fallback, then streams the SECOND argv file (index.tsv again)
#     applying the SAME filter and, for each surviving row, computing and
#     printing its score directly from that row's own fields — no array of
#     other documents is ever consulted. Memory here is O(query terms) for
#     df[]/qw[], not O(document count).
#
# The caller (_q_cmd_search in quipu) runs bm25count then bm25score as two
# separate awk processes joined by dfout, a small ordinary file (never
# `awk -v`, per PLAN 4.16 — dfout, like idxfile, is a controlled path this
# program itself wrote, not raw user data). Bill: index.tsv is now read from
# disk 2 times (bm25count's main pass + bm25score's pass) or 3 (bm25count's
# fallback getline adds one more) instead of the old design's 1-read-into-
# memory. Accepted trade (docs/FAZ12-SPEC.md K-2): memory now scales with
# QUERY size, not document count, at the cost of one or two extra sequential
# disk reads per search.
#
# Both modes are invoked the same way the old single mode=bm25 was:
#   awk -v mode=bm25count ... -f lib/search.awk index.tsv
#   awk -v mode=bm25score ... -f lib/search.awk dfout index.tsv
# `terms` is the query, already folded to ASCII and lowercased by the caller
# (same fold profile + tr 'A-Z' 'a-z' as the index). mode=bm25score additionally
# takes -v brief=1 -v snip=120 to request the snippet column (J-5).
# -v tagf=<folded-tag> / -v statf=<folded-status> (FAZ 10 Z-3/Z-4) require an
# exact match against a document's RAW tag list (column 3, comma-split) / RAW
# status (column 6); a document that fails either filter is not emitted at
# all — an elimination, not a score boost like the existing tag boost below. A row whose validity
# column (index.tsv $8, blocks.tsv $7) is "rejected" is dropped the same way
# unless -v showall=1 (search --all).
# Both `tagf` and `statf` are folded by the caller (the only category PLAN
# 4.16 allows through `-v`), so this is an exact match of a folded query
# value against an UNFOLDED column — a raw tag such as `#İstanbul` will not
# match `-v tagf=istanbul`. Documented limit, not fixed here (README). The
# SAME filter runs in bm25count and bm25score (K-4) so the surviving
# population n/avgdl/df describe is exactly the population that gets scored.
#
# Output (mode=bm25score only; mode=bm25count writes no document rows, only
# dfout) : skor<TAB>yol<TAB>başlık<TAB>etiketler   (skor %.3f). Documents that
#          match no query term are suppressed.
#          With brief=1 a 5th TAB-separated column is appended: the leading
#          `snip` units (default 120) of the folded field, trimmed back to
#          the last word boundary inside that window so no word is split.
#          A field no longer than `snip` is emitted whole. The snippet
#          carries no marker and no ellipsis, and the cut uses only
#          substr()/length()/index() — no regex, no gsub — so the PLAN 4.11
#          no-literal-backslash contract still holds.
#
#          `snip` unit caveat: length()/substr() count CHARACTERS in gawk but
#          BYTES in mawk/BWK awk, so `snip` is a byte budget only where the
#          folded field is ASCII — which is what the tr fold profile produces.
#          Under fold=default the field keeps its multi-byte characters, so a
#          window with no space in it can be cut mid-character on byte-based
#          awks. Accepted limitation (FAZ 7 L-5), not a correctness bug: the
#          snippet is a display hint, never a key or a matching input.
#
#          Row safety (V1-DUZELTME): every printed field (title, tags, and the
#          brief snippet) is passed through scrub() first, which turns any
#          embedded TAB/CR/LF into a space. title/tags are RAW columns (never
#          folded/squeezed) and the snippet is a substr() of the folded field,
#          so nothing upstream guarantees either is single-line — a heading
#          with a literal tab, CRLF content that leaked a stray CR into a
#          field (see lib/index.awk collect_tags()), or a byte-based
#          substr()/length() edge case on a non-gawk awk can otherwise turn
#          one logical row into more than one physical output line or shift
#          it off the 4/5-column contract. scrub() is the single choke point
#          that makes the row shape a guarantee instead of an assumption,
#          regardless of that mechanism (CI run 32576726590, see V1-DUZELTME
#          notes retained in git history for this file).
#
# Contract (PLAN 4.11): no literal backslash; no regex beyond split()/index()
# (both take plain string separators). Word matching pads each field with
# spaces and searches " terim " via index(), so "ac" never matches "acik".
# Title/tag boosts compare the folded term against the RAW title/tag fields,
# so they fire only when those fields already equal the folded form (e.g.
# plain-ASCII words). Documented limitation of FAZ 1 lexical search.
#
# Fallback: if no query term word-matches ANY document (e.g. the user typed a
# prefix such as "istan"), matching degrades to a substring scan via
# index(katlanmış, terim); tf becomes the substring occurrence count and the
# title/tag boosts become substring checks too. This keeps prefix queries
# usable at the cost of precision (PLAN Dilim 3). FAZ 12 moves the DETECTION
# of this case (df recompute) into bm25count's END block (a second getline
# pass over idxfile) and the CONSEQUENCE of it (tf/boost via substring
# instead of word match) into bm25score's per-row block, driven by the single
# `fallback` flag handed across in dfout.

BEGIN {
  TAB = sprintf("%c", 9)
  LF  = sprintf("%c", 10)
  CR  = sprintf("%c", 13)
  FS  = TAB
  OFS = TAB
  US = sprintf("%c", 31)
  k1 = 1.2
  b  = 0.75
  n = 0
  qc = split(terms, qw, " ")
  fallback = 0
  avgdl = 1
  if (snip + 0 <= 0) snip = 120
}

# ---- mode: bm25count ---------------------------------------------------------

mode == "bm25count" && blocksfile != "" && FILENAME == blocksfile {
  # Block rows (.quipu/blocks.tsv) take no part in n/avgdl/df -- those describe
  # the NOTE population, so a note under the cap scores exactly as before. They
  # only answer one question: did any query term word-match anywhere? Without
  # this a word that lives only in a long note's tail would look like "no
  # match at all" and wrongly switch the whole search to the substring
  # fallback. Once something matched, the rest of the file is skipped.
  if (total > 0) next
  if (!filter_ok()) next
  pad = " " $5 " "
  for (t = 1; t <= qc; t++) {
    term = qw[t]
    if (term == "") continue
    if (count_occ_bounded(pad, term) > 0) { total++; break }
  }
  next
}

mode == "bm25count" {
  # FAZ 10 Z-3/Z-4 elimination filter, applied before the row can affect
  # n/sumlen/df at all — same filter bm25score reapplies below (K-4).
  if (!filter_ok()) next
  n++
  sumlen += split($5, w, " ")
  pad = " " $5 " "
  for (t = 1; t <= qc; t++) {
    term = qw[t]
    if (term == "") continue
    if (count_occ_bounded(pad, term) > 0) {
      df[term]++
      total++
    }
  }
}

END {
  if (mode == "bm25count") {
    avgdl = (n > 0 && sumlen > 0) ? (sumlen / n) : 1

    # Substring fallback (E-4/K-1): no term word-matched ANY surviving
    # document, so re-read idxfile from disk a second time and recompute df
    # by substring scan instead. index()/substr() only, no regex.
    if (n > 0 && qc > 0 && total == 0) {
      fallback = 1
      for (t = 1; t <= qc; t++) df[qw[t]] = 0
      while ((getline fline < idxfile) > 0) {
        nfc = split(fline, fcol, TAB)
        if (nfc < 7) continue
        if (!filter_ok_cols(fcol[3], fcol[6], fcol[8])) continue
        for (t = 1; t <= qc; t++) {
          term = qw[t]
          if (term == "") continue
          if (index(fcol[5], term) > 0) df[term]++
        }
      }
      close(idxfile)
    }

    for (t = 1; t <= qc; t++) {
      term = qw[t]
      if (term == "") continue
      print "df", term, df[term] > dfout
    }
    print "avgdl", avgdl > dfout
    print "n", n > dfout
    print "fallback", fallback > dfout
    close(dfout)
  }
}

# ---- mode: bm25score ----------------------------------------------------------

# First argv file: bm25count's dfout summary. Same FNR==NR idiom mode=plan
# uses for oldfile/allfile and mode=assemble uses for joinfile (lib/index.awk)
# — the first file's rows all `next` here, so the block below only ever sees
# rows from the SECOND argv file (index.tsv).
mode == "bm25score" && FNR == NR {
  if ($1 == "df") df[$2] = $3 + 0
  else if ($1 == "avgdl") avgdl = $2 + 0
  else if ($1 == "n") n = $2 + 0
  else if ($1 == "fallback") fallback = $2 + 0
  next
}

mode == "bm25score" {
  # Block rows share index.tsv's column positions for path/title/tags/folded/
  # status ($1,$2,$3,$5,$6); only $4 differs (heading path instead of mtime).
  isblk = (blocksfile != "" && FILENAME == blocksfile) ? 1 : 0
  if (!filter_ok()) next
  dl = split($5, w, " ")
  pad = " " $5 " "
  ptitle = " " $2 " "
  ntag = split($3, ta, ",")
  # Aliases (see lib/index.awk): a note row whose search field starts with
  # "alias words SP US SP" carries them before the US; aliases weigh like the
  # title. Rows without a US (no aliases, block rows) are untouched.
  ap = isblk ? 0 : index($5, US)
  areg = (ap > 0) ? " " substr($5, 1, ap - 1) " " : ""
  score = 0
  matched = 0
  fpos = 0
  for (t = 1; t <= qc; t++) {
    term = qw[t]
    if (term == "") continue
    if (fallback) {
      tf = count_occ($5, term)
    } else {
      tf = count_occ_bounded(pad, term)
    }
    if (tf == 0) continue
    matched = 1
    if (isblk) {
      # Earliest match inside the block, for the --brief snippet window.
      fp = fallback ? index($5, term) : index(pad, " " term)
      if (fp > 0 && (fpos == 0 || fp < fpos)) fpos = fp
    }
    idf = log((n - df[term] + 0.5) / (df[term] + 0.5))
    contrib = idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (dl / avgdl)))
    if (fallback) {
      if (index($2, term) > 0) contrib *= 2
      else if (ap > 0 && index(areg, term) > 0) contrib *= 2
      if (index($3, term) > 0) contrib *= 1.5
    } else {
      if (index(ptitle, " " term " ") > 0) contrib *= 2
      else if (ap > 0 && index(areg, " " term " ") > 0) contrib *= 2
      for (j = 1; j <= ntag; j++) {
        if (ta[j] == term) { contrib *= 1.5; break }
      }
    }
    score += contrib
  }
  if (matched) {
    if (brief + 0) {
      # A block hit shows where in the note it sits, "[H1 > H2] text", and
      # its snippet starts just before the first match: a block is up to
      # 2000 characters and the match is usually not in its first 120.
      if (isblk) {
        sn = snippet_at($5, snip, fpos)
        if ($4 != "") sn = "[" $4 "] " sn
      } else if (ap > 0) sn = snippet(substr($5, ap + 2), snip)
      else sn = snippet($5, snip)
      printf "%.3f%c%s%c%s%c%s%c%s", score, 9, $1, 9, scrub($2), 9, scrub($3), 9, scrub(sn)
    } else {
      printf "%.3f%c%s%c%s%c%s", score, 9, $1, 9, scrub($2), 9, scrub($3)
    }
    # blocks=1: a trailing internal column (0 note row, 1 block row) so the
    # caller's sort puts the note row first on a score tie and its dedupe can
    # keep one row per path. The caller strips it again; it never reaches the
    # user.
    if (blocks + 0) printf "%c%d", 9, isblk
    printf "%c", 10
  }
}

# ---- shared helpers -----------------------------------------------------------

# --tag/--status elimination filter against the CURRENT record's own fields
# ($3 = raw tag list, $6 = raw status). Used by both mode=bm25count's main
# block and mode=bm25score's row block, so the two passes can never drift
# apart on which documents survive (K-4).
function filter_ok() {
  return filter_ok_cols($3, $6, (blocksfile != "" && FILENAME == blocksfile) ? $7 : $8)
}

# Same filter, explicit-argument form: bm25count's END-block fallback re-read
# builds its own row via getline + split() into fcol[], not $0, so it cannot
# call filter_ok() directly (that reads $3/$6 of the awk main loop's current
# record, which is stale inside END). This is the ONE filter definition both
# call sites share.
function filter_ok_cols(tag3, stat6, valid,   tagok, ntg, tgi, tg) {
  if (tagf != "") {
    tagok = 0
    ntg = split(tag3, tg, ",")
    for (tgi = 1; tgi <= ntg; tgi++) { if (tg[tgi] == tagf) { tagok = 1; break } }
    if (!tagok) return 0
  }
  if (statf != "" && stat6 != statf) return 0
  if (valid == "rejected" && !showall) return 0
  return 1
}

function count_occ(s, needle,   pos, cnt, len, rest) {
  cnt = 0
  len = length(needle)
  rest = s
  pos = index(rest, needle)
  while (pos > 0) {
    cnt++
    rest = substr(rest, pos + len)
    pos = index(rest, needle)
  }
  return cnt
}

# FAZ 17 (AG-2): trailing punctuation set a folded-field token can carry —
# IDENTICAL to lib/index.awk's strip_punct() character set, kept as a
# separate copy here (not a shared file — this repo has no awk "include"
# mechanism, PLAN 4.11) so search-side boundary matching recognizes exactly
# the punctuation the index side never strips.
function is_trail_punct(c) {
  return (c == "." || c == "," || c == ";" || c == ":" || c == "!" || c == "?" || c == ")" || c == "'" || c == sprintf("%c", 34))
}

# FAZ 17 (AG-2): word-boundary match count for `term` inside `padded` (a
# " "-wrapped folded field, same shape count_occ(pad, " " term " ") used
# before this function existed), TOLERANT of trailing punctuation glued to
# the matched token — the "noktaya bitişik terim" fix (docs/PLAN.md §7,
# docs/FAZ17-SPEC.md).
#
# Left boundary is still a literal space (index(rest, " " term)) — no change
# there, so "term" still never matches inside "terminal" (the character right
# after the candidate match must be a space, or a run of is_trail_punct()
# characters followed by a space or end-of-string; "terminal"'s next
# character is "i", neither, so it falls through to the no-match branch).
#
# Right boundary walks forward past ANY run of trailing punctuation
# (mirrors lib/index.awk's strip_punct() loop, character-by-character, no
# regex) and only counts a match if that walk lands on a space or the end of
# `padded`. A glued case like "term.ly" is correctly rejected: after "term"
# the "." is consumed as punctuation, but the next character "l" is neither
# punctuation nor a boundary, so the walk aborts and this position is not a
# match — same discipline as the plain word-boundary case, extended one
# character-class further.
#
# Byte-identical with the old count_occ(pad, " " term " ") algorithm on the
# clean branch (c == " "): same left-anchor search, same rest = substr(...)
# advance-past-the-boundary-space step, so for text with no punctuation-glued
# occurrences of `term` this returns EXACTLY what the old call returned,
# including its known adjacent-duplicate undercount quirk (e.g. "term term
# term" -> 2, not 3 — the shared trailing/leading space between two adjacent
# hits gets consumed once; see docs/FAZ17-SPEC.md AF-4). That quirk carries
# over unchanged into the new punctuation branch too (an immediately-
# following occurrence right after a punctuation-glued hit can lose its own
# leading space the same way) — accepted as continuing a pre-existing
# behavior, not a new one, and irrelevant to the bug this function fixes
# (distinct notes, not adjacent tokens in one note).
function count_occ_bounded(padded, term,   pos, cnt, rest, plen, idx2, c, k, cc, tail) {
  cnt = 0
  plen = length(term)
  rest = padded
  while (1) {
    pos = index(rest, " " term)
    if (pos == 0) break
    idx2 = pos + 1 + plen
    c = substr(rest, idx2, 1)
    if (c == " ") {
      cnt++
      rest = substr(rest, idx2 + 1)
      continue
    }
    k = idx2
    while (1) {
      cc = substr(rest, k, 1)
      if (is_trail_punct(cc)) { k++; continue }
      break
    }
    if (k > idx2) {
      tail = substr(rest, k, 1)
      if (tail == " " || tail == "") {
        cnt++
        rest = (tail == "") ? "" : substr(rest, k + 1)
        continue
      }
    }
    # No boundary-valid match at this position (e.g. "term.ly", or "term"
    # glued straight to another word) -- advance past just the leading space
    # so the scan keeps looking for a LATER genuine occurrence instead of
    # looping forever or skipping past one.
    rest = substr(rest, pos + 1)
  }
  return cnt
}

# Output-row safety net: a --brief (and plain) row is a TAB-joined, single-line
# contract (path/title/tags/snippet). title/tags come from the RAW index.tsv
# columns and are never folded, so nothing upstream guarantees they are
# TAB/CR/LF-free (a heading with a literal tab, a stray CR from CRLF content,
# or an implementation quirk in a non-gawk substr()/length() feeding snippet()
# a byte that was never in the source text). scrub() is the single choke point
# before printf: any TAB/CR/LF in a printed field becomes a space, so the row
# can never gain a TAB-column or split across physical lines regardless of
# what produced the offending byte. substr()/length() only (PLAN 4.11).
function scrub(s,   i, c, out) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == TAB || c == LF || c == CR) c = " "
    out = out c
  }
  return out
}

# snippet() of s starting a few words before position `pos` (1-based, the
# first match): back up about 20 units, then forward to the next space so the
# window starts on a word. Near the start of s it is plain snippet().
function snippet_at(s, max, pos,   st) {
  st = pos - 20
  if (pos <= 0 || st < 2) return snippet(s, max)
  while (st < pos && substr(s, st, 1) != " ") st++
  return snippet(substr(s, st + 1), max)
}

# First `max` bytes of s, trimmed back to the last space inside the window so
# the snippet never ends mid-word. substr/length only (PLAN 4.11).
function snippet(s, max,   cut, i) {
  if (length(s) <= max) return s
  cut = substr(s, 1, max)
  for (i = length(cut); i >= 1; i--) {
    if (substr(cut, i, 1) == " ") return substr(cut, 1, i - 1)
  }
  return cut
}
