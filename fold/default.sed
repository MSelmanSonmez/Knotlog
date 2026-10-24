# knotlog fold profile: default.
# ASCII-only: folds nothing itself. ASCII A-Z is lowercased by the tr step:
#
#   sed -f fold/default.sed < input | tr 'A-Z' 'a-z'
#
# Multibyte characters pass through unchanged — no lossy folding without an
# explicit profile. For Latin-script accent folding use latin.sed; for
# Turkish use tr.sed.
