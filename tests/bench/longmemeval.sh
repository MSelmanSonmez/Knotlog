#!/bin/sh
# LongMemEval-S retrieval bench for `knotlog search` (method: agentmemory's
# eval/runner, k = 5, one note per haystack session, query = question text).
#
#   sh tests/bench/longmemeval.sh DATA WORKDIR [N]
#
#   DATA     longmemeval_s_cleaned.json (read only, never executed)
#   WORKDIR  new or empty directory for the per-question vaults and results
#   N        first N questions only (default: all 500)
#   KNOTLOG  env: the knotlog script to measure (default: this checkout's)
#
# Writes WORKDIR/results.tsv: one row per question
#   question_id TAB abs TAB hits TAB gold TAB any TAB all
# and '#' summary lines at the end (recall_any / recall_all over the
# non-abstention questions: 470 on the full set); knotlog stderr goes to
# WORKDIR/stderr.log. Each question gets a fresh
# vault, indexed once, searched once, then removed. Not called by run.sh.
set -eu

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo "usage: $0 DATA WORKDIR [N]" >&2; exit 2; }
DATA=$1 WORK=$2 N=${3:-0}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
KL=${KNOTLOG:-$ROOT/knotlog}
K=5

[ -r "$DATA" ] || { echo "longmemeval: cannot read $DATA" >&2; exit 2; }
[ -f "$KL" ] || { echo "longmemeval: no knotlog at $KL" >&2; exit 2; }
case $N in '' | *[!0-9]*) echo "longmemeval: N must be a number" >&2; exit 2 ;; esac
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "longmemeval: $WORK is not empty" >&2; exit 2; }

OUT=$WORK/results.tsv
T0=$(date +%s)
LC_ALL=C awk -v mode=split -v out="$WORK/q" -v max="$N" \
  -f "$ROOT/lib/jsonfield.awk" -f "$HERE/longmemeval.awk" "$DATA" </dev/null
T1=$(date +%s)

{
  printf '# %s (%s), k=%s, host %s, %s\n' "$(sh "$KL" --version </dev/null)" "$KL" "$K" "$(uname -n)" "$(date '+%Y-%m-%d %H:%M')"
  printf '# split %ss\n' "$((T1 - T0))"
  printf '# question_id\tabs\thits\tgold\tany\tall\n'
} > "$OUT"

for d in "$WORK"/q/q*; do
  [ -d "$d" ] || continue
  IFS=$(printf '\t') read -r qid abs q < "$d/meta.tsv"
  # A leading '-' would read as a flag; search splits terms on blanks, so a
  # leading space changes nothing else.
  case $q in -*) q=" $q" ;; esac
  # stderr (e.g. awk warnings from search) goes to one log, not the terminal.
  (cd "$d/vault" && sh "$KL" index </dev/null >/dev/null) 2>> "$WORK/stderr.log"
  (cd "$d/vault" && sh "$KL" search --paths --limit "$K" "$q" </dev/null) > "$d/hits.txt" 2>> "$WORK/stderr.log"
  awk -v mode=score -v mapf="$d/map.tsv" -v goldf="$d/gold.txt" -v qid="$qid" -v abs="$abs" \
    -f "$HERE/longmemeval.awk" "$d/hits.txt" </dev/null >> "$OUT"
  rm -rf "$d"
done
T2=$(date +%s)

awk -v mode=summary -v secs="$((T2 - T0))" -f "$HERE/longmemeval.awk" "$OUT" </dev/null > "$WORK/summary.tmp"
printf '# search loop %ss\n' "$((T2 - T1))" >> "$OUT"
cat "$WORK/summary.tmp" >> "$OUT"
rm -f "$WORK/summary.tmp"
rmdir "$WORK/q" 2>/dev/null || true
grep '^# ' "$OUT" | tail -n 5
