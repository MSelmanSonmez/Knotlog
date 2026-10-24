# quipu — release JSON reader for `update --check`.
# Reads a GitHub Releases API response ({"tag_name": "v2.8.0", ...}, one
# object, possibly pretty-printed across many lines) from stdin and prints
# the tag_name string, or nothing if the field is absent. Loaded alongside
# jsonfield.awk (awk -f lib/jsonfield.awk -f lib/release.awk), same as every
# other JSON reader in this project (PLAN 4.8: no jq, no regex).
{ s = s $0 nl_() }
END {
  print jsonfield(s, "tag_name")
}
