# The text of the first content item of an MCP tool result (one JSON object per line).
{
  k = q_() "type" q_() ":" q_() "text" q_() "," q_() "text" q_()
  p = index($0, k)
  if (p) printf "%s", jf_read($0, p + length(k))
}
