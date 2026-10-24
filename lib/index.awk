# quipu — index builder helpers.
#
# Contract (PLAN 4.11): this file contains NO literal backslash. Every control
# character comes from its code point, so no quoting layer can corrupt it.
# No regex is used where a plain index()/substr() scan will do.
#
# Modes (-v mode=...):
#   plan   args: <old-index> <current-list> <all-list>
#          vars: oldfile=<old-index path>  allfile=<all-list path>
#          old-index rows:   path TAB title TAB tags TAB mtime TAB folded
#          current-list rows: path TAB mtime
#          all-list rows:     path
#          emits:
#            "reuse" TAB <whole old row>   (in current-list, mtime unchanged)
#            "stale" TAB path TAB mtime    (in current-list, changed / new)
#            "carry" TAB <whole old row>   (unchanged, path still exists)
#            "drop"  TAB path              (old row whose path is gone)
#   meta   args: <file.md>        emits: title TAB tags TAB status TAB type
#          (FAZ 10 Z-1: status/type come only from frontmatter `status:`/
#          `type:` lines; absent -> empty field. substr()-only, no regex.)
#   links  args: <file.md>        emits: kaynak TAB hedef, one row per
#          [[hedef]] / [[hedef|görünen]] / [[hedef#bölüm]] occurrence found
#          in the file's BODY (frontmatter is skipped — same fm boundary as
#          meta). kaynak is FILENAME as given on argv (the caller passes the
#          vault-relative path, same convention as mode=meta). Duplicates
#          are NOT deduped — count is meaningful (FAZ 10 Z-5). index()/
#          substr() only, no regex.
#   resolve (FAZ 13 N-1/N-2) args: <index.tsv> <links.tsv>
#          Resolves each links.tsv wikilink target to a vault path using
#          index.tsv's own path/title columns — NO second .md scan (Z-5's
#          ban is about re-reading .md files, not re-reading index.tsv).
#          FNR==NR over argv[1] (index.tsv) builds three tables: exists[yol],
#          bytitle[başlık] (";yol1;yol2;…;", empty titles skipped),
#          bybase[taban] (same shape, taban = the path's last "/"-segment
#          with a trailing ".md" stripped). The second pass (argv[2],
#          links.tsv) resolves each kaynak/hedef row through a fixed,
#          first-match-wins priority — tam yol -> başlık -> dosya adı ->
#          broken — and prints kaynak TAB hedef TAB durum TAB bilgi, durum
#          in {ok, ambiguous, broken}. A stage with 2+ candidates reports
#          ambiguous and does NOT fall through to the next stage (silently
#          picking the first candidate is exactly the mistake this phase
#          exists to avoid). index()/substr()/split() only, no regex.
#   flat   stdin: folded text     emits: one squeezed line, at most `max` chars
#   scan   (FAZ 11 F-3) no argv file; vars: pathsfile=<one vault-relative path
#          per line>  rawout=<raw line dump>  boundsout=<path TAB linecount>
#          metaout=<path TAB title TAB tags TAB status TAB type>
#          linksout=<kaynak TAB hedef, same shape as mode=links>
#          Reads pathsfile with getline (a FILE, never awk -v — PLAN 4.16),
#          then for each listed path reads it with getline < path and runs
#          the SAME frontmatter/title/tags/status/type extraction as mode=meta
#          and the SAME scan_links() as mode=links in one pass (no second
#          read of the file — FAZ 10 Z-5 generalized). Every raw line is
#          echoed to rawout via print, which normalizes trailing-newline
#          absence at EOF so two files back-to-back in the combined stream
#          never merge (F-3). boundsout records line counts so the SAME
#          combined stream, after `sed|tr`, can be re-split by mode=flatjoin
#          purely by counting — no text-based delimiter (F-4).
#   flatjoin (FAZ 11 F-4) no argv file; vars: boundsfile=<mode=scan's
#          boundsout>  metafile=<mode=scan's metaout>  max=2000 (default);
#          stdin: the COMBINED rawout stream after ONE `sed -f fold/PROFIL.sed
#          | tr 'A-Z' 'a-z'` pass (not per file — the whole point of F-4).
#          For each boundsfile row (path, linecount, in the SAME order
#          mode=scan wrote them), reads exactly linecount lines off stdin —
#          counting is exact because none of fold/*.sed's commands add/
#          remove/merge lines and `tr` does not either (verified: no `N`/`D`/
#          `P`/`G`/`H`/`x`/`n` in fold/*.sed, only `s///`), applies the SAME
#          squeeze-and-cap logic as mode=flat (gsub TAB/CR to space, collapse
#          runs of spaces, stop appending past `max` bytes but keep consuming
#          the segment's lines so the shared stream stays in sync for the
#          NEXT file), then joins with that path's metafile row and emits:
#            path TAB title TAB tags TAB folded TAB status TAB type
#          (6 columns — mtime is not here; mode=assemble supplies it from
#          plan.txt's own stale row, F-6). index()/substr() only, no regex.
#          Aliases (2026-09-30): mode=scan also reads frontmatter `aliases:`
#          (inline list, YAML block list, single value) and appends ONE extra
#          line to the file's rawout segment (a US control character, then the
#          alias words), counted in boundsout. That line goes through the same
#          fold pass as the note text; here it is taken back off the end of the
#          segment and written at the FRONT of the search field as
#          "alias words SP US SP note text" (alias part capped at 500
#          characters, whole field still capped at `max`). search.awk reads the
#          part before the US as the aliases. Notes without aliases get no
#          extra line and no US: their rows are byte-identical to before.
#          Optional blocksout=<file>: a note whose search field hit the `max`
#          cap ALSO gets block rows written there (path TAB title TAB tags
#          TAB heading path TAB folded block TAB status) covering its whole
#          text, so the part past the cap stays searchable (see build_blocks).
#   assemble (FAZ 11 F-6) args: <joinfile> <planfile>
#          vars: joinfile=<mode=flatjoin's output, same path as argv[1]>
#          keptout=<reuse/carry paths, one per line — feeds the SAME
#          links.tsv carry-forward join FAZ 10 Z-5 already does>
#          countsout=<"reused stale dropped" counts, space-separated>
#          Preloads joinfile (path -> title/tags/folded/status/type) via the
#          FNR==NR idiom mode=plan already uses for oldfile/allfile, THEN
#          reads planfile (mode=plan's own plan.txt, unmodified, "END"
#          sentinel and all) in its ORIGINAL row order and re-emits:
#            reuse/carry -> the stored old row, verbatim, unchanged
#            stale       -> path/mtime from plan.txt + the rest from joinfile
#            drop        -> nothing (counted, not printed)
#          Row order out equals plan.txt's row order in (F-6) — the SAME
#          order the pre-FAZ11 per-file shell loop produced, since that loop
#          also walked plan.txt top to bottom. index()/substr() only.

BEGIN {
  TAB = sprintf("%c", 9)
  CR  = sprintf("%c", 13)
  US  = sprintf("%c", 31)
  FS  = TAB
  OFS = TAB
  if (max + 0 == 0) max = 2000
  buf = ""
  title = ""
  tags = ""
  status = ""
  validity = ""
  typ = ""
  ntag = 0
  nold = 0
  fm = 0
  if (mode == "scan") {
    run_scan()
    exit
  }
  if (mode == "flatjoin") {
    run_flatjoin()
    exit
  }
}

# ---- mode: plan -------------------------------------------------------------

mode == "plan" && FILENAME == allfile {
  if ($1 != "") exists[$1] = 1
  next
}

mode == "plan" && FILENAME == oldfile {
  oldrow[$1] = $0
  oldmt[$1] = $4
  paths[++nold] = $1
  next
}

mode == "plan" {
  if ($1 == "") next
  seen[$1] = 1
  # The trailing "END" sentinel keeps the shell reader from losing empty
  # status/type columns: `read` strips trailing IFS (TAB) characters, so a
  # 7-column row ending in two empties came back as 5 columns and the next
  # run mistook it for the pre-FAZ10 schema (CI 32594576381, test 217). Kept
  # unconditionally in FAZ 11's batch design too (mode=assemble reads it the
  # same way this comment describes, just with awk field-splitting instead
  # of `read` — T-159).
  if (($1 in oldmt) && oldmt[$1] == $2) print "reuse", oldrow[$1], "END"
  else {
    print "stale", $1, $2, "END"
    # FAZ 11 F-2 stage 1 ("mode=plan, genişletilmiş"): stream the bare stale
    # path to stalepathsout AS IT IS DETECTED, so mode=scan's pathsfile
    # comes straight from this single pass over plan's inputs — no second
    # read of plan.txt to extract it (optional: "" when the caller is a
    # direct/legacy mode=plan invocation that never asked for it, e.g. T-159).
    if (stalepathsout != "") print $1 > stalepathsout
  }
  next
}

# ---- mode: assemble (FAZ 11 F-6) ---------------------------------------------

# Preload mode=flatjoin's output (path -> title/tags/folded/status/type),
# the SAME FNR==NR-over-a-named-argv-file idiom mode=plan uses for oldfile/
# allfile above.
mode == "assemble" && FILENAME == joinfile {
  jtitle[$1]  = $2
  jtags[$1]   = $3
  jfolded[$1] = $4
  jstatus[$1] = $5
  jtype[$1]   = $6
  jvalid[$1]  = $7
  next
}

# planfile: mode=plan's own plan.txt, read in its ORIGINAL row order (the
# second argv file) so index.tsv's row order matches plan.txt's (F-6). Every
# row carries the trailing "END" sentinel (T-159) — reuse/carry rows have 9
# fields (verb + the 7 old-row columns + END), stale rows have 4 (verb, path,
# mtime, END), drop rows have 3 (verb, path, END); the sentinel is always
# the LAST field, so lastf = NF - 1 unconditionally reconstructs the old row
# without ever treating "END" itself as data.
mode == "assemble" && FILENAME == planfile {
  if ($1 == "") next
  if ($1 == "reuse" || $1 == "carry") {
    lastf = NF - 1
    row = $2
    for (i = 3; i <= lastf; i++) row = row TAB $i
    print row
    if (keptout != "") print $2 > keptout
    rcount++
    next
  }
  if ($1 == "stale") {
    p = $2
    print p, jtitle[p], jtags[p], $3, jfolded[p], jstatus[p], jtype[p], jvalid[p]
    scount++
    next
  }
  if ($1 == "drop") {
    dcount++
    next
  }
  next
}

# ---- mode: meta -------------------------------------------------------------

mode == "meta" && FNR == 1 && chomp_($0) == "---" { fm = 1; next }

mode == "meta" && fm == 1 {
  fl = chomp_($0)
  if (fl == "---" || fl == "...") { fm = 2; next }
  if (substr(fl, 1, 6) == "title:") { if (title == "") title = trim_(substr(fl, 7)) }
  if (substr(fl, 1, 5) == "tags:")  { collect_tags(substr(fl, 6)) }
  if (substr(fl, 1, 7) == "status:") { if (status == "") status = trim_(substr(fl, 8)) }
  if (substr(fl, 1, 5) == "type:")   { if (typ == "") typ = trim_(substr(fl, 6)) }
  next
}

mode == "meta" {
  if (title == "" && substr($0, 1, 2) == "# ") title = trim_(substr($0, 3))
  collect_tags($0)
  next
}

# ---- mode: links --------------------------------------------------------------

mode == "links" && FNR == 1 && chomp_($0) == "---" { fm = 1; next }

mode == "links" && fm == 1 {
  fl = chomp_($0)
  if (fl == "---" || fl == "...") fm = 2
  next
}

mode == "links" {
  if (is_fence_($0)) { infence = !infence; next }
  if (infence) next
  scan_links(strip_code_($0))
  next
}

# ---- mode: resolve (FAZ 13 N-1/N-2) ------------------------------------------

mode == "resolve" && FNR == NR {
  if ($1 != "") exists[$1] = 1
  if ($2 != "") add_member(bytitle, $2, $1)
  bb = base_of($1)
  if (bb != "") add_member(bybase, bb, $1)
  next
}

mode == "resolve" {
  resolve_link($1, $2)
  next
}

# ---- mode: flat -------------------------------------------------------------

mode == "flat" {
  if (length(buf) >= max) next
  line = $0
  gsub(TAB, " ", line)
  gsub(CR, " ", line)
  gsub(/  */, " ", line)
  buf = buf " " line
  next
}

# ---- helpers ----------------------------------------------------------------

# One trailing CR dropped (CRLF note): only used to recognise frontmatter
# fence and key lines. LF lines come back unchanged; file content is not rewritten.
function chomp_(s) {
  if (substr(s, length(s), 1) == CR) return substr(s, 1, length(s) - 1)
  return s
}

function trim_(s) {
  sub(/^[ ]+/, "", s)
  sub(/[ ]+$/, "", s)
  gsub(TAB, " ", s)
  gsub(CR, "", s)
  return s
}

# Replace ',' '[' ']' with spaces; character loop, no regex (PLAN 4.11).
function squish_brackets(s,   i, c, out) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "," || c == "[" || c == "]") c = " "
    out = out c
  }
  return out
}

# Collect "#word" tags and bare comma/space separated frontmatter values.
#
# CRLF note (V1-DUZELTME): trim_() strips CR for titles, but a tag scanned
# here never went through trim_ — squish_brackets()/strip_punct() only touch
# ',' '[' ']' and end-of-word punctuation, never CR. A CRLF-authored note
# hands $0 to collect_tags with a trailing CR still attached (only LF is a
# record separator to awk), and if that CR lands on the LAST token of the
# line (e.g. a trailing "#tag"), it rides along past split(" ") on any awk
# whose whitespace-splitting doesn't treat CR as blank, straight into the
# stored tag value and from there into index.tsv and search output. gawk's
# split(" ") happens to also drop CR as whitespace, which quietly masks the
# gap there but not on every awk. Strip it explicitly so the tag is clean
# regardless of implementation.
function collect_tags(s,   n, i, w, parts) {
  gsub(CR, "", s)
  s = squish_brackets(s)
  n = split(s, parts, " ")
  for (i = 1; i <= n; i++) {
    w = parts[i]
    if (substr(w, 1, 1) == "#") {
      if (w !~ /^#[0-9A-Za-z_-]/) continue
      w = substr(w, 2)
    }
    else if (fm != 1) continue     # bare words are tags only inside frontmatter
    w = strip_punct(w)
    if (w == "") continue
    if (w in seen) continue
    seen[w] = 1
    ntag++
    tags = (tags == "") ? w : tags "," w
  }
}

# Frontmatter `aliases:` (2026-09-30). collect_alias_list() takes what follows
# the key on the same line: an inline list "[a, "b c"]", a single value, or
# nothing (a block list follows). collect_alias_item() takes a following
# "- item" line of a block list and returns 1, or returns 0 for any other
# non-blank line, which ends the list. Quotes around an item are dropped; no
# regex.
function collect_alias_list(s,   n, i, parts) {
  gsub(CR, "", s)
  n = split(s, parts, ",")
  for (i = 1; i <= n; i++) add_alias(parts[i])
}

function collect_alias_item(s,   t) {
  gsub(CR, "", s)
  t = squeeze_(s)
  if (t == "") return 1
  if (substr(t, 1, 2) != "- ") return 0
  add_alias(substr(t, 3))
  return 1
}

# Brackets of an inline list sit on the first and last item; drop them, then
# one pair of matching quotes.
function add_alias(s,   q) {
  s = squeeze_(s)
  if (substr(s, 1, 1) == "[") s = squeeze_(substr(s, 2))
  if (substr(s, length(s), 1) == "]") s = squeeze_(substr(s, 1, length(s) - 1))
  q = substr(s, 1, 1)
  if (length(s) > 1 && (q == "'" || q == sprintf("%c", 34)) && substr(s, length(s), 1) == q) s = squeeze_(substr(s, 2, length(s) - 2))
  if (s == "") return
  aliases = (aliases == "") ? s : aliases " " s
}

# ---- code-span / fence filtering (2026-09-03) --------------------------------
# A wikilink inside code is documentation, not a link. Measured on a virgin
# vault: a TOML table-array written in backticks became an unresolvable link
# target and doctor reported it as a broken wikilink. The same class of bug
# inflates doctor's path scan, and this note's own first draft reproduced it
# by quoting the example.
#
# index()/substr() only, no regex, per PLAN 4.11.

# A fence line opens or closes a fenced block: ``` or ~~~ after optional
# leading spaces. Returns 1 for a fence line, 0 otherwise.
function is_fence_(line,   t) {
  t = line
  # TAB comes from BEGIN (sprintf); shipped .awk sources carry no literal
  # backslash (PLAN 4.11, locked by the source-hygiene test).
  while (substr(t, 1, 1) == " " || substr(t, 1, 1) == TAB) t = substr(t, 2)
  return (substr(t, 1, 3) == "```" || substr(t, 1, 3) == "~~~") ? 1 : 0
}

# Blank out every backtick-delimited span so the scanner cannot see inside it.
# An unpaired trailing backtick closes nothing, so its remainder is kept --
# dropping it would silently swallow real links after a stray backtick.
function strip_code_(line,   out, rest, ob, cb) {
  out = ""
  rest = line
  while (1) {
    ob = index(rest, "`")
    if (ob == 0) { out = out rest; break }
    cb = index(substr(rest, ob + 1), "`")
    if (cb == 0) { out = out rest; break }
    out = out substr(rest, 1, ob - 1)
    rest = substr(rest, ob + 1 + cb)
  }
  return out
}

# Scan one line for [[hedef]] / [[hedef|görünen]] / [[hedef#bölüm]] and emit
# kaynak TAB hedef for each occurrence found. Delimiter search is index()/
# substr() only, no regex (FAZ 10 Z-5, PLAN 4.11).
#
# src/dest (FAZ 11 F-3): optional. mode=links calls scan_links(line) with
# both omitted — src=="" falls back to FILENAME and dest=="" prints to
# stdout, i.e. byte-for-byte the pre-FAZ11 behavior (T-139 regression).
# mode=scan passes both explicitly: src is the path being read via
# getline (FILENAME does not track that — there is no ARGV file), dest is
# the shared links_new.tsv-bound output.
function scan_links(line, src, dest,   pos, op, cp, inner, cutpos, pbar, phash, target) {
  pos = 1
  while (1) {
    op = index(substr(line, pos), "[[")
    if (op == 0) break
    op = pos + op - 1
    cp = index(substr(line, op + 2), "]]")
    if (cp == 0) break
    cp = op + 2 + cp - 1
    inner = substr(line, op + 2, cp - (op + 2))
    pbar = index(inner, "|")
    phash = index(inner, "#")
    cutpos = length(inner) + 1
    if (pbar  > 0 && pbar  < cutpos) cutpos = pbar
    if (phash > 0 && phash < cutpos) cutpos = phash
    target = trim_(substr(inner, 1, cutpos - 1))
    if (target != "") {
      if (dest == "") print (src == "" ? FILENAME : src), target
      else             print (src == "" ? FILENAME : src), target > dest
    }
    pos = cp + 2
  }
}

# Append one candidate path to a ";"-delimited membership string, keyed by
# `key` in table `tbl` (passed by reference — awk arrays are call-by-ref).
# Leading AND trailing ";" are the boundary markers (N-1): a later membership
# test uses index(tbl[key], ";" y ";") > 0 so a path can never match as a
# substring of a longer neighboring path.
function add_member(tbl, key, val) {
  tbl[key] = (key in tbl) ? tbl[key] val ";" : ";" val ";"
}

# The path's last "/"-segment, with a trailing ".md" stripped by length
# comparison (no regex, per N-1: substr(parça, length(parça)-2) == ".md").
function base_of(path,   parts, n, b) {
  n = split(path, parts, "/")
  b = parts[n]
  if (length(b) > 2 && substr(b, length(b) - 2) == ".md") b = substr(b, 1, length(b) - 3)
  return b
}

# N-2's fixed, first-match-wins priority: tam yol (aynen ya da + ".md") ->
# başlık -> dosya adı -> broken. A stage with 2+ members reports ambiguous
# and does NOT fall through to the next stage.
function resolve_link(kaynak, hedef,   hmd, arr, n) {
  hmd = hedef ".md"
  if (hedef in exists) { print kaynak, hedef, "ok", hedef; return }
  if (hmd in exists)   { print kaynak, hedef, "ok", hmd; return }
  if (hedef in bytitle) {
    n = split(bytitle[hedef], arr, ";") - 2
    if (n == 1) { print kaynak, hedef, "ok", arr[2]; return }
    print kaynak, hedef, "ambiguous", bytitle[hedef]
    return
  }
  if (hedef in bybase) {
    n = split(bybase[hedef], arr, ";") - 2
    if (n == 1) { print kaynak, hedef, "ok", arr[2]; return }
    print kaynak, hedef, "ambiguous", bybase[hedef]
    return
  }
  print kaynak, hedef, "broken", ""
}

# ---- mode: scan (FAZ 11 F-3) -------------------------------------------------

# Drive the whole stale-file batch from pathsfile (one vault-relative path per
# line, a FILE argument per PLAN 4.16 — never awk -v). No ARGV file is read;
# BEGIN calls exit right after this returns, so awk never falls through to
# the normal main input loop (POSIX: exit in BEGIN skips it entirely).
function run_scan(   p) {
  if (pathsfile == "") return
  while ((getline p < pathsfile) > 0) {
    if (p == "") continue
    process_one(p)
  }
  close(pathsfile)
}

# Read one file with getline < p and run the SAME frontmatter/title/tags/
# status/type extraction as mode=meta and the SAME scan_links() as mode=links
# in a single pass — the file is never read twice (FAZ 10 Z-5 generalized).
# title/tags/status/typ/fm/seen are the same globals mode=meta/END already
# use; reset here because a single awk process now visits many files instead
# of one (the old per-file design got a fresh process, and so fresh globals,
# for free).
function process_one(p,   ln, line, fl) {
  ln = 0
  fm = 0
  aliases = ""
  inalias = 0
  # Per-file: an unclosed fence must not leak into the next file's scan.
  scanfence = 0
  title = ""
  tags = ""
  status = ""
  validity = ""
  typ = ""
  delete seen
  while ((getline line < p) > 0) {
    ln++
    # print's own ORS terminates every line regardless of whether the
    # source file's last line had one — this is what keeps two files'
    # content from merging in the combined rawout stream (F-3/T-154).
    print line > rawout
    if (ln == 1 && chomp_(line) == "---") { fm = 1; continue }
    if (fm == 1) {
      fl = chomp_(line)
      if (fl == "---" || fl == "...") { fm = 2; continue }
      if (inalias) {
        if (collect_alias_item(fl)) continue
        inalias = 0
      }
      if (substr(fl, 1, 8) == "aliases:") {
        collect_alias_list(substr(fl, 9))
        inalias = 1
        continue
      }
      if (substr(fl, 1, 6) == "title:")  { if (title == "") title = trim_(substr(fl, 7)) }
      if (substr(fl, 1, 5) == "tags:")   collect_tags(substr(fl, 6))
      if (substr(fl, 1, 7) == "status:") { if (status == "") status = trim_(substr(fl, 8)) }
      if (substr(fl, 1, 5) == "type:")   { if (typ == "") typ = trim_(substr(fl, 6)) }
      if (substr(fl, 1, 9) == "validity:") { if (validity == "") validity = rejected_(substr(fl, 10)) }
      continue
    }
    if (title == "" && substr(line, 1, 2) == "# ") title = trim_(substr(line, 3))
    collect_tags(line)
    if (is_fence_(line)) { scanfence = !scanfence; continue }
    if (scanfence) continue
    scan_links(strip_code_(line), p, linksout)
  }
  close(p)
  if (aliases != "") {
    print US " " aliases > rawout
    ln++
  }
  print p, ln > boundsout
  print p, title, tags, status, typ, validity > metaout
}

# `validity: rejected` (case-insensitive, spaces and quotes ignored) -> "rejected", anything else -> "".
# Char loop, not gsub: T-163 pins the number of regex literals in this file.
function rejected_(s,   i, c, o) {
  DQ = sprintf("%c", 34)
  s = tolower(s)
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c != " " && c != TAB && c != CR && c != DQ && c != "'") o = o c
  }
  return (o == "rejected") ? "rejected" : ""
}

# ---- mode: flatjoin (FAZ 11 F-4) ---------------------------------------------

# Load boundsfile/metafile (both FILE arguments — PLAN 4.16), then walk
# boundsfile in order, consuming exactly that many lines off the shared
# stdin stream for each path (Option B, F-4: a LINE-COUNT boundary, never a
# text delimiter — a delimiter string could appear in real note content and
# silently shift the split; a count cannot).
function run_flatjoin(   mline, mp, n, mparts, bline, bp, bn, k, fline, fbuf, trunc, skipped, apre, nreal) {
  while ((getline mline < metafile) > 0) {
    n = split(mline, mparts, TAB)
    mp = mparts[1]
    fjtitle[mp]  = mparts[2]
    fjtags[mp]   = mparts[3]
    fjstatus[mp] = mparts[4]
    fjtype[mp]   = mparts[5]
    fjvalid[mp]  = mparts[6]
  }
  close(metafile)

  while ((getline bline < boundsfile) > 0) {
    n = split(bline, mparts, TAB)
    bp = mparts[1]
    bn = mparts[2] + 0
    fbuf = ""
    skipped = 0
    apre = ""
    delete fjline
    for (k = 1; k <= bn; k++) {
      if ((getline fline) <= 0) break
      # The alias line (see the header) is the LAST line of its segment and
      # starts with US; it is not note text, so it stays out of the field body
      # and out of the block rows.
      if (k == bn && substr(fline, 1, 1) == US) {
        apre = substr(squeeze_(substr(fline, 2)), 1, 500)
        continue
      }
      # Block index (2026-09-30): keep the folded line so a note that hits the
      # cap below can be cut into blocks without a second read of the stream.
      # Only assigned, never squeezed here, so notes under the cap pay for a
      # plain array store per line and nothing else.
      fjline[k] = fline
      # Same squeeze as mode=flat: TAB/CR to space, collapse space runs, stop
      # APPENDING once at `max` — but keep reading every line in the segment
      # so the shared stream stays aligned for the file that follows.
      if (length(fbuf) < max) {
        gsub(TAB, " ", fline)
        gsub(CR, " ", fline)
        gsub(/  */, " ", fline)
        fbuf = fbuf " " fline
      }
      else if (!skipped && has_text(fline)) skipped = 1
    }
    sub(/^[ ]+/, "", fbuf)
    # The search field hit the cap when it ended up at least `max` long, or
    # when real text was left out after it filled. Only then does the note
    # get block rows (blocksout); everything else is unchanged.
    trunc = (skipped || length(fbuf) >= max) ? 1 : 0
    nreal = k - 1
    if (apre != "") {
      fbuf = apre " " US " " fbuf
      if (length(fbuf) > max) trunc = 1
      nreal--
    }
    fbuf = substr(fbuf, 1, max)
    print bp, fjtitle[bp], fjtags[bp], fbuf, fjstatus[bp], fjtype[bp], fjvalid[bp]
    if (trunc && blocksout != "") build_blocks(bp, nreal, fjtitle[bp], fjtags[bp], fjstatus[bp], fjvalid[bp])
  }
  close(boundsfile)
}

# ---- block index (2026-09-30) -------------------------------------------------
# The search field above stops at `max` characters, so the rest of a long note
# was unsearchable. For a note that hit that cap, build_blocks() cuts the WHOLE
# folded text into blocks of at most `max` characters and writes one row each
# to blocksout:
#   path TAB title TAB tags TAB heading path TAB folded block text TAB status
# (columns 1,2,3,5,6 sit where index.tsv keeps the same fields, so search.awk
# filters and scores both files with the same code). Cut rules: a heading line
# ("#".."######" then a space, outside a fenced block and outside frontmatter)
# starts a new block, except that a heading with no body yet just extends the
# pending block; a section longer than `max` is cut at line boundaries; a
# single line longer than `max` is cut at the last space inside the window
# (hard cut when there is none). The heading path ("H1 > H2") is the one in
# force where the block starts. index()/substr() only, no regex except the
# same gsub squeeze mode=flat uses.
function has_text(s) {
  return (squeeze_(s) != "")
}

# TAB/CR to space, runs of spaces to one, both ends trimmed. No regex LITERAL
# on purpose: T-163 pins the number of /.../ literals in this file, and a
# string separator (gsub("  ", " ") repeated until no double space is left)
# does the same job.
function squeeze_(s) {
  gsub(TAB, " ", s)
  gsub(CR, " ", s)
  while (index(s, "  ") > 0) gsub("  ", " ", s)
  if (substr(s, 1, 1) == " ") s = substr(s, 2)
  if (substr(s, length(s), 1) == " ") s = substr(s, 1, length(s) - 1)
  return s
}

function blk_flush() {
  if (bbuf != "") print bpath, btitle, btags, blabel, bbuf, bstatus, bvalid > blocksout
  bbuf = ""
  bbody = 0
}

function blk_add(s,   pos, len, win, cut, i) {
  len = length(s)
  if (len > max) {
    blk_flush()
    pos = 1
    while (len - pos + 1 > max) {
      win = substr(s, pos, max)
      cut = max
      for (i = max; i > max / 2; i--) {
        if (substr(win, i, 1) == " ") { cut = i; break }
      }
      bbuf = squeeze_(substr(win, 1, cut))
      blabel = bcur
      blk_flush()
      pos += cut
    }
    s = squeeze_(substr(s, pos))
    if (s == "") return
    len = length(s)
  }
  if (bbuf != "" && length(bbuf) + 1 + len > max) blk_flush()
  if (bbuf == "") { bbuf = s; blabel = bcur }
  else bbuf = bbuf " " s
}

function build_blocks(p, n, ti, tg, st, va,   k, sq, i, lvl, head, j, lab, fmz, fence) {
  bpath = p; btitle = ti; btags = tg; bstatus = st; bvalid = va
  bbuf = ""; bbody = 0; blabel = ""; bcur = ""
  delete hs
  fmz = 0
  fence = 0
  for (k = 1; k <= n; k++) {
    sq = squeeze_(fjline[k])
    if (sq == "") continue
    # bbody is set AFTER blk_add: blk_add may flush (size), which clears it,
    # and the line just added is the body of the block that flush started.
    if (k == 1 && sq == "---") { fmz = 1; blk_add(sq); bbody = 1; continue }
    if (fmz == 1) {
      if (sq == "---" || sq == "...") fmz = 2
      blk_add(sq)
      bbody = 1
      continue
    }
    if (is_fence_(sq)) { fence = !fence; blk_add(sq); bbody = 1; continue }
    lvl = 0
    if (!fence) {
      i = 1
      while (substr(sq, i, 1) == "#") i++
      lvl = i - 1
      if (lvl < 1 || lvl > 6 || substr(sq, i, 1) != " ") lvl = 0
      else {
        head = squeeze_(substr(sq, i + 1))
        if (head == "") lvl = 0
      }
    }
    if (lvl > 0) {
      if (bbody) blk_flush()
      hs[lvl] = head
      for (j = lvl + 1; j <= 6; j++) hs[j] = ""
      lab = ""
      for (j = 1; j <= lvl; j++) {
        if (hs[j] != "") lab = (lab == "") ? hs[j] : lab " > " hs[j]
      }
      bcur = lab
      # A heading with no body yet (pending block is only headings): the block
      # now belongs to the newer heading.
      if (bbuf != "") blabel = bcur
      blk_add(sq)
      continue
    }
    blk_add(sq)
    bbody = 1
  }
  blk_flush()
}

function strip_punct(w,   c) {
  while (length(w) > 0) {
    c = substr(w, length(w), 1)
    if (c == "." || c == "," || c == ";" || c == ":" || c == "!" || c == "?" || c == ")" || c == "'" || c == sprintf("%c", 34)) w = substr(w, 1, length(w) - 1)
    else break
  }
  return w
}

END {
  if (mode == "meta") print title, tags, status, typ
  if (mode == "flat") { sub(/^[ ]+/, "", buf); print substr(buf, 1, max) }
  if (mode == "plan") {
    for (i = 1; i <= nold; i++) {
      p = paths[i]
      if (!(p in exists)) print "drop", p, "END"
      else if (!(p in seen)) print "carry", oldrow[p], "END"
    }
  }
  if (mode == "assemble" && countsout != "") {
    # Plain space, not TAB (OFS) — the shell side reads this with an
    # ordinary `read -r R S D`, no IFS juggling needed. The trailing
    # newline is NOT decorative: POSIX `read` returns a nonzero (EOF)
    # status for a line with no terminating newline even though it still
    # populates the variables, and `_q_cmd_index` runs under `set -eu` —
    # without it, a correct "0 3 0" line still aborted the whole command.
    # `print ""` (not a literal backslash-n) supplies that trailing
    # newline from awk's own ORS, keeping this file backslash-free (PLAN
    # 4.11) the same way TAB/CR above come from sprintf("%c", N).
    printf "%d %d %d", rcount + 0, scount + 0, dcount + 0 > countsout
    print "" > countsout
  }
}
