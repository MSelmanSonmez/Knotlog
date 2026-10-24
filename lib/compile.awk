# quipu — deterministic source compiler.
#
# mode=scan reads index.tsv and the indexed Markdown files, emitting a sorted
# event stream. M events carry concept, source pointer, mtime, kind, ISO date,
# and indexed status; mode=render consumes that stream and writes one derived
# note per concept. No external parser or runtime is needed.

BEGIN {
  TAB = sprintf("%c", 9)
  CR = sprintf("%c", 13)
  FS = TAB
  OFS = TAB
  if (mode == "scan") {
    vault = ENVIRON["Q_COMPILE_VAULT"]
    scan_all()
  }
  if (mode == "render") load_status_()
}

function load_status_(    line, n, fields, slug, mark) {
  if (status_file == "") return
  while ((getline line < status_file) > 0) {
    n = split(line, fields, TAB)
    if (n < 2) continue
    slug = trim_(fields[1])
    mark = trim_(fields[2])
    if (slug != "" && mark != "") {
      status_map[slug] = mark
      known_mark[mark] = 1
    }
  }
  close(status_file)
}

function trim_(s) {
  gsub(CR, "", s)
  gsub(TAB, " ", s)
  sub(/^ +/, "", s)
  sub(/ +$/, "", s)
  return s
}

function clean_(s,    p, q) {
  s = trim_(s)
  p = index(s, "|")
  if (p > 0) s = substr(s, 1, p - 1)
  p = index(s, "#")
  if (p > 0) s = substr(s, 1, p - 1)
  return trim_(s)
}

function source_allowed_(path) {
  return index(path, ".agents/skills/") != 1 && index(path, ".claude/skills/") != 1
}

function concept_allowed_(c,    i, ch, has_content) {
  if (c == "") return 0
  if (c ~ /^[0-9]+[[:lower:]]?[.):_-]/) return 0
  for (i = 1; i <= length(c); i++) {
    ch = substr(c, i, 1)
    if (ch !~ /^[0-9[:space:]_.:-]$/) {
      has_content = 1
      break
    }
  }
  return has_content
}

function add_(c, path, line, mt, kind, date, status,    k) {
  c = clean_(c)
  if (!source_allowed_(path) || !concept_allowed_(c)) return
  doc[path SUBSEP c] = 1
  print "M", c, path, line, mt, kind, date, status
}

function scan_links_(s, path, line, mt, date, status,    p, q, inside, rest) {
  rest = s
  while ((p = index(rest, "[[")) > 0) {
    rest = substr(rest, p + 2)
    q = index(rest, "]]" )
    if (q == 0) return
    inside = substr(rest, 1, q - 1)
    add_(inside, path, line, mt, "wikilink", date, status)
    rest = substr(rest, q + 2)
  }
}

function date_(s,    i, j, c, ok, chunk, year, month, day, maxday) {
  for (i = 1; i <= length(s) - 9; i++) {
    chunk = substr(s, i, 10)
    if (substr(chunk, 5, 1) != "-" || substr(chunk, 8, 1) != "-") continue
    ok = 1
    for (j = 1; j <= 10; j++) {
      c = substr(chunk, j, 1)
      if (j != 5 && j != 8 && (c < "0" || c > "9")) ok = 0
    }
    if (!ok) continue
    year = substr(chunk, 1, 4) + 0
    month = substr(chunk, 6, 2) + 0
    day = substr(chunk, 9, 2) + 0
    maxday = 31
    if (month == 2) {
      maxday = 28
      if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) maxday = 29
    } else if (month == 4 || month == 6 || month == 9 || month == 11) maxday = 30
    if (year >= 1000 && month >= 1 && month <= 12 && day >= 1 && day <= maxday) return chunk
  }
  return ""
}

function scan_file_(path, mt, status,    f, line, n, h, date, text, line_date) {
  f = vault "/" path
  date = date_(path)
  n = 0
  while ((getline line < f) > 0) {
    n++
    text = line
    line_date = date
    h = 0
    while (substr(text, h + 1, 1) == "#") h++
    if (line_date == "" && h > 0) line_date = date_(text)
    if (h > 0 && (substr(text, h + 1, 1) == " " || substr(text, h + 1, 1) == TAB)) {
      add_(substr(text, h + 2), path, n, mt, "heading", line_date, status)
    }
    scan_links_(text, path, n, mt, line_date, status)
  }
  close(f)
}
function scan_all(    line, f, n, p, fields, path, mt, title, status, date, k, m, a, b, i, j, t) {
  while ((getline line < indexfile) > 0) {
    n = split(line, fields, TAB)
    if (n < 1 || fields[1] == "") continue
    path = fields[1]
    mt = (n >= 4 ? fields[4] : 0) + 0
    title = (n >= 2 ? fields[2] : "")
    status = (n >= 6 ? fields[6] : "")
    if (n >= 8 && fields[8] == "rejected") continue
    if (compiled_prefix != "" && index(path, compiled_prefix) == 1) continue
    paths[path] = 1
    times[path] = mt
    statuses[path] = status
    dates[path] = date_(path)
    if (title != "") add_(title, path, 1, mt, "index", dates[path], status)
  }
  close(indexfile)
  while ((getline line < pathsfile) > 0) {
    path = trim_(line)
    if (path == "" || !(path in paths)) continue
    scan_file_(path, times[path], statuses[path])
    m = 0
    for (k in doc) {
      if (index(k, path SUBSEP) != 1) continue
      a = substr(k, length(path SUBSEP) + 1)
      docs[path, ++m] = a
    }
    for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++) {
      a = docs[path, i]
      b = docs[path, j]
      if (a > b) { t = a; a = b; b = t }
      print "E", a, b
    }
  }
  close(pathsfile)
}


function status_mark_(s,    m, pos, best, bestpos) {
  s = trim_(s)
  if (s in status_map) return status_map[s]
  # Byte-mode awk (Windows: LANG empty) splits a multibyte emoji into bytes,
  # so a per-character scan never matches it. index() matches whole marks in
  # either mode; the earliest mark in s wins, as the old scan did.
  bestpos = 0
  for (m in known_mark) {
    pos = index(s, m)
    if (pos > 0 && (bestpos == 0 || pos < bestpos)) { bestpos = pos; best = m }
  }
  return best
}

function timeline_add_(c, date, status,    mark, key) {
  date = trim_(date)
  mark = status_mark_(status)
  if (date == "" || mark == "") return
  key = c SUBSEP date SUBSEP mark
  if (key in timeline_seen) return
  timeline_seen[key] = 1
  timeline_n[c]++
  timeline_date[c, timeline_n[c]] = date
  timeline_mark[c, timeline_n[c]] = mark
}

function timeline_sort_(c,    i, j, d, m) {
  for (i = 1; i <= timeline_n[c]; i++) for (j = i + 1; j <= timeline_n[c]; j++) {
    if (timeline_date[c, j] < timeline_date[c, i] ||
        (timeline_date[c, j] == timeline_date[c, i] && timeline_mark[c, j] < timeline_mark[c, i])) {
      d = timeline_date[c, i]
      timeline_date[c, i] = timeline_date[c, j]
      timeline_date[c, j] = d
      m = timeline_mark[c, i]
      timeline_mark[c, i] = timeline_mark[c, j]
      timeline_mark[c, j] = m
    }
  }
}

mode == "render" {
  kind = $1
  c = $2
  if (kind == "M" && c != "") {
    if (!(c in first) || ($5 + 0) < first[c]) first[c] = $5 + 0
    if (!(c in last) || ($5 + 0) > last[c]) last[c] = $5 + 0
    count[c]++
    timeline_add_(c, $7, $8)
    pk = c SUBSEP $3 SUBSEP $4
    if (!(pk in pointer_seen)) {
      pointer_seen[pk] = 1
      pn[c]++
      pointer[c, pn[c]] = $3 TAB $4
    }
    if (!(c in concept_seen)) {
      concept_seen[c] = 1
      cn[++concept_n] = c
    }
  } else if (kind == "E" && $2 != "" && $3 != "" && $2 != $3) {
    a = $2
    b = $3
    if (a > b) { t = a; a = b; b = t }
    ek = a SUBSEP b
    if (!(ek in edge_seen)) {
      edge_seen[ek] = 1
      en[a]++
      edge[a, en[a]] = b
      en[b]++
      edge[b, en[b]] = a
    }
  }
  next
}

function slug_(s,    i, c, out, lastdash) {
  out = ""
  lastdash = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if ((c >= "A" && c <= "Z") || (c >= "a" && c <= "z") ||
        (c >= "0" && c <= "9") || c == "." || c == "_") {
      out = out c
      lastdash = 0
    } else if (!lastdash) {
      out = out "-"
      lastdash = 1
    }
  }
  while (substr(out, 1, 1) == "-") out = substr(out, 2)
  while (substr(out, length(out), 1) == "-") out = substr(out, 1, length(out) - 1)
  if (length(out) > 120) out = substr(out, 1, 120)
  while (substr(out, length(out), 1) == "-") out = substr(out, 1, length(out) - 1)
  if (out == "") out = "concept"
  return out
}

function pick_file_(c,    base, candidate, n, firstline, secondline, status, title_status) {
  base = outdir "/" slug_(c)
  candidate = base ".md"
  n = 1
  while (1) {
    firstline = ""
    secondline = ""
    status = getline firstline < candidate
    if (status > 0) title_status = getline secondline < candidate
    else title_status = status
    close(candidate)
    if (status < 0 || ((index(firstline, "knotlog:compiled:start") > 0 || index(firstline, "quipu:compiled:start") > 0) && title_status > 0 && secondline == "# " c)) return candidate
    n++
    candidate = base "-" n ".md"
  }
}

function render_(c,    file, i, j, ptr, nbr) {
  file = pick_file_(c)
  print "<!-- knotlog:compiled:start -->" > file
  print "# " c > file
  print "" > file
  print "## " band > file
  print "- " first_label ": " first[c] > file
  print "- " last_label ": " last[c] > file
  print "- " count_label ": " count[c] > file
  print "" > file
  print "## " timeline_label > file
  timeline_sort_(c)
  if (timeline_n[c] > 0) {
    for (i = 1; i <= timeline_n[c]; i++) print "- " timeline_date[c, i] ": " timeline_mark[c, i] > file
  } else print "- " timeline_empty > file
  print "" > file
  print "## " pointer_label > file
  for (i = 1; i <= pn[c]; i++) {
    ptr = pointer[c, i]
    split(ptr, pp, TAB)
    print "- `" pp[1] ":" pp[2] "`" > file
  }
  print "" > file
  print "## " comention_label > file
  for (i = 1; i <= en[c]; i++) print "- " edge[c, i] > file
  print "" > file
  print "## " source_label > file
  print "- " source_text > file
  print "<!-- knotlog:compiled:end -->" > file
  close(file)
  rendered++
}

END {
  if (mode != "render") exit
  # The scan stream is sorted by concept before this pass. Sorting concepts here
  # again would need non-POSIX asorti; event order already makes cn stable.
  for (i = 1; i <= concept_n; i++) render_(cn[i])
  print rendered
}
