# Rewrite only Knotlog-owned Claude command prefixes; preserve every other setting.
# The first input file contains the current absolute source command.
# Two owned prefixes: the current one and the pre-rename one an older vault's
# settings still carry; each keeps its own env name (both are read).
BEGIN {
  mnew = "KNOTLOG_HOOK=1 knotlog"; mold = "QUIPU_HOOK=1 quipu"
  command_key = sprintf("%ccommand%c", 34, 34); dq = sprintf("%c", 34); bs = sprintf("%c", 92)
}
NR == FNR { source = $0; next }
{
  if (index($0, command_key) == 0) {
    print
    next
  }
  rest = $0
  output = ""
  for (;;) {
    pn = index(rest, mnew)
    po = index(rest, mold)
    if (pn == 0 && po == 0) break
    if (pn != 0 && (po == 0 || pn < po)) { p = pn; m = mnew; env = "KNOTLOG_HOOK=1 " }
    else { p = po; m = mold; env = "QUIPU_HOOK=1 " }
    output = output substr(rest, 1, p - 1) env bs dq source bs dq
    rest = substr(rest, p + length(m))
  }
  print output rest
}
