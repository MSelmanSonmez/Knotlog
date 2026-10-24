# Update one icon metadata key while preserving unrelated file lines.
# First input row: kind TAB icon path. Remaining input is metadata text.
BEGIN { tab = sprintf("%c", 9) }
NR == FNR {
  p = index($0, tab)
  kind = substr($0, 1, p - 1)
  icon = substr($0, p + 1)
  next
}
{
  if (kind == "directory" && index($0, "Icon=") == 1) {
    print "Icon=" icon
    found = 1
    next
  }
  if (kind == "desktop" && index($0, "IconResource=") == 1) {
    print "IconResource=" icon ",0"
    found = 1
    next
  }
  print
}
END {
  if (!found) {
    if (kind == "directory") print "Icon=" icon
    if (kind == "desktop") print "IconResource=" icon ",0"
  }
}
