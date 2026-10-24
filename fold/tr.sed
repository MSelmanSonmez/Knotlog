# knotlog fold profile: tr (Turkish).
# Turkish folds fully to ASCII, per PLAN 4.2 and PLAN 7 (açık and acık must
# collide in the index): İ -> i, I -> ı -> i, Ğ/ğ -> g, Ş/ş -> s. Ç/Ö/Ü and
# their lowercase forms already fold to ASCII via the latin base below.
# PLAN 4.3 order applies: fold first, then tr 'A-Z' 'a-z'.
#
# Usage: sed -f fold/tr.sed < input | tr 'A-Z' 'a-z'

# Latin base (same set as fold/latin.sed)

# A
s/À/a/g
s/Á/a/g
s/Â/a/g
s/Ã/a/g
s/Ä/a/g
s/Å/a/g
s/à/a/g
s/á/a/g
s/â/a/g
s/ã/a/g
s/ä/a/g
s/å/a/g

# AE
s/Æ/ae/g
s/æ/ae/g

# C
s/Ç/c/g
s/ç/c/g

# E
s/È/e/g
s/É/e/g
s/Ê/e/g
s/Ë/e/g
s/è/e/g
s/é/e/g
s/ê/e/g
s/ë/e/g

# I (latin base: dotted accents only, ASCII I is handled by Turkish block)
s/Ì/i/g
s/Í/i/g
s/Î/i/g
s/Ï/i/g
s/ì/i/g
s/í/i/g
s/î/i/g
s/ï/i/g

# D (Icelandic eth)
s/Ð/d/g
s/ð/d/g

# N
s/Ñ/n/g
s/ñ/n/g

# O
s/Ò/o/g
s/Ó/o/g
s/Ô/o/g
s/Õ/o/g
s/Ö/o/g
s/Ø/o/g
s/ò/o/g
s/ó/o/g
s/ô/o/g
s/õ/o/g
s/ö/o/g
s/ø/o/g

# U
s/Ù/u/g
s/Ú/u/g
s/Û/u/g
s/Ü/u/g
s/ù/u/g
s/ú/u/g
s/û/u/g
s/ü/u/g

# Y
s/Ý/y/g
s/ý/y/g
s/ÿ/y/g
s/Ÿ/y/g

# TH (Icelandic thorn)
s/Þ/th/g
s/þ/th/g

# SZ (German sharp s)
s/ß/ss/g

# OE
s/Œ/oe/g
s/œ/oe/g

# Turkish specifics (PLAN 4.2: I goes through dotless ı to i; İ goes to i).
# Order matters: I -> ı must run before ı -> i.
s/I/ı/g
s/İ/i/g
s/ı/i/g
s/Ğ/g/g
s/ğ/g/g
s/Ş/s/g
s/ş/s/g
