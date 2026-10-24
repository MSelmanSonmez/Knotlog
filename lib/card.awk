# knotlog - per-session handoff card in the last-session file.
# Usage: awk -v tail=<" . id8"> -v head=<heading line> -f card.awk FILE < body
# Every "## " card whose heading ends with `tail` is removed, with its body (up
# to the next "## " heading or marker comment), and the new card is appended at
# the bottom, so the last "## " block is always the newest (doctor D3, compact).
# Everything else passes through verbatim. No regex, no literal backslash.
BEGIN {
  while ((getline line < "-") > 0) body = (body == "") ? line : body sprintf("%c", 10) line
  close("-")
  cr = sprintf("%c", 13)
}
{
  h = $0
  if (substr(h, length(h)) == cr) h = substr(h, 1, length(h) - 1)
  if (substr(h, 1, 3) == "## ") skip = (substr(h, length(h) - length(tail) + 1) == tail)
  else if (substr(h, 1, 5) == "<!-- ") skip = 0
  if (!skip) { print; last = h }
}
END {
  if (NR > 0 && last != "") print ""
  print head
  if (body != "") print body
}
