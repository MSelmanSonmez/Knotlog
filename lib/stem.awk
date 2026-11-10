# knotlog — stem.awk: Turkish suffix stemming for search.
#
# One shared function, loaded with an extra `-f` next to lib/search.awk, so the
# query side and the document side of a search can never stem differently.
#
#   stem_word(w)
#
# `w` is ONE folded token (fold/tr.sed + tr 'A-Z' 'a-z': ASCII, lowercase), with
# no trailing punctuation (the caller strips and re-attaches that). The longest
# known suffix is dropped, up to two rounds, so stacked endings fall away too
# (guncelleme + si, kurulum + u).
#
# Rules:
#   - a token shorter than 4 characters is never touched;
#   - only tokens made of the letters a-z are touched, so numbers, node.js,
#     c++, #tag, snake_case and anything with a non-ASCII letter (fold=default)
#     pass through unchanged;
#   - a suffix is dropped only if enough letters remain: at least 4 for a
#     one- or two-letter suffix, at least 3 for a longer one (okulu -> okul;
#     dosya and dosta stay whole, evden is not cut to evd). A suffix that
#     would leave too little is skipped and a shorter one is tried;
#   - the result is always a PREFIX of w. search.awk relies on this to skip the
#     stemming of rows that cannot contain a query stem at all.
#
# Suffix table (folded; i is also the folded dotless i, u also the folded u-
# umlaut):
#   1: i u
#   2: in un im um da de ta te ya ye na ne yi yu di ti ar er ir ur ma me ic
#      en an si su li lu ki
#   3: lar ler lik lig luk lug sin siz mak mek dan den tan ten ici mis mus
#      yor ini unu imi umu ina una ine une
#   4: mesi masi lari leri ecek acak
#
# Contract (PLAN 4.11): no literal backslash, no regex; index()/substr()/split().

function stem_init(   n, i, a) {
  ST_AZ = "abcdefghijklmnopqrstuvwxyz"
  n = split("i u in un im um da de ta te ya ye na ne yi yu di ti ar er ir ur ma me ic en an si su li lu ki lar ler lik lig luk lug sin siz mak mek dan den tan ten ici mis mus yor ini unu imi umu ina una ine une mesi masi lari leri ecek acak", a, " ")
  ST_MAX = 0
  for (i = 1; i <= n; i++) {
    ST_SUF[a[i]] = 1
    if (length(a[i]) > ST_MAX) ST_MAX = length(a[i])
  }
  ST_READY = 1
}

# Drop the longest known suffix from w once; w itself when none applies.
function stem_strip(w,   len, k, keep) {
  len = length(w)
  for (k = ST_MAX; k >= 1; k--) {
    keep = len - k
    if (keep < (k <= 2 ? 4 : 3)) continue
    if (substr(w, keep + 1) in ST_SUF) return substr(w, 1, keep)
  }
  return w
}

function stem_word(w,   len, i, r, nw) {
  len = length(w)
  if (len < 4) return w
  if (!ST_READY) stem_init()
  for (i = 1; i <= len; i++) {
    if (index(ST_AZ, substr(w, i, 1)) == 0) return w
  }
  for (r = 1; r <= 2; r++) {
    nw = stem_strip(w)
    if (nw == w) break
    w = nw
  }
  return w
}
