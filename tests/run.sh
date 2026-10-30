#!/bin/sh
# quipu — test suite for the FAZ 1 Adim 1 primitives.
# Zero external framework (PLAN FAZ 1). Run: sh tests/run.sh
# CI executes this on ubuntu / macos / windows (PLAN Adim 2).
#
# Backslash policy: PLAN 4.11 forbids escape-sequence-based CODE in the
# shipped sources (lib/*.awk, fold/*.sed). In this file backslashes appear
# only as DATA inside single-quoted expected values; single quotes preserve
# them verbatim through every shell layer.

# File-wide, deliberate: SC2059 -- printf formats are the i18n templates under
# test; SC2016 -- single quotes hold literal fixture text ($HOME, $_q_...) that must
# not expand; SC2209 -- `QUIPU_LANG=tr sh ...` is an env prefix, not an assignment.
# shellcheck disable=SC2059,SC2016,SC2209,SC2030,SC2031
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/lib"
FOLD="$ROOT/fold"
FIX="$ROOT/tests/fixtures"
DRV="$ROOT/tests/drivers"

PASS=0
FAIL=0
SKIP=0
NUM=0
TMP=${TMPDIR:-/tmp}/quipu-tests-$$
mkdir -p "$TMP" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# FAZ 15 (AA-7/T-233): a developer running `sh tests/run.sh` from a real
# terminal would otherwise hand every subprocess fd0 inherited from that
# terminal -- `[ -t 0 ]` would read true, and the interactive `init` path
# (AB-1) would block on its first question. CI's stdin is already close to
# /dev/null so this is a no-op there; a bare terminal run needs it closed
# explicitly, once, here, before any test spawns a subprocess.
exec < /dev/null

# B11 T-408/T-409: same class of leak as the stdin fix just above, but
# through $EDITOR instead of fd0. `_q_cmd_plan` (quipu) opens "$EDITOR" on
# the freshly written file when $EDITOR is set -- correct, wanted behavior
# for an interactive `knotlog plan`. But this whole suite already runs with
# stdin closed (exec < /dev/null right above), so a developer whose
# personal $EDITOR is a full-screen program (nano, vim, ...) hands it a
# non-terminal stdin the moment `knotlog plan` execs it; nano in particular
# exits 1 with "Standard input is not a terminal", which becomes `quipu
# plan`'s own exit code even though the file was written correctly -- only
# the exit-code assertions (not the file-content ones) fail, and only on a
# machine that happens to have $EDITOR set. Unsetting it here, once, before
# any test runs, keeps the suite's result independent of whoever's shell
# invokes it -- exactly the same reasoning as the stdin close above, and
# not a change to `quipu` itself: opening $EDITOR after a successful write
# is the correct, wanted behavior for real interactive use.
unset EDITOR VISUAL
# GNU grep 3.0 on Git for Windows fails multibyte fixed-string matches under
# UTF-8 locales. Wrapping grep in LC_ALL=C ensures test-suite assertion greps
# match bytes deterministically. SUT (`sh "$ROOT/knotlog"`) runs as a separate
# process and retains the caller's locale environment.
grep() { LC_ALL=C command grep "$@"; }

ok()     { PASS=$((PASS + 1)); printf 'ok %d - %s\n' "$NUM" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %d - %s\n' "$NUM" "$1"; }
skip()   { SKIP=$((SKIP + 1)); printf 'ok %d - %s # SKIP %s\n' "$NUM" "$1" "$2"; }
t()      { NUM=$((NUM + 1)); }
# touch_at EPOCH FILE... -- set mtime from epoch seconds. `touch -d @N` is GNU
# only; `touch -t` is POSIX. The stamp comes from GNU `date -d @N`, else BSD `date -r N`.
touch_at() {
  _ta_e=$1; shift
  _ta_s=$(date -d "@$_ta_e" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$_ta_e" +%Y%m%d%H%M.%S)
  touch -t "$_ta_s" "$@"
}

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    not_ok "$1"
    printf '#    expected: [%s]\n#    got:      [%s]\n' "$2" "$3"
  fi
}

field() { # driver.awk file
  awk -f "$LIB/jsonfield.awk" -f "$DRV/$1" "$2"
}
scoped()   { field filepath_scoped.awk "$1"; }
unscoped() { field filepath_unscoped.awk "$1"; }
toolname() { field toolname.awk "$1"; }

fold_p() { # profile-name
  # SC2018/SC2019 suggest [:upper:]/[:lower:], but PLAN 4.3 forbids them here:
  # BSD tr is byte-based and multibyte classes can corrupt UTF-8. ASCII
  # ranges after folding are safe on every platform (verified on macOS CI).
  # shellcheck disable=SC2018,SC2019
  sed -f "$FOLD/$1.sed" | tr 'A-Z' 'a-z'
}

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
TAB=$(printf '\t')

# ---- jsonfield: escapes, control bytes, UTF-8, missing field (PLAN 4.8) ----

t; assert_eq "jsonfield decodes escaped quote and backslashes" 'a"b' "$(toolname "$FIX/escapes.json")"
t; assert_eq "scoped file_path keeps Windows path" 'C:\Users\x\not.md' "$(scoped "$FIX/escapes.json")"
t; assert_eq "unscoped agrees when the real field comes first" 'C:\Users\x\not.md' "$(unscoped "$FIX/escapes.json")"

CTL=$(awk 'BEGIN{printf "li%cne%ctab%cret",10,9,13}')
t; assert_eq "jsonfield decodes newline tab carriage-return" "$CTL" "$(toolname "$FIX/controls.json")"

t; assert_eq "jsonfield preserves UTF-8" 'İstanbul çğöü 日本語 🔮' "$(toolname "$FIX/utf8.json")"
t; assert_eq "missing field returns empty string" '' "$(scoped "$FIX/missing.json")"

# ---- scoping: trap in tool_response (PLAN 4.8 sinir 1) ----

t; assert_eq "real captured schema: scoped file_path correct" 'C:\Users\alice\projects\demo\taskbar_overflow.png' "$(scoped "$FIX/posttooluse.json")"
t; assert_eq "real captured schema: unscoped agrees" 'C:\Users\alice\projects\demo\taskbar_overflow.png' "$(unscoped "$FIX/posttooluse.json")"
t; assert_eq "trap before tool_input: scoped wins" 'dogru.md' "$(scoped "$FIX/trap-before.json")"
printf '# info: unscoped on trap-before.json returns [%s] (documented failure mode)\n' "$(unscoped "$FIX/trap-before.json")"

# ---- jsonemit -> jsonfield round-trip ----

roundtrip() { # fixture expected
  t
  emit=$(awk -f "$LIB/jsonfield.awk" -f "$LIB/jsonemit.awk" -f "$DRV/roundtrip.awk" "$1")
  back=$(printf '{"x":%s}' "$emit" | awk -f "$LIB/jsonfield.awk" -f "$DRV/value.awk" -)
  assert_eq "round-trip: $(basename "$1")" "$2" "$back"
}

roundtrip "$FIX/roundtrip-path.json" 'C:\Users\x\not.md "quoted"'
MULTI=$(awk 'BEGIN{printf "line1%cline2%ctabbed",10,9}')
roundtrip "$FIX/roundtrip-multi.json" "$MULTI"
roundtrip "$FIX/roundtrip-utf8.json" 'İstanbul çğöü 日本語 🔮'
roundtrip "$FIX/roundtrip-ctl.json" "a$(awk 'BEGIN{printf "%c", 27}')b"   # uXXXX now decodes (T-869); ESC survives the round trip

# ---- big payload: scoped reads, bounded time (PLAN 4.12, 4.8 sinir 2) ----

printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"big/target.md"},"tool_response":"base64:' > "$TMP/big.json"
awk 'BEGIN{for(i=0;i<7000;i++) printf "0000000000000000000000000000000000000000000000000000000000000000"}' >> "$TMP/big.json"
printf '%s' '"}' >> "$TMP/big.json"

t; START=$(date +%s)
FULL=$(field filepath_scoped.awk "$TMP/big.json")
END=$(date +%s)
assert_eq "448 KB payload: full read returns scoped path" 'big/target.md' "$FULL"
t; assert_eq "448 KB payload: bounded time" 'yes' "$([ $((END - START)) -lt 30 ] && printf yes || printf no)"

t; PREFIX=$(head -c 65536 "$TMP/big.json" | awk -f "$LIB/jsonfield.awk" -f "$DRV/filepath_scoped.awk" -)
assert_eq "448 KB payload: 64 KB prefix returns same path" 'big/target.md' "$PREFIX"

# ---- folding profiles (PLAN 4.1-4.3) ----

t; assert_eq "latin: PLAN 4.1 canonical" 'uber munchen cafe naive senor strasse joao' "$(printf '%s\n' 'Über MÜNCHEN Café NAÏVE Señor Straße João' | fold_p latin)"
t; assert_eq "latin: german" 'arger ol ubung strasse' "$(printf '%s\n' 'Ärger Öl Übung Straße' | fold_p latin)"
t; assert_eq "latin: french" 'cafe naive coeur creme deja-vu' "$(printf '%s\n' 'Café NAÏVE cœur Crème déjà-vu' | fold_p latin)"
t; assert_eq "latin: spanish" 'senor espana camion pinguino' "$(printf '%s\n' 'Señor España CAMIÓN pingüino' | fold_p latin)"
t; assert_eq "latin: CJK Cyrillic emoji untouched" '日本語 中文 Привет 🔮' "$(printf '%s\n' '日本語 中文 Привет 🔮' | fold_p latin)"
t; assert_eq "tr: I goes through dotless i to i" 'istanbul isik calisma guzel' "$(printf '%s\n' 'İstanbul IŞIK çalışma ĞÜZEL' | fold_p tr)"
t; assert_eq "tr: latin base included" 'uber munchen cafe naive' "$(printf '%s\n' 'Über MÜNCHEN Café NAÏVE' | fold_p tr)"
t; assert_eq "tr: PLAN 4.3 order passthrough" 'uber 日本語 Привет 🔮 cafe' "$(printf '%s\n' 'Über 日本語 Привет 🔮 Cafe' | fold_p tr)"
t; assert_eq "default: folds nothing, tr lowercases ASCII" 'café naÏve mÜnchen' "$(printf '%s\n' 'Café NAÏVE MÜNCHEN' | fold_p default)"

# ---- source hygiene (PLAN 4.1, 4.11) ----

t; BAD=$(awk 'index($0, sprintf("%c", 92)) != 0 { print FILENAME ":" NR }' "$LIB"/*.awk "$FOLD"/*.sed)
assert_eq "no literal backslash in shipped sources" '' "$BAD"

t; BAD=$(grep -Fl '[' "$FOLD"/*.sed)
assert_eq "no character classes in fold profiles" '' "$BAD"

# ---- mtime portability (PLAN 4.4) ----

: > "$TMP/mtime.txt"
t; EXPECTED=$(stat -c %Y "$TMP/mtime.txt" 2>/dev/null || stat -f %m "$TMP/mtime.txt" 2>/dev/null || echo 0)
assert_eq "mtime returns the platform stat value" "$EXPECTED" "$(mtime "$TMP/mtime.txt")"
t; assert_eq "mtime of missing file falls back to 0" '0' "$(mtime "$TMP/does-not-exist.txt")"

# ---- POSIX compliance (PLAN 3) ----

if command -v shellcheck >/dev/null 2>&1; then
  t
  case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*)
    skip "shellcheck POSIX clean" "Windows shellcheck runs out of memory on this file; Linux and macOS CI lint it" ;;
  *)
  # Full dataflow analysis exhausts runner memory on this file; the flag exists in ShellCheck 0.10+, older ones run without it.
  SC_XA=
  shellcheck --help 2>&1 | grep -q extended-analysis && SC_XA=--extended-analysis=false
  # shellcheck disable=SC2086
  if shellcheck -s sh $SC_XA "$ROOT/tests/run.sh" >/dev/null 2>&1; then
    ok "shellcheck POSIX clean"
  else
    not_ok "shellcheck POSIX clean"
    # shellcheck disable=SC2086
    shellcheck -s sh $SC_XA "$ROOT/tests/run.sh" || true
  fi ;;
  esac
  t
  if shellcheck -s sh "$ROOT/knotlog" >/dev/null 2>&1; then
    ok "shellcheck POSIX clean (quipu)"
  else
    not_ok "shellcheck POSIX clean (quipu)"
    shellcheck -s sh "$ROOT/knotlog" || true
  fi
else
  t; skip "shellcheck POSIX clean" "shellcheck not installed (CI installs it)"
  t; skip "shellcheck POSIX clean (quipu)" "shellcheck not installed (CI installs it)"
fi

# ---- cli skeleton ----

t; VERSION=$(sh "$ROOT/knotlog" --version)
t; assert_eq "knotlog --version prints knotlog 1.2.0" 'knotlog 1.2.0' "$VERSION"

mkdir -p "$TMP/empty"
t; (cd "$TMP/empty" && "$ROOT/knotlog" doctor) >"$TMP/empty.out" 2>&1; RC=$?
assert_eq "doctor in empty dir exits 0" '0' "$RC"
t
if grep -q 'knotlog doctor' "$TMP/empty.out"; then
  ok "doctor output mentions knotlog doctor"
else
  not_ok "doctor output mentions knotlog doctor"
fi

mkdir -p "$TMP/vault/.knotlog"
: > "$TMP/vault/.knotlog/config"
t; (cd "$TMP/vault" && "$ROOT/knotlog" doctor) >"$TMP/vault.out" 2>&1; RC=$?
assert_eq "doctor with vault exits 0" '0' "$RC"

t; (cd "$TMP/empty" && QUIPU_LANG=zz "$ROOT/knotlog" doctor) >"$TMP/zz.out" 2>&1; RC=$?
assert_eq "doctor with QUIPU_LANG=zz exits 0" '0' "$RC"



# ---- explicit help language contract ----

mkdir -p "$TMP/help-tr/.knotlog"
printf '%s\n' 'lang=tr' > "$TMP/help-tr/.knotlog/config"
t; (cd "$TMP/help-tr" && sh "$ROOT/knotlog" help) >"$TMP/help-en.out" 2>"$TMP/help-en.err"; RC=$?
assert_eq "help: tr vault defaults to English and exits 0" '0' "$RC"
t; assert_eq "help: tr vault emits English usage" 'Usage: knotlog COMMAND [options]' \
  "$(sed -n '1p' "$TMP/help-en.out")"
t; (cd "$TMP/help-tr" && sh "$ROOT/knotlog" help --tr) >"$TMP/help-tr.out" 2>"$TMP/help-tr.err"; RC=$?
assert_eq "help: --tr exits 0" '0' "$RC"
t; assert_eq "help: --tr emits Turkish usage" 'Kullanım: knotlog KOMUT [seçenekler]' \
  "$(sed -n '1p' "$TMP/help-tr.out")"
t; (cd "$TMP/help-tr" && sh "$ROOT/knotlog" help --en) >"$TMP/help-en-flag.out" 2>"$TMP/help-en-flag.err"; RC=$?
assert_eq "help: --en emits English usage" 'Usage: knotlog COMMAND [options]' \
  "$(sed -n '1p' "$TMP/help-en-flag.out")"
t; (cd "$TMP/help-tr" && sh "$ROOT/knotlog" help --lang) \
  >"$TMP/help-invalid.out" 2>"$TMP/help-invalid.err"; RC=$?
assert_eq "help: missing language exits 2" '2' "$RC"
t; (cd "$TMP/help-tr" && sh "$ROOT/knotlog" help --tr extra) \
  >"$TMP/help-excess.out" 2>"$TMP/help-excess.err"; RC=$?
assert_eq "help: excess language arguments exit 2" '2' "$RC"
t; (cd "$TMP/help-tr" && sh "$ROOT/knotlog" help --zz) \
  >"$TMP/help-unknown.out" 2>"$TMP/help-unknown.err"; RC=$?
assert_eq "help: unknown language exits 2" '2' "$RC"
t; assert_eq "help: invalid argument gives a localized clear error" \
  'help argüman kabul etmez; yalnızca gönderilen bir dilin --<kod> bayrağı kullanılabilir (örn. --en, --tr)' \
  "$(cat "$TMP/help-unknown.err")"
t; (cd "$TMP/help-tr" && sh "$ROOT/knotlog" nonsense) >"$TMP/help-fallback.out" \
  2>"$TMP/help-fallback.err"; RC=$?
assert_eq "help: unknown fallback retains active Turkish usage and exits 2" '2' "$RC"
t; assert_eq "help: unknown fallback remains active-language usage" \
  'Kullanım: knotlog KOMUT [seçenekler]' "$(sed -n '1p' "$TMP/help-fallback.out")"
# ---- capture (PLAN FAZ 1) ----

mkvault() { mkdir -p "$TMP/$1/.knotlog"; : > "$TMP/$1/.knotlog/config"; }
# ctx_same_body BEFORE AFTER: both `knotlog context` outputs start with the
# i18n now-line (en "now: ", tr "şimdi: ") and the rest is byte-identical.
# The now-line carries the wall-clock minute, so a whole-file cmp fails when
# the two calls straddle a minute boundary; comparing the body alone does not.
ctx_same_body() {
  head -n 1 "$1" | grep -Eq '^(now|şimdi): ' || return 1
  head -n 1 "$2" | grep -Eq '^(now|şimdi): ' || return 1
  tail -n +2 "$1" > "$1.body" && tail -n +2 "$2" > "$2.body" && cmp -s "$1.body" "$2.body"
}
log_line() { awk 'END{i=index($0," | "); print substr($0,i+3)}' "$1/.knotlog/activity.log"; }

mkvault vcap

t; QUIPU_VAULT="$TMP/vcap" sh "$ROOT/knotlog" capture < "$FIX/posttooluse.json"
assert_eq "capture: posttooluse appends one line" 'PostToolUse | Read | C:\Users\alice\projects\demo\taskbar_overflow.png' "$(log_line "$TMP/vcap")"

t; printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_response":{"file_path":"TUZAK.md"},"tool_input":{"file_path":"dogru.md"}}' | QUIPU_VAULT="$TMP/vcap" sh "$ROOT/knotlog" capture
assert_eq "capture: scoped path beats tool_response trap" 'PostToolUse | Read | dogru.md' "$(log_line "$TMP/vcap")"

# 448 KB payload (big.json pattern) plus a trap file_path past the 64 KB bound.
printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"big/target.md"},"tool_response":"base64:' > "$TMP/bigcap.json"
awk 'BEGIN{for(i=0;i<7000;i++) printf "0000000000000000000000000000000000000000000000000000000000000000"}' >> "$TMP/bigcap.json"
printf '%s' '","trap":{"file_path":"C:\Users\x\trap.md"}}' >> "$TMP/bigcap.json"
t; START=$(date +%s)
QUIPU_VAULT="$TMP/vcap" sh "$ROOT/knotlog" capture < "$TMP/bigcap.json"
END=$(date +%s)
assert_eq "capture: 448 KB payload returns first scoped path" 'PostToolUse | Read | big/target.md' "$(log_line "$TMP/vcap")"
t; assert_eq "capture: 448 KB payload bounded time" 'yes' "$([ $((END - START)) -lt 30 ] && printf yes || printf no)"

mkvault vcapctl
t; printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"a\nb\tc\rd"}}' | QUIPU_VAULT="$TMP/vcapctl" sh "$ROOT/knotlog" capture
assert_eq "capture: control bytes in path stay on one line" '1' "$(awk 'END{print NR}' "$TMP/vcapctl/.knotlog/activity.log")"
t; assert_eq "capture: control bytes stripped from path" 'PostToolUse | Read | abcd' "$(log_line "$TMP/vcapctl")"

t; QUIPU_VAULT="$TMP/vcap" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path 500-Knowledge/not.md
assert_eq "capture: flag mode appends line" 'PostToolUse | Edit | 500-Knowledge/not.md' "$(log_line "$TMP/vcap")"

t
# literal $HOME in the single-quoted JSON is the test payload (test data, not expansion).
# shellcheck disable=SC2016
printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"C:\\Users\\x$HOME\\not.md"}}' | QUIPU_VAULT="$TMP/vcap" sh "$ROOT/knotlog" capture
# literal $HOME in the expected value is part of the same test.
# shellcheck disable=SC2016
assert_eq "capture: dollar in path preserved literally" 'PostToolUse | Read | C:\Users\x$HOME\not.md' "$(log_line "$TMP/vcap")"

mkvault vcaprot
t; LONGPATH=$(awk 'BEGIN{for(i=0;i<200;i++) printf "x"}')
QUIPU_VAULT="$TMP/vcaprot" QUIPU_LOG_MAX=100 sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path "$LONGPATH"
QUIPU_VAULT="$TMP/vcaprot" QUIPU_LOG_MAX=100 sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path two.md
assert_eq "capture: rotation creates activity.log.1" 'yes' "$([ -f "$TMP/vcaprot/.knotlog/activity.log.1" ] && printf yes || printf no)"
t; assert_eq "capture: rotated log keeps one line" '1' "$(awk 'END{print NR}' "$TMP/vcaprot/.knotlog/activity.log")"
t; assert_eq "capture: rotated log has latest entry" 'PostToolUse | Edit | two.md' "$(log_line "$TMP/vcaprot")"

# ---- capture: multi-schema apply_patch (FAZ 4) ----

mkvault vcodex
t; QUIPU_VAULT="$TMP/vcodex" sh "$ROOT/knotlog" capture < "$FIX/codex-apply-patch.json"
assert_eq "capture: apply_patch single file logs one row" 'PostToolUse | apply_patch | alice/demo/not.md' "$(log_line "$TMP/vcodex")"

mkvault vcodexm
t; QUIPU_VAULT="$TMP/vcodexm" sh "$ROOT/knotlog" capture < "$FIX/codex-apply-patch-multi.json"
MLINES=$(awk '{ i=index($0," | "); print substr($0,i+3) }' "$TMP/vcodexm/.knotlog/activity.log")
assert_eq "capture: native apply_patch keeps Unicode/spaces, ignores content headers, and deduplicates paths" 'PostToolUse | apply_patch | alice/demo/İstanbul notu.md
PostToolUse | apply_patch | alice/demo/a file.md' "$MLINES"

mkvault vcodexd
t; QUIPU_VAULT="$TMP/vcodexd" sh "$ROOT/knotlog" capture < "$FIX/codex-apply-patch-delete.json"
assert_eq "capture: native apply_patch Delete File logs the deleted path" 'PostToolUse | apply_patch | alice/demo/gone.md' "$(log_line "$TMP/vcodexd")"

mkvault vcodexmv
t; QUIPU_VAULT="$TMP/vcodexmv" sh "$ROOT/knotlog" capture < "$FIX/codex-apply-patch-move.json"
MVLINES=$(awk '{ i=index($0," | "); print substr($0,i+3) }' "$TMP/vcodexmv/.knotlog/activity.log")
assert_eq "capture: native apply_patch move logs source and destination" 'PostToolUse | apply_patch | alice/demo/old name.md
PostToolUse | apply_patch | alice/demo/new name.md' "$MVLINES"

mkvault vcodexlegacy
t; QUIPU_VAULT="$TMP/vcodexlegacy" sh "$ROOT/knotlog" capture < "$FIX/codex-apply-patch-legacy.json"
LEGLINES=$(awk '{ i=index($0," | "); print substr($0,i+3) }' "$TMP/vcodexlegacy/.knotlog/activity.log")
assert_eq "capture: legacy unified-diff payload remains supported" 'PostToolUse | apply_patch | alice/demo/legacy-a.md
PostToolUse | apply_patch | alice/demo/legacy-b.md' "$LEGLINES"

mkvault vcodextrap
t; QUIPU_VAULT="$TMP/vcodextrap" sh "$ROOT/knotlog" capture < "$FIX/codex-apply-patch-trap.json"
assert_eq "capture: missing tool_input command never falls through to tool_response traps" 'no' "$([ -s "$TMP/vcodextrap/.knotlog/activity.log" ] && printf yes || printf no)"

mkvault vcodexctl
t; printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: alice/demo/a\tb\rc.md\n+x\n*** End Patch"},"tool_response":{"success":true}}' | QUIPU_VAULT="$TMP/vcodexctl" sh "$ROOT/knotlog" capture
assert_eq "capture: native apply_patch strips path control bytes without adding log lines" 'PostToolUse | apply_patch | alice/demo/abc.md' "$(log_line "$TMP/vcodexctl")"

mkvault vcodextrunc
t; printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: alice/demo/truncated.md\n+x"}}' | QUIPU_VAULT="$TMP/vcodextrunc" sh "$ROOT/knotlog" capture
assert_eq "capture: truncated native apply_patch envelope emits no rows" 'no' "$([ -s "$TMP/vcodextrunc/.knotlog/activity.log" ] && printf yes || printf no)"

mkvault vcodexr
t; QUIPU_VAULT="$TMP/vcodexr" sh "$ROOT/knotlog" capture < "$FIX/posttooluse.json"
assert_eq "capture: Claude Code payload unchanged (regression)" 'PostToolUse | Read | C:\Users\alice\projects\demo\taskbar_overflow.png' "$(log_line "$TMP/vcodexr")"

# ---- init + context ----

t; QUIPU_VAULT="$TMP/vinit" sh "$ROOT/knotlog" init --lang tr
for _f in config index.tsv activity.log; do
  t; assert_eq "init: creates .knotlog/$_f" 'yes' "$([ -f "$TMP/vinit/.knotlog/$_f" ] && printf yes || printf no)"
done
t; assert_eq "init: config records lang=tr" 'yes' "$(grep -q '^lang=tr$' "$TMP/vinit/.knotlog/config" && printf yes || printf no)"
t; (cd "$TMP/vinit" && "$ROOT/knotlog" doctor) >"$TMP/vinit-doctor.out" 2>&1; RC=$?
assert_eq "init: doctor exits 0 in the vault" '0' "$RC"

# Second init must not duplicate the bridge block nor disturb user text.
printf '# My notes\nkeep this line\n' >> "$TMP/vinit/AGENTS.md"
t; QUIPU_VAULT="$TMP/vinit" sh "$ROOT/knotlog" init
assert_eq "init: second run preserves user text" 'yes' "$(grep -q '^keep this line$' "$TMP/vinit/AGENTS.md" && printf yes || printf no)"
t; CNT=$(grep -c 'knotlog:start' "$TMP/vinit/AGENTS.md")
assert_eq "init: second run does not duplicate bridge block" '1' "$CNT"
t;
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Read | C:\Users\alice\demo\taskbar.png' >> "$TMP/vinit/.knotlog/activity.log"

# context --json round-trips back to the plain output.
# The two calls render their own wall clock; a minute boundary between them is
# legitimate, so the now-line (en "now: ", tr "şimdi: ") is stripped from both
# sides, as T-44 does below.
printf '2026-08-20T10:00 | PostToolUse | Read | not.md\n' >> "$TMP/vinit/.knotlog/activity.log"
t; PLAIN=$(QUIPU_VAULT="$TMP/vinit" sh "$ROOT/knotlog" context | sed '/^now: /d; /^şimdi: /d')
JSON=$(QUIPU_VAULT="$TMP/vinit" sh "$ROOT/knotlog" context --json SessionStart)
DECODED=$(printf '%s' "$JSON" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" - | sed '/^now: /d; /^şimdi: /d')
assert_eq "context: --json round-trips to plain output" "$PLAIN" "$DECODED"

# Empty vault: context exits 0 without crashing.
mkdir -p "$TMP/vempty/.knotlog"
: > "$TMP/vempty/.knotlog/config"
t; (cd "$TMP/vempty" && "$ROOT/knotlog" context) >"$TMP/vempty.out" 2>&1; RC=$?
assert_eq "context: empty vault exits 0" '0' "$RC"

# init without an AGENTS.md creates it with the bridge heading.
t; QUIPU_VAULT="$TMP/vagents" sh "$ROOT/knotlog" init
assert_eq "init: creates AGENTS.md when absent" 'yes' "$([ -f "$TMP/vagents/AGENTS.md" ] && printf yes || printf no)"
t; assert_eq "init: AGENTS.md contains bridge heading" 'yes' "$(grep -q '^## knotlog$' "$TMP/vagents/AGENTS.md" && printf yes || printf no)"
# ---- FAZ 2: layout + identity ----

t; BAD=$(awk 'index($0, sprintf("%c", 92)) != 0 { print FILENAME ":" NR }' "$ROOT/layout"/*.txt "$ROOT/persona"/*.md)
assert_eq "no literal backslash in layout and persona data" '' "$BAD"

SL1=$(awk -F"$TAB" '$0 !~ /^#/ && NF >= 2 {print $1}' "$ROOT/layout/emoji.txt")
SL2=$(awk -F"$TAB" '$0 !~ /^#/ && NF >= 2 {print $1}' "$ROOT/layout/plain.txt")
t; assert_eq "layout files share identical slug columns" "$SL1" "$SL2"
SL3=$(awk -F"$TAB" '$0 !~ /^#/ && NF >= 2 {print $1}' "$ROOT/layout/tr.txt")
SL4=$(awk -F"$TAB" '$0 !~ /^#/ && NF >= 2 {print $1}' "$ROOT/layout/en.txt")
t; assert_eq "layout: tr keeps the canonical slug column" "$SL1" "$SL3"
t; assert_eq "layout: en keeps the canonical slug column" "$SL1" "$SL4"

KTR=$(awk -F= 'NF >= 1 && $1 !~ /^#/ {print $1}' "$ROOT/i18n/tr.txt" | sort)
KEN=$(awk -F= 'NF >= 1 && $1 !~ /^#/ {print $1}' "$ROOT/i18n/en.txt" | sort)
t; assert_eq "i18n tr/en key sets identical" "$KEN" "$KTR"

mkvault vexcl
: > "$TMP/vexcl/CLAUDE.md"
printf '# Not\n' > "$TMP/vexcl/not.md"
t; (cd "$TMP/vexcl" && "$ROOT/knotlog" index) >/dev/null 2>&1
assert_eq "index: CLAUDE.md excluded, not.md indexed" '1' "$(awk 'END{print NR}' "$TMP/vexcl/.knotlog/index.tsv")"
t; assert_eq "index: CLAUDE.md has no row" '' "$(awk -F"$TAB" 'index($1, "CLAUDE.md") {print $1}' "$TMP/vexcl/.knotlog/index.tsv")"
layout_names() { # emoji|plain -> one folder name per line
  awk -F"$TAB" '$0 !~ /^#/ && NF >= 2 {print $2}' "$ROOT/layout/$1.txt"
}
comp_name() { # emoji|plain -> companion folder name
  awk -F"$TAB" '$1=="companion"{print $2;exit}' "$ROOT/layout/$1.txt"
}
cmd_name() { # emoji|plain -> command-center folder name
  awk -F"$TAB" '$1=="command"{print $2;exit}' "$ROOT/layout/$1.txt"
}

mkvault vlay
QUIPU_VAULT="$TMP/vlay" QUIPU_LANG=en sh "$ROOT/knotlog" init

t; FAILED=$(layout_names emoji | while IFS= read -r _n; do
  if [ -d "$TMP/vlay/$_n" ] && [ -f "$TMP/vlay/$_n/.gitkeep" ]; then :; else printf '%s\n' "$_n"; fi
done)
assert_eq "init: every emoji layout folder has .gitkeep" '' "$FAILED"

mkvault vplain
QUIPU_VAULT="$TMP/vplain" sh "$ROOT/knotlog" init --plain
t; MISSD=$(layout_names plain | while IFS= read -r _n; do
  [ -d "$TMP/vplain/$_n" ] || printf '%s\n' "$_n"
done)
assert_eq "init --plain: every plain layout folder exists" '' "$MISSD"
t; GOT=$(cd "$TMP/vplain" && find . -maxdepth 1 -mindepth 1 -type d ! -name .knotlog ! -name .git | cut -c3- | sort)
assert_eq "init --plain: no unexpected top-level folders" "$(layout_names plain | awk -F/ '{print $1}' | sort -u)" "$GOT"
t; BAD=$( (cd "$TMP/vplain" && find . -maxdepth 1 -mindepth 1 -type d ! -name .knotlog ! -name .git) | LC_ALL=C grep '[^ -~]' || true)
assert_eq "init --plain: folder names contain no non-ASCII bytes" '' "$BAD"
t; assert_eq "init --plain: config records layout=plain" 'yes' "$(grep -q '^layout=plain$' "$TMP/vplain/.knotlog/config" && printf yes || printf no)"

# ---- localized number-free layouts (tr/en) ----

mkvault vtr
QUIPU_VAULT="$TMP/vtr" QUIPU_LANG=en sh "$ROOT/knotlog" init --layout tr >/dev/null 2>&1; RC=$?
t; assert_eq "init --layout tr: exits 0" '0' "$RC"
t; assert_eq "init --layout tr: config records layout=tr" 'yes' "$(grep -q '^layout=tr$' "$TMP/vtr/.knotlog/config" && printf yes || printf no)"
t; MISTR=$(layout_names tr | while IFS= read -r _n; do
  if [ -d "$TMP/vtr/$_n" ] && [ -f "$TMP/vtr/$_n/.gitkeep" ]; then :; else printf '%s\n' "$_n"; fi
done)
assert_eq "init --layout tr: every localized folder has .gitkeep" '' "$MISTR"
t; GOTTR=$(cd "$TMP/vtr" && find . -maxdepth 1 -mindepth 1 -type d ! -name .knotlog ! -name .git | cut -c3- | sort)
assert_eq "init --layout tr: exactly ten localized top-level folders" \
  "$(layout_names tr | awk -F/ '{print $1}' | sort -u)" "$GOTTR"
t; NODIGIT=$(printf '%s' "$GOTTR" | LC_ALL=C grep '[0-9]' || true)
assert_eq "init --layout tr: top-level folders are number-free" '' "$NODIGIT"
t; TRDUMP=$(awk -F"$TAB" '$1=="dump"{print $2}' "$ROOT/layout/tr.txt")
assert_eq "init --layout tr: Dump is a top-level Trash, not under the inbox" 'yes' \
  "$([ -d "$TMP/vtr/$TRDUMP" ] && [ "$(dirname "$TRDUMP")" = . ] && printf yes || printf no)"

mkvault ven
QUIPU_VAULT="$TMP/ven" QUIPU_LANG=en sh "$ROOT/knotlog" init --layout en >/dev/null 2>&1; RC=$?
t; assert_eq "init --layout en: exits 0" '0' "$RC"
t; assert_eq "init --layout en: config records layout=en" 'yes' "$(grep -q '^layout=en$' "$TMP/ven/.knotlog/config" && printf yes || printf no)"
t; MISEN=$(layout_names en | while IFS= read -r _n; do
  if [ -d "$TMP/ven/$_n" ] && [ -f "$TMP/ven/$_n/.gitkeep" ]; then :; else printf '%s\n' "$_n"; fi
done)
assert_eq "init --layout en: every localized folder has .gitkeep" '' "$MISEN"

mkvault vlaybad
t; QUIPU_VAULT="$TMP/vlaybad" QUIPU_LANG=en sh "$ROOT/knotlog" init --layout fr \
  >/dev/null 2>"$TMP/vlaybad.err"; RC=$?
assert_eq "init --layout fr: unknown layout exits 2" '2' "$RC"
t; assert_eq "init --layout fr: validation precedes any vault writes" 'yes' \
  "$([ ! -f "$TMP/vlaybad/.knotlog/index.tsv" ] \
     && ! grep -q '^layout=' "$TMP/vlaybad/.knotlog/config" && printf yes || printf no)"
t; QUIPU_VAULT="$TMP/vlaybad" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --layout tr \
  >/dev/null 2>&1; RC=$?
assert_eq "init --plain --layout tr: flag conflict exits 2" '2' "$RC"

mkvault vlaycfl
printf 'layout=emoji\n' > "$TMP/vlaycfl/.knotlog/config"
t; QUIPU_VAULT="$TMP/vlaycfl" QUIPU_LANG=en sh "$ROOT/knotlog" init --layout tr \
  >/dev/null 2>"$TMP/vlaycfl.err"; RC=$?
assert_eq "init --layout tr on emoji-config vault exits 2" '2' "$RC"
t; assert_eq "init --layout tr on emoji-config vault keeps config value" 'yes' \
  "$(grep -q '^layout=emoji$' "$TMP/vlaycfl/.knotlog/config" && printf yes || printf no)"

t; assert_eq "init: config records layout=emoji" 'yes' "$(grep -q '^layout=emoji$' "$TMP/vlay/.knotlog/config" && printf yes || printf no)"
t; assert_eq "init --plain: config records layout=plain" 'yes' "$(grep -q '^layout=plain$' "$TMP/vplain/.knotlog/config" && printf yes || printf no)"

D0=$(find "$TMP/vlay" -type d | wc -l | tr -d ' ')
QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" init --plain >"$TMP/vlay-conflict.out" 2>&1; RC=$?
t; assert_eq "init --plain on emoji vault exits 2" '2' "$RC"
t; assert_eq "init --plain conflict changes no folders" "$D0" "$(find "$TMP/vlay" -type d | wc -l | tr -d ' ')"

D0=$(find "$TMP/vlay" -type d | wc -l | tr -d ' ')
K0=$(find "$TMP/vlay" -name .gitkeep | wc -l | tr -d ' ')
QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" init >/dev/null 2>&1
t; assert_eq "init: second run keeps folder count" "$D0" "$(find "$TMP/vlay" -type d | wc -l | tr -d ' ')"
t; assert_eq "init: second run keeps .gitkeep count" "$K0" "$(find "$TMP/vlay" -name .gitkeep | wc -l | tr -d ' ')"

t; assert_eq "init: companion.md created and non-empty" 'yes' "$([ -s "$TMP/vlay/$(comp_name emoji)/companion.md" ] && printf yes || printf no)"

printf 'user marker 7\n' >> "$TMP/vlay/$(comp_name emoji)/companion.md"
QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" init >/dev/null 2>&1
t; assert_eq "init: user companion.md edits preserved" 'yes' "$(grep -q '^user marker 7$' "$TMP/vlay/$(comp_name emoji)/companion.md" && printf yes || printf no)"

mkvault vlaytr
QUIPU_VAULT="$TMP/vlaytr" sh "$ROOT/knotlog" init --lang tr >/dev/null 2>&1
t; assert_eq "init --lang tr: companion.md from Turkish persona" 'yes' "$(grep -q 'Üslup' "$TMP/vlaytr/$(comp_name emoji)/companion.md" && printf yes || printf no)"

# CLAUDE.md used to carry a thin "see AGENTS.md" pointer. It now carries the
# SAME protocol body as AGENTS.md, so a Claude session and a Codex session read
# identical instructions without either having to open the other's file.
# Asserted as byte-identical blocks: a pointer, a truncated copy, or a drifted
# copy all fail here.
t; assert_eq "init: CLAUDE.md carries the full bridge body, not a pointer" 'yes' \
  "$([ -f "$TMP/vlay/CLAUDE.md" ] && grep -q 'knotlog:start' "$TMP/vlay/CLAUDE.md" \
     && grep -q '^## knotlog$' "$TMP/vlay/CLAUDE.md" \
     && ! grep -q 'See AGENTS.md for vault layout' "$TMP/vlay/CLAUDE.md" \
     && printf yes || printf no)"
t; assert_eq "init: AGENTS.md and CLAUDE.md bridge blocks are byte-identical" 'yes' \
  "$(sed -n '/knotlog:start/,/knotlog:end/p' "$TMP/vlay/AGENTS.md" > "$TMP/br-a.txt"
     sed -n '/knotlog:start/,/knotlog:end/p' "$TMP/vlay/CLAUDE.md" > "$TMP/br-c.txt"
     cmp -s "$TMP/br-a.txt" "$TMP/br-c.txt" && printf yes || printf no)"

mkvault vclau
printf 'user claude text\nkeep this too\n' > "$TMP/vclau/CLAUDE.md"
QUIPU_VAULT="$TMP/vclau" sh "$ROOT/knotlog" init >/dev/null 2>&1
QUIPU_VAULT="$TMP/vclau" sh "$ROOT/knotlog" init >/dev/null 2>&1
t; assert_eq "init: pre-existing CLAUDE.md text preserved" 'yes' "$(grep -q '^keep this too$' "$TMP/vclau/CLAUDE.md" && printf yes || printf no)"
t; assert_eq "init: CLAUDE.md block not duplicated" '1' "$(grep -c 'knotlog:start' "$TMP/vclau/CLAUDE.md")"

t; MISS=$(layout_names emoji | while IFS= read -r _n; do
  awk -v s="$_n" 'index($0, s) {found=1} END {exit !found}' "$TMP/vlay/AGENTS.md" || printf '%s\n' "$_n"
done)
assert_eq "init: AGENTS.md block lists every layout folder" '' "$MISS"

t; assert_eq "init: Threads.md seeded" 'yes' "$([ -f "$TMP/vlay/Threads.md" ] && printf yes || printf no)"
TITLE=$(awk -F= -v k=threads_seed_title '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
NOTE=$(awk -F= -v k=threads_seed_note '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
CTX=$(QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" context)
t; assert_eq "context: prints threads section and seed" 'yes' "$(printf '%s\n' "$CTX" | grep -q "$TITLE" && printf '%s\n' "$CTX" | grep -q "$NOTE" && printf yes || printf no)"

printf 'user thread marker\n' >> "$TMP/vlay/Threads.md"
QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" init >/dev/null 2>&1
t; assert_eq "init: user Threads.md lines preserved" 'yes' "$(grep -q '^user thread marker$' "$TMP/vlay/Threads.md" && printf yes || printf no)"

DTITLE=$(awk -F= -v k=dashboard_seed_title '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
DNOTE=$(awk -F= -v k=dashboard_seed_note '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
t; assert_eq "init: Dashboard.md seeded from i18n title and note" 'yes' "$([ -f "$TMP/vlay/$(cmd_name emoji)/Dashboard.md" ] && grep -qF "$DTITLE" "$TMP/vlay/$(cmd_name emoji)/Dashboard.md" && grep -qF "$DNOTE" "$TMP/vlay/$(cmd_name emoji)/Dashboard.md" && printf yes || printf no)"

printf 'user dashboard marker\n' >> "$TMP/vlay/$(cmd_name emoji)/Dashboard.md"
QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" init >/dev/null 2>&1
t; assert_eq "init: user Dashboard.md lines preserved" 'yes' "$(grep -q '^user dashboard marker$' "$TMP/vlay/$(cmd_name emoji)/Dashboard.md" && printf yes || printf no)"

QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" index >/dev/null 2>&1
t; assert_eq "index: companion.md has a row" 'yes' "$(awk -F"$TAB" 'index($1, "companion.md") {print "yes"; exit}' "$TMP/vlay/.knotlog/index.tsv")"
t; assert_eq "index: companion.md path uses emoji folder" 'yes' "$(awk -F"$TAB" -v n="$(comp_name emoji)" 'index($1, "companion.md") && index($1, n) {print "yes"; exit}' "$TMP/vlay/.knotlog/index.tsv")"

P=$(QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" search Boundaries --paths)
t; assert_eq "search: finds companion.md content" 'yes' "$(printf '%s\n' "$P" | grep -q 'companion.md' && printf yes || printf no)"
t; assert_eq "search --paths: prints emoji folder path" 'yes' "$(printf '%s\n' "$P" | awk -v s="$(comp_name emoji)" 'index($0, s) {found=1} END {exit !found}' && printf yes || printf no)"

TARGET="$(comp_name emoji)/not.md"
QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path "$TARGET"
t; assert_eq "capture: emoji-folder path logged intact" 'yes' "$(awk -v s="$TARGET" 'index($0, s) {found=1} END {exit !found}' "$TMP/vlay/.knotlog/activity.log" && printf yes || printf no)"
CTX=$(QUIPU_VAULT="$TMP/vlay" sh "$ROOT/knotlog" context)
t; assert_eq "context: prints emoji-folder capture path" 'yes' "$(printf '%s\n' "$CTX" | awk -v s="$TARGET" 'index($0, s) {found=1} END {exit !found}' && printf yes || printf no)"

mkvault vfresh
QUIPU_VAULT="$TMP/vfresh" sh "$ROOT/knotlog" init >/dev/null 2>&1
t; (cd "$TMP/vfresh" && QUIPU_LANG=en "$ROOT/knotlog" doctor) >"$TMP/vfresh.out" 2>&1; RC=$?
assert_eq "doctor: fresh emoji vault exits 0" '0' "$RC"

mkvault vfreshp
QUIPU_VAULT="$TMP/vfreshp" sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
t; (cd "$TMP/vfreshp" && QUIPU_LANG=en "$ROOT/knotlog" doctor) >"$TMP/vfreshp.out" 2>&1; RC=$?
assert_eq "doctor: fresh --plain vault exits 0" '0' "$RC"

t; assert_eq "doctor: layout line shows emoji" 'yes' "$(awk -F"$TAB" '$2=="layout" && $3=="emoji" {print "yes"; exit}' "$TMP/vfresh.out")"
t; assert_eq "doctor: layout line shows plain" 'yes' "$(awk -F"$TAB" '$2=="layout" && $3=="plain" {print "yes"; exit}' "$TMP/vfreshp.out")"
# doctor: the OneDrive install-path warning must not depend on a vault existing.
ODH="$TMP/OneDrive-home"
mkdir -p "$ODH"
cp "$ROOT/knotlog" "$ODH/"
cp -r "$ROOT/lib" "$ROOT/i18n" "$ROOT/fold" "$ROOT/layout" "$ROOT/persona" "$ODH/"
mkdir -p "$TMP/odwork"
t; OUT=$( (cd "$TMP/odwork" && sh "$ODH/knotlog" doctor) 2>&1 )
assert_eq "doctor: OneDrive install path warns with no vault" 'yes' \
  "$(printf '%s\n' "$OUT" | grep -q OneDrive && printf yes || printf no)"
t; OUT=$( (cd "$TMP/vfreshp" && sh "$ODH/knotlog" doctor) 2>&1 )
assert_eq "doctor: plain layout suppresses the OneDrive warning" 'no' \
  "$(printf '%s\n' "$OUT" | grep -q OneDrive && printf yes || printf no)"

# ---- index ----

mk_index_vault() { # dir
  mkdir -p "$TMP/$1/.knotlog"
  cat > "$TMP/$1/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
  cat > "$TMP/$1/fm.md" <<'EOF'
---
title: Frontmatter Başlık
tags: alpha beta
---
# Frontmatter Başlık
Frontmatter body.
EOF
  cat > "$TMP/$1/heading.md" <<'EOF'
# Başlık
Heading body.
EOF
  cat > "$TMP/$1/turkce.md" <<'EOF'
İstanbul çalışma üzerine.
EOF
}

idx_nums() { # summary-file -> "N R S D"
  awk '{ gsub(/[^0-9]/," "); s=""; for (i=1;i<=NF;i++) if ($i!="") s=s (s==""?"":" ") $i; print s }' "$1"
}

mk_index_vault idx1

t; (cd "$TMP/idx1" && "$ROOT/knotlog" index) >"$TMP/idx1.out" 2>&1; RC=$?
assert_eq "index: first run exits 0" '0' "$RC"
t; assert_eq "index: first run writes 3 rows" '3' "$(awk 'END{print NR}' "$TMP/idx1/.knotlog/index.tsv")"
t; assert_eq "T-131: index: every row has 8 columns" 'yes' "$(awk -F'\t' '{if (NF != 8) bad++} END{print (bad ? "no" : "yes")}' "$TMP/idx1/.knotlog/index.tsv")"
t; assert_eq "index: first run counts" '3 0 3 0' "$(idx_nums "$TMP/idx1.out")"

sleep 1
touch "$TMP/idx1/heading.md"
t; (cd "$TMP/idx1" && "$ROOT/knotlog" index) >"$TMP/idx1.out" 2>&1
assert_eq "index: touch one file reuses 2, stale 1" '3 2 1 0' "$(idx_nums "$TMP/idx1.out")"

rm "$TMP/idx1/fm.md"
t; (cd "$TMP/idx1" && "$ROOT/knotlog" index) >"$TMP/idx1.out" 2>&1
assert_eq "index: delete one file leaves 2 rows" '2' "$(awk 'END{print NR}' "$TMP/idx1/.knotlog/index.tsv")"
t; assert_eq "index: delete one file drops 1" '2 2 0 1' "$(idx_nums "$TMP/idx1.out")"

t; assert_eq "index: folded field contains calisma" 'yes' "$(awk -F'\t' '$1=="turkce.md" {print (index($5,"calisma")>0) ? "yes" : "no"}' "$TMP/idx1/.knotlog/index.tsv")"
t; assert_eq "index: folded field drops raw çalışma" 'no' "$(awk -F'\t' '$1=="turkce.md" {print (index($5,"çalışma")>0) ? "yes" : "no"}' "$TMP/idx1/.knotlog/index.tsv")"

mk_index_vault idxfull
t; (cd "$TMP/idxfull" && "$ROOT/knotlog" index) >/dev/null 2>&1
(cd "$TMP/idxfull" && "$ROOT/knotlog" index --full) >"$TMP/idxfull.out" 2>&1
assert_eq "index: --full regenerates all rows" '3 0 3 0' "$(idx_nums "$TMP/idxfull.out")"

mkdir -p "$TMP/idxemoji/.knotlog"
: > "$TMP/idxemoji/.knotlog/config"
mkdir -p "$TMP/idxemoji/🔮 notlar"
cat > "$TMP/idxemoji/🔮 notlar/d.md" <<'EOF'
# Not
emoji folder.
EOF
t; (cd "$TMP/idxemoji" && "$ROOT/knotlog" index) >"$TMP/idxemoji.out" 2>&1; RC=$?
assert_eq "index: emoji folder doc indexed (exits 0)" '0' "$RC"
t; assert_eq "index: emoji folder path preserved" '🔮 notlar/d.md' "$(awk -F'\t' 'NR==1 {print $1}' "$TMP/idxemoji/.knotlog/index.tsv")"

mk_index_vault idxlang
t; (cd "$TMP/idxlang" && QUIPU_LANG=en "$ROOT/knotlog" index) >"$TMP/idxlang.out" 2>&1
# idx_summary is the controlled i18n template (not user data); args are integers.
# shellcheck disable=SC2059
EXPECT=$(printf "$(awk -F= -v k=idx_summary '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")" 3 0 3 0)
assert_eq "index: summary uses i18n idx_summary template" "$EXPECT" "$(cat "$TMP/idxlang.out")"

mkdir -p "$TMP/idxempty/.knotlog"
: > "$TMP/idxempty/.knotlog/config"
t; (cd "$TMP/idxempty" && "$ROOT/knotlog" index) >"$TMP/idxempty.out" 2>&1; RC=$?
assert_eq "index: empty vault exits 0" '0' "$RC"
t; assert_eq "index: empty vault counts" '0 0 0 0' "$(idx_nums "$TMP/idxempty.out")"

# ---- FAZ 10: index schema — status/type + 7-column migration (T-130..T-133) ----

# T-130: mode=meta reads status:/type: from frontmatter; absent -> empty field.
mkdir -p "$TMP/t130"
cat > "$TMP/t130/note.md" <<'EOF'
---
title: T130 Note
tags: alpha
status: active
type: task
---
body here
EOF
cat > "$TMP/t130/note2.md" <<'EOF'
---
title: T130 No Status
tags: beta
---
body
EOF
t; META=$(cd "$TMP/t130" && awk -v mode=meta -f "$LIB/index.awk" note.md)
assert_eq "T-130: mode=meta reads status/type from frontmatter" "T130 Note${TAB}alpha${TAB}active${TAB}task" "$META"
t; META2=$(cd "$TMP/t130" && awk -v mode=meta -f "$LIB/index.awk" note2.md)
assert_eq "T-130: mode=meta: missing status/type -> empty field" "T130 No Status${TAB}beta${TAB}${TAB}" "$META2"

# T-132: a pre-FAZ10 (5-column) index.tsv is treated as fully stale — the
# schema difference is self-detected, no --full ask, and the rebuilt file is
# 7 columns wide.
mkdir -p "$TMP/idxschema/.knotlog"
printf 'fold=tr\nlang=en\n' > "$TMP/idxschema/.knotlog/config"
printf '# Doc One\nbody one\n' > "$TMP/idxschema/one.md"
printf '# Doc Two\nbody two\n' > "$TMP/idxschema/two.md"
printf 'one.md\tDoc One\t\t111\told-flat-one\n' > "$TMP/idxschema/.knotlog/index.tsv"
printf 'two.md\tDoc Two\t\t222\told-flat-two\n' >> "$TMP/idxschema/.knotlog/index.tsv"
t; (cd "$TMP/idxschema" && "$ROOT/knotlog" index) >"$TMP/idxschema.out" 2>&1
assert_eq "T-132: legacy 5-col index.tsv -> all rows stale" '2 0 2 0' "$(idx_nums "$TMP/idxschema.out")"
t; assert_eq "T-132: rebuilt index.tsv rows have 8 columns" 'yes' "$(awk -F'\t' '{if (NF != 8) bad++} END{print (bad ? "no" : "yes")}' "$TMP/idxschema/.knotlog/index.tsv")"

# T-133: doctor warns doc_index_schema on a 5-column index.tsv and still
# exits 0 (mirror of the doc_index_stale pattern).
mkdir -p "$TMP/docschema/.knotlog"
: > "$TMP/docschema/.knotlog/config"
printf 'one.md\tTitle\t\t111\tflat\n' > "$TMP/docschema/.knotlog/index.tsv"
t; DOUT=$( (cd "$TMP/docschema" && QUIPU_LANG=en "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
assert_eq "T-133: doctor exits 0 on legacy index schema" '0' "$RC"
# i18n() is defined later in this file; look the key up inline here (same
# pattern as the idx_summary check above) so definition order never matters.
DISCHEMA=$(awk -F= -v k=doc_index_schema '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
t; assert_eq "T-133: doctor warns doc_index_schema" 'yes' "$(printf '%s\n' "$DOUT" | awk -F"$TAB" -v m="$DISCHEMA" '$2=="index" && $3==m {print "yes"; exit}')"

# ---- search ----

mk_search_vault() { # dir
  mkdir -p "$TMP/$1/.knotlog"
  cat > "$TMP/$1/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
  printf '# notlar\n\nİstanbul üzerine notlar. Işık deneyleri burada.\n' > "$TMP/$1/istanbul-a.md"
  printf 'İstanbul ve ışık bu dosyada anlatılıyor.\n' > "$TMP/$1/istanbul-b.md"
  printf 'Çalışma notları ve günlük plan.\n' > "$TMP/$1/calisma-a.md"
  printf 'Bu dosyada çalışma düzeni var.\n' > "$TMP/$1/calisma-b.md"
  printf '# alpha\nalpha appears in the body too.\n' > "$TMP/$1/title-doc.md"
  printf '# beta\nalpha appears in the body as well.\n' > "$TMP/$1/body-doc.md"
}

mk_search_vault searchv
QUIPU_VAULT="$TMP/searchv" sh "$ROOT/knotlog" index >/dev/null 2>&1

# §4.2 live check. A raw `grep -i` over these docs returns 1/2, 1/2, 0/2 for
# İstanbul / IŞIK / çalışma (the Turkish folding gap); folded search is 2/2.
t; assert_eq "search İstanbul returns 2/2" '2' "$(QUIPU_VAULT="$TMP/searchv" sh "$ROOT/knotlog" search İstanbul | awk 'END{print NR}')"
t; assert_eq "search IŞIK returns 2/2" '2' "$(QUIPU_VAULT="$TMP/searchv" sh "$ROOT/knotlog" search IŞIK | awk 'END{print NR}')"
t; assert_eq "search çalışma returns 2/2" '2' "$(QUIPU_VAULT="$TMP/searchv" sh "$ROOT/knotlog" search çalışma | awk 'END{print NR}')"

# A title match ranks ahead of a body-only match.
t; FIRST=$(QUIPU_VAULT="$TMP/searchv" sh "$ROOT/knotlog" search alpha | awk 'NR==1{print $2}')
assert_eq "search ranks title match first" 'title-doc.md' "$FIRST"

# --limit and --paths shapes.
t; assert_eq "search --limit 1 returns one line" '1' "$(QUIPU_VAULT="$TMP/searchv" sh "$ROOT/knotlog" search çalışma --limit 1 | awk 'END{print NR}')"
t; PATHS=$(QUIPU_VAULT="$TMP/searchv" sh "$ROOT/knotlog" search çalışma --paths | sort)
assert_eq "search --paths prints only the two paths" 'calisma-a.md
calisma-b.md' "$PATHS"
t; assert_eq "search --paths lines have no TAB" '' "$(printf '%s\n' "$PATHS" | awk 'index($0, sprintf("%c", 9)) != 0 { print NR }')"

# Empty query is a usage error; an unmatched query is empty but successful.
t; QUIPU_VAULT="$TMP/searchv" sh "$ROOT/knotlog" search >"$TMP/search-empty.out" 2>&1; RC=$?
assert_eq "search empty query exits 2" '2' "$RC"
t; OUT=$(QUIPU_VAULT="$TMP/searchv" sh "$ROOT/knotlog" search xyzzy); RC=$?
assert_eq "search no-match exits 0" '0' "$RC"
t; assert_eq "search no-match empty output" '' "$OUT"

# ---- FAZ 10: search --tag / --status (T-134..T-138) ----

mk_tag_vault() { # dir
  mkdir -p "$TMP/$1/.knotlog"
  cat > "$TMP/$1/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
  cat > "$TMP/$1/alpha-active.md" <<'EOF'
---
title: Alpha Active
tags: alpha, common
status: active
type: task
---
common word appears here.
EOF
  cat > "$TMP/$1/beta-closed.md" <<'EOF'
---
title: Beta Closed
tags: beta, common
status: closed
type: task
---
common word appears here too.
EOF
  cat > "$TMP/$1/notag.md" <<'EOF'
---
title: No Tag
---
common word appears here without any tag or status.
EOF
  cat > "$TMP/$1/istanbul.md" <<'EOF'
---
title: Istanbul Doc
tags: İstanbul
---
ortak kelime burada duruyor.
EOF
}

mk_tag_vault tagv
QUIPU_VAULT="$TMP/tagv" sh "$ROOT/knotlog" index >/dev/null 2>&1

# T-134: --tag alpha keeps only the tagged doc; the untagged doc drops.
t; TAGGED=$(QUIPU_VAULT="$TMP/tagv" sh "$ROOT/knotlog" search common --tag alpha --paths | sort)
assert_eq "T-134: --tag alpha returns only the tagged doc" 'alpha-active.md' "$TAGGED"

# T-135: --status narrows the same way; --tag + --status combine as AND.
t; STATUSED=$(QUIPU_VAULT="$TMP/tagv" sh "$ROOT/knotlog" search common --status closed --paths | sort)
assert_eq "T-135: --status closed returns only the closed doc" 'beta-closed.md' "$STATUSED"
t; BOTH=$(QUIPU_VAULT="$TMP/tagv" sh "$ROOT/knotlog" search common --tag common --status active --paths | sort)
assert_eq "T-135: --tag + --status combine as AND" 'alpha-active.md' "$BOTH"

# T-136: --tag + --brief: still 5 fields, snippet still <=120 bytes, rows
# come out already filtered.
t; BRIEFTAG=$(QUIPU_VAULT="$TMP/tagv" QUIPU_LANG=en sh "$ROOT/knotlog" search common --tag alpha --brief)
assert_eq "T-136: --tag + --brief keeps 5 fields" 'yes' "$(printf '%s\n' "$BRIEFTAG" | awk -F"$TAB" '{if (NF != 5) bad++} END{print (bad ? "no" : "yes")}')"
t; assert_eq "T-136: --tag + --brief snippet <=120 bytes" 'yes' "$(printf '%s\n' "$BRIEFTAG" | awk -F"$TAB" '{if (length($5) > 120) bad++} END{print (bad ? "no" : "yes")}')"
t; assert_eq "T-136: --tag + --brief rows are filtered" '1' "$(printf '%s\n' "$BRIEFTAG" | awk 'END{print NR}')"

# T-137 (FAZ 7 J-3/J-4 regression): --tag with no value -> exit 2
# err_missing_arg; unknown --tagg -> exit 2 err_unknown_flag.
t; QUIPU_VAULT="$TMP/tagv" sh "$ROOT/knotlog" search common --tag >"$TMP/tagv-noarg.out" 2>&1; RC=$?
assert_eq "T-137: --tag without a value exits 2" '2' "$RC"
t; QUIPU_VAULT="$TMP/tagv" sh "$ROOT/knotlog" search common --tagg alpha >"$TMP/tagv-unknown.out" 2>&1; RC=$?
assert_eq "T-137: --tagg (typo) exits 2" '2' "$RC"

# T-138: honest limit — a raw (unfolded) tag such as İstanbul is not found
# through a folded --tag istanbul. Not a bug: a documented limit (README).
t; HONEST=$(QUIPU_VAULT="$TMP/tagv" sh "$ROOT/knotlog" search ortak --tag istanbul --paths)
assert_eq "T-138: unfolded tag not matched by folded --tag (honest limit)" '' "$HONEST"

# ---- FAZ 10: wikilink graph (T-139, T-141; T-140 was replaced by FAZ 13's
# T-194 below — see N-6, T-190..T-198 live near the end of this file) ----

# T-139: [[hedef]] / [[hedef|ad]] / [[hedef#bölüm]] all resolve to "hedef";
# links.tsv row count matches the number of occurrences. Unit-tested directly
# against mode=links, same style as the T-130 mode=meta unit test.
mkdir -p "$TMP/t139"
cat > "$TMP/t139/note.md" <<'EOF'
---
title: Link Doc
---
See [[Target One]] and [[Target Two|Alias]] plus [[Target Three#Section]].
EOF
t; LINKS139=$(cd "$TMP/t139" && awk -v mode=links -f "$LIB/index.awk" note.md)
assert_eq "T-139: [[hedef]]/[[hedef|ad]]/[[hedef#bölüm]] all resolve to hedef" \
  "note.md${TAB}Target One
note.md${TAB}Target Two
note.md${TAB}Target Three" "$LINKS139"
t; assert_eq "T-139: links.tsv row count matches occurrence count" '3' "$(printf '%s\n' "$LINKS139" | awk 'END{print NR}')"

# T-194 (FAZ 13 N-6, replaces T-140): `knotlog links <yol>` prints
# outgoing/incoming in the right sections for a REALISTIC Obsidian
# backlink — the target note is referenced by its frontmatter TITLE
# ("Alfa Notu"), not its bare filename ("a"). Pre-FAZ13 this incoming link
# was invisible (M-1/FAZ10-KONTROL §7 kırmızı bayrak 1: `$2 == key` only
# matched a literal path, never a title); N-2's title-resolution stage now
# finds it. The old bare-filename scenario this test used to cover is not
# lost — it moved to T-197 below as an explicit backward-compat check for
# N-2 stage 1 (T-190..T-198 live near the end of this file).
mkdir -p "$TMP/linkv/.knotlog"
cat > "$TMP/linkv/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/linkv/a.md" <<'EOF'
---
title: Alfa Notu
---
# Alfa Notu
Links to [[Doc B]].
EOF
cat > "$TMP/linkv/Doc B.md" <<'EOF'
# Doc B
Links back to [[Alfa Notu]].
EOF
QUIPU_VAULT="$TMP/linkv" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1
t; LOUT140=$(QUIPU_VAULT="$TMP/linkv" QUIPU_LANG=en sh "$ROOT/knotlog" links a.md)
LOUTHDR=$(awk -F= -v k=links_out '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
LINHDR=$(awk -F= -v k=links_in '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
assert_eq "T-194: knotlog links shows a title-form incoming wikilink (M-1 fixed)" \
  "$LOUTHDR
Doc B
$LINHDR
Doc B.md" "$LOUT140"

# T-141: a broken wikilink target -> doctor warns doc_links_broken, exit 0.
mkdir -p "$TMP/brokenv/.knotlog"
: > "$TMP/brokenv/.knotlog/config"
cat > "$TMP/brokenv/a.md" <<'EOF'
# Doc A
See [[Nonexistent Note]].
EOF
QUIPU_VAULT="$TMP/brokenv" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1
t; BOUT141=$( (cd "$TMP/brokenv" && QUIPU_LANG=en "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
assert_eq "T-141: doctor exits 0 with a broken wikilink" '0' "$RC"
DLBFMT=$(awk -F= -v k=doc_links_broken '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
# shellcheck disable=SC2059
DLBMSG=$(printf "$DLBFMT" 1)
t; assert_eq "T-141: doctor warns doc_links_broken" 'yes' "$(printf '%s\n' "$BOUT141" | awk -F"$TAB" -v m="$DLBMSG" '$2=="links" && $3==m {print "yes"; exit}')"

# ---- FAZ 10: status alphabet as data (T-142) ----

# T-142: layout/status.txt parses with the standard TAB format (same reading
# pattern as layout/emoji.txt / layout/plain.txt), and the status emoji
# literals live ONLY there — never hardcoded in quipu or lib/*.awk. A
# multi-byte literal is searched with awk index(), never grep (PLAN 4.17:
# grep can silently miss multi-byte patterns on some platforms).
t; STATUS_SLUGS=$(awk -F"$TAB" 'NF>=2{print $1}' "$ROOT/layout/status.txt" | sort)
assert_eq "T-142: layout/status.txt parses; slugs are active/blocked/paused/progress" \
  'active
blocked
paused
progress' "$STATUS_SLUGS"
t; EMOJI_IN_CODE=$(awk 'index($0,"🟢")||index($0,"🟡")||index($0,"🔴")||index($0,"⚪"){print FILENAME":"FNR}' "$ROOT/knotlog" "$LIB"/*.awk)
assert_eq "T-142: no status emoji literal in quipu or lib/*.awk" '' "$EMOJI_IN_CODE"

# ---- FAZ 11: batch index pipeline -- mode=scan (T-151/T-152/T-159/T-160) ----
#
# FAZ 11's goal is process-count, not correctness (T-150/T-163..T-165 land
# with the later slices that actually rewire `knotlog index` onto the batch
# pipeline). These four are added now, before that rewrite, as an early
# regression anchor: they must stay green through every remaining slice.

# T-151: knotlog index end-to-end over a multi-file vault -- title/tags/status/
# type land correctly per row (the batch-path counterpart of T-130's direct
# mode=meta unit test).
mkdir -p "$TMP/vt151/.knotlog"
cat > "$TMP/vt151/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt151/one.md" <<'EOF'
---
title: One Title
tags: a1 a2
status: active
type: task
---
body one
EOF
cat > "$TMP/vt151/two.md" <<'EOF'
---
title: Two Title
tags: b1
status: paused
type: idea
---
body two
EOF
cat > "$TMP/vt151/three.md" <<'EOF'
# Three Heading
plain body, no frontmatter.
EOF
(cd "$TMP/vt151" && "$ROOT/knotlog" index) >/dev/null 2>&1
t; assert_eq "T-151: one.md title/tags/status/type" "One Title${TAB}a1,a2${TAB}active${TAB}task" \
  "$(awk -F"$TAB" '$1=="one.md"{print $2 FS $3 FS $6 FS $7}' "$TMP/vt151/.knotlog/index.tsv")"
t; assert_eq "T-151: two.md title/tags/status/type" "Two Title${TAB}b1${TAB}paused${TAB}idea" \
  "$(awk -F"$TAB" '$1=="two.md"{print $2 FS $3 FS $6 FS $7}' "$TMP/vt151/.knotlog/index.tsv")"
t; assert_eq "T-151: three.md heading title, empty status/type" "Three Heading${TAB}${TAB}${TAB}" \
  "$(awk -F"$TAB" '$1=="three.md"{print $2 FS $3 FS $6 FS $7}' "$TMP/vt151/.knotlog/index.tsv")"

# T-152: more than one stale file's [[hedef]]/[[hedef|ad]] wikilinks land in
# links.tsv in the SAME index run, correctly and without cross-file mixing
# (the batch-path counterpart of T-139's direct mode=links unit test).
mkdir -p "$TMP/vt152/.knotlog"
: > "$TMP/vt152/.knotlog/config"
cat > "$TMP/vt152/alpha.md" <<'EOF'
# Alpha
See [[Beta]] and [[Gamma|G]].
EOF
cat > "$TMP/vt152/beta.md" <<'EOF'
# Beta
Back to [[Alpha]].
EOF
(cd "$TMP/vt152" && "$ROOT/knotlog" index) >/dev/null 2>&1
t; LINKS152=$(sort "$TMP/vt152/.knotlog/links.tsv")
assert_eq "T-152: multi-file wikilinks land in links.tsv without cross-file mixing" \
  "alpha.md${TAB}Beta
alpha.md${TAB}Gamma
beta.md${TAB}Alpha" "$LINKS152"

# T-159: mode=plan's trailing "END" sentinel (commit 1388e73 -- read strips
# trailing IFS, so without it a 7-column row loses its empty status/type
# columns) is still present in a direct call, unaffected by the batch design.
mkdir -p "$TMP/t159"
: > "$TMP/t159/old.tsv"
printf 'note.md\t1000\n' > "$TMP/t159/cur.tsv"
printf 'note.md\n' > "$TMP/t159/all.txt"
t; PLAN159=$(awk -v mode=plan -v oldfile="$TMP/t159/old.tsv" -v allfile="$TMP/t159/all.txt" -f "$LIB/index.awk" "$TMP/t159/old.tsv" "$TMP/t159/cur.tsv" "$TMP/t159/all.txt")
assert_eq "T-159: mode=plan END sentinel still present for a stale row" "stale${TAB}note.md${TAB}1000${TAB}END" "$PLAN159"

# T-160: cross-validation -- awk -v mode=meta run directly against a file and
# the SAME file's row inside mode=scan's batch meta.tsv are byte-for-byte
# identical.
mkdir -p "$TMP/t160"
cat > "$TMP/t160/note.md" <<'EOF'
---
title: T160 Note
tags: gamma delta
status: paused
type: idea
---
# T160 Note
body text with [[Other Note]].
EOF
cat > "$TMP/t160/plain.md" <<'EOF'
No frontmatter, title only from the heading below.
# Heading Title
EOF
printf 'note.md\nplain.md\n' > "$TMP/t160/paths.txt"
(cd "$TMP/t160" && awk -v mode=scan -v pathsfile=paths.txt -v rawout=raw.txt -v boundsout=bounds.tsv -v metaout=meta.tsv -v linksout=links.tsv -f "$LIB/index.awk" </dev/null)
DIRECT160=$(cd "$TMP/t160" && awk -v mode=meta -f "$LIB/index.awk" note.md)
SCAN160=$(cd "$TMP/t160" && awk -F"$TAB" '$1=="note.md"{print $2 FS $3 FS $4 FS $5}' meta.tsv)
t; assert_eq "T-160: mode=scan meta row for note.md matches direct mode=meta" "$DIRECT160" "$SCAN160"
DIRECT160B=$(cd "$TMP/t160" && awk -v mode=meta -f "$LIB/index.awk" plain.md)
SCAN160B=$(cd "$TMP/t160" && awk -F"$TAB" '$1=="plain.md"{print $2 FS $3 FS $4 FS $5}' meta.tsv)
t; assert_eq "T-160: mode=scan meta row for plain.md (no frontmatter) matches direct mode=meta" "$DIRECT160B" "$SCAN160B"

# ---- FAZ 11: batch index pipeline -- mode=flatjoin (T-153/T-154/T-155) ----
#
# Same status as the T-151/T-152/T-159/T-160 block above: mode=flatjoin is
# not yet wired into `knotlog index` (that lands with mode=assemble, F-6) --
# these exercise the library function directly, against mode=scan's own
# rawout/boundsout/metaout, feeding the SAME `sed -f fold/PROFIL.sed | tr`
# pass the real command will eventually use once for the whole batch.

# T-153: fold=tr, a Turkish note -- the batch flatjoin chain's folded field
# is byte-for-byte identical to the OLD per-file chain (sed | tr | awk
# mode=flat) for the SAME file (regression: istanbul == İstanbul class
# folding, T-73's family).
mkdir -p "$TMP/t153"
cat > "$TMP/t153/tr.md" <<'EOF'
---
title: TR Note
tags: a
---
İstanbul çalışma IŞIK üzerine notlar burada duruyor ve kısa kalıyor.
EOF
cat > "$TMP/t153/en.md" <<'EOF'
# EN Note
Straightforward ascii body line here.
EOF
printf 'tr.md\nen.md\n' > "$TMP/t153/paths.txt"
(cd "$TMP/t153" && awk -v mode=scan -v pathsfile=paths.txt -v rawout=raw.txt -v boundsout=bounds.tsv -v metaout=meta.tsv -v linksout=links.tsv -f "$LIB/index.awk" </dev/null)
# shellcheck disable=SC2018,SC2019
(cd "$TMP/t153" && sed -f "$FOLD/tr.sed" raw.txt | tr 'A-Z' 'a-z' | awk -v mode=flatjoin -v boundsfile=bounds.tsv -v metafile=meta.tsv -f "$LIB/index.awk" > joined.tsv)
# shellcheck disable=SC2018,SC2019
OLD_TR=$(cd "$TMP/t153" && sed -f "$FOLD/tr.sed" tr.md | tr 'A-Z' 'a-z' | awk -v mode=flat -v max=2000 -f "$LIB/index.awk")
NEW_TR=$(awk -F"$TAB" '$1=="tr.md"{print $4}' "$TMP/t153/joined.tsv")
t; assert_eq "T-153: batch flatjoin folded field matches old per-file chain (tr.md)" "$OLD_TR" "$NEW_TR"
# shellcheck disable=SC2018,SC2019
OLD_EN=$(cd "$TMP/t153" && sed -f "$FOLD/tr.sed" en.md | tr 'A-Z' 'a-z' | awk -v mode=flat -v max=2000 -f "$LIB/index.awk")
NEW_EN=$(awk -F"$TAB" '$1=="en.md"{print $4}' "$TMP/t153/joined.tsv")
t; assert_eq "T-153: batch flatjoin folded field matches old per-file chain (en.md)" "$OLD_EN" "$NEW_EN"
t; assert_eq "T-153: folded field keeps the tr folding (calisma)" 'yes' "$(printf '%s\n' "$NEW_TR" | awk '{print (index($0,"calisma")>0) ? "yes" : "no"}')"

# T-154: a file with no trailing newline at EOF, immediately followed by
# another file in the SAME batch -- neither folded field is corrupted and
# the two never merge (F-3's print-normalizes-EOF reasoning, exercised
# through the full scan+flatjoin chain this time, not just rawout/bounds).
mkdir -p "$TMP/t154"
printf '# NoNL\nlast line no newline' > "$TMP/t154/nonl.md"
printf '# After\nclean second file body.\n' > "$TMP/t154/after.md"
printf 'nonl.md\nafter.md\n' > "$TMP/t154/paths.txt"
(cd "$TMP/t154" && awk -v mode=scan -v pathsfile=paths.txt -v rawout=raw.txt -v boundsout=bounds.tsv -v metaout=meta.tsv -v linksout=links.tsv -f "$LIB/index.awk" </dev/null)
# shellcheck disable=SC2018,SC2019
(cd "$TMP/t154" && sed -f "$FOLD/default.sed" raw.txt | tr 'A-Z' 'a-z' | awk -v mode=flatjoin -v boundsfile=bounds.tsv -v metafile=meta.tsv -f "$LIB/index.awk" > joined.tsv)
t; assert_eq "T-154: no-trailing-newline file's folded field is intact, not merged into the next file" \
  '# nonl last line no newline' "$(awk -F"$TAB" '$1=="nonl.md"{print $4}' "$TMP/t154/joined.tsv")"
t; assert_eq "T-154: the following file's folded field starts clean, no leaked prefix" \
  '# after clean second file body.' "$(awk -F"$TAB" '$1=="after.md"{print $4}' "$TMP/t154/joined.tsv")"

# T-155: a CRLF-authored note's folded field carries no CR byte after the
# batch chain (F-4's accepted risk -- must hold on all three OS CI runners).
# CR is matched with sprintf("%c",13)/index(), the same idiom the source
# hygiene test above uses for backslash -- never a literal control byte.
mkdir -p "$TMP/t155"
printf '# CRLF Doc\r\nBody line with a carriage return at EOL.\r\n' > "$TMP/t155/crlf.md"
printf 'crlf.md\n' > "$TMP/t155/paths.txt"
(cd "$TMP/t155" && awk -v mode=scan -v pathsfile=paths.txt -v rawout=raw.txt -v boundsout=bounds.tsv -v metaout=meta.tsv -v linksout=links.tsv -f "$LIB/index.awk" </dev/null)
# shellcheck disable=SC2018,SC2019
(cd "$TMP/t155" && sed -f "$FOLD/default.sed" raw.txt | tr 'A-Z' 'a-z' | awk -v mode=flatjoin -v boundsfile=bounds.tsv -v metafile=meta.tsv -f "$LIB/index.awk" > joined.tsv)
t; CRCHECK=$(awk -F"$TAB" '$1=="crlf.md"{print (index($4, sprintf("%c",13)) > 0) ? "has-cr" : "clean"}' "$TMP/t155/joined.tsv")
assert_eq "T-155: CRLF note's folded field has no CR byte" 'clean' "$CRCHECK"

# ---- FAZ 11: batch stat via xargs (T-161/T-162) ----
#
# Unlike mode=scan/mode=flatjoin above, _q_stat_batch/_q_nul_list are shell
# functions inside `quipu` itself, not a separately invocable lib/*.awk
# mode -- so F-5 IS already wired into `knotlog index`'s cur.txt step (the old
# per-changed-file mtime subshell is gone; the stale-row meta/flat/links
# processing loop is untouched until mode=assemble, dilim 4). These two
# exercise the real CLI end-to-end.

# T-161: a file touched to a fresh mtime -- index.tsv's 4th column (mtime)
# is correct after going through the batch xargs/stat path (F-5 regression).
mkdir -p "$TMP/t161/.knotlog"
: > "$TMP/t161/.knotlog/config"
printf '# Doc\nbody\n' > "$TMP/t161/doc.md"
QUIPU_VAULT="$TMP/t161" sh "$ROOT/knotlog" index >/dev/null 2>&1
sleep 1
touch "$TMP/t161/doc.md"
EXPECT_MT161=$(mtime "$TMP/t161/doc.md")
QUIPU_VAULT="$TMP/t161" sh "$ROOT/knotlog" index >/dev/null 2>&1
t; assert_eq "T-161: index.tsv mtime column matches stat after the batch xargs path" \
  "$EXPECT_MT161" "$(awk -F"$TAB" '$1=="doc.md"{print $4}' "$TMP/t161/.knotlog/index.tsv")"

# T-162: more stale files than one xargs chunk. QUIPU_STAT_CHUNK (an
# internal override read by _q_stat_batch, default 200 for real use) is set
# to 3 here so 10 files cross the chunk boundary three times -- the SAME
# boundary-crossing code path a real 250-300-file vault at the default
# chunk size would exercise, without paying msys fork costs on 200+ real
# files just to prove the split arithmetic. No loss/duplication at a chunk
# boundary.
mkdir -p "$TMP/t162/.knotlog"
: > "$TMP/t162/.knotlog/config"
i=1
while [ "$i" -le 10 ]; do
  printf '# Doc %s\nbody %s\n' "$i" "$i" > "$TMP/t162/n$i.md"
  i=$((i + 1))
done
QUIPU_STAT_CHUNK=3 QUIPU_VAULT="$TMP/t162" sh "$ROOT/knotlog" index >"$TMP/t162.out" 2>&1
t; assert_eq "T-162: chunk-crossing batch stat indexes all 10 files" '10 0 10 0' "$(idx_nums "$TMP/t162.out")"
t; assert_eq "T-162: index.tsv has exactly 10 rows, no chunk-boundary loss/dup" '10' "$(awk 'END{print NR}' "$TMP/t162/.knotlog/index.tsv")"
t; UNIQ162=$(awk -F"$TAB" '{print $1}' "$TMP/t162/.knotlog/index.tsv" | sort -u | awk 'END{print NR}')
assert_eq "T-162: all 10 paths are distinct (no duplicate row)" '10' "$UNIQ162"

# ---- FAZ 11: mode=assemble, the real batch pipeline wired into `quipu
# index` (T-156/T-157/T-158) ----
#
# F-6/mode=assemble is the slice that finally rewires `knotlog index` end to
# end onto the batch pipeline (stages 1-5, F-2) -- everything above this
# point in the file still exercises the pipeline it replaced, or the new
# pieces in isolation. These three are the regression gate for that
# rewiring itself: mixed reuse+stale+drop in one run, links.tsv's carry-
# forward (FAZ 10 Z-5) surviving the rewrite, and the hook-silence contract
# with more than one stale file.

# T-156: a single run with reuse, carry, stale, AND drop all present --
# summary counts correct, and index.tsv's row SET (not order) matches.
mkdir -p "$TMP/t156/.knotlog"
: > "$TMP/t156/.knotlog/config"
printf '# A\naaa\n' > "$TMP/t156/a.md"
printf '# B\nbbb\n' > "$TMP/t156/b.md"
printf '# C\nccc\n' > "$TMP/t156/c.md"
printf '# D\nddd\n' > "$TMP/t156/d.md"
QUIPU_VAULT="$TMP/t156" sh "$ROOT/knotlog" index >/dev/null 2>&1
sleep 1
touch "$TMP/t156/a.md"
rm "$TMP/t156/d.md"
QUIPU_VAULT="$TMP/t156" sh "$ROOT/knotlog" index >"$TMP/t156.out" 2>&1
t; assert_eq "T-156: mixed reuse+stale+drop summary counts (N R S D)" '3 2 1 1' "$(idx_nums "$TMP/t156.out")"
t; ROWSET156=$(awk -F"$TAB" '{print $1}' "$TMP/t156/.knotlog/index.tsv" | sort)
assert_eq "T-156: index.tsv row SET matches expected (order not asserted)" 'a.md
b.md
c.md' "$ROWSET156"

# T-157: an unchanged file's links.tsv rows survive a second run CARRIED,
# not rescanned. Proven directly, not just by before/after equality: after
# the first index, a.md's WIKILINK TARGET is changed on disk but its mtime
# is restored (cp -p for a same-mtime reference copy, then touch -r) so
# `find -newer` never flags it. If the second run rescanned it, links.tsv
# would show the NEW target; FAZ 10 Z-5's carry-forward join means it must
# still show the OLD one.
mkdir -p "$TMP/t157/.knotlog"
: > "$TMP/t157/.knotlog/config"
printf '# A\nSee [[Original]].\n' > "$TMP/t157/a.md"
printf '# B\nplaceholder\n' > "$TMP/t157/b.md"
QUIPU_VAULT="$TMP/t157" sh "$ROOT/knotlog" index >/dev/null 2>&1
cp -p "$TMP/t157/a.md" "$TMP/t157/a.mtimeref"
printf '# A\nSee [[Different]].\n' > "$TMP/t157/a.md"
touch -r "$TMP/t157/a.mtimeref" "$TMP/t157/a.md"
rm "$TMP/t157/a.mtimeref"
QUIPU_VAULT="$TMP/t157" sh "$ROOT/knotlog" index >"$TMP/t157.out" 2>&1
t; assert_eq "T-157: unchanged mtime -> second run treats it as reused, not stale" '2 2 0 0' "$(idx_nums "$TMP/t157.out")"
t; assert_eq "T-157: links.tsv still shows the OLD target -- not rescanned" 'Original' \
  "$(awk -F"$TAB" '$1=="a.md"{print $2}' "$TMP/t157/.knotlog/links.tsv")"

# T-158: QUIPU_HOOK=1 with MORE THAN ONE stale file -- stdout stays empty,
# exit 0, index.tsv fully up to date (multi-file regression of T-95).
mkdir -p "$TMP/t158/.knotlog"
: > "$TMP/t158/.knotlog/config"
printf '# A\naaa\n' > "$TMP/t158/a.md"
printf '# B\nbbb\n' > "$TMP/t158/b.md"
printf '# C\nccc\n' > "$TMP/t158/c.md"
t; OUT158=$(QUIPU_HOOK=1 QUIPU_VAULT="$TMP/t158" sh "$ROOT/knotlog" index); RC158=$?
assert_eq "T-158: QUIPU_HOOK=1 with 3 stale files: stdout empty" '' "$OUT158"
t; assert_eq "T-158: QUIPU_HOOK=1 exits 0" '0' "$RC158"
t; assert_eq "T-158: QUIPU_HOOK=1 still writes a fully up to date index.tsv" '3' \
  "$(awk 'END{print NR}' "$TMP/t158/.knotlog/index.tsv")"

# ---- FAZ 11: closing the gate — T-150/T-163 (T-164/T-165 below, no new code) ----

# T-150: process-scale sensitivity. PATH gets counting wrappers for awk/
# sed/tr/stat (each appends its own name to a counter file, then execs the
# REAL binary resolved via `command -v` BEFORE the wrapper dir goes on
# PATH, so there is no self-recursion); a 5-stale-doc vault and a 50-stale-
# doc vault are indexed under that wrapped PATH and the counter's growth is
# compared. F-1's whole point is that this growth stays flat regardless of
# file count — 10x more files must NOT cost anywhere near 10x more external
# awk/sed/tr/stat processes (docs/FAZ11-BULGULAR.md B-1..B-5). The exact
# process count is already pinned by reading the code (B-1..B-4); this test
# only locks the REGRESSION — a future change that reintroduces a per-file
# fork would fail it.
mkdir -p "$TMP/t150wrap"
mk_wrap() { # tool realpath dir counterfile
  printf '#!/bin/sh\n' > "$3/$1"
  printf 'echo %s >> "%s"\n' "$1" "$4" >> "$3/$1"
  printf 'exec "%s" "$@"\n' "$2" >> "$3/$1"
  chmod +x "$3/$1"
}
for _q_t150 in awk sed tr stat; do
  mk_wrap "$_q_t150" "$(command -v "$_q_t150")" "$TMP/t150wrap" "$TMP/t150.count"
done

mkdir -p "$TMP/vt150a/.knotlog"
: > "$TMP/vt150a/.knotlog/config"
i=1
while [ "$i" -le 5 ]; do
  printf '# not %s\nbody %s here\n' "$i" "$i" > "$TMP/vt150a/n$i.md"
  i=$((i + 1))
done
: > "$TMP/t150.count"
PATH="$TMP/t150wrap:$PATH" QUIPU_VAULT="$TMP/vt150a" sh "$ROOT/knotlog" index >/dev/null 2>&1
COUNT5=$(awk 'END{print NR}' "$TMP/t150.count")

mkdir -p "$TMP/vt150b/.knotlog"
: > "$TMP/vt150b/.knotlog/config"
i=1
while [ "$i" -le 50 ]; do
  printf '# not %s\nbody %s here\n' "$i" "$i" > "$TMP/vt150b/n$i.md"
  i=$((i + 1))
done
: > "$TMP/t150.count"
PATH="$TMP/t150wrap:$PATH" QUIPU_VAULT="$TMP/vt150b" sh "$ROOT/knotlog" index >/dev/null 2>&1
COUNT50=$(awk 'END{print NR}' "$TMP/t150.count")

t; assert_eq "T-150: 5-doc vault indexes correctly under a wrapped PATH" '5' \
  "$(awk 'END{print NR}' "$TMP/vt150a/.knotlog/index.tsv")"
t; assert_eq "T-150: 50-doc vault indexes correctly under a wrapped PATH" '50' \
  "$(awk 'END{print NR}' "$TMP/vt150b/.knotlog/index.tsv")"
# 10x more files, process-count growth kept well under 10x -- COUNT5 * 5 is
# a generous, portable-arithmetic threshold (POSIX sh has no floating
# point) comfortably below the literal 10x bar the spec names.
t; assert_eq "T-150: 50-doc process count stays well under 10x the 5-doc count" 'yes' \
  "$([ "$COUNT50" -lt $((COUNT5 * 5)) ] && printf yes || printf no)"

# T-163: static check — count of `/.../` REGEX LITERALS in lib/index.awk,
# not just `~`/`!~` occurrences (an earlier version of this test counted
# only `~`, which run_flatjoin's two gsub(/.../)/sub(/.../) additions never
# use — that version stayed green while FAZ11-BULGULAR.md's "adds none"
# claim was already false; corrected in docs/FAZ11-BULGULAR.md's Dilim 5).
# Matches any `/.../` reached via gsub(/, sub(/, match(/, split(...,/, or
# `~`/`!~` — the constructs that actually introduce an awk regex literal.
# Pinned to 7, broken down so a future edit updates it knowingly:
#   3  trim_() -- sub(/^[ ]+/), sub(/[ ]+$/), plus mode=flat's END trim
#      reusing the same leading-space pattern (pre-FAZ11)
#   1  mode=flat's own gsub(/  */, " ", line) space-run squeeze (pre-FAZ11)
#   1  collect_tags()'s w !~ /^#[0-9A-Za-z_-]/ tag-prefix check (pre-FAZ11)
#   2  run_flatjoin() (FAZ 11, F-4): gsub(/  */, " ", fline) and
#      sub(/^[ ]+/, "", fbuf) -- LITERAL COPIES of the two patterns above
#      (the code comment above them says so: "Same squeeze as mode=flat"),
#      not a new regex CLASS, but still two new /.../ literals -- the count
#      grew 5 -> 7, not 5 -> 5 as the old test implied.
# Separator note: the split() clause requires the separator to start with an
# UNQUOTED "/" (`, *\/`). `split(path, parts, "/")` passes a quoted STRING
# separator, not a regex literal, and must NOT be counted — FAZ 13's
# base_of() uses exactly that form and would otherwise show up as a phantom
# 8th regex.
t; REGEX_COUNT=$(awk '/(gsub|sub|match)\(\// || /~ *\// || /split\([^)]*, *\// {n++} END{print n+0}' "$LIB/index.awk")
assert_eq "T-163: lib/index.awk regex-literal count pinned (7: 5 pre-FAZ11 + 2 copied by run_flatjoin)" '7' "$REGEX_COUNT"

# T-164/T-165 (no new test code — see docs/FAZ11-BULGULAR.md "Dilim 5"):
# `knotlog index` has no old/new pipeline toggle, so the EXISTING T-85 scale
# vault and T-72/T-130..T-142 chain already run the batch pipeline this
# spec built, the moment they run at all. T-164 is "T-85, now known to
# exercise mode=scan/flatjoin/assemble" and T-165 is "T-72 + T-130..T-142,
# same fact" — not separate assertions to add. Per the session's explicit
# instruction, the 5000-doc scale block (T-85..T-87) was NOT run this
# session; T-151..T-163 above plus the isolated re-runs of the pre-FAZ11
# index/search/tag/status/links sections (recorded in FAZ11-BULGULAR.md)
# stand in as the regression evidence gathered so far. Real T-164 timing
# and the full suite (T-72 included) are CI's job, not this session's.

# ---- context output bound (C-16/C-17) ----

mkvault vctxb
printf 'lang=en\n' >> "$TMP/vctxb/.knotlog/config"
: > "$TMP/vctxb/.knotlog/index.tsv"
: > "$TMP/vctxb/.knotlog/activity.log"
awk 'BEGIN { for (i=1; i<=200; i++) printf "thread line %03d padding padding padding\n", i }' > "$TMP/vctxb/Threads.md"

t; QUIPU_CTX_MAX=1000 QUIPU_VAULT="$TMP/vctxb" sh "$ROOT/knotlog" context > "$TMP/vctxb.out"
SIZE=$(wc -c < "$TMP/vctxb.out" | tr -d ' ')
assert_eq "context bound: body within QUIPU_CTX_MAX" 'yes' "$([ "$SIZE" -le 1000 ] && printf yes || printf no)"
t; assert_eq "context bound: activity header present" 'yes' "$(grep -q '^recent activity$' "$TMP/vctxb.out" && printf yes || printf no)"
t; assert_eq "context bound: index header present" 'yes' "$(grep -q '^index stats$' "$TMP/vctxb.out" && printf yes || printf no)"
t; assert_eq "context bound: last threads line cut" 'no' "$(grep -q 'thread line 200' "$TMP/vctxb.out" && printf yes || printf no)"

# T-42: multibyte lines must survive the cut as valid UTF-8 (C-17).
mkvault vctxu
printf 'lang=en\n' >> "$TMP/vctxu/.knotlog/config"
: > "$TMP/vctxu/.knotlog/index.tsv"
: > "$TMP/vctxu/.knotlog/activity.log"
awk 'BEGIN { for (i=1; i<=60; i++) printf "İstanbul ğüşiöç 🔮 日本語 — line %d\n", i }' > "$TMP/vctxu/Threads.md"

t; QUIPU_CTX_MAX=800 QUIPU_VAULT="$TMP/vctxu" sh "$ROOT/knotlog" context > "$TMP/vctxu.out"
if LC_ALL=C awk '
  BEGIN { for (i = 0; i < 256; i++) ORD[sprintf("%c", i)] = i; need = 0 }
  {
    for (i = 1; i <= length($0); i++) {
      b = ORD[substr($0, i, 1)]
      if (need > 0) {
        if (b < 128 || b > 191) { bad = 1; exit 1 }
        need--
      } else if (b < 128) {
        continue
      } else if (b >= 194 && b <= 223) {
        need = 1
      } else if (b >= 224 && b <= 239) {
        need = 2
      } else if (b >= 240 && b <= 244) {
        need = 3
      } else {
        bad = 1; exit 1
      }
    }
  }
  END { if (need > 0) exit 1 }
' "$TMP/vctxu.out"; then
  VUTF=yes
else
  VUTF=no
fi
assert_eq "context bound: truncated multibyte output is valid UTF-8" 'yes' "$VUTF"

# T-43: the truncation marker appears exactly once.
CTRUNC=$(awk -F= -v k=ctx_truncated '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
t; assert_eq "context bound: truncated marker appears exactly once" '1' "$(grep -F -c "$CTRUNC" "$TMP/vctxb.out")"

# T-44: truncated --json stays valid and round-trips to the plain output.
t; CTXBJSON=$(QUIPU_CTX_MAX=1000 QUIPU_VAULT="$TMP/vctxb" sh "$ROOT/knotlog" context --json SessionStart)
# The two invocations render their own wall clock; a minute boundary between
# them is legitimate (the round-trip pins content, not the timestamp), so the
# now: line is stripped from both sides before the comparison.
CTXBDEC=$(printf '%s' "$CTXBJSON" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" - | sed '/^now: /d')
CTXBPLAIN=$(QUIPU_CTX_MAX=1000 QUIPU_VAULT="$TMP/vctxb" sh "$ROOT/knotlog" context | sed '/^now: /d')
assert_eq "context bound: truncated --json round-trips to plain" "$CTXBPLAIN" "$CTXBDEC"

# ---- context nudge (C-19/C-20) ----

mkvault vnudge
QUIPU_VAULT="$TMP/vnudge" sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
printf 'lang=en\n' >> "$TMP/vnudge/.knotlog/config"
for _n in 1 2 3; do
  printf '2026-08-20T10:0%s | PostToolUse | Read | nudge%s.md\n' "$_n" "$_n" >> "$TMP/vnudge/.knotlog/activity.log"
done

CPREC=$(awk -F= -v k=ctx_precompact '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
# shellcheck disable=SC2059
CPREC_EXPECT=$(printf "$CPREC" '700-Sessions')

t; NJ=$(QUIPU_NUDGE_AFTER=2 QUIPU_VAULT="$TMP/vnudge" sh "$ROOT/knotlog" context --json UserPromptSubmit)
ND=$(printf '%s' "$NJ" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "nudge: UserPromptSubmit adds ctx_precompact" 'yes' "$(printf '%s\n' "$ND" | grep -F -q "$CPREC_EXPECT" && printf yes || printf no)"
t; assert_eq "nudge: .knotlog/nudged created" 'yes' "$([ -f "$TMP/vnudge/.knotlog/nudged" ] && printf yes || printf no)"
t; assert_eq "nudge: .knotlog/nudged equals last log line" '2026-08-20T10:03 | PostToolUse | Read | nudge3.md' "$(cat "$TMP/vnudge/.knotlog/nudged")"

t; NJ2=$(QUIPU_NUDGE_AFTER=2 QUIPU_VAULT="$TMP/vnudge" sh "$ROOT/knotlog" context --json UserPromptSubmit)
ND2=$(printf '%s' "$NJ2" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "nudge: not repeated without new lines" 'no' "$(printf '%s\n' "$ND2" | grep -F -q "$CPREC_EXPECT" && printf yes || printf no)"

for _n in 4 5 6; do
  printf '2026-08-20T10:0%s | PostToolUse | Read | nudge%s.md\n' "$_n" "$_n" >> "$TMP/vnudge/.knotlog/activity.log"
done
t; NJ3=$(QUIPU_NUDGE_AFTER=2 QUIPU_VAULT="$TMP/vnudge" sh "$ROOT/knotlog" context --json UserPromptSubmit)
ND3=$(printf '%s' "$NJ3" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "nudge: re-triggers after threshold re-crossed" 'yes' "$(printf '%s\n' "$ND3" | grep -F -q "$CPREC_EXPECT" && printf yes || printf no)"

mkvault vnudge9
QUIPU_VAULT="$TMP/vnudge9" sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
printf 'lang=en\n' >> "$TMP/vnudge9/.knotlog/config"
printf '2026-08-20T10:00 | PostToolUse | Read | nudge9.md\n' >> "$TMP/vnudge9/.knotlog/activity.log"
t; NJ9=$(QUIPU_NUDGE_AFTER=999 QUIPU_VAULT="$TMP/vnudge9" sh "$ROOT/knotlog" context --json UserPromptSubmit)
ND9=$(printf '%s' "$NJ9" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "nudge: threshold never reached -> no ctx_precompact" 'no' "$(printf '%s\n' "$ND9" | grep -F -q "$CPREC_EXPECT" && printf yes || printf no)"
t; assert_eq "nudge: .knotlog/nudged not created" 'no' "$([ -f "$TMP/vnudge9/.knotlog/nudged" ] && printf yes || printf no)"

# ---- remember (FAZ 3) ----

i18n() { awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt"; }
mkrem() { QUIPU_VAULT="$TMP/$1" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain >/dev/null 2>&1; }
rem() { _r_v=$1; shift; QUIPU_VAULT="$TMP/$_r_v" QUIPU_LANG=en sh "$ROOT/knotlog" remember "$@"; }

D=$(date +%Y-%m-%d)
REM_EMPTY=$(i18n remember_empty)
REM_GIT=$(i18n remember_git)
REM_BUSY=$(i18n remember_busy)

mkrem vr30
t; OUT=$(rem vr30); RC=$?
assert_eq "remember: empty log leaves nothing behind" 'yes' \
  "$([ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qF "$REM_EMPTY" && [ ! -f "$TMP/vr30/700-Sessions/$D.md" ] && [ ! -f "$TMP/vr30/Last-Session.md" ] && [ ! -f "$TMP/vr30/.knotlog/remembered" ] && printf yes || printf no)"

mkrem vr31
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' '2026-08-20T10:01 | PostToolUse | Read | 300-Projects/p.md' '2026-08-20T10:02 | PostToolUse | Write | 000-Inbox/i.md' >> "$TMP/vr31/.knotlog/activity.log"
t; OUT=$(rem vr31); RC=$?
assert_eq "remember: writes session file and watermark" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -s "$TMP/vr31/700-Sessions/$D.md" ] && grep -qF '## ' "$TMP/vr31/700-Sessions/$D.md" && grep -qF '500-Knowledge/not.md' "$TMP/vr31/700-Sessions/$D.md" && [ "$(cat "$TMP/vr31/.knotlog/remembered")" = '2026-08-20T10:02 | PostToolUse | Write | 000-Inbox/i.md' ] && printf yes || printf no)"

printf '%s\n' '2026-08-20T10:03 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vr31/.knotlog/activity.log"
t; OUT=$(rem vr31); RC=$?
assert_eq "remember: appends second section same day" 'yes' \
  "$([ "$RC" -eq 0 ] && [ "$(grep -c '^## ' "$TMP/vr31/700-Sessions/$D.md")" = 2 ] && grep -qF '2026-08-20T10:00' "$TMP/vr31/700-Sessions/$D.md" && printf yes || printf no)"

t; BEFORE=$(wc -l < "$TMP/vr31/700-Sessions/$D.md" | tr -d ' ')
OUT=$(rem vr31); RC=$?
assert_eq "remember: no new lines is a no-op" 'yes' \
  "$([ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qF "$REM_EMPTY" && [ "$(wc -l < "$TMP/vr31/700-Sessions/$D.md" | tr -d ' ')" = "$BEFORE" ] && printf yes || printf no)"

# Two overlapping hooks must not digest the same activity window twice.
mkrem vr31race
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/race.md' >> "$TMP/vr31race/.knotlog/activity.log"
(rem vr31race >/dev/null 2>&1) & RACE_PID=$!
(rem vr31race >/dev/null 2>&1) & RACE_PID2=$!
wait "$RACE_PID"; wait "$RACE_PID2"
assert_eq "remember: concurrent calls append one digest" 'yes' \
  "$([ "$(grep -c '^## ' "$TMP/vr31race/700-Sessions/$D.md")" = 1 ] && [ "$(grep -c '2026-08-20T10:00' "$TMP/vr31race/700-Sessions/$D.md")" = 1 ] && printf yes || printf no)"

# A live owner can outlast the bounded lock wait.  Standalone remember must
# report that it skipped the transaction, while a hook must stay successful so
# its surrounding hook chain can continue.  The activity and watermark checks
# below prove the skipped call is retryable, not a data-loss path.
#
# The owner's sleep only bounds how long it stays alive; it is killed the moment
# remember returns, so a generous value costs no wall clock.  It must outlast
# the bounded wait on the SLOWEST runner, not on this one: the wait is 50 idle
# `sleep 0.1` processes, and Windows spawns processes an order of magnitude
# slower than Linux (the same suite: 2m20s on ubuntu, 30m48s on windows).  A
# margin tuned to Linux dies mid-wait there, the owner PID goes stale, remember
# takes the dead-owner recovery branch and SUCCEEDS -- the exact opposite of
# what these two assertions demand.  6 and then 8 seconds were both guessed too
# small this way; the value below is far past any plausible wait instead.
mkrem vr31busy
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/busy.md' >> "$TMP/vr31busy/.knotlog/activity.log"
sleep 300 & BUSY_PID=$!
mkdir "$TMP/vr31busy/.knotlog/remember.lock"
printf '%s\n' "$BUSY_PID" > "$TMP/vr31busy/.knotlog/remember.lock/pid"
QUIPU_VAULT="$TMP/vr31busy" QUIPU_LANG=en sh "$ROOT/knotlog" remember >"$TMP/vr31busy.out" 2>"$TMP/vr31busy.err"; RC=$?
kill "$BUSY_PID" 2>/dev/null || true; wait "$BUSY_PID" 2>/dev/null || true
rm -f "$TMP/vr31busy/.knotlog/remember.lock/pid"
rmdir "$TMP/vr31busy/.knotlog/remember.lock" 2>/dev/null || true
t; assert_eq "remember: lock timeout is visible and nonzero for CLI" 'yes' \
  "$([ "$RC" -ne 0 ] && grep -qF "$REM_BUSY" "$TMP/vr31busy.err" && [ ! -f "$TMP/vr31busy/.knotlog/remembered" ] && printf yes || printf no)"

sleep 300 & BUSY_PID=$!
mkdir "$TMP/vr31busy/.knotlog/remember.lock"
printf '%s\n' "$BUSY_PID" > "$TMP/vr31busy/.knotlog/remember.lock/pid"
QUIPU_HOOK=1 QUIPU_VAULT="$TMP/vr31busy" QUIPU_LANG=en sh "$ROOT/knotlog" remember >"$TMP/vr31busy-hook.out" 2>"$TMP/vr31busy-hook.err"; RC=$?
kill "$BUSY_PID" 2>/dev/null || true; wait "$BUSY_PID" 2>/dev/null || true
rm -f "$TMP/vr31busy/.knotlog/remember.lock/pid"
rmdir "$TMP/vr31busy/.knotlog/remember.lock" 2>/dev/null || true
t; assert_eq "remember: lock timeout stays successful but visible in hooks" 'yes' \
  "$([ "$RC" -eq 0 ] && grep -qF "$REM_BUSY" "$TMP/vr31busy-hook.err" && [ ! -f "$TMP/vr31busy/.knotlog/remembered" ] && printf yes || printf no)"

t; OUT=$(rem vr31busy); RC=$?
assert_eq "remember: skipped lock transaction is recovered on next run" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -f "$TMP/vr31busy/.knotlog/remembered" ] && grep -qF 'busy.md' "$TMP/vr31busy/700-Sessions/$D.md" && printf yes || printf no)"

printf '%s\n' '2026-08-20T11:00 | PostToolUse | Edit | 500-Knowledge/new.md' > "$TMP/vr31/.knotlog/activity.log"
printf '%s\n' '2026-08-20T11:01 | PostToolUse | Read | 500-Knowledge/new.md' >> "$TMP/vr31/.knotlog/activity.log"
t; BEFORE=$(grep -c '## ' "$TMP/vr31/700-Sessions/$D.md")
OUT=$(rem vr31); RC=$?
assert_eq "remember: rotation reprocesses whole log" 'yes' \
  "$([ "$RC" -eq 0 ] && [ "$(grep -c '## ' "$TMP/vr31/700-Sessions/$D.md")" = "$((BEFORE + 1))" ] && printf yes || printf no)"

mkrem vr35
printf 'user marker L1\n' > "$TMP/vr35/Last-Session.md"
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vr35/.knotlog/activity.log"
rem vr35 >/dev/null 2>&1
printf '%s\n' '2026-08-20T10:01 | PostToolUse | Read | 500-Knowledge/other.md' >> "$TMP/vr35/.knotlog/activity.log"
rem vr35 >/dev/null 2>&1
t; assert_eq "remember: Last-Session keeps user line and one block" 'yes' \
  "$(grep -qF 'user marker L1' "$TMP/vr35/Last-Session.md" && [ "$(grep -c 'knotlog:start' "$TMP/vr35/Last-Session.md")" = 1 ] && printf yes || printf no)"

# T-539: remember writes the session file doctor reads, not a hardcoded
# English root file. Finding (a real vault, 2026-09-24): in a Turkish vault
# remember always wrote `Last-Session.md` at the root while doctor resolved
# the session file as `Son-Oturum.md` (vault language first, then legacy
# name; root first, then the companion folder) -- the two commands disagreed
# about which file is the session file, and the root file nobody read even
# shadowed the real one for doctor. The summary line's "events" word was
# hardcoded English too.
QUIPU_VAULT="$TMP/vr539" QUIPU_LANG=tr sh "$ROOT/knotlog" init --layout tr >/dev/null 2>&1
mkdir -p "$TMP/vr539/🔮 Asistan"
printf '## oturum\n\nelle yazilmis satir\n' > "$TMP/vr539/🔮 Asistan/Son-Oturum.md"
rm -f "$TMP/vr539/Son-Oturum.md" "$TMP/vr539/Last-Session.md"
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | not.md' >> "$TMP/vr539/.knotlog/activity.log"
QUIPU_VAULT="$TMP/vr539" QUIPU_LANG=tr sh "$ROOT/knotlog" remember >/dev/null 2>&1
t; assert_eq "T-539: a Turkish vault gets no root Last-Session.md" 'no' \
  "$([ -f "$TMP/vr539/Last-Session.md" ] && printf yes || printf no)"
t; assert_eq "T-539: the companion-folder Son-Oturum.md receives the block, user text kept" 'yes' \
  "$(grep -qF 'elle yazilmis satir' "$TMP/vr539/🔮 Asistan/Son-Oturum.md" \
     && [ "$(grep -c 'knotlog:start' "$TMP/vr539/🔮 Asistan/Son-Oturum.md")" = 1 ] && printf yes || printf no)"
t; assert_eq "T-539: the summary line uses the vault language" 'yes' \
  "$(grep -qF " $(awk -F= '$1 == "remember_events" { sub(/^[^=]*=/, ""); print; exit }' "$ROOT/i18n/tr.txt") · " \
       "$TMP/vr539/🔮 Asistan/Son-Oturum.md" && printf yes || printf no)"
# Control: with no session file anywhere, remember creates the vault-language
# name at the root -- Son-Oturum.md here, Last-Session.md in an en vault (vr35).
rm -f "$TMP/vr539/🔮 Asistan/Son-Oturum.md"
printf '%s\n' '2026-08-20T10:01 | PostToolUse | Read | baska.md' >> "$TMP/vr539/.knotlog/activity.log"
QUIPU_VAULT="$TMP/vr539" QUIPU_LANG=tr sh "$ROOT/knotlog" remember >/dev/null 2>&1
t; assert_eq "T-539: with no session file, the Turkish name is created at the root" 'yes' \
  "$([ -f "$TMP/vr539/Son-Oturum.md" ] && [ ! -f "$TMP/vr539/Last-Session.md" ] && printf yes || printf no)"

mkrem vr36
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vr36/.knotlog/activity.log"
t; OUT=$(rem vr36 --dry-run); RC=$?
assert_eq "remember: dry-run prints but writes nothing" 'yes' \
  "$([ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qF '## ' && printf '%s\n' "$OUT" | grep -qF 'Range: ' && [ ! -f "$TMP/vr36/700-Sessions/$D.md" ] && [ ! -f "$TMP/vr36/Last-Session.md" ] && [ ! -f "$TMP/vr36/.knotlog/remembered" ] && printf yes || printf no)"

mkrem vr37
printf '%s\n' \
  '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' \
  '2026-08-20T10:01 | PostToolUse | Edit | 500-Knowledge/not.md' \
  '2026-08-20T10:02 | PostToolUse | Read | 500-Knowledge/not.md' \
  '2026-08-20T10:03 | PostToolUse | Read | 500-Knowledge/other.md' \
  >> "$TMP/vr37/.knotlog/activity.log"
t; OUT=$(rem vr37); RC=$?
F37A=$(printf '  - %2d  %s' 3 '500-Knowledge/not.md')
F37B=$(printf '  - %2d  %s' 1 '500-Knowledge/other.md')
assert_eq "remember: digest counts tools and files" 'yes' \
  "$([ "$RC" -eq 0 ] && grep -qF 'Edit 2' "$TMP/vr37/700-Sessions/$D.md" && grep -qF 'Read 2' "$TMP/vr37/700-Sessions/$D.md" && grep -qF "$F37A" "$TMP/vr37/700-Sessions/$D.md" && grep -qF "$F37B" "$TMP/vr37/700-Sessions/$D.md" && printf yes || printf no)"

mkrem vr38
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/a.md' >> "$TMP/vr38/.knotlog/activity.log"
printf '%s\n' '2026-08-20T10:01 | PostToolUse | Read | 500-Knowledge/b.md' >> "$TMP/vr38/.knotlog/activity.log"
t; OUT=$(rem vr38 --limit 1); RC=$?
assert_eq "remember: --limit 1 lists one file" 'yes' \
  "$([ "$RC" -eq 0 ] && [ "$(grep -c '  - ' "$TMP/vr38/700-Sessions/$D.md")" = 1 ] && printf yes || printf no)"

mkrem vr39
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vr39/.knotlog/activity.log"
t; OUT=$(rem vr39 --git); RC=$?
assert_eq "remember: --git outside a repo is a no-op" 'yes' \
  "$([ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qF 'wrote:' && [ "$(printf '%s\n' "$OUT" | grep -cF "$REM_GIT")" = 0 ] && printf yes || printf no)"

mkrem vr40
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vr40/.knotlog/activity.log"
git init -q "$TMP/vr40"
t; OUT=$(GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t QUIPU_VAULT="$TMP/vr40" QUIPU_LANG=en sh "$ROOT/knotlog" remember --git); RC=$?
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t QUIPU_VAULT="$TMP/vr40" QUIPU_LANG=en sh "$ROOT/knotlog" remember --git >/dev/null 2>&1; RC2=$?
assert_eq "remember: --git commits once and skips empty" 'yes' \
  "$([ "$RC" -eq 0 ] && [ "$(git -C "$TMP/vr40" log --oneline | wc -l | tr -d ' ')" = 1 ] && printf '%s\n' "$OUT" | grep -qF "$REM_GIT" && [ "$RC2" -eq 0 ] && [ "$(git -C "$TMP/vr40" log --oneline | wc -l | tr -d ' ')" = 1 ] && printf yes || printf no)"

mkrem vr50
printf 'not a valid log line\n' > "$TMP/vr50/.knotlog/activity.log"
t; OUT=$(rem vr50); RC=$?
assert_eq "remember: malformed log is a no-op" 'yes' \
  "$([ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qF "$REM_EMPTY" && [ ! -f "$TMP/vr50/700-Sessions/$D.md" ] && [ ! -f "$TMP/vr50/Last-Session.md" ] && [ ! -f "$TMP/vr50/.knotlog/remembered" ] && printf yes || printf no)"

# ---- FAZ 3 E-4: claude-code adapter (data) + QUIPU_HOOK silent success ----

# T-46: adapter is pure data — no Windows shell cruft, no .sh in commands.
t; BAD=$(grep -E 'conhost|cmd\.exe' "$ROOT/adapters/claude-code.json")
assert_eq "adapter: no conhost/cmd.exe" '' "$BAD"
t; BAD=$(grep -oE '"command": "[^"]*"' "$ROOT/adapters/claude-code.json" | grep -E '\.sh')
assert_eq "adapter: no .sh in any command" '' "$BAD"

# T-47: every command is prefixed QUIPU_HOOK=1 quipu, every shell is bash,
# and "async": true appears exactly once (the PostToolUse hook).
t; CMDS=$(grep -cE '"command": "' "$ROOT/adapters/claude-code.json")
PREFIXED=$(grep -cE '"command": "KNOTLOG_HOOK=1 knotlog ' "$ROOT/adapters/claude-code.json")
assert_eq "adapter: every command starts with QUIPU_HOOK=1 quipu" "$CMDS" "$PREFIXED"
t; SHELLS=$(grep -cE '"shell": "' "$ROOT/adapters/claude-code.json")
BASHES=$(grep -cE '"shell": "bash"' "$ROOT/adapters/claude-code.json")
assert_eq "adapter: every shell is bash" "$SHELLS" "$BASHES"
t; ASYNC=$(grep -c '"async": true' "$ROOT/adapters/claude-code.json")
assert_eq "adapter: exactly one async hook" '1' "$ASYNC"

# T-48: QUIPU_HOOK turns _q_die into a silent success — exit 0 instead of the
# error code, while the message still reaches stderr. A vault-less cwd (no
# QUIPU_VAULT override, no .knotlog/config ancestor) triggers _q_die err_no_vault.
mkdir -p "$TMP/t48"
t; (cd "$TMP/t48" && QUIPU_HOOK=1 sh "$ROOT/knotlog" remember) >/dev/null 2>"$TMP/t48a.err"; RC=$?
assert_eq "hook: remember no vault exits 0 with stderr" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -s "$TMP/t48a.err" ] && printf yes || printf no)"
t; (cd "$TMP/t48" && sh "$ROOT/knotlog" remember) >/dev/null 2>"$TMP/t48b.err"; RC=$?
assert_eq "no-hook: remember no vault exits 1 with stderr" 'yes' \
  "$([ "$RC" -eq 1 ] && [ -s "$TMP/t48b.err" ] && printf yes || printf no)"
t; printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"x.md"}}' | (cd "$TMP/t48" && QUIPU_HOOK=1 sh "$ROOT/knotlog" capture) >/dev/null 2>"$TMP/t48c.err"; RC=$?
assert_eq "hook: capture no vault exits 0 with stderr" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -s "$TMP/t48c.err" ] && printf yes || printf no)"
t; printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"x.md"}}' | (cd "$TMP/t48" && sh "$ROOT/knotlog" capture) >/dev/null 2>"$TMP/t48d.err"; RC=$?
assert_eq "no-hook: capture no vault exits 1 with stderr" 'yes' \
  "$([ "$RC" -eq 1 ] && [ -s "$TMP/t48d.err" ] && printf yes || printf no)"

# T-49: doctor claude hooks line (C-28): settings with quipu -> installed,
# settings without quipu -> not installed. Both runs exit 0.
mkdir -p "$TMP/fakeh/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"quipu context --json SessionStart"}]}]}}\n' > "$TMP/fakeh/.claude/settings.json"
t; (cd "$TMP" && HOME="$TMP/fakeh" QUIPU_LANG=en sh "$ROOT/knotlog" doctor) >"$TMP/fakeh1.out" 2>&1; RC=$?
assert_eq "doctor: hooks installed when settings has quipu" 'yes' \
  "$([ "$RC" -eq 0 ] && awk -F"$TAB" '$2=="claude hooks" && $3=="installed" {f=1} END {exit !f}' "$TMP/fakeh1.out" && printf yes || printf no)"
printf '{}\n' > "$TMP/fakeh/.claude/settings.json"
t; (cd "$TMP" && HOME="$TMP/fakeh" QUIPU_LANG=en sh "$ROOT/knotlog" doctor) >"$TMP/fakeh2.out" 2>&1; RC=$?
assert_eq "doctor: hooks not installed when settings lacks quipu" 'yes' \
  "$([ "$RC" -eq 0 ] && awk -F"$TAB" '$2=="claude hooks" && $3=="not installed" {f=1} END {exit !f}' "$TMP/fakeh2.out" && printf yes || printf no)"

# T-293..T-295: doctor claude hooks line, vault-local settings.json (C-28
# regression: knotlog install >=v2.1.3 writes the hook to
# <vault>/.claude/settings.json, not the global $HOME/.claude/settings.json
# T-49 above covers; a correctly installed vault used to be reported as
# "not installed"). All three run with an empty $HOME/.claude (no global
# file) unless noted, and cd into the vault so _q_vault resolves it.
mkvault v293
mkdir -p "$TMP/v293/.claude" "$TMP/home293/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"quipu context --json SessionStart"}]}]}}\n' > "$TMP/v293/.claude/settings.json"
t; (cd "$TMP/v293" && HOME="$TMP/home293" QUIPU_LANG=en sh "$ROOT/knotlog" doctor) >"$TMP/v293.out" 2>&1; RC=$?
assert_eq "T-293: doctor hooks installed (vault) when vault-local settings.json has quipu" 'yes' \
  "$([ "$RC" -eq 0 ] && awk -F"$TAB" '$2=="claude hooks" && $3=="installed (vault)" {f=1} END {exit !f}' "$TMP/v293.out" && printf yes || printf no)"

mkvault v294
mkdir -p "$TMP/home294/.claude"
t; (cd "$TMP/v294" && HOME="$TMP/home294" QUIPU_LANG=en sh "$ROOT/knotlog" doctor) >"$TMP/v294.out" 2>&1; RC=$?
assert_eq "T-294: doctor hooks not installed when neither vault-local nor global settings.json exist" 'yes' \
  "$([ "$RC" -eq 0 ] && awk -F"$TAB" '$2=="claude hooks" && $3=="not installed" {f=1} END {exit !f}' "$TMP/v294.out" && printf yes || printf no)"

mkvault v295
mkdir -p "$TMP/home295/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"quipu context --json SessionStart"}]}]}}\n' > "$TMP/home295/.claude/settings.json"
t; (cd "$TMP/v295" && HOME="$TMP/home295" QUIPU_LANG=en sh "$ROOT/knotlog" doctor) >"$TMP/v295.out" 2>&1; RC=$?
assert_eq "T-295: doctor hooks installed (global) when only global settings.json has quipu and cwd is inside a vault" 'yes' \
  "$([ "$RC" -eq 0 ] && awk -F"$TAB" '$2=="claude hooks" && $3=="installed" {f=1} END {exit !f}' "$TMP/v295.out" && printf yes || printf no)"

# T-296..T-298: doctor identity warning names the key that is actually
# missing (regression: previously any single missing key printed the
# "user=/companion=" combined text even when the other value was present).
mkvault v296
QUIPU_VAULT="$TMP/v296" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --user Ayse >/dev/null 2>&1
t; (cd "$TMP/v296" && QUIPU_LANG=en "$ROOT/knotlog" doctor) >"$TMP/v296.out" 2>&1; RC=$?
assert_eq "T-296: doctor with only user= set names companion as missing, not user" 'yes' \
  "$([ "$RC" -eq 0 ] && awk -F"$TAB" '$2=="identity" && $1=="warn" {print $3}' "$TMP/v296.out" | grep -qF "$(i18n doc_identity_missing_companion)" && ! awk -F"$TAB" '$2=="identity"{print $3}' "$TMP/v296.out" | grep -qF "$(i18n doc_identity_missing_user)" && printf yes || printf no)"

mkvault v297
QUIPU_VAULT="$TMP/v297" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --companion Kuz >/dev/null 2>&1
t; (cd "$TMP/v297" && QUIPU_LANG=en "$ROOT/knotlog" doctor) >"$TMP/v297.out" 2>&1; RC=$?
assert_eq "T-297: doctor with only companion= set names user as missing, not companion" 'yes' \
  "$([ "$RC" -eq 0 ] && awk -F"$TAB" '$2=="identity" && $1=="warn" {print $3}' "$TMP/v297.out" | grep -qF "$(i18n doc_identity_missing_user)" && ! awk -F"$TAB" '$2=="identity"{print $3}' "$TMP/v297.out" | grep -qF "$(i18n doc_identity_missing_companion)" && printf yes || printf no)"

mkvault v298
QUIPU_VAULT="$TMP/v298" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
t; (cd "$TMP/v298" && QUIPU_LANG=en "$ROOT/knotlog" doctor) >"$TMP/v298.out" 2>&1; RC=$?
assert_eq "T-298: doctor with neither set names both as missing" 'yes' \
  "$([ "$RC" -eq 0 ] && awk -F"$TAB" '$2=="identity" && $1=="warn" {print $3}' "$TMP/v298.out" | grep -qF "$(i18n doc_identity_missing)" && printf yes || printf no)"

# ---- FAZ 4: codex adapter (data) + static checks (T-54..T-56) ----

# T-54: four event keys present, no PreCompact (K-11).
t; EVENTS=$(grep -cE '"(SessionStart|UserPromptSubmit|PostToolUse|SessionEnd)":' "$ROOT/adapters/codex/hooks.json")
assert_eq "codex adapter: four events present, no PreCompact" 'yes' \
  "$([ "$EVENTS" = 4 ] && ! grep -q 'PreCompact' "$ROOT/adapters/codex/hooks.json" && printf yes || printf no)"

# T-55: no "shell" field, "env" key, conhost, cmd.exe, or .sh (K-14/K-16).
t; BAD=$(grep -E '"shell"|"env"|conhost|cmd\.exe|\.sh' "$ROOT/adapters/codex/hooks.json")
assert_eq "codex adapter: no shell/env/conhost/cmd.exe/.sh" '' "$BAD"

# T-56: every command prefixed QUIPU_HOOK=1 quipu, commandWindows count matches,
# PostToolUse is synchronous and its matcher is apply_patch (K-12/K-13/K-15).
# Five commands since the checkpoint signal added Stop (485b012): the four
# events above plus Stop.
t; CMDS=$(grep -cE '"command":' "$ROOT/adapters/codex/hooks.json")
WINS=$(grep -cE '"commandWindows":' "$ROOT/adapters/codex/hooks.json")
PREFIXED=$(grep -cE '"command": "KNOTLOG_HOOK=1 knotlog ' "$ROOT/adapters/codex/hooks.json")
ASYNC=$(grep -c '"async": true' "$ROOT/adapters/codex/hooks.json")
MATCHER=$(grep -c '"matcher": "apply_patch"' "$ROOT/adapters/codex/hooks.json")
assert_eq "codex adapter: prefixed commands, windows parity, sync capture, apply_patch matcher" 'yes' \
  "$([ "$CMDS" = 5 ] && [ "$WINS" = 5 ] && grep -q '"Stop":' "$ROOT/adapters/codex/hooks.json" && [ "$PREFIXED" = "$CMDS" ] && [ "$ASYNC" = 0 ] && [ "$MATCHER" = 1 ] && printf yes || printf no)"

# ---- capture: Windows-form path normalization (FAZ 3, live layer finding) ----

if command -v cygpath >/dev/null 2>&1; then
  mkvault vcapwin
  WINTMP=$(cygpath -w "$TMP/vcapwin")
  # The backslashes below are DATA inside single quotes (PLAN 4.11).
  t; QUIPU_VAULT="$TMP/vcapwin" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path "$WINTMP\\500-Knowledge\\not.md"
  assert_eq "capture: Windows path becomes vault-relative" 'PostToolUse | Edit | 500-Knowledge/not.md' "$(log_line "$TMP/vcapwin")"
else
  t; skip "capture: Windows path becomes vault-relative" "cygpath not installed"
fi

# ---- FAZ 5: capture --git (T-57..T-64, T-69, T-70) + context --bridge (T-65..T-68, T-71) ----

git_commit() { # dir msg
  git -C "$TMP/$1" add -A
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -C "$TMP/$1" commit -qm "$2"
}
mk_git_vault() { # dir -> mkvault + git init + initial commit
  mkvault "$1"
  git init -q "$TMP/$1"
  git_commit "$1" init
}

# T-57: one changed tracked .md -> one gitdiff line.
mk_git_vault vgit57
printf 'v1\n' > "$TMP/vgit57/note.md"
git_commit vgit57 add-note
printf 'v2\n' >> "$TMP/vgit57/note.md"
t; QUIPU_VAULT="$TMP/vgit57" sh "$ROOT/knotlog" capture --git
assert_eq "capture --git: one changed .md -> one line" 'gitdiff | git | note.md' "$(log_line "$TMP/vgit57")"

# T-58: multi-file diff -> one line per file, exact count.
mk_git_vault vgit58
printf 'a\n' > "$TMP/vgit58/a.md"
printf 'b\n' > "$TMP/vgit58/b.md"
printf 'c\n' > "$TMP/vgit58/c.md"
git_commit vgit58 add
printf 'a2\n' >> "$TMP/vgit58/a.md"
printf 'b2\n' >> "$TMP/vgit58/b.md"
printf 'c2\n' >> "$TMP/vgit58/c.md"
t; QUIPU_VAULT="$TMP/vgit58" sh "$ROOT/knotlog" capture --git
assert_eq "capture --git: multi-file diff -> 3 lines" '3' "$(awk 'END{print NR}' "$TMP/vgit58/.knotlog/activity.log")"

# T-59: untracked new .md -> captured via ls-files --others.
mk_git_vault vgit59
printf 'new\n' > "$TMP/vgit59/new.md"
t; QUIPU_VAULT="$TMP/vgit59" sh "$ROOT/knotlog" capture --git
assert_eq "capture --git: untracked new .md captured" 'gitdiff | git | new.md' "$(log_line "$TMP/vgit59")"

# T-60: non-.md change -> no line (H-4 filter).
mk_git_vault vgit60
printf 'd\n' > "$TMP/vgit60/data.txt"
git_commit vgit60 add-txt
printf 'd2\n' >> "$TMP/vgit60/data.txt"
t; OUT=$(QUIPU_VAULT="$TMP/vgit60" sh "$ROOT/knotlog" capture --git); RC=$?
assert_eq "capture --git: non-md change -> no line" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$TMP/vgit60/.knotlog/activity.log" ] && printf yes || printf no)"

# T-61: AGENTS.md / CLAUDE.md change -> no line (H-4).
mk_git_vault vgit61
printf '# a\n' > "$TMP/vgit61/AGENTS.md"
printf '# c\n' > "$TMP/vgit61/CLAUDE.md"
git_commit vgit61 add-bridge
printf '# a2\n' >> "$TMP/vgit61/AGENTS.md"
printf '# c2\n' >> "$TMP/vgit61/CLAUDE.md"
t; OUT=$(QUIPU_VAULT="$TMP/vgit61" sh "$ROOT/knotlog" capture --git); RC=$?
assert_eq "capture --git: AGENTS.md/CLAUDE.md change -> no line" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$TMP/vgit61/.knotlog/activity.log" ] && printf yes || printf no)"

# T-62 (DZ-8b): vault that is not a repo -> silent exit 0; "git yok" left [doğrulanmadı].
mkvault vgit62
printf 'x\n' > "$TMP/vgit62/note.md"
t; OUT=$(QUIPU_VAULT="$TMP/vgit62" sh "$ROOT/knotlog" capture --git); RC=$?
assert_eq "capture --git: not a repo -> silent exit 0" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$TMP/vgit62/.knotlog/activity.log" ] && printf yes || printf no)"

# T-63: clean tree -> exit 0, no line.
mk_git_vault vgit63
printf 'x\n' > "$TMP/vgit63/note.md"
git_commit vgit63 add
t; OUT=$(QUIPU_VAULT="$TMP/vgit63" sh "$ROOT/knotlog" capture --git); RC=$?
assert_eq "capture --git: clean tree -> silent exit 0" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$TMP/vgit63/.knotlog/activity.log" ] && printf yes || printf no)"

# T-64: deleted .md -> recorded (H-9; index `drop` handles it later).
mk_git_vault vgit64
printf 'x\n' > "$TMP/vgit64/gone.md"
git_commit vgit64 add
rm "$TMP/vgit64/gone.md"
t; QUIPU_VAULT="$TMP/vgit64" sh "$ROOT/knotlog" capture --git
assert_eq "capture --git: deleted .md recorded" 'gitdiff | git | gone.md' "$(log_line "$TMP/vgit64")"

# T-69 (DZ-2): unborn HEAD + untracked .md -> no abort, line present (ls-files path).
mkvault vgit69
git init -q "$TMP/vgit69"
printf 'x\n' > "$TMP/vgit69/note.md"
t; OUT=$(QUIPU_VAULT="$TMP/vgit69" sh "$ROOT/knotlog" capture --git); RC=$?
assert_eq "capture --git: unborn HEAD + untracked .md -> line present" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ "$(log_line "$TMP/vgit69")" = 'gitdiff | git | note.md' ] && printf yes || printf no)"

# T-70 (DZ-3): .md under .knotlog/ -> filtered out (prefix test, not the old filter).
mk_git_vault vgit70
printf 'x\n' > "$TMP/vgit70/.knotlog/secret.md"
t; OUT=$(QUIPU_VAULT="$TMP/vgit70" sh "$ROOT/knotlog" capture --git); RC=$?
assert_eq "capture --git: .knotlog/ .md filtered out" 'yes' \
  "$([ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$TMP/vgit70/.knotlog/activity.log" ] && printf yes || printf no)"

# ---- context --bridge (T-65..T-68, T-71) ----

# T-65: context block + context text inside; static block and user content preserved.
mkvault vbridge
printf 'user line 1\nuser line 2\n' > "$TMP/vbridge/AGENTS.md"
printf 'static body\n' | awk -f "$LIB/block.awk" "$TMP/vbridge/AGENTS.md" > "$TMP/vbridge/.knotlog/t.tmp" && mv "$TMP/vbridge/.knotlog/t.tmp" "$TMP/vbridge/AGENTS.md"
printf '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md\n' >> "$TMP/vbridge/.knotlog/activity.log"
t; QUIPU_LANG=en QUIPU_VAULT="$TMP/vbridge" sh "$ROOT/knotlog" context --bridge >/dev/null 2>&1
assert_eq "context --bridge: context block + user content + static block preserved" 'yes' \
  "$(grep -q '^<!-- knotlog:context:start -->$' "$TMP/vbridge/AGENTS.md" \
     && grep -q '^<!-- knotlog:context:end -->$' "$TMP/vbridge/AGENTS.md" \
     && grep -q '^<!-- knotlog:start -->$' "$TMP/vbridge/AGENTS.md" \
     && grep -q '^user line 1$' "$TMP/vbridge/AGENTS.md" \
     && grep -q '^user line 2$' "$TMP/vbridge/AGENTS.md" \
     && grep -q '500-Knowledge/not.md' "$TMP/vbridge/AGENTS.md" && printf yes || printf no)"

# T-284 (regression): vbridge's config has no user=/companion= (mkvault
# writes an empty config) -- the new identity line (ctx_identity_*) must stay
# entirely absent, not just empty, for an identity-less vault.
t; assert_eq "T-284: context --bridge: no identity line for identity-less vault" 'no' \
  "$(grep -qE 'in this vault|is named' "$TMP/vbridge/AGENTS.md" && printf yes || printf no)"

# T-66: idempotent — second run does not duplicate the block.
t; QUIPU_LANG=en QUIPU_VAULT="$TMP/vbridge" sh "$ROOT/knotlog" context --bridge >/dev/null 2>&1
assert_eq "context --bridge: idempotent (single context block)" '1' "$(grep -c 'knotlog:context:start' "$TMP/vbridge/AGENTS.md")"

# T-67: stdout carries only the confirmation, not the raw context (i18n, QUIPU_LANG=en).
t; OUT=$(QUIPU_LANG=en QUIPU_VAULT="$TMP/vbridge" sh "$ROOT/knotlog" context --bridge); RC=$?
BRIDGE_OK=$(i18n bridge_updated)
assert_eq "context --bridge: stdout only confirmation" "$BRIDGE_OK" "$OUT"

# T-68 (DZ-5): -v override targets the context markers (conditional BEGIN).
: > "$TMP/t68.md"
printf 'ctx body\n' | awk -v start='<!-- quipu:context:start -->' -v end='<!-- quipu:context:end -->' -f "$LIB/block.awk" "$TMP/t68.md" > "$TMP/t68.out"
t; assert_eq "block.awk: -v override replaces default markers" 'yes' \
  "$(grep -q '^<!-- quipu:context:start -->$' "$TMP/t68.out" && grep -q '^ctx body$' "$TMP/t68.out" && ! grep -q '^<!-- quipu:start -->$' "$TMP/t68.out" && printf yes || printf no)"

# T-71 (DZ-5): without -v the exact default markers are preserved (literal lock).
: > "$TMP/t71.md"
printf 'default body\n' | awk -f "$LIB/block.awk" "$TMP/t71.md" > "$TMP/t71.out"
t; assert_eq "block.awk: default markers exact text" 'yes' \
  "$(grep -q '^<!-- knotlog:start -->$' "$TMP/t71.out" && grep -q '^<!-- knotlog:end -->$' "$TMP/t71.out" && grep -q '^default body$' "$TMP/t71.out" && printf yes || printf no)"

# ---- FAZ 6: e2e chain scenarios (T-72..T-73) ----

# T-72 (I-2): the whole chain in one vault — init -> flag-mode capture -> index
# -> search. Each step's exit code is asserted on its own (SPEC 3, T-72), so a
# regression is pinned to one link instead of surfacing only at the last hop.
# `init` now pins fold=tr itself (V1-DUZELTME R-1), so no manual config patch
# is needed (P-6). QUIPU_LANG is deliberately NOT set on this init call: it
# would outrank the just-written config lang=tr in the _q_lang chain and pin
# fold=default instead (`init --lang tr` alone is enough; only the message
# text of the LATER commands needs QUIPU_LANG=en for ASCII stability).
t; QUIPU_VAULT="$TMP/vchain" sh "$ROOT/knotlog" init --lang tr >/dev/null 2>&1; RC=$?
assert_eq "chain: init exits 0" '0' "$RC"
printf '# Notlar\n\nAlpha zincir notu.\n' > "$TMP/vchain/note.md"

# Flag-mode capture needs no JSON fixture (G-4) — the chain stays hermetic.
t; QUIPU_VAULT="$TMP/vchain" QUIPU_LANG=en sh "$ROOT/knotlog" capture --event PostToolUse --tool Write --path note.md; RC=$?
assert_eq "chain: capture exits 0" '0' "$RC"
t; assert_eq "chain: capture appends the flag-mode line" 'PostToolUse | Write | note.md' "$(log_line "$TMP/vchain")"

t; QUIPU_VAULT="$TMP/vchain" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1; RC=$?
assert_eq "chain: index exits 0" '0' "$RC"

t; CHAIN_HIT=$(QUIPU_VAULT="$TMP/vchain" QUIPU_LANG=en sh "$ROOT/knotlog" search alpha | awk -F"$TAB" 'NR==1{print $2}')
assert_eq "chain: search returns the captured note" 'note.md' "$CHAIN_HIT"

# T-73 (I-3): the Turkish form of the same chain. The note says "İstanbul ışık";
# indexing folds it, so the lowercase query hits, and the dotted-capital query
# must return the byte-identical result set — index folding == query folding all
# the way along the chain (SPEC 4.2 in chain form). `init` pins fold=tr itself
# (R-1); QUIPU_LANG is withheld on this call for the same reason as T-72 (P-6).
QUIPU_VAULT="$TMP/vchaintr" sh "$ROOT/knotlog" init --lang tr >/dev/null 2>&1
printf '# Işık\n\nİstanbul ışık deneyleri burada.\n' > "$TMP/vchaintr/istanbul.md"
QUIPU_VAULT="$TMP/vchaintr" QUIPU_LANG=en sh "$ROOT/knotlog" capture --event PostToolUse --tool Write --path istanbul.md >/dev/null 2>&1
QUIPU_VAULT="$TMP/vchaintr" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1

t; CHAIN_TR_LOWER=$(QUIPU_VAULT="$TMP/vchaintr" QUIPU_LANG=en sh "$ROOT/knotlog" search istanbul | awk -F"$TAB" '{print $2}')
assert_eq "chain tr: lowercase query returns the folded note" 'istanbul.md' "$CHAIN_TR_LOWER"

# Dotted capital İ (U+0130): same path list, or the folding broke mid-chain.
t; CHAIN_TR_UPPER=$(QUIPU_VAULT="$TMP/vchaintr" QUIPU_LANG=en sh "$ROOT/knotlog" search İstanbul | awk -F"$TAB" '{print $2}')
assert_eq "chain tr: dotted-capital query matches lowercase run" "$CHAIN_TR_LOWER" "$CHAIN_TR_UPPER"

# ---- FAZ 6: index summary shape + git chain + doctor (T-74..T-77) ----

# T-74 (I-4): first index run. The exact line is locked against the i18n
# template under QUIPU_LANG=en, then the same counts are re-read through
# language-independent field extraction so a translation change cannot mask a
# counting bug.
mk_index_vault vidx74
(cd "$TMP/vidx74" && QUIPU_LANG=en "$ROOT/knotlog" index) >"$TMP/vidx74.out" 2>&1
# idx_summary is the controlled i18n template (not user data); args are integers.
# shellcheck disable=SC2059
EXP74=$(printf "$(awk -F= -v k=idx_summary '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")" 3 0 3 0)
t; assert_eq "index: first run summary is the exact idx_summary line" "$EXP74" "$(cat "$TMP/vidx74.out")"
t; assert_eq "index: first run fields are 3 0 3 0" '3 0 3 0' "$(idx_nums "$TMP/vidx74.out")"

# T-75 (I-4): an unchanged second run reuses every row; touching one file makes
# exactly that row stale and leaves the other two reused.
(cd "$TMP/vidx74" && QUIPU_LANG=en "$ROOT/knotlog" index) >"$TMP/vidx74.out" 2>&1
t; assert_eq "index: unchanged second run reuses 3, stale 0" '3 3 0 0' "$(idx_nums "$TMP/vidx74.out")"
sleep 1
touch "$TMP/vidx74/heading.md"
(cd "$TMP/vidx74" && QUIPU_LANG=en "$ROOT/knotlog" index) >"$TMP/vidx74.out" 2>&1
t; assert_eq "index: one touched file leaves stale 1, reused 2" '3 2 1 0' "$(idx_nums "$TMP/vidx74.out")"

# T-76 (I-5): the git chain in one vault — init --git -> commit -> note.md ->
# capture --git -> index -> search hit -> remember --git (which commits by
# itself) -> commit leftovers -> capture --git again. The core claim is the last
# one: the commit consumed the diff, so no second gitdiff line appears (H-9
# honesty proven end to end). `init` pins fold=tr itself (R-1); QUIPU_LANG is
# withheld on this call for the same reason as T-72/T-73 (P-6). gitdiff lines
# are counted with awk index() rather than grep, keeping the pattern policy
# uniform (PLAN 4.3).
mkdir -p "$TMP/vgitchain"
QUIPU_VAULT="$TMP/vgitchain" sh "$ROOT/knotlog" init --git --lang tr >/dev/null 2>&1
git_commit vgitchain init
printf 'Alpha git zinciri notu.\n' > "$TMP/vgitchain/note.md"

t; QUIPU_VAULT="$TMP/vgitchain" sh "$ROOT/knotlog" capture --git
assert_eq "git chain: first capture --git logs one gitdiff line" '1' \
  "$(awk 'index($0, "gitdiff") > 0 {c++} END{print c+0}' "$TMP/vgitchain/.knotlog/activity.log")"

t; (cd "$TMP/vgitchain" && QUIPU_LANG=en "$ROOT/knotlog" index) >"$TMP/vgitchain.idx" 2>&1; RC=$?
assert_eq "git chain: index after capture exits 0" '0' "$RC"

t; assert_eq "git chain: search alpha returns note.md" 'note.md' \
  "$(QUIPU_VAULT="$TMP/vgitchain" QUIPU_LANG=en sh "$ROOT/knotlog" search alpha | awk 'NR==1{print $2}')"

GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  QUIPU_VAULT="$TMP/vgitchain" QUIPU_LANG=en sh "$ROOT/knotlog" remember --git >/dev/null 2>&1
# remember --git already committed; this only drains anything it left behind and
# must not fail the run when the tree is clean.
git_commit vgitchain after-remember >/dev/null 2>&1 || true

t; QUIPU_VAULT="$TMP/vgitchain" sh "$ROOT/knotlog" capture --git
assert_eq "git chain: capture --git after the commit adds no gitdiff line" '1' \
  "$(awk 'index($0, "gitdiff") > 0 {c++} END{print c+0}' "$TMP/vgitchain/.knotlog/activity.log")"

# T-77 (I-6): doctor over the full chain vault. The summary wording and the ok /
# warn counts are free to move (claude hooks are not installed here), so only the
# trailing number — the failure count — is asserted, language-independently.
t; (cd "$TMP/vgitchain" && QUIPU_LANG=en "$ROOT/knotlog" doctor) >"$TMP/vgitchain.doc" 2>&1; RC=$?
assert_eq "doctor: chain vault exits 0" '0' "$RC"
t; assert_eq "doctor: chain vault summary reports 0 fail" '0' \
  "$(awk 'END{ gsub(/[^0-9]/, " "); n = split($0, f, " "); print f[n] }' "$TMP/vgitchain.doc")"

# ---- FAZ 7: DZ-4 unknown flag diagnosis (T-78..T-81) ----

# DZ-4: an unrecognized flag must name itself and exit 2 on every command that
# parses flags, while the legacy "missing required argument" diagnosis stays
# byte-identical. err_unknown_flag is the controlled i18n template; the only
# argument is the flag itself.
# shellcheck disable=SC2059
FLAG_MSG=$(printf "$(i18n err_unknown_flag)\n" --bogus)

# T-78: capture.
mkvault vflag78
t; QUIPU_VAULT="$TMP/vflag78" QUIPU_LANG=en sh "$ROOT/knotlog" capture --bogus \
  </dev/null >/dev/null 2>"$TMP/vflag78-capture.err"; RC=$?
assert_eq "capture --bogus exits 2" '2' "$RC"
t; assert_eq "capture --bogus names the flag" "$FLAG_MSG" "$(cat "$TMP/vflag78-capture.err")"

# T-79: same diagnosis from init / context / remember.
for _c in init context remember; do
  t; QUIPU_VAULT="$TMP/vflag78" QUIPU_LANG=en sh "$ROOT/knotlog" "$_c" --bogus \
    </dev/null >/dev/null 2>"$TMP/vflag78-$_c.err"; RC=$?
  assert_eq "$_c --bogus exits 2" '2' "$RC"
  t; assert_eq "$_c --bogus names the flag" "$FLAG_MSG" "$(cat "$TMP/vflag78-$_c.err")"
done

# T-80: search must diagnose the flag instead of swallowing it as a query word.
# The vault is fully indexed, so nothing but the flag can fail the run.
mk_search_vault vflag80
QUIPU_VAULT="$TMP/vflag80" sh "$ROOT/knotlog" index >/dev/null 2>&1
t; QUIPU_VAULT="$TMP/vflag80" QUIPU_LANG=en sh "$ROOT/knotlog" search --bogus \
  >"$TMP/vflag80.out" 2>"$TMP/vflag80.err"; RC=$?
assert_eq "search --bogus exits 2" '2' "$RC"
t; assert_eq "search --bogus names the flag" "$FLAG_MSG" "$(cat "$TMP/vflag80.err")"
t; assert_eq "search --bogus prints no results" '' "$(cat "$TMP/vflag80.out")"

# T-81 regression: `_q_die key code` callers are untouched — a known flag
# starved of its value still gets the old message, with no flag interpolation.
t; QUIPU_VAULT="$TMP/vflag78" QUIPU_LANG=en sh "$ROOT/knotlog" capture --event \
  </dev/null >/dev/null 2>"$TMP/vflag78-event.err"; RC=$?
assert_eq "capture --event without value exits 2" '2' "$RC"
t; assert_eq "capture --event without value keeps err_missing_arg" \
  "$(i18n err_missing_arg)" "$(cat "$TMP/vflag78-event.err")"
t; assert_eq "capture --event without value mentions no flag" 'no' \
  "$(grep -qE 'unknown|--bogus' "$TMP/vflag78-event.err" && printf yes || printf no)"

# ---- FAZ 7: search --brief (T-82..T-84) ----

# The search fixture plus one document whose folded field is far longer than
# the 120-byte snippet window, so the cut path is actually exercised.
mk_search_vault vbrief
awk 'BEGIN{ s = "alpha"; for (i = 1; i <= 48; i++) s = s " wordnumber" i; print "# longdoc"; print ""; print s }' > "$TMP/vbrief/long-doc.md"
QUIPU_VAULT="$TMP/vbrief" sh "$ROOT/knotlog" index >/dev/null 2>&1

# T-82 (J-5): --brief adds a 5th TAB field, never wider than 120 bytes, and a
# folded field that already fits is carried through uncut.
#
# Byte vs character: gawk counts length()/substr() in CHARACTERS, mawk in
# BYTES. The claim below is a byte claim, so it only holds while every row
# matching `alpha` is pure ASCII — which it is: the fixture pins fold=tr, and
# the three matching documents (title-doc / body-doc / long-doc) are ASCII to
# begin with (measured: 194 bytes == 194 awk chars for the whole column).
# Do NOT add a matching document with non-ASCII folded text without switching
# this assertion to a real byte count.
BRIEF=$(QUIPU_VAULT="$TMP/vbrief" QUIPU_LANG=en sh "$ROOT/knotlog" search alpha --brief)
t; assert_eq "search --brief: every row has 5 fields" 'yes' "$(printf '%s\n' "$BRIEF" | awk -F"$TAB" '{if (NF != 5) bad++} END{print (bad ? "no" : "yes")}')"
t; assert_eq "search --brief: snippet is at most 120 bytes" 'yes' "$(printf '%s\n' "$BRIEF" | awk -F"$TAB" '{if (length($5) > 120) bad++} END{print (bad ? "no" : "yes")}')"
t; SHORT_FULL=$(awk -F"$TAB" '$1 == "body-doc.md" { print $5 }' "$TMP/vbrief/.knotlog/index.tsv")
assert_eq "search --brief: short field is emitted whole" "$SHORT_FULL" "$(printf '%s\n' "$BRIEF" | awk -F"$TAB" '$2 == "body-doc.md" { print $5 }')"

# T-83 (J-5): the long document's snippet stops on a word boundary. Proof: it
# does not end with a space, and in the full folded field the byte right after
# the snippet IS a space, so no word was split. The snippet and the full field
# reach awk as file arguments (never `awk -v`, which would mangle raw data).
QUIPU_VAULT="$TMP/vbrief" QUIPU_LANG=en sh "$ROOT/knotlog" search alpha --brief \
  | awk -F"$TAB" '$2 == "long-doc.md" { print $5 }' > "$TMP/vbrief-brief.txt"
awk -F"$TAB" '$1 == "long-doc.md" { print $5 }' "$TMP/vbrief/.knotlog/index.tsv" > "$TMP/vbrief-full.txt"
t; assert_eq "search --brief: snippet has no trailing space" 'yes' "$(awk 'NR == 1 { print (substr($0, length($0), 1) == " " ? "no" : "yes") }' "$TMP/vbrief-brief.txt")"
t; assert_eq "search --brief: cut lands on a word boundary" 'yes' "$(awk 'FNR == 1 && NR == 1 { b = $0; next } FNR == 1 { print (substr($0, 1, length(b)) == b && substr($0, length(b) + 1, 1) == " " ? "yes" : "no") }' "$TMP/vbrief-brief.txt" "$TMP/vbrief-full.txt")"

# T-84 (J-6): --brief and --paths are mutually exclusive.
t; QUIPU_VAULT="$TMP/vbrief" QUIPU_LANG=en sh "$ROOT/knotlog" search alpha --brief --paths >"$TMP/vbrief-conf.out" 2>"$TMP/vbrief-conf.err"; RC=$?
assert_eq "search --brief --paths exits 2" '2' "$RC"
t; assert_eq "search --brief --paths reports the conflict" "$(i18n err_conflict)" "$(cat "$TMP/vbrief-conf.err")"

# ---- V1-DUZELTME: CRLF-authored tag stays CR-free (--brief row safety) ----
#
# CI run 32576726590 (commit d955757, ubuntu-latest + macos-latest only;
# windows-latest passed) failed "scale: --brief rows have 5 fields" and
# "scale: --brief honours --limit 50 at scale" (expected 50, got 52). The
# SAME run's non-brief "scale: search returns all 5000 hits" (T-86) passed at
# an exact 5000/5000, which rules out a matching/count bug in path/title/tags
# and isolates the failure to the brief-only path (the extra snippet
# column). A later run (32578854473, commit fdf1218) reproduced the identical
# split ubuntu+macos fail / windows pass, confirming it tracks the AWK
# implementation (mawk on ubuntu, BWK awk on macOS; gawk ships with Git Bash
# on windows-latest), not the OS by itself.
#
# Investigation found a real, implementation-sensitive gap upstream of
# search.awk: lib/index.awk's trim_() strips CR from a title (gsub(CR, "",
# s)), but collect_tags() — used for BOTH frontmatter "tags:" values and body
# "#hashtag" scanning — never did. A CRLF-authored note hands collect_tags a
# $0 with a trailing \r still attached (only \n is a record separator to
# awk); when that \r lands on a line's LAST token (e.g. a trailing "#tag"),
# whether it survives split(s, parts, " ") depends on whether that specific
# awk's whitespace-splitting treats \r as blank. gawk does, which quietly
# masked the gap here (verified locally: this exact CRLF fixture round-trips
# clean under gawk even without the fix below) — nothing guarantees mawk or
# BWK awk do too. lib/index.awk's collect_tags() now strips CR itself
# (gsub(CR, "", s) before squish_brackets/split), independent of whichever
# awk's split(" ") happens to treat as whitespace. lib/search.awk additionally
# gained a scrub() choke point (title/tags/snippet all pass through it before
# printf) as defense in depth: whatever the exact byte-level mechanism behind
# the ubuntu/macos --brief split turns out to be, no field reaching that
# printf can carry a raw TAB/CR/LF into the emitted row.
#
# NOT independently reproduced at 5000-doc scale here: real `knotlog index`
# costs ~6 subprocess spawns per stale file, and this environment measured
# ~3.7s/file (vs. 27s TOTAL for all 5000 files on ubuntu-latest CI) — a real
# 5000-doc index would run for hours, not the ~40 minutes the scale test
# already costs on a normal Linux runner, so it was not attempted here. This
# fixture instead pins the ONE gap identified by static+dynamic (gawk)
# investigation: it would have failed before the collect_tags() fix (an
# unfixed run leaves the \r on the tag, so index.tsv's tags column and its
# length() both come out dirty) and passes after it, on the only awk (gawk)
# available in this environment.
mkdir -p "$TMP/vcrlf/.knotlog"
printf 'fold=default\nlang=en\n' > "$TMP/vcrlf/.knotlog/config"
CRB=$(printf '\r')
printf '# crlf note%s\n%s\nortakterim body #tag1 #tag2%s\n' "$CRB" "$CRB" "$CRB" > "$TMP/vcrlf/crlf-doc.md"
QUIPU_VAULT="$TMP/vcrlf" sh "$ROOT/knotlog" index >/dev/null 2>&1
t; assert_eq "index: CRLF-authored tag has no embedded CR" '9' \
  "$(awk -F"$TAB" '$1 == "crlf-doc.md" { print length($3) }' "$TMP/vcrlf/.knotlog/index.tsv")"
t; assert_eq "index: CRLF-authored tag value is exactly tag1,tag2" 'tag1,tag2' \
  "$(awk -F"$TAB" '$1 == "crlf-doc.md" { print $3 }' "$TMP/vcrlf/.knotlog/index.tsv")"
BRIEFCRLF=$(QUIPU_VAULT="$TMP/vcrlf" QUIPU_LANG=en sh "$ROOT/knotlog" search ortakterim --brief)
t; assert_eq "search --brief: CRLF-doc row is one line with 5 fields" 'yes' \
  "$(printf '%s\n' "$BRIEFCRLF" | awk -F"$TAB" '{n++; if (NF != 5) bad=1} END{print (n == 1 && bad != 1) ? "yes" : "no"}')"

# ---- FAZ 12: streamed two-pass search engine (T-170..T-180) ----
#
# lib/search.awk's pre-FAZ12 mode=bm25 read index.tsv once into four
# parallel per-document arrays (path[]/title[]/tags[]/folded[]), so memory
# grew with document count (docs/FAZ12-BULGULAR.md E-1/E-2). FAZ 12 replaced
# it with mode=bm25count (df/avgdl/fallback, streamed) + mode=bm25score
# (per-row scoring, streamed), joined by a small dfstats scratch file whose
# size is bounded by QUERY TERM count, not document count. The expected
# scores pinned below were captured by running the pre-FAZ12 engine
# (git show 4207b64:lib/search.awk) against the SAME fixtures before the
# rewrite (docs/FAZ12-BULGULAR.md's "uygulama sonrası doğrulama notu").

mk_search_vault vt170
QUIPU_VAULT="$TMP/vt170" sh "$ROOT/knotlog" index >/dev/null 2>&1

# T-170: two-pass engine output is byte-identical to the pre-FAZ12
# single-pass engine's output on the mk_search_vault fixture.
T170=$(QUIPU_VAULT="$TMP/vt170" sh "$ROOT/knotlog" search alpha)
t; assert_eq "T-170: two-pass score/order matches the pre-FAZ12 reference (title-doc first)" \
  "1.099${TAB}title-doc.md${TAB}alpha${TAB}
0.520${TAB}body-doc.md${TAB}beta${TAB}" "$T170"

# T-171: process-structure proof that K-1's split actually landed -- a
# wrapped PATH (same counting-wrapper technique as T-150) shows `awk -f
# .../lib/search.awk` running exactly 2 times per `knotlog search` call (the
# outer sort/limit awk has no -f lib/search.awk, so it does not count).
mkdir -p "$TMP/t171wrap"
: > "$TMP/t171.count"
REALAWK=$(command -v awk)
cat > "$TMP/t171wrap/awk" <<WRAPEOF
#!/bin/sh
case "\$*" in
  *search.awk*) printf 'x\n' >> "$TMP/t171.count" ;;
esac
exec "$REALAWK" "\$@"
WRAPEOF
chmod +x "$TMP/t171wrap/awk"
PATH="$TMP/t171wrap:$PATH" QUIPU_VAULT="$TMP/vt170" sh "$ROOT/knotlog" search alpha >/dev/null 2>&1
t; assert_eq "T-171: knotlog search runs -f lib/search.awk exactly 2 times" '2' "$(awk 'END{print NR}' "$TMP/t171.count")"

# T-172 (K-3 regression under the two-pass engine): --brief still 5 fields,
# snippet still <=120 bytes.
mk_search_vault vt172
awk 'BEGIN{ s = "alpha"; for (i = 1; i <= 48; i++) s = s " wordnumber" i; print "# longdoc"; print ""; print s }' > "$TMP/vt172/long-doc.md"
QUIPU_VAULT="$TMP/vt172" sh "$ROOT/knotlog" index >/dev/null 2>&1
BRIEF172=$(QUIPU_VAULT="$TMP/vt172" sh "$ROOT/knotlog" search alpha --brief)
t; assert_eq "T-172: --brief still 5 fields under two-pass" 'yes' "$(printf '%s\n' "$BRIEF172" | awk -F"$TAB" '{if (NF != 5) bad++} END{print (bad ? "no" : "yes")}')"
t; assert_eq "T-172: --brief snippet still <=120 bytes under two-pass" 'yes' "$(printf '%s\n' "$BRIEF172" | awk -F"$TAB" '{if (length($5) > 120) bad++} END{print (bad ? "no" : "yes")}')"

# T-173 (K-4 regression): --tag/--status narrowing still an elimination
# filter under the split count/score passes.
mkdir -p "$TMP/vt173/.knotlog"
cat > "$TMP/vt173/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt173/alpha-active.md" <<'EOF'
---
title: Alpha Active
tags: alpha, common
status: active
type: task
---
common word appears here.
EOF
cat > "$TMP/vt173/beta-closed.md" <<'EOF'
---
title: Beta Closed
tags: beta, common
status: closed
type: task
---
common word appears here too.
EOF
QUIPU_VAULT="$TMP/vt173" sh "$ROOT/knotlog" index >/dev/null 2>&1
t; TAGGED173=$(QUIPU_VAULT="$TMP/vt173" sh "$ROOT/knotlog" search common --tag alpha --paths)
assert_eq "T-173: --tag alpha keeps only the tagged doc under two-pass" 'alpha-active.md' "$TAGGED173"
t; STATUSED173=$(QUIPU_VAULT="$TMP/vt173" sh "$ROOT/knotlog" search common --status closed --paths)
assert_eq "T-173: --status closed keeps only the closed doc under two-pass" 'beta-closed.md' "$STATUSED173"

# T-174 (K-5 regression): --limit stays awk-side, not `head` -- no "Broken
# pipe" on stderr (209a326's fixed class must not reopen).
QUIPU_VAULT="$TMP/vt170" sh "$ROOT/knotlog" search alpha --limit 1 >"$TMP/t174.out" 2>"$TMP/t174.err"
t; assert_eq "T-174: small --limit produces no stderr (no Broken pipe)" '' "$(cat "$TMP/t174.err")"

# T-175: single-doc vault, negative IDF -- the `matched` flag still
# compensates and returns the hit (PLAN §7 "Negatif IDF" regression).
mkdir -p "$TMP/vt175/.knotlog"
cat > "$TMP/vt175/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
printf '# only\n\nonly document with unique words here.\n' > "$TMP/vt175/solo.md"
QUIPU_VAULT="$TMP/vt175" sh "$ROOT/knotlog" index >/dev/null 2>&1
T175=$(QUIPU_VAULT="$TMP/vt175" sh "$ROOT/knotlog" search unique --paths)
t; assert_eq "T-175: single-doc vault, negative IDF still returns the match" 'solo.md' "$T175"

# T-176 (K-6 regression): title (x2) and tag (x1.5) boosts still outrank a
# body-only match. Needs df well below n -- with df==n the IDF is negative
# and multiplying a negative contrib by the boost factor makes the score
# MORE negative (inherent to the pre-FAZ12 formula too, ported unchanged,
# not a two-pass artifact), so three term-free filler docs keep df << n.
mkdir -p "$TMP/vt176/.knotlog"
cat > "$TMP/vt176/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt176/title-boost.md" <<'EOF'
# boostword
plain body text with unrelated words.
EOF
cat > "$TMP/vt176/body-only.md" <<'EOF'
# unrelated heading
boostword appears only in this body.
EOF
cat > "$TMP/vt176/tag-boost.md" <<'EOF'
---
title: Unrelated Title
tags: boosttag
---
boosttag appears once in this body too.
EOF
cat > "$TMP/vt176/tag-plain.md" <<'EOF'
---
title: Unrelated Title Two
---
boosttag appears once in this body as well.
EOF
printf 'filler one with none of the query terms at all.\n' > "$TMP/vt176/filler1.md"
printf 'filler two with none of the query terms at all.\n' > "$TMP/vt176/filler2.md"
printf 'filler three with none of the query terms at all.\n' > "$TMP/vt176/filler3.md"
QUIPU_VAULT="$TMP/vt176" sh "$ROOT/knotlog" index >/dev/null 2>&1
FIRST176T=$(QUIPU_VAULT="$TMP/vt176" sh "$ROOT/knotlog" search boostword | awk 'NR==1{print $2}')
t; assert_eq "T-176: title match (x2 boost) ranks ahead of body-only match" 'title-boost.md' "$FIRST176T"
FIRST176G=$(QUIPU_VAULT="$TMP/vt176" sh "$ROOT/knotlog" search boosttag | awk 'NR==1{print $2}')
t; assert_eq "T-176: tag match (x1.5 boost) ranks ahead of body-only match" 'tag-boost.md' "$FIRST176G"

# T-177 (E-4/K-1 regression): prefix query ("istan") still returns hits via
# the substring fallback -- proof bm25count's END-block second getline pass
# over idxfile still works.
T177=$(QUIPU_VAULT="$TMP/vt170" sh "$ROOT/knotlog" search istan)
t; assert_eq "T-177: prefix query 'istan' returns hits via substring fallback" \
  "0.619${TAB}istanbul-b.md${TAB}${TAB}
0.549${TAB}istanbul-a.md${TAB}notlar${TAB}" "$T177"

# T-178 (K-7): static check -- lib/search.awk's new bm25count/bm25score code
# introduces no `~`/`!~` regex usage (same whole-file static-check style
# T-163 already uses for lib/index.awk, applied here for the first time).
REGEX_COUNT_SEARCH=$(awk '/~/{n++} END{print n+0}' "$LIB/search.awk")
t; assert_eq "T-178: lib/search.awk has no ~ regex-operator usage" '0' "$REGEX_COUNT_SEARCH"

# T-179 (PLAN 4.16 regression): the dfstats.tsv join never carries raw user
# data through awk -v -- a title with quotes/$/backtick survives intact.
mkdir -p "$TMP/vt179/.knotlog"
cat > "$TMP/vt179/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt179/quoted.md" <<'EOF'
---
title: Note with "quotes" and $dollar and `backtick`
---
uniqueterm179 appears in the body.
EOF
QUIPU_VAULT="$TMP/vt179" sh "$ROOT/knotlog" index >/dev/null 2>&1
T179=$(QUIPU_VAULT="$TMP/vt179" sh "$ROOT/knotlog" search uniqueterm179 --paths)
t; assert_eq "T-179: title with quotes/dollar/backtick survives the dfstats join intact" 'quoted.md' "$T179"
T179TITLE=$(QUIPU_VAULT="$TMP/vt179" sh "$ROOT/knotlog" search uniqueterm179 | awk -F"$TAB" '{print $3}')
t
# literal $dollar/`backtick` in the expected value is test data, not expansion.
# shellcheck disable=SC2016
assert_eq "T-179: title text itself is unmangled through the two-pass pipeline" 'Note with "quotes" and $dollar and `backtick`' "$T179TITLE"

# T-180: mixed query -- one term word-matches, one term matches nothing
# anywhere (df=0). No crash, df=0 term contributes nothing (tf==0 skips
# before any idf/log() is computed for it), matching docs still returned.
T180=$(QUIPU_VAULT="$TMP/vt170" sh "$ROOT/knotlog" search "alpha xyzzynotfound" --paths | sort); RC180=$?
t; assert_eq "T-180: mixed query (matched + df=0 term) exits 0, no crash" '0' "$RC180"
t; assert_eq "T-180: mixed query still returns the alpha-matching docs" 'body-doc.md
title-doc.md' "$T180"

# ---- FAZ 7: scale, 5000 docs (T-85..T-87) ----

# J-7 turns the "5000 notes" claim into a measurement instead of a sentence in
# prose, on Linux, macOS and Windows alike. The corpus is generated here by one
# loop and never committed: ~100 bytes per note, a term every document shares
# (`ortakterim`) plus a per-file unique term. Note 1 additionally carries a long
# ASCII word run, so the 120-byte --brief cut is exercised at scale too.
printf '# info: scale vault: generating 5000 docs\n'
mkvault vscale
printf 'fold=tr\nlang=en\n' > "$TMP/vscale/.knotlog/config"
i=1
while [ "$i" -le 5000 ]; do
  printf '# not %s\n\nortakterim tekil%s satir govdesi burada duruyor ve kisa kaliyor.\n' "$i" "$i" > "$TMP/vscale/n$i.md"
  i=$((i + 1))
done
awk 'BEGIN{ s = "ortakterim tekil1"; for (i = 1; i <= 48; i++) s = s " wordnumber" i; print "# not 1"; print ""; print s }' > "$TMP/vscale/n1.md"

# T-85 (J-7): a cold index over 5000 documents completes and indexes every one
# of them. On Windows/msys each stale file costs ~6 process spawns, which is the
# cost J-7 exists to expose, so the number that matters is the printed one.
printf '# info: scale vault: indexing 5000 docs (a few seconds on Windows)\n'
START=$(date +%s)
QUIPU_VAULT="$TMP/vscale" QUIPU_LANG=en sh "$ROOT/knotlog" index > "$TMP/vscale.out" 2>&1
END=$(date +%s)
t; assert_eq "scale: index of a clean 5000-doc vault counts 5000" '5000 0 5000 0' "$(idx_nums "$TMP/vscale.out")"
t; assert_eq "scale: index.tsv has 5000 rows" '5000' "$(awk 'END{print NR}' "$TMP/vscale/.knotlog/index.tsv")"
printf '# info: index 5000 docs: %s s\n' "$((END - START))"
# 120s is a hang/regression ceiling, not a performance claim; the real number is
# printed above. This bound was 3600s pre-FAZ11 (measured 2150-2367 s for 5000 docs
# on Windows msys, old per-file-fork pipeline: ~6-8 process spawns/file). FAZ 11's
# batch pipeline (mode=scan/flatjoin/assemble, docs/FAZ11-BULGULAR.md B-1..B-5)
# collapsed that to a near-constant ~10-15 processes TOTAL regardless of file count;
# CI run 32626147495 (PR #15 "faz11 ci") measured, per OS: ubuntu-latest 0s,
# macOS 1s, Windows 3s. 3600s was left absurdly loose after that drop. 120s is
# ~40x the worst measured value (3s, Windows) -- wide enough to not flake on a
# slow/loaded CI runner, tight enough to still catch a real regression (e.g. a
# reintroduced per-file fork).
t; assert_eq "scale: index 5000 docs within bound" 'yes' "$([ $((END - START)) -lt 120 ] && printf yes || printf no)"

# T-86 (J-7): search over the 5000-row index stays interactive. `ortakterim` is
# in every document, so --limit 5000 must return all 5000 rows.
START=$(date +%s)
QUIPU_VAULT="$TMP/vscale" QUIPU_LANG=en sh "$ROOT/knotlog" search ortakterim --limit 5000 > "$TMP/vscale-search.out" 2>&1
END=$(date +%s)
t; assert_eq "scale: search returns all 5000 hits" '5000' "$(awk 'END{print NR}' "$TMP/vscale-search.out")"
printf '# info: search 5000-doc index: %s s\n' "$((END - START))"
t; assert_eq "scale: search on a 5000-doc index within bound" 'yes' "$([ $((END - START)) -lt 30 ] && printf yes || printf no)"

# T-87 (J-7): the --brief contract (5 TAB fields, snippet capped at 120 bytes)
# and --limit hold at scale, not just on the six-document fixture.
QUIPU_VAULT="$TMP/vscale" QUIPU_LANG=en sh "$ROOT/knotlog" search ortakterim --limit 50 --brief > "$TMP/vscale-brief.out" 2> "$TMP/vscale-brief.err"
# stderr is kept OUT of the row file on purpose: merging it with 2>&1 used to
# inject warning lines into the TSV, which broke both the field-count and the
# --limit assertions below (CI 32576726590/32581466504: got 52 rows for
# --limit 50 on mawk and BSD awk, while gawk on windows-latest stayed silent).
printf '# info: scale --brief stderr: %s\n' "$(awk 'END{print NR}' "$TMP/vscale-brief.err") line(s)"
awk '{print "# info: scale --brief stderr: " $0}' "$TMP/vscale-brief.err"
t; assert_eq "scale: --brief rows have 5 fields" 'yes' "$(awk -F"$TAB" '{if (NF != 5) bad++} END{print (bad ? "no" : "yes")}' "$TMP/vscale-brief.out")"
t; assert_eq "scale: --brief snippet is at most 120 bytes" 'yes' "$(awk -F"$TAB" '{if (length($5) > 120) bad++} END{print (bad ? "no" : "yes")}' "$TMP/vscale-brief.out")"
t; assert_eq "scale: --brief honours --limit 50 at scale" '50' "$(awk 'END{print NR}' "$TMP/vscale-brief.out")"

# ---- FAZ 12: streamed engine at scale + regression roundup (T-181/T-182) ----

# T-181 (K-2's expectation check): the two-pass engine at scale, reusing
# vscale's own pre-built 5000-doc index (no second index build) -- confirms
# 5000/5000 hits (T-86 regression) AND that the process count stays the
# structural 2 (T-171's technique) even at this scale, a regression bar
# against a future change reintroducing a per-batch/per-document search.awk
# fork. Real elapsed time is recorded via a printf info line for
# docs/FAZ12-BULGULAR.md; K-2's "no visible cost" expectation is confirmed
# or refuted per OS by CI, not asserted here as a new fixed bound.
mkdir -p "$TMP/t181wrap"
: > "$TMP/t181.count"
REALAWK181=$(command -v awk)
cat > "$TMP/t181wrap/awk" <<WRAP181EOF
#!/bin/sh
case "\$*" in
  *search.awk*) printf 'x\n' >> "$TMP/t181.count" ;;
esac
exec "$REALAWK181" "\$@"
WRAP181EOF
chmod +x "$TMP/t181wrap/awk"
START=$(date +%s)
PATH="$TMP/t181wrap:$PATH" QUIPU_VAULT="$TMP/vscale" QUIPU_LANG=en sh "$ROOT/knotlog" search ortakterim --limit 5000 > "$TMP/vscale-search181.out" 2>&1
END=$(date +%s)
t; assert_eq "T-181: two-pass search at 5000-doc scale still finds all 5000 hits" '5000' "$(awk 'END{print NR}' "$TMP/vscale-search181.out")"
t; assert_eq "T-181: process count stays the structural 2 even at 5000-doc scale" '2' "$(awk 'END{print NR}' "$TMP/t181.count")"
printf '# info: FAZ 12 two-pass search on 5000-doc index: %s s\n' "$((END - START))"

# T-182 (no new test code, same "T-164/T-165" precedent FAZ 11 set): the
# full regression block this faz must not break -- T-82..T-87 (--brief,
# scale) and T-134..T-138 (--tag/--status) -- already lives earlier in this
# SAME file and runs in the same suite invocation as everything above. Their
# continued green status after lib/search.awk's rewrite to mode=bm25count/
# mode=bm25score IS T-182; this session's own isolated re-runs (T-170..T-181
# above, docs/FAZ12-BULGULAR.md) additionally exercised --brief/--tag/
# --status/--limit end to end through `knotlog search` under the two-pass
# engine and found no output difference from the pre-FAZ12 reference.

# ---- V1-DUZELTME: fold profile pinning + index self-refresh (T-88..T-95) ----

# T-88 (R-1): `init --lang tr` pins fold=tr; `init` with no --lang flag under
# LC_ALL=C pins fold=default. QUIPU_LANG must stay unset on these calls — see
# the P-6 note on T-72 above: it would outrank the config lang= just written
# and corrupt the derivation.
t; QUIPU_VAULT="$TMP/vt88tr" sh "$ROOT/knotlog" init --lang tr >/dev/null 2>&1; RC=$?
assert_eq "T-88: init --lang tr exits 0" '0' "$RC"
t; assert_eq "T-88: init --lang tr pins fold=tr" 'tr' \
  "$(awk -F= -v k=fold '$1==k{sub(/^[^=]*=/,"");print;exit}' "$TMP/vt88tr/.knotlog/config")"

t; QUIPU_VAULT="$TMP/vt88def" LC_ALL=C sh "$ROOT/knotlog" init >/dev/null 2>&1; RC=$?
assert_eq "T-88: init without --lang exits 0" '0' "$RC"
t; assert_eq "T-88: init without --lang under LC_ALL=C pins fold=default" 'default' \
  "$(awk -F= -v k=fold '$1==k{sub(/^[^=]*=/,"");print;exit}' "$TMP/vt88def/.knotlog/config")"

# T-89 (R-2): a second `init --lang en` updates lang= but never touches an
# already-pinned fold=.
t; QUIPU_VAULT="$TMP/vt89" sh "$ROOT/knotlog" init --lang tr >/dev/null 2>&1; RC=$?
assert_eq "T-89: first init --lang tr exits 0" '0' "$RC"
t; QUIPU_VAULT="$TMP/vt89" sh "$ROOT/knotlog" init --lang en >/dev/null 2>&1; RC=$?
assert_eq "T-89: second init --lang en exits 0" '0' "$RC"
t; assert_eq "T-89: second init updates lang=en" 'en' \
  "$(awk -F= -v k=lang '$1==k{sub(/^[^=]*=/,"");print;exit}' "$TMP/vt89/.knotlog/config")"
t; assert_eq "T-89: fold=tr survives the second init" 'tr' \
  "$(awk -F= -v k=fold '$1==k{sub(/^[^=]*=/,"");print;exit}' "$TMP/vt89/.knotlog/config")"

# T-90 (R-2): a hand-written fold= is never overwritten by `init`, known or
# unknown profile alike.
mkdir -p "$TMP/vt90/.knotlog"
printf 'fold=latin\n' > "$TMP/vt90/.knotlog/config"
t; QUIPU_VAULT="$TMP/vt90" sh "$ROOT/knotlog" init --lang tr >/dev/null 2>&1; RC=$?
assert_eq "T-90: init over a hand-written fold= exits 0" '0' "$RC"
t; assert_eq "T-90: init never overwrites a hand-written fold=" 'latin' \
  "$(awk -F= -v k=fold '$1==k{sub(/^[^=]*=/,"");print;exit}' "$TMP/vt90/.knotlog/config")"

# T-91 (P-3 regression): the exact live scenario from V1-DUZELTME-BULGULAR.md.
# init --lang tr -> note -> index -> a SECOND note added and indexed under
# QUIPU_LANG=en. Before R-1/R-4 the second note's folded field kept its raw
# Turkish diacritics (a different profile than the first note) and was
# unreachable by any query; now both rows fold with the SAME pinned profile.
t; QUIPU_VAULT="$TMP/vt91" sh "$ROOT/knotlog" init --lang tr >/dev/null 2>&1; RC=$?
assert_eq "T-91: init --lang tr exits 0" '0' "$RC"
printf '# dpi\n\nİkinci monitörde taşbar taşması.\n' > "$TMP/vt91/dpi.md"
t; QUIPU_VAULT="$TMP/vt91" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1; RC=$?
assert_eq "T-91: first index exits 0" '0' "$RC"

printf '# dpi2\n\nÜçüncü monitörde ölçek sorunu.\n' > "$TMP/vt91/dpi2.md"
t; QUIPU_VAULT="$TMP/vt91" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1; RC=$?
assert_eq "T-91: second index (QUIPU_LANG=en) exits 0" '0' "$RC"

t; assert_eq "T-91: no raw Turkish letter survives in any folded column" 'yes' \
  "$(awk -F"$TAB" '{if (index($5,"ı") || index($5,"ş") || index($5,"İ") || index($5,"Ü") || index($5,"ü") || index($5,"Ö") || index($5,"ö")) bad++} END{print (bad ? "no" : "yes")}' "$TMP/vt91/.knotlog/index.tsv")"
t; assert_eq "T-91: QUIPU_LANG=en search monitor finds both notes" '2' \
  "$(QUIPU_VAULT="$TMP/vt91" QUIPU_LANG=en sh "$ROOT/knotlog" search monitor | awk 'END{print NR}')"

# T-92 (R-3): doctor's fold check — absent fold= warns (exit stays 0), an
# unknown profile fails (exit 1). doc_summary's last number is read back
# language-independently, same technique as idx_nums above.
mkdir -p "$TMP/vt92a/.knotlog"
printf 'layout=emoji\nlang=en\n' > "$TMP/vt92a/.knotlog/config"
t; QUIPU_VAULT="$TMP/vt92a" QUIPU_LANG=en sh "$ROOT/knotlog" doctor >"$TMP/vt92a.out" 2>&1; RC=$?
assert_eq "T-92: doctor with no fold= exits 0" '0' "$RC"
t; assert_eq "T-92: doctor with no fold= warns" 'yes' \
  "$(awk -F"$TAB" '$2=="fold profile" && $1=="warn" {f=1} END{exit !f}' "$TMP/vt92a.out" && printf yes || printf no)"

mkdir -p "$TMP/vt92b/.knotlog"
printf 'layout=emoji\nlang=en\nfold=yokboyleprofil\n' > "$TMP/vt92b/.knotlog/config"
t; QUIPU_VAULT="$TMP/vt92b" QUIPU_LANG=en sh "$ROOT/knotlog" doctor >"$TMP/vt92b.out" 2>&1; RC=$?
assert_eq "T-92: doctor with unknown fold= exits 1" '1' "$RC"
t; assert_eq "T-92: doc_summary's last field (fail count) is 1" '1' \
  "$(awk '/^summary:/{ gsub(/[^0-9]/," "); s=""; for (i=1;i<=NF;i++) if ($i!="") s=s (s==""?"":" ") $i; n=split(s,a," "); print a[n] }' "$TMP/vt92b.out")"

# T-93 (R-4): `_q_fold_prof` is the single source for both index and search —
# a profile-specific fold (fold=latin: Straße -> strasse) shows up identically
# in index.tsv column 5 and in the search hit.
mkdir -p "$TMP/vt93/.knotlog"
printf 'fold=latin\nlang=en\n' > "$TMP/vt93/.knotlog/config"
printf '# strasse\n\nStraße Notizen hier.\n' > "$TMP/vt93/strasse.md"
t; QUIPU_VAULT="$TMP/vt93" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1; RC=$?
assert_eq "T-93: index under fold=latin exits 0" '0' "$RC"
t; assert_eq "T-93: index.tsv column 5 folds Straße to strasse" '# strasse  strasse notizen hier.' \
  "$(awk -F"$TAB" '$1=="strasse.md"{print $5}' "$TMP/vt93/.knotlog/index.tsv")"
t; assert_eq "T-93: search strasse hits the same latin-folded document" 'strasse.md' \
  "$(QUIPU_VAULT="$TMP/vt93" QUIPU_LANG=en sh "$ROOT/knotlog" search strasse | awk -F"$TAB" 'NR==1{print $2}')"

# T-94 (R-5): adapter data, static check (T-54..T-56 pattern) — SessionEnd
# runs `index` after `remember` in both adapters, commandWindows included.
t; assert_eq "claude-code adapter: SessionEnd command runs index" 'yes' \
  "$(awk '/"SessionEnd"/,/\]/' "$ROOT/adapters/claude-code.json" | grep -q '"command":.*knotlog index' && printf yes || printf no)"
t; assert_eq "codex adapter: SessionEnd command runs index" 'yes' \
  "$(awk '/"SessionEnd"/,/\]/' "$ROOT/adapters/codex/hooks.json" | grep -q '"command":.*knotlog index' && printf yes || printf no)"
t; assert_eq "codex adapter: SessionEnd commandWindows runs index" 'yes' \
  "$(awk '/"SessionEnd"/,/\]/' "$ROOT/adapters/codex/hooks.json" | grep -q '"commandWindows":.*knotlog index' && printf yes || printf no)"

# T-95 (R-6): the hook path stays silent on `index`, the same H-7 rule as the
# other commands; the index is still written.
mk_index_vault vt95
t; OUT=$(QUIPU_VAULT="$TMP/vt95" QUIPU_HOOK=1 sh "$ROOT/knotlog" index 2>"$TMP/vt95.err"); RC=$?
assert_eq "T-95: QUIPU_HOOK=1 index exits 0" '0' "$RC"
t; assert_eq "T-95: QUIPU_HOOK=1 index prints nothing to stdout" '' "$OUT"
t; assert_eq "T-95: QUIPU_HOOK=1 index prints nothing to stderr" '' "$(cat "$TMP/vt95.err")"
t; assert_eq "T-95: index.tsv is still written" '3' "$(awk 'END{print NR}' "$TMP/vt95/.knotlog/index.tsv")"

# ---- FAZ 8: reflection block + missed-reflection catcher (T-96..T-108) ----

# T-96: the first `remember` appends a reflection block; the three headings
# come from i18n (QUIPU_LANG=en).
mkrem vr96
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vr96/.knotlog/activity.log"
t; rem vr96 >/dev/null 2>&1
assert_eq "reflect: first remember appends a block with three i18n headings" 'yes' \
  "$(grep -q '^<!-- knotlog:reflect:start -->$' "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md" \
     && grep -q '^<!-- knotlog:reflect:end -->$' "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md" \
     && grep -qF "### $(i18n reflect_head_what)" "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md" \
     && grep -qF "### $(i18n reflect_head_where)" "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md" \
     && grep -qF "### $(i18n reflect_head_threads)" "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md" \
     && printf yes || printf no)"

# T-97: a model line inside the block survives a same-day second `remember`;
# no second block is added. The block sits at EOF after the first remember, so
# the end marker is re-appended around the model line (sed '$d' drops it).
sed '$d' "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md" > "$TMP/vr96/.tmp"
printf '%s\n' 'Model wrote this reflection line.' >> "$TMP/vr96/.tmp"
printf '%s\n' '<!-- knotlog:reflect:end -->' >> "$TMP/vr96/.tmp"
mv "$TMP/vr96/.tmp" "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md"
printf '%s\n' '2026-08-20T10:01 | PostToolUse | Read | 500-Knowledge/other.md' >> "$TMP/vr96/.knotlog/activity.log"
t; rem vr96 >/dev/null 2>&1
assert_eq "reflect: same-day second remember keeps the model line, one block" 'yes' \
  "$(grep -qF 'Model wrote this reflection line.' "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md" \
     && [ "$(grep -c 'knotlog:reflect:start' "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md")" = 1 ] \
     && printf yes || printf no)"

# T-98: user text written OUTSIDE the block survives further remembers
# (append-only regression; the reflection block is never rewritten).
printf '%s\n' 'User note outside the reflection block.' >> "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md"
printf '%s\n' '2026-08-20T10:02 | PostToolUse | Write | 000-Inbox/i.md' >> "$TMP/vr96/.knotlog/activity.log"
t; rem vr96 >/dev/null 2>&1
assert_eq "reflect: user text outside the block preserved" 'yes' \
  "$(grep -qF 'User note outside the reflection block.' "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md" \
     && [ "$(grep -c 'knotlog:reflect:start' "$TMP/vr96/700-Sessions/$(date +%Y-%m-%d).md")" = 1 ] \
     && printf yes || printf no)"

# T-99: a block holding only markers + headings + blank lines is EMPTY, so the
# SessionStart ask appears. (ctx_reflect_ask is the controlled i18n template;
# its two %s are the path and the marker name — SC2059 pattern.)
mkrem vr99
{
  printf '%s\n' '<!-- quipu:reflect:start -->'
  printf '### %s\n' "$(i18n reflect_head_what)"
  printf '%s\n' ''
  printf '### %s\n' "$(i18n reflect_head_where)"
  printf '%s\n' ''
  printf '### %s\n' "$(i18n reflect_head_threads)"
  printf '%s\n' ''
  printf '%s\n' '<!-- quipu:reflect:end -->'
} > "$TMP/vr99/700-Sessions/$(date +%Y-%m-%d).md"
t; A99=$(QUIPU_VAULT="$TMP/vr99" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart)
A99D=$(printf '%s' "$A99" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
# shellcheck disable=SC2059
A99_EXPECT=$(printf "$(i18n ctx_reflect_ask)" "700-Sessions/$(date +%Y-%m-%d).md" 'quipu:reflect')
assert_eq "reflect: headings and blanks do not count as content" 'yes' \
  "$(printf '%s\n' "$A99D" | grep -qF "$A99_EXPECT" && printf yes || printf no)"

# T-100: one content line makes the block filled: no ask.
mkrem vr100
{
  printf '%s\n' '<!-- quipu:reflect:start -->'
  printf '### %s\n' "$(i18n reflect_head_what)"
  printf '%s\n' ''
  printf '%s\n' 'a single reflection line'
  printf '%s\n' '<!-- quipu:reflect:end -->'
} > "$TMP/vr100/700-Sessions/$(date +%Y-%m-%d).md"
t; A100=$(QUIPU_VAULT="$TMP/vr100" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart)
A100D=$(printf '%s' "$A100" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
# shellcheck disable=SC2059
A100_EXPECT=$(printf "$(i18n ctx_reflect_ask)" "700-Sessions/$(date +%Y-%m-%d).md" 'quipu:reflect')
assert_eq "reflect: one content line -> block filled, no ask" 'no' \
  "$(printf '%s\n' "$A100D" | grep -qF "$A100_EXPECT" && printf yes || printf no)"

# T-101: an empty-block PREVIOUS day + remember -> needs_reflection written as
# "day count", the count parsed from the digest Range line ((3 events)); the
# "(top 10)" files header must NOT be counted.
mkrem vr101
{
  printf '%s\n' '## 09:00'
  printf '%s\n' 'Range: 08:00 → 09:00 (3 events)'
  printf '%s\n' 'Tools: Read 3'
  printf '%s\n' 'Touched files (top 10):'
  printf '%s\n' '  -  3  prev.md'
  printf '%s\n' '<!-- quipu:reflect:start -->'
  printf '### %s\n' "$(i18n reflect_head_what)"
  printf '%s\n' ''
  printf '%s\n' '<!-- quipu:reflect:end -->'
} > "$TMP/vr101/700-Sessions/2020-01-01.md"
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vr101/.knotlog/activity.log"
t; rem vr101 >/dev/null 2>&1
assert_eq "reflect: empty previous block -> needs_reflection written" '2020-01-01 3' "$(cat "$TMP/vr101/.knotlog/needs_reflection")"

# T-102: SessionStart puts the missed notice in the context and deletes the
# flag (single shot).
t; M102=$(QUIPU_VAULT="$TMP/vr101" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart)
M102D=$(printf '%s' "$M102" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
# shellcheck disable=SC2059
M102_EXPECT=$(printf "$(i18n ctx_reflect_missed)" '2020-01-01' '3')
assert_eq "reflect: SessionStart shows missed notice and deletes the flag" 'yes' \
  "$(printf '%s\n' "$M102D" | grep -qF "$M102_EXPECT" \
     && [ ! -f "$TMP/vr101/.knotlog/needs_reflection" ] && printf yes || printf no)"

# T-103: a second SessionStart carries no missed notice.
t; M103=$(QUIPU_VAULT="$TMP/vr101" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart)
M103D=$(printf '%s' "$M103" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "reflect: second SessionStart has no missed notice" 'no' \
  "$(printf '%s\n' "$M103D" | grep -qF "$M102_EXPECT" && printf yes || printf no)"

# T-104: a filled previous-day block -> no needs_reflection at all.
mkrem vr104
{
  printf '%s\n' '## 09:00'
  printf '%s\n' 'Range: 08:00 → 09:00 (3 events)'
  printf '%s\n' '<!-- quipu:reflect:start -->'
  printf '### %s\n' "$(i18n reflect_head_what)"
  printf '%s\n' 'filled content line'
  printf '%s\n' '<!-- quipu:reflect:end -->'
} > "$TMP/vr104/700-Sessions/2020-01-01.md"
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vr104/.knotlog/activity.log"
t; rem vr104 >/dev/null 2>&1
assert_eq "reflect: filled previous block -> no needs_reflection" 'no' \
  "$([ -f "$TMP/vr104/.knotlog/needs_reflection" ] && printf yes || printf no)"

# T-105: today's empty block -> the SessionStart ask names the session path
# and the quipu:reflect marker.
mkrem vr105
{
  printf '%s\n' '<!-- quipu:reflect:start -->'
  printf '### %s\n' "$(i18n reflect_head_what)"
  printf '%s\n' ''
  printf '%s\n' '<!-- quipu:reflect:end -->'
} > "$TMP/vr105/700-Sessions/$(date +%Y-%m-%d).md"
t; A105=$(QUIPU_VAULT="$TMP/vr105" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart)
A105D=$(printf '%s' "$A105" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "reflect: ask names the path and the marker" 'yes' \
  "$(printf '%s\n' "$A105D" | grep -qF "700-Sessions/$(date +%Y-%m-%d).md" \
     && printf '%s\n' "$A105D" | grep -qF 'quipu:reflect' && printf yes || printf no)"

# T-106: the updated ctx_precompact text points at the reflection block.
mkrem vr106
printf 'lang=en\n' >> "$TMP/vr106/.knotlog/config"
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Read | x.md' >> "$TMP/vr106/.knotlog/activity.log"
# ctx_precompact is the controlled i18n template; the argument is a folder name.
# shellcheck disable=SC2059
CP106=$(printf "$(i18n ctx_precompact)" '700-Sessions')
t; NJ106=$(QUIPU_NUDGE_AFTER=0 QUIPU_VAULT="$TMP/vr106" QUIPU_LANG=en sh "$ROOT/knotlog" context --json UserPromptSubmit)
NJ106D=$(printf '%s' "$NJ106" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "reflect: ctx_precompact points at the reflection block" 'yes' \
  "$(printf '%s\n' "$NJ106D" | grep -qF "$CP106" \
     && printf '%s\n' "$NJ106D" | grep -qF 'reflection block' && printf yes || printf no)"

# T-107: the AGENTS.md bridge body carries the memory protocol paragraph from
# i18n; raw reflect_/ctx_reflect_ keys never appear (a missing key would leak
# its name through _q_msg's fallback).
mkrem vr107
QUIPU_VAULT="$TMP/vr107" QUIPU_LANG=en sh "$ROOT/knotlog" init >/dev/null 2>&1
t; assert_eq "reflect: bridge protocol paragraph, no raw keys" 'yes' \
  "$(grep -qF "$(i18n bridge_reflect)" "$TMP/vr107/AGENTS.md" \
     && ! grep -qE 'reflect_head_|ctx_reflect_' "$TMP/vr107/AGENTS.md" && printf yes || printf no)"
# T-108: static honesty gates (S-5 is not repeated). python3 appears nowhere in
# quipu; the "stat " line count stays PINNED so that any new stat usage has to
# be reviewed deliberately rather than sneaking in. Current value 10, broken
# down so a future edit updates it knowingly instead of blindly:
#   1  mtime() two-tier wrapper (GNU -c, then BSD -f)
#   2  _q_stat_batch comment lines describing that same two-tier fallback
#   2  _q_stat_batch real calls (FAZ 11 F-5: xargs -0 batch mtime)
#   5  doctor dialect probe (2 probes + 3 _q_line result rows)
# FAZ 8 added no stat usage; FAZ 11 added the batch pair (6 -> 10).
t; assert_eq "reflect: no python3, stat count pinned" '10 0' \
  "$(grep -c 'stat ' "$ROOT/knotlog") $(grep -c 'python3' "$ROOT/knotlog")"

# ---- FAZ 9: identity + personalized seed + runbook gates (T-110..T-120) ----

# T-110 (V-2): init --user Ada --companion Kuz -> config user=/companion=.
# --plain rides along on this SAME call so it is the vault's first-ever init:
# an unnamed init first (e.g. via mkrem, as this used to do) would seed
# companion.md with neutral defaults, and the only-if-missing guard
# (quipu:679) then skips personalization on the named init that follows,
# starving T-112 of the names it checks for. --plain also pins layout=plain
# in one shot, which CN110=$(comp_name plain) below depends on.
QUIPU_VAULT="$TMP/v110" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --user Ada --companion Kuz >/dev/null 2>&1
t; assert_eq "identity: config has user and companion lines" 'yes' \
  "$(grep -q '^user=Ada$' "$TMP/v110/.knotlog/config" \
     && grep -q '^companion=Kuz$' "$TMP/v110/.knotlog/config" && printf yes || printf no)"

# T-111 (V-2): a second init --user Baska must never overwrite user=Ada.
QUIPU_VAULT="$TMP/v110" QUIPU_LANG=en sh "$ROOT/knotlog" init --user Baska >/dev/null 2>&1
t; assert_eq "identity: second init keeps user=Ada" 'yes' \
  "$(grep -q '^user=Ada$' "$TMP/v110/.knotlog/config" \
     && ! grep -q '^user=Baska$' "$TMP/v110/.knotlog/config" && printf yes || printf no)"

# T-112 (V-3): the seed carries both names; no raw %s survives.
CN110=$(comp_name plain)
t; assert_eq "identity: companion.md personalized, no raw %s" 'yes' \
  "$(grep -qF 'Kuz' "$TMP/v110/$CN110/companion.md" \
     && grep -qF 'Ada' "$TMP/v110/$CN110/companion.md" \
     && ! grep -qF '%s' "$TMP/v110/$CN110/companion.md" && printf yes || printf no)"

# T-113 (V-3): unnamed init -> neutral i18n defaults, still no raw %s.
mkrem v113
t; assert_eq "identity: unnamed init uses neutral defaults, no raw %s" 'yes' \
  "$(grep -qF "$(i18n persona_default_companion)" "$TMP/v113/$(comp_name plain)/companion.md" \
     && grep -qF "$(i18n persona_default_user)" "$TMP/v113/$(comp_name plain)/companion.md" \
     && ! grep -qF '%s' "$TMP/v113/$(comp_name plain)/companion.md" && printf yes || printf no)"

# T-114 (V-3): a user-edited companion.md survives a second init (regression of
# the only-if-missing guarantee).
printf '%s\n' 'My custom persona line' >> "$TMP/v113/$(comp_name plain)/companion.md"
QUIPU_VAULT="$TMP/v113" sh "$ROOT/knotlog" init >/dev/null 2>&1
t; assert_eq "identity: second init preserves edited companion.md" 'yes' \
  "$(grep -qF 'My custom persona line' "$TMP/v113/$(comp_name plain)/companion.md" \
     && ! grep -qF '%s' "$TMP/v113/$(comp_name plain)/companion.md" && printf yes || printf no)"

# T-115 (V-4): the AGENTS.md bridge body names the companion; the raw
# bridge_companion key never leaks (a missing key would print its name).
t; assert_eq "identity: bridge names companion, no raw key" 'yes' \
  "$(grep -qF 'Kuz' "$TMP/v110/AGENTS.md" \
     && ! grep -qF 'bridge_companion' "$TMP/v110/AGENTS.md" && printf yes || printf no)"

# T-116 (V-5): doctor warns when user=/companion= is absent and still exits 0.
# The identity row is extracted by its message content (both languages carry
# "user=" and "companion=" in doc_identity_missing), not by a translation.
mkvault v116
QUIPU_VAULT="$TMP/v116" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
t; (cd "$TMP/v116" && QUIPU_LANG=en "$ROOT/knotlog" doctor) >"$TMP/v116.doc" 2>&1; RC=$?
assert_eq "identity: doctor with no identity warns, exit 0" '0' "$RC"
t; assert_eq "identity: warn row extracted language-independently" 'yes' \
  "$(awk -F"$TAB" '$3 ~ /user=/ && $3 ~ /companion=/ {found=1} END{print (found ? "yes" : "no")}' "$TMP/v116.doc")"
t; assert_eq "identity: warn row is a warn, not a fail" \
  "$(i18n doc_warn)" "$(awk -F"$TAB" '$3 ~ /user=/ {print $1; exit}' "$TMP/v116.doc")"
# With identity present the row turns ok (same extraction path).
QUIPU_VAULT="$TMP/v116" QUIPU_LANG=en sh "$ROOT/knotlog" init --user Ada --companion Kuz >/dev/null 2>&1
t; (cd "$TMP/v116" && QUIPU_LANG=en "$ROOT/knotlog" doctor) >"$TMP/v116b.doc" 2>&1; RC=$?
assert_eq "identity: doctor with identity ok, exit 0" '0' "$RC"
t; assert_eq "identity: ok row shows both names" 'yes' \
  "$(awk -F"$TAB" '$2=="identity" && $3=="Ada/Kuz" {found=1} END{print (found ? "yes" : "no")}' "$TMP/v116b.doc")"

# T-117 (V-2 + FAZ 7 -*) regression: --user starved of its value keeps the old
# err_missing_arg; --companion followed by a flag diagnoses that flag instead
# of swallowing it as a name.
mkvault v117
t; QUIPU_VAULT="$TMP/v117" QUIPU_LANG=en sh "$ROOT/knotlog" init --user \
  >/dev/null 2>"$TMP/v117-user.err"; RC=$?
assert_eq "identity: init --user without value exits 2" '2' "$RC"
t; assert_eq "identity: init --user without value keeps err_missing_arg" \
  "$(i18n err_missing_arg)" "$(cat "$TMP/v117-user.err")"
t; QUIPU_VAULT="$TMP/v117" QUIPU_LANG=en sh "$ROOT/knotlog" init --companion --bogus \
  >/dev/null 2>"$TMP/v117-comp.err"; RC=$?
assert_eq "identity: init --companion --bogus exits 2" '2' "$RC"
t; # shellcheck disable=SC2059
assert_eq "identity: init --companion --bogus names the flag" \
  "$(printf "$(i18n err_unknown_flag)\n" --bogus)" "$(cat "$TMP/v117-comp.err")"

# T-118: the four new keys exist in both languages and the key sets stay equal.
t; IDKEYS=$(for _k in persona_default_companion persona_default_user doc_identity doc_identity_missing; do
  for _f in en tr; do
    grep -q "^$_k=" "$ROOT/i18n/$_f.txt" || printf '%s:%s\n' "$_k" "$_f"
  done
done)
assert_eq "identity: FAZ 9 keys present in both languages" '' "$IDKEYS"
t; KTR9=$(awk -F= 'NF >= 1 && $1 !~ /^#/ {print $1}' "$ROOT/i18n/tr.txt" | sort)
KEN9=$(awk -F= 'NF >= 1 && $1 !~ /^#/ {print $1}' "$ROOT/i18n/en.txt" | sort)
assert_eq "identity: i18n tr/en key sets identical" "$KEN9" "$KTR9"

# T-119: static runbook gate — the platform-specific tool strings never appear
# in docs/USAGE.md (ASCII grep; the doc is written without them).
t; BAD119=$(grep -nE 'brew|python3|osacompile|swift|apt-get|winget' "$ROOT/docs/USAGE.md" || true)
assert_eq "runbook: no platform-specific tool strings" '' "$BAD119"

# T-120: every phase heading is present and every command the runbook calls is
# within the setup whitelist {doctor, init, index, search, context, remember} —
# compared against the usage list so no invented command can slip in.
t; MISS120=$(for _n in 0 1 2 3 4 5; do
  grep -q "^## Phase $_n " "$ROOT/docs/USAGE.md" || printf '%s\n' "$_n"
done)
assert_eq "runbook: every phase heading present (Faz 0..5)" '' "$MISS120"
t; CMDS120=$(LC_ALL=C grep -oE 'knotlog [a-z-]+' "$ROOT/docs/USAGE.md" | awk '{print $2}' | sort -u | tr '\n' ' ' | sed 's/ $//')
assert_eq "runbook: only documented setup commands called" 'context digest doctor import index init install remember search' "$CMDS120"
t; USAGE120=$(awk -F= '/^usage_/ {sub(/^usage_/,""); print $1}' "$ROOT/i18n/en.txt" | sort | tr '\n' ' ')
# Membership test without a `case` inside $( ): bash 3.2 (macOS /bin/sh)
# fails to parse a quoted glob pattern like *" $x "*) when the case sits in a
# command substitution — CI 32592944953 died with "syntax error near
# unexpected token ';;'" on macos-latest while dash and newer bash accepted it.
BAD120=$(for _c in $CMDS120; do
  printf '%s\n' "$USAGE120" | tr ' ' '\n' | grep -qx "$_c" || printf '%s\n' "$_c"
done)
assert_eq "runbook: every called command exists in the usage list" '' "$BAD120"
t; assert_eq "runbook: capture command not mentioned" 'no' \
  "$(grep -qw capture "$ROOT/docs/USAGE.md" && printf yes || printf no)"

# ---- FAZ 15: interactive init -- the gate (T-220..T-222) ----

# T-220: unflagged init on an empty config, in this suite's non-tty shell,
# returns immediately (does not block), exit 0, and writes no purpose=/
# companion=/user= line -- nothing was flagged, nothing was asked.
mkvault v220
t; QUIPU_VAULT="$TMP/v220" sh "$ROOT/knotlog" init --plain >/dev/null 2>&1; RC=$?
assert_eq "FAZ15 T-220: unflagged init on empty config exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-220: no purpose/companion/user line written" 'yes' \
  "$(! grep -q '^purpose=' "$TMP/v220/.knotlog/config" \
     && ! grep -q '^companion=' "$TMP/v220/.knotlog/config" \
     && ! grep -q '^user=' "$TMP/v220/.knotlog/config" && printf yes || printf no)"

# T-222: --no-prompt alone (no QUIPU_HOOK) closes the gate even under
# QUIPU_FORCE_TTY=1 with real answers piped in -- proves --no-prompt is a
# self-sufficient escape hatch, not dependent on the hook check.
mkvault v222
t; printf 'Kuz\nAda\nYazi\n' | QUIPU_VAULT="$TMP/v222" QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" init --plain --no-prompt >/dev/null 2>&1; RC=$?
assert_eq "FAZ15 T-222: --no-prompt + FORCE_TTY exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-222: --no-prompt alone closes the gate, nothing written" 'yes' \
  "$(! grep -q '^purpose=' "$TMP/v222/.knotlog/config" \
     && ! grep -q '^companion=' "$TMP/v222/.knotlog/config" \
     && ! grep -q '^user=' "$TMP/v222/.knotlog/config" && printf yes || printf no)"

# ---- FAZ 15: hook safety -- stdout stays silent too (AB-10, T-221) ----

# T-221 (AB-1 + AB-10): QUIPU_HOOK=1 beats QUIPU_FORCE_TTY=1 even with real
# answers piped in -- no field is written, AND stdout/stderr are both
# completely empty (T-95's three-part pattern for `index`, applied to
# `init`): a hook-invoked init must never block AND must never print its
# success-path summary.
mkvault v221
t; OUT221=$(printf 'Kuz\nAda\nYazi\n' | QUIPU_VAULT="$TMP/v221" QUIPU_HOOK=1 QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" init --plain 2>"$TMP/v221.err"); RC=$?
assert_eq "FAZ15 T-221: QUIPU_HOOK=1 + FORCE_TTY exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-221: no field written" 'yes' \
  "$(! grep -q '^purpose=' "$TMP/v221/.knotlog/config" \
     && ! grep -q '^companion=' "$TMP/v221/.knotlog/config" \
     && ! grep -q '^user=' "$TMP/v221/.knotlog/config" && printf yes || printf no)"
t; assert_eq "FAZ15 T-221: stdout is empty" '' "$OUT221"
t; assert_eq "FAZ15 T-221: stderr is empty" '' "$(cat "$TMP/v221.err")"

# ---- FAZ 15: the three questions -- companion/user/purpose (T-223..T-235) ----

# T-223: a flag-given field is never asked; an unset field still is.
# --companion Kuz rides the flag, so only the user question consumes the one
# piped line ("Baris"). The purpose question left the interactive flow
# (wizard UX round 2): nothing else consumes stdin, and no purpose= is
# ever written without an explicit --purpose.
mkvault v223
QUIPU_VAULT="$TMP/v223" sh "$ROOT/knotlog" init --plain --companion Kuz >/dev/null 2>&1
t; printf 'Baris\n' | QUIPU_VAULT="$TMP/v223" QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" init --plain --companion Kuz >/dev/null 2>&1; RC=$?
assert_eq "FAZ15 T-223: exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-223: companion from flag (not asked), user asked+written, purpose never asked" 'yes' \
  "$(grep -q '^companion=Kuz$' "$TMP/v223/.knotlog/config" \
     && grep -q '^user=Baris$' "$TMP/v223/.knotlog/config" \
     && ! grep -q '^purpose=' "$TMP/v223/.knotlog/config" && printf yes || printf no)"

# T-224: a field already in the config is never asked, and (crucially) never
# consumes a stdin line -- so the companion question being skipped does not
# shift "Second" onto it; "Second" lands on user. The removed purpose
# question no longer consumes the second piped line either: "Yazi" stays
# unread and no purpose= is written.
mkvault v224
QUIPU_VAULT="$TMP/v224" sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
printf 'companion=Existing\n' >> "$TMP/v224/.knotlog/config"
t; printf 'Second\nYazi\n' | QUIPU_VAULT="$TMP/v224" QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" init --plain >/dev/null 2>&1; RC=$?
assert_eq "FAZ15 T-224: exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-224: companion unchanged, user from the right line, purpose not asked" 'yes' \
  "$(grep -q '^companion=Existing$' "$TMP/v224/.knotlog/config" \
     && grep -q '^user=Second$' "$TMP/v224/.knotlog/config" \
     && ! grep -q '^purpose=' "$TMP/v224/.knotlog/config" && printf yes || printf no)"

# T-225: blank answers (bare Enter) skip every asked field -- no invented
# default is ever written to the config -- while companion.md still
# personalizes with the i18n neutral defaults (existing T-113 mechanism,
# unaffected by the empty-answer path). The trailing line is left unread
# since the purpose question no longer exists.
mkvault v225
t; printf '\n\n\n' | QUIPU_VAULT="$TMP/v225" QUIPU_FORCE_TTY=1 QUIPU_LANG=en \
  sh "$ROOT/knotlog" init --plain >/dev/null 2>&1; RC=$?
assert_eq "FAZ15 T-225: exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-225: blank answers write no field" 'yes' \
  "$(! grep -q '^purpose=' "$TMP/v225/.knotlog/config" \
     && ! grep -q '^companion=' "$TMP/v225/.knotlog/config" \
     && ! grep -q '^user=' "$TMP/v225/.knotlog/config" && printf yes || printf no)"
t; assert_eq "FAZ15 T-225: companion.md still gets neutral defaults, no raw %s" 'yes' \
  "$(grep -qF "$(i18n persona_default_companion)" "$TMP/v225/$(comp_name plain)/companion.md" \
     && grep -qF "$(i18n persona_default_user)" "$TMP/v225/$(comp_name plain)/companion.md" \
     && ! grep -qF '%s' "$TMP/v225/$(comp_name plain)/companion.md" && printf yes || printf no)"

# T-226: happy path, both remaining questions answered; config has both,
# companion.md carries both names (T-112 pattern). The third piped line is
# deliberately left unread: the purpose question is gone from the flow, and
# the config/bridge must prove no purpose text can leak in without the
# explicit --purpose flag (no raw bridge_purpose key anywhere, T-115).
mkvault v226
t; printf 'Kuz\nAda\nYazi isleri\n' | QUIPU_VAULT="$TMP/v226" QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" init --plain >/dev/null 2>&1; RC=$?
assert_eq "FAZ15 T-226: exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-226: both fields written, third line (purpose) never consumed" 'yes' \
  "$(grep -q '^companion=Kuz$' "$TMP/v226/.knotlog/config" \
     && grep -q '^user=Ada$' "$TMP/v226/.knotlog/config" \
     && ! grep -q '^purpose=' "$TMP/v226/.knotlog/config" && printf yes || printf no)"
t; assert_eq "FAZ15 T-226: companion.md has both names" 'yes' \
  "$(grep -qF 'Kuz' "$TMP/v226/$(comp_name plain)/companion.md" \
     && grep -qF 'Ada' "$TMP/v226/$(comp_name plain)/companion.md" && printf yes || printf no)"
t; assert_eq "FAZ15 T-226: AGENTS.md bridge carries no purpose text and no raw key" 'yes' \
  "$(! grep -qF 'Yazi isleri' "$TMP/v226/AGENTS.md" \
     && ! grep -qF 'bridge_purpose' "$TMP/v226/AGENTS.md" && printf yes || printf no)"

# T-227: purpose never answered at all (--no-prompt, no --purpose flag) -> the
# AGENTS.md bridge has no purpose line whatsoever, not even an empty one
# (AB-8/AB-9's "skip the line, never fabricate" rule).
mkvault v227
t; QUIPU_VAULT="$TMP/v227" sh "$ROOT/knotlog" init --plain --no-prompt >/dev/null 2>&1; RC=$?
assert_eq "FAZ15 T-227: exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-227: no purpose line in the bridge at all" 'no' \
  "$(grep -qi 'purpose' "$TMP/v227/AGENTS.md" && printf yes || printf no)"

# T-228: regression gate -- persona/en.md and persona/tr.md still carry
# EXACTLY two %s placeholders (static count; FAZ 15 never touches persona),
# and a fresh FAZ 15 init leaves no raw %s in companion.md (T-112/T-113
# repeated unchanged).
t; assert_eq "FAZ15 T-228: persona/en.md still has exactly two %s" '2' \
  "$(grep -o '%s' "$ROOT/persona/en.md" | awk 'END{print NR+0}')"
t; assert_eq "FAZ15 T-228: persona/tr.md still has exactly two %s" '2' \
  "$(grep -o '%s' "$ROOT/persona/tr.md" | awk 'END{print NR+0}')"

# T-229: --purpose follows the --user/--companion -* value-rejection pattern,
# and a missing argument keeps the old err_missing_arg.
mkvault v229
t; QUIPU_VAULT="$TMP/v229" QUIPU_LANG=en sh "$ROOT/knotlog" init --purpose -oops \
  >/dev/null 2>"$TMP/v229a.err"; RC=$?
assert_eq "FAZ15 T-229: --purpose -oops exits 2" '2' "$RC"
t; # shellcheck disable=SC2059
assert_eq "FAZ15 T-229: --purpose -oops names the flag" \
  "$(printf "$(i18n err_unknown_flag)\n" -oops)" "$(cat "$TMP/v229a.err")"
t; QUIPU_VAULT="$TMP/v229" QUIPU_LANG=en sh "$ROOT/knotlog" init --purpose \
  >/dev/null 2>"$TMP/v229b.err"; RC=$?
assert_eq "FAZ15 T-229: --purpose without a value exits 2" '2' "$RC"
t; assert_eq "FAZ15 T-229: --purpose without a value keeps err_missing_arg" \
  "$(i18n err_missing_arg)" "$(cat "$TMP/v229b.err")"

# T-230: --no-prompt is safe on its own, with no tty numbers involved at all
# (no QUIPU_FORCE_TTY) -- the escape hatch does not depend on the suite's
# non-tty test shell to be safe.
mkvault v230
t; QUIPU_VAULT="$TMP/v230" sh "$ROOT/knotlog" init --no-prompt --plain --user Ada \
  >/dev/null 2>&1; RC=$?
assert_eq "FAZ15 T-230: --no-prompt --user Ada exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-230: user=Ada written" 'yes' \
  "$(grep -q '^user=Ada$' "$TMP/v230/.knotlog/config" && printf yes || printf no)"

# T-231: doctor regression -- an absent purpose= gets no new warning row;
# identity's own warning test (T-116) is untouched.
mkvault v231
QUIPU_VAULT="$TMP/v231" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
t; (cd "$TMP/v231" && QUIPU_LANG=en "$ROOT/knotlog" doctor) >"$TMP/v231.doc" 2>&1
assert_eq "FAZ15 T-231: doctor adds no purpose row" 'no' \
  "$(awk -F"$TAB" '$0 ~ /purpose/ {found=1} END{print (found ? "yes" : "no")}' "$TMP/v231.doc")"
# T-232: the remaining FAZ 15 keys exist in both languages (the general "key sets
# identical" test above already gates this structurally; this test names
# WHICH keys were added, T-118's pattern).
t; PKEYS=$(for _k in init_ask_head init_ask_companion init_ask_user bridge_purpose init_purpose; do
  for _f in en tr; do
    grep -q "^$_k=" "$ROOT/i18n/$_f.txt" || printf '%s:%s\n' "$_k" "$_f"
  done
done)
assert_eq "FAZ15 T-232: the six new keys are present in both languages" '' "$PKEYS"

# T-233: static self-lock -- tests/run.sh itself carries an `exec < /dev/null`
# (or equivalent) line near its head, T-108's static-count technique applied
# to this file instead of quipu: if someone deletes the line added for AA-7,
# the suite catches its own regression rather than silently reintroducing a
# terminal-run hang.
t; assert_eq "FAZ15 T-233: tests/run.sh redirects stdin near its head" '1' \
  "$(awk 'NR<=40 && /^exec < \/dev\/null$/{n++} END{print n+0}' "$ROOT/tests/run.sh")"

# T-234 [manual, not automatable -- see AB-1/AB-2's honest limit]: whether the
# OS's isatty(0) actually agrees with POSIX `[ -t 0 ]` cannot be proven by a
# piped test shell (that is exactly what QUIPU_FORCE_TTY exists to route
# around, T-221..T-227 cover the question+fill+skip mechanics in full). The
# one unverifiable piece is documented as a manual check in README.md's
# "Honest limits" section -- run `knotlog init` in an empty folder from a real
# terminal and confirm the questions appear.

# T-235: raw round-trip -- a purpose value containing '=' survives the
# common config-read pattern (awk -F= splitting on the FIRST '=' only)
# without being truncated or corrupted.
mkvault v235
t; QUIPU_VAULT="$TMP/v235" sh "$ROOT/knotlog" init --plain --purpose 'Notlar = hafiza' \
  >/dev/null 2>&1; RC=$?
assert_eq "FAZ15 T-235: exits 0" '0' "$RC"
t; assert_eq "FAZ15 T-235: purpose= line keeps the embedded '=' verbatim" \
  'purpose=Notlar = hafiza' "$(grep '^purpose=' "$TMP/v235/.knotlog/config")"
t; assert_eq "FAZ15 T-235: the common awk -F= read pattern reads it back whole" \
  'Notlar = hafiza' \
  "$(awk -F= -v k=purpose '$1==k{sub(/^[^=]*=/,"");print;exit}' "$TMP/v235/.knotlog/config")"

# ---- FAZ 16: Threads.md scaffold + fullness + doctor (T-240..T-252) ----

# T-240: the first `remember` in a freshly-initialized vault seeds a
# knotlog:threads block -- both markers present, two i18n headings (QUIPU_LANG=en).
mkrem vr240
printf '%s\n' '2026-08-23T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vr240/.knotlog/activity.log"
t; rem vr240 >/dev/null 2>&1
assert_eq "FAZ16 T-240: first remember seeds a threads block with two i18n headings" 'yes' \
  "$(grep -q '^<!-- knotlog:threads:start -->$' "$TMP/vr240/Threads.md" \
     && grep -q '^<!-- knotlog:threads:end -->$' "$TMP/vr240/Threads.md" \
     && grep -qF "### $(i18n threads_head_active)" "$TMP/vr240/Threads.md" \
     && grep -qF "### $(i18n threads_head_closed)" "$TMP/vr240/Threads.md" \
     && printf yes || printf no)"

# T-241: a second remember (same day) never adds a second block.
printf '%s\n' '2026-08-23T10:01 | PostToolUse | Read | x.md' >> "$TMP/vr240/.knotlog/activity.log"
t; rem vr240 >/dev/null 2>&1
assert_eq "FAZ16 T-241: second remember keeps a single threads block" '1' \
  "$(grep -c 'knotlog:threads:start' "$TMP/vr240/Threads.md")"

# T-242: a line the model wrote inside the marker range survives a further
# remember, verbatim, with the block count still 1.
awk '/<!-- knotlog:threads:end -->/{print "Proje X ile devam"} {print}' \
  "$TMP/vr240/Threads.md" > "$TMP/vr240/Threads.md.tmp" && mv "$TMP/vr240/Threads.md.tmp" "$TMP/vr240/Threads.md"
printf '%s\n' '2026-08-23T10:02 | PostToolUse | Write | y.md' >> "$TMP/vr240/.knotlog/activity.log"
t; rem vr240 >/dev/null 2>&1
assert_eq "FAZ16 T-242: a manually added line inside the block survives, one block" 'yes' \
  "$(grep -qF 'Proje X ile devam' "$TMP/vr240/Threads.md" \
     && [ "$(grep -c 'knotlog:threads:start' "$TMP/vr240/Threads.md")" = 1 ] \
     && printf yes || printf no)"

# T-243: backward migration -- a pre-FAZ16 Threads.md (only init's own
# threads_seed_title/threads_seed_note lines, no marker) gets the scaffold
# PREPENDED (AD-2); the old two lines survive, byte-for-byte, right after
# the end marker.
mkvault vr243
printf '%s\n%s\n' "$(i18n threads_seed_title)" "$(i18n threads_seed_note)" > "$TMP/vr243/Threads.md"
printf '%s\n' '2026-08-23T10:00 | PostToolUse | Edit | a.md' >> "$TMP/vr243/.knotlog/activity.log"
t; rem vr243 >/dev/null 2>&1
OLD243=$(printf '%s\n%s' "$(i18n threads_seed_title)" "$(i18n threads_seed_note)")
t; assert_eq "FAZ16 T-243: migration -- marker block sits at the very top" \
  '<!-- knotlog:threads:start -->' "$(awk 'NR==1' "$TMP/vr243/Threads.md")"
t; assert_eq "FAZ16 T-243: migration -- old seed lines intact right after the block" \
  "$OLD243" "$(awk '/<!-- knotlog:threads:end -->/{f=1;next} f' "$TMP/vr243/Threads.md")"

# T-244: the model already wrote its own free text into a pre-FAZ16
# Threads.md (no marker, no seed lines either -- e.g. hand-authored). A
# `remember` still prepends the block and leaves that free text, unchanged
# to the letter, below it -- the hardest append-only test in the migration
# scenario.
mkvault vr244
printf '%s\n' 'Ongoing: X projesi' > "$TMP/vr244/Threads.md"
printf '%s\n' '2026-08-23T10:00 | PostToolUse | Edit | a.md' >> "$TMP/vr244/.knotlog/activity.log"
t; rem vr244 >/dev/null 2>&1
t; assert_eq "FAZ16 T-244: migration -- marker block sits at the top" \
  '<!-- knotlog:threads:start -->' "$(awk 'NR==1' "$TMP/vr244/Threads.md")"
t; assert_eq "FAZ16 T-244: migration -- the model's free text is untouched" \
  'Ongoing: X projesi' "$(awk '/<!-- knotlog:threads:end -->/{f=1;next} f' "$TMP/vr244/Threads.md")"

# T-245..T-248: _q_threads_filled (AD-3) has no CLI surface of its own (same
# as _q_reflect_filled's quipu:core caller, T-262's rationale), so its
# literal source -- both _q_reflect_filled (the generalized algorithm it
# wraps) and _q_threads_filled itself -- is extracted out of quipu and run
# in a throwaway one-shot harness script; no quipu dispatch runs.
FN_RF=$(awk '/^_q_reflect_filled\(\) \{/,/^\}/' "$ROOT/knotlog")
FN_TF=$(awk '/^_q_threads_filled\(\) \{/,/^\}/' "$ROOT/knotlog")
TFH="$TMP/tf_harness.sh"
{
  printf '%s\n' "$FN_RF"
  printf '%s\n' "$FN_TF"
  # literal $1 belongs to the generated harness script, not expansion here.
  # shellcheck disable=SC2016
  printf '%s\n' '_q_threads_filled "$1"'
  # literal $_q_tf belongs to the generated harness script, not expansion here.
  # shellcheck disable=SC2016
  printf '%s\n' 'printf "%s" "$_q_tf"'
} > "$TFH"

# T-245: only headings + blank lines -> _q_tf=0 (T-99's Threads.md counterpart).
mkvault vr245
{
  printf '%s\n' '<!-- quipu:threads:start -->'
  printf '### %s\n' "$(i18n threads_head_active)"
  printf '%s\n' ''
  printf '### %s\n' "$(i18n threads_head_closed)"
  printf '%s\n' ''
  printf '%s\n' '<!-- quipu:threads:end -->'
} > "$TMP/vr245/Threads.md"
t; RF245=$(sh "$TFH" "$TMP/vr245/Threads.md")
assert_eq "FAZ16 T-245: headings + blank lines only -> not filled" '0' "$RF245"

# T-246: one real (non-blank, non-heading) line inside the block -> _q_tf=1.
awk '/<!-- quipu:threads:end -->/{print "- Proje X"} {print}' "$TMP/vr245/Threads.md" > "$TMP/vr246.md"
t; RF246=$(sh "$TFH" "$TMP/vr246.md")
assert_eq "FAZ16 T-246: one real line -> filled" '1' "$RF246"

# T-247: no marker at all (raw pre-FAZ16 file) -> _q_tf=0, no crash.
printf '%s\n' 'just some Threads.md text, no markers here at all' > "$TMP/vr247.md"
t; RF247=$(sh "$TFH" "$TMP/vr247.md")
assert_eq "FAZ16 T-247: no marker at all -> not filled, no crash" '0' "$RF247"

# T-248: the marker range is empty (start immediately followed by end, not
# even a blank line between them) -> _q_tf=0, the awk loop returns cleanly.
{
  printf '%s\n' '<!-- quipu:threads:start -->'
  printf '%s\n' '<!-- quipu:threads:end -->'
} > "$TMP/vr248.md"
t; RF248=$(sh "$TFH" "$TMP/vr248.md")
assert_eq "FAZ16 T-248: empty marker range -> not filled" '0' "$RF248"

# T-249: Threads.md missing entirely -> doctor warns doc_threads_empty, exit 0.
mkvault vr249
t; DOUT249=$( (cd "$TMP/vr249" && QUIPU_LANG=en "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
assert_eq "FAZ16 T-249: doctor exits 0 with no Threads.md" '0' "$RC"
DTMSG=$(i18n doc_threads_empty)
t; assert_eq "FAZ16 T-249: doctor warns doc_threads_empty (file missing)" 'yes' \
  "$(printf '%s\n' "$DOUT249" | awk -F"$TAB" -v m="$DTMSG" '$2=="threads" && $3==m {print "yes"; exit}')"

# T-250: Threads.md exists but the marker block is empty (T-245's vault) ->
# the same warn -- "empty" and "missing" produce the identical user message.
t; DOUT250=$( (cd "$TMP/vr245" && QUIPU_LANG=en "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
assert_eq "FAZ16 T-250: doctor exits 0 with an empty threads block" '0' "$RC"
t; assert_eq "FAZ16 T-250: doctor warns doc_threads_empty (block empty)" 'yes' \
  "$(printf '%s\n' "$DOUT250" | awk -F"$TAB" -v m="$DTMSG" '$2=="threads" && $3==m {print "yes"; exit}')"

# T-251: Threads.md's marker block is filled (vr240, after T-242's manual
# line) -> the doc_threads_empty row is NOT printed at all, exit 0.
t; DOUT251=$( (cd "$TMP/vr240" && QUIPU_LANG=en "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
assert_eq "FAZ16 T-251: doctor exits 0 with a filled threads block" '0' "$RC"
t; assert_eq "FAZ16 T-251: doctor prints no doc_threads_empty row when filled" 'no' \
  "$(printf '%s\n' "$DOUT251" | awk -F"$TAB" -v m="$DTMSG" '$2=="threads" && $3==m {f=1} END{print (f ? "yes" : "no")}')"

# T-252: context regression -- marker lines pass through _q_ctx_text's read/
# cut logic byte-for-byte (AD-5 is a documentation-only no-op on that code
# path). Also the AD-2 accepted-risk regression: with the block PREPENDED,
# a tiny QUIPU_CTX_MAX keeps the top block inside budget while a line
# appended at the BOTTOM of a large Threads.md still gets cut and flagged
# by ctx_truncated -- proof the budget behavior itself is unchanged.
#
# Budget recalibrated 700 (was 200) when the tone block (Fixed part 0c)
# joined the fixed part: mkrem's vault carries a companion.md, so its Tone
# section now inflates every fixed-part measurement here too -- 200 no
# longer leaves room for the threads start marker itself. 700 is measured
# to reproduce the same shape (start marker present, tail line cut,
# ctx_truncated present) with the tone block included.
mkrem vr252
printf '%s\n' '2026-08-23T10:00 | PostToolUse | Edit | a.md' >> "$TMP/vr252/.knotlog/activity.log"
t; rem vr252 >/dev/null 2>&1
awk '/<!-- knotlog:threads:end -->/{print "- real content"} {print}' \
  "$TMP/vr252/Threads.md" > "$TMP/vr252/Threads.md.tmp" && mv "$TMP/vr252/Threads.md.tmp" "$TMP/vr252/Threads.md"
t; CTX252=$(QUIPU_VAULT="$TMP/vr252" QUIPU_LANG=en sh "$ROOT/knotlog" context)
assert_eq "FAZ16 T-252: context passes threads markers through verbatim" 'yes' \
  "$(printf '%s\n' "$CTX252" | grep -qF '<!-- knotlog:threads:start -->' \
     && printf '%s\n' "$CTX252" | grep -qF '<!-- knotlog:threads:end -->' && printf yes || printf no)"
printf '%s\n' 'a tail line appended well below the block, long enough on its own to blow a tiny budget xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
  >> "$TMP/vr252/Threads.md"
t; CTX252B=$(QUIPU_CTX_MAX=700 QUIPU_VAULT="$TMP/vr252" QUIPU_LANG=en sh "$ROOT/knotlog" context)
CTXTRUNC=$(i18n ctx_truncated)
assert_eq "FAZ16 T-252: tiny budget keeps the top block, drops+marks the tail" 'yes' \
  "$(printf '%s\n' "$CTX252B" | grep -qF '<!-- knotlog:threads:start -->' \
     && ! printf '%s\n' "$CTX252B" | grep -qF 'a tail line appended well below' \
     && printf '%s\n' "$CTX252B" | grep -qF "$CTXTRUNC" && printf yes || printf no)"

# ---- FAZ 15 sec 3.1: companion.md's accumulating "never forget" block (T-260..T-264) ----

# T-260: a fresh vault's first `init` seeds a knotlog:core block in companion.md
# -- both markers present, and between them nothing but the core_head
# heading and one blank line (AE-3's skeleton, the reflect block's shape).
mkvault v260
QUIPU_VAULT="$TMP/v260" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
CN260=$(comp_name plain)
CF260="$TMP/v260/$CN260/companion.md"
t; assert_eq "FAZ15 T-260: knotlog:core markers both present" 'yes' \
  "$(grep -qF '<!-- knotlog:core:start -->' "$CF260" \
     && grep -qF '<!-- knotlog:core:end -->' "$CF260" && printf yes || printf no)"
awk '/<!-- knotlog:core:start -->/{f=1;next} /<!-- knotlog:core:end -->/{f=0} f' "$CF260" > "$TMP/v260-core-block.txt"
t; assert_eq "FAZ15 T-260: block is exactly two lines (heading + blank)" '2' \
  "$(awk 'END{print NR}' "$TMP/v260-core-block.txt")"
t; assert_eq "FAZ15 T-260: first line is the core_head heading" "### $(i18n core_head)" \
  "$(awk 'NR==1' "$TMP/v260-core-block.txt")"
t; assert_eq "FAZ15 T-260: second line is blank" '' \
  "$(awk 'NR==2' "$TMP/v260-core-block.txt")"

# T-261: a second `init` never touches companion.md again, byte-for-byte --
# even after the model has filled the block by hand (AE-3's write-once rule
# extends to the AC block exactly like the rest of the file).
printf '%s\n' 'Ada builds his own systems.' >> "$CF260"
BEFORE261=$(cat "$CF260")
QUIPU_VAULT="$TMP/v260" sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
t; assert_eq "FAZ15 T-261: companion.md unchanged by a second init" "$BEFORE261" "$(cat "$CF260")"

# T-262: fullness detection -- the generalized _q_reflect_filled(path, marker)
# has no CLI surface of its own (AE-4 deliberately adds no doctor/context
# wiring for quipu:core), so its literal source is extracted out of quipu
# and run in a throwaway one-shot harness script -- no quipu dispatch runs,
# only the one function body is defined and then called directly with the
# "quipu:core" marker.
FN262=$(awk '/^_q_reflect_filled\(\) \{/,/^\}/' "$ROOT/knotlog")
RFH262="$TMP/rf_harness.sh"
{
  printf '%s\n' "$FN262"
  # literal $1/$2 belong to the generated harness script, not expansion here.
  # shellcheck disable=SC2016
  printf '%s\n' '_q_reflect_filled "$1" "$2"'
  # literal $_q_rf belongs to the generated harness script, not expansion here.
  # shellcheck disable=SC2016
  printf '%s\n' 'printf "%s" "$_q_rf"'
} > "$RFH262"
mkvault v262
QUIPU_VAULT="$TMP/v262" sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
CF262="$TMP/v262/$(comp_name plain)/companion.md"
t; RF262A=$(sh "$RFH262" "$CF262" knotlog:core)
assert_eq "FAZ15 T-262: freshly seeded core block is not filled" '0' "$RF262A"
# Simulate the model editing the file: insert one real line right before the
# end marker (no stat/mtime touch of any kind -- content only).
awk '/<!-- knotlog:core:end -->/{print "Ada prefers direct, high-signal answers."} {print}' \
  "$CF262" > "$CF262.tmp" && mv "$CF262.tmp" "$CF262"
t; RF262B=$(sh "$RFH262" "$CF262" knotlog:core)
assert_eq "FAZ15 T-262: a manually added line makes the block filled" '1' "$RF262B"

# T-263: the three marker names never cross-contaminate each other's text --
# a fresh companion.md never mentions quipu:reflect, and a session note
# written by `remember` never mentions quipu:core.
mkrem v263
t; assert_eq "FAZ15 T-263: companion.md never mentions knotlog:reflect" 'no' \
  "$(grep -qF 'knotlog:reflect' "$TMP/v263/$(comp_name plain)/companion.md" && printf yes || printf no)"
printf '%s\n' '2026-08-23T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/v263/.knotlog/activity.log"
t; rem v263 >/dev/null 2>&1
D263=$(date +%Y-%m-%d)
t; assert_eq "FAZ15 T-263: a remember session note never mentions knotlog:core" 'no' \
  "$(grep -qF 'knotlog:core' "$TMP/v263/700-Sessions/$D263.md" && printf yes || printf no)"

# T-264: i18n -- core_head exists in both languages (T-118/T-232's pattern),
# and persona/en.md + persona/tr.md still carry exactly two %s (T-228's
# static count repeated -- the AC block added zero persona placeholders).
t; assert_eq "FAZ15 T-264: core_head present in both languages" 'yes' \
  "$(grep -q '^core_head=' "$ROOT/i18n/en.txt" \
     && grep -q '^core_head=' "$ROOT/i18n/tr.txt" && printf yes || printf no)"
t; assert_eq "FAZ15 T-264: persona/en.md still has exactly two %s" '2' \
  "$(grep -o '%s' "$ROOT/persona/en.md" | awk 'END{print NR+0}')"
t; assert_eq "FAZ15 T-264: persona/tr.md still has exactly two %s" '2' \
  "$(grep -o '%s' "$ROOT/persona/tr.md" | awk 'END{print NR+0}')"

# ---- FAZ 13: knotlog links hedef çözümlemesi (T-190..T-198) ----
#
# docs/FAZ13-SPEC.md, kaynak: docs/FAZ10-KONTROL.md §7/§8 madde 1. links.tsv'nin
# hedef sütunu wikilink metnidir ([[Beta]] -> "Beta"), dosya yoluna çözülmüyordu;
# `knotlog links`'in gelen-bağlantı taraması birebir dize eşitliği arıyordu (M-1).
# lib/index.awk'ın yeni mode=resolve'u (N-1/N-2) index.tsv'nin path/title
# sütunlarından üç arama tablosu kurup her links.tsv satırını tam yol -> başlık
# -> dosya adı sırasıyla çözer, belirsizlikte bir sonraki aşamaya düşmez.

# ---- T-190..T-193: mode=resolve birim testleri (süreç ayağa kaldırmadan,
# doğrudan awk çağrısı) ----

# T-190: başlık eşleşmesi -- index.tsv'de sub/b.md'nin başlığı "Beta Notu";
# links.tsv'de a.md'den "Beta Notu"ya bir wikilink -> ok, sub/b.md.
mkdir -p "$TMP/t190"
printf 'sub/b.md\tBeta Notu\t\t0\t\t\t\n' > "$TMP/t190/index.tsv"
printf 'a.md\tBeta Notu\n' > "$TMP/t190/links.tsv"
t; RES190=$(awk -v mode=resolve -f "$LIB/index.awk" "$TMP/t190/index.tsv" "$TMP/t190/links.tsv")
assert_eq "T-190: title match resolves a link to the note whose title equals the target" \
  "a.md${TAB}Beta Notu${TAB}ok${TAB}sub/b.md" "$RES190"

# T-191: dosya adı eşleşmesi -- title sütunu BOŞ ama yolun taban adı "Gamma.md"
# olan bir nota [[Gamma]] bağlantısı -> ok, bilgi klasörlüsüyle birlikte yol.
mkdir -p "$TMP/t191"
printf 'notes/Gamma.md\t\t\t0\t\t\t\n' > "$TMP/t191/index.tsv"
printf 'a.md\tGamma\n' > "$TMP/t191/links.tsv"
t; RES191=$(awk -v mode=resolve -f "$LIB/index.awk" "$TMP/t191/index.tsv" "$TMP/t191/links.tsv")
assert_eq "T-191: filename-stem match resolves when the title column is empty" \
  "a.md${TAB}Gamma${TAB}ok${TAB}notes/Gamma.md" "$RES191"

# T-192: öncelik -- hedef hem exists'te tam yol olarak ("Delta.md") hem de
# başka bir notun başlığı olarak ("title: Delta.md") geçiyor -> aşama 1
# (tam yol) kazanır, başlık aşamasına hiç bakılmaz.
mkdir -p "$TMP/t192"
printf 'Delta.md\tSome Title\t\t0\t\t\t\n' > "$TMP/t192/index.tsv"
printf 'other.md\tDelta.md\t\t0\t\t\t\n' >> "$TMP/t192/index.tsv"
printf 'a.md\tDelta.md\n' > "$TMP/t192/links.tsv"
t; RES192=$(awk -v mode=resolve -f "$LIB/index.awk" "$TMP/t192/index.tsv" "$TMP/t192/links.tsv")
assert_eq "T-192: exact-path stage wins over a same-string title match" \
  "a.md${TAB}Delta.md${TAB}ok${TAB}Delta.md" "$RES192"

# T-193: belirsizlik -- iki farklı yolun başlığı aynı ("Ortak Baslik") -> o
# başlığa yapılan bağlantı ambiguous, ilkine sessizce düşmüyor. index.tsv satır
# sırası tersine çevrilip aynı sonucun çıktığı da doğrulanıyor (sıra bağımsız).
mkdir -p "$TMP/t193"
printf 'one.md\tOrtak Baslik\t\t0\t\t\t\n' > "$TMP/t193/index.tsv"
printf 'two.md\tOrtak Baslik\t\t0\t\t\t\n' >> "$TMP/t193/index.tsv"
printf 'a.md\tOrtak Baslik\n' > "$TMP/t193/links.tsv"
t; RES193A=$(awk -v mode=resolve -f "$LIB/index.awk" "$TMP/t193/index.tsv" "$TMP/t193/links.tsv" | awk -F"$TAB" '{print $3}')
assert_eq "T-193: two notes sharing a title makes a link to it ambiguous, not the first pick" \
  'ambiguous' "$RES193A"
printf 'two.md\tOrtak Baslik\t\t0\t\t\t\n' > "$TMP/t193/index-rev.tsv"
printf 'one.md\tOrtak Baslik\t\t0\t\t\t\n' >> "$TMP/t193/index-rev.tsv"
t; RES193B=$(awk -v mode=resolve -f "$LIB/index.awk" "$TMP/t193/index-rev.tsv" "$TMP/t193/links.tsv" | awk -F"$TAB" '{print $3}')
assert_eq "T-193: ambiguity result is unchanged with index.tsv row order reversed" \
  'ambiguous' "$RES193B"

# ---- T-195/T-196: doctor entegrasyonu ----

# T-195: iki not aynı başlığı taşıyor, üçüncü bir not o başlığa [[...]] ile
# bağlanıyor -> doctor doc_links_ambiguous warn satırı basıyor, exit 0.
mkdir -p "$TMP/t195/.knotlog"
: > "$TMP/t195/.knotlog/config"
cat > "$TMP/t195/p.md" <<'EOF'
---
title: Shared Title
---
# Shared Title
P body.
EOF
cat > "$TMP/t195/q.md" <<'EOF'
---
title: Shared Title
---
# Shared Title
Q body.
EOF
cat > "$TMP/t195/r.md" <<'EOF'
# Doc R
See [[Shared Title]].
EOF
QUIPU_VAULT="$TMP/t195" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1
t; DOUT195=$( (cd "$TMP/t195" && QUIPU_LANG=en "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
assert_eq "T-195: doctor exits 0 with an ambiguous wikilink" '0' "$RC"
DLAFMT=$(awk -F= -v k=doc_links_ambiguous '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
# shellcheck disable=SC2059
DLAMSG195=$(printf "$DLAFMT" 1)
t; assert_eq "T-195: doctor warns doc_links_ambiguous with the correct count (1)" 'yes' \
  "$(printf '%s\n' "$DOUT195" | awk -F"$TAB" -v m="$DLAMSG195" '$2=="links" && $3==m {print "yes"; exit}')"
t; assert_eq "T-195: doctor emits exactly one 'links' warn row (ambiguous only, no broken)" '1' \
  "$(printf '%s\n' "$DOUT195" | awk -F"$TAB" '$2=="links"{n++} END{print n+0}')"

# T-196: regresyon kapısı -- aynı vault'ta hem eski (aşama-1-only, birebir
# eski heuristiğin simülasyonu -- FAZ 13 öncesi quipu:369-379'un aynısı) hem
# yeni doctor sayacı hesaplanıp karşılaştırılıyor. Kurgu bilinçli: "Deep Note"
# başlık biçiminde bağlanıyor (eski heuristik bulamaz, yeni algoritma başlık
# aşamasında bulur) ve "Ghost Note" gerçekten yok, İKİ AYRI nottan bağlanıyor
# (links.tsv'de iki satır, dedup olmadan sayılırsa yeni sayaç eskiyi geçerdi
# -- doctor'ın !seen[$2]++ dedup'ı bunu önlüyor, bkz. quipu N-3 yorumu).
mkdir -p "$TMP/t196/.knotlog"
: > "$TMP/t196/.knotlog/config"
cat > "$TMP/t196/x.md" <<'EOF'
---
title: Deep Note
---
# Deep Note
Some content.
EOF
cat > "$TMP/t196/a.md" <<'EOF'
# Doc A
Refers to [[Deep Note]] and [[Ghost Note]].
EOF
cat > "$TMP/t196/b.md" <<'EOF'
# Doc B
Also refers to [[Ghost Note]].
EOF
QUIPU_VAULT="$TMP/t196" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1
# Eski heuristiğin (pre-FAZ13) simülasyonu: hedef, aynen ya da ".md" eklenmiş
# hâliyle vault'ta bir dosyaya karşılık gelmiyorsa kırık sayılır, tekil hedef
# başına bir kez (!seen[$2]++ dedup, doctor'ın eski kodunun birebir aynısı).
t; OLDB196=$(awk -F"$TAB" '!seen[$2]++{print $2}' "$TMP/t196/.knotlog/links.tsv" | while IFS= read -r _t; do
  [ -n "$_t" ] || continue
  _tf="$TMP/t196/$_t.md"
  if [ "${_t%.md}" != "$_t" ]; then _tf="$TMP/t196/$_t"; fi
  [ -f "$_tf" ] || printf 'x\n'
done | awk 'END{print NR}')
assert_eq "T-196: old-style stage-1-only simulation counts 2 broken (Deep Note + Ghost Note)" '2' "$OLDB196"
t; DOUT196=$( (cd "$TMP/t196" && QUIPU_LANG=en "$ROOT/knotlog" doctor) 2>&1 )
DLBFMT196=$(awk -F= -v k=doc_links_broken '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
# shellcheck disable=SC2059
DLBMSG196=$(printf "$DLBFMT196" 1)
t; assert_eq "T-196: new doctor resolves Deep Note via title, leaves only Ghost Note broken (1)" 'yes' \
  "$(printf '%s\n' "$DOUT196" | awk -F"$TAB" -v m="$DLBMSG196" '$2=="links" && $3==m {print "yes"; exit}')"
t; assert_eq "T-196: new broken count (1) does not exceed the old simulation's (2)" 'yes' \
  "$([ 1 -le "$OLDB196" ] && printf yes || printf no)"

# ---- T-194/T-197/T-198: `knotlog links` uçtan uca ----
#
# T-194 already lives above, in place of the old T-140 (see the FAZ 10
# wikilink-graph section banner and N-6).

# T-197: geri uyum -- [[a]] (çıplak dosya adı, eski T-140'ın senaryosu) hâlâ
# a.md'yi incoming bölümünde buluyor (N-2 aşama 1'in ".md" ekleme sezgisi
# bozulmadı).
mkdir -p "$TMP/linkv197/.knotlog"
cat > "$TMP/linkv197/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/linkv197/a.md" <<'EOF'
# Doc A
Links to [[Doc B]].
EOF
cat > "$TMP/linkv197/Doc B.md" <<'EOF'
# Doc B
Links back to [[a]].
EOF
QUIPU_VAULT="$TMP/linkv197" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1
t; LOUT197=$(QUIPU_VAULT="$TMP/linkv197" QUIPU_LANG=en sh "$ROOT/knotlog" links a.md)
assert_eq "T-197: bare-filename wikilink ([[a]] -> a.md) still resolves via N-2 stage 1" \
  "$LOUTHDR
Doc B
$LINHDR
Doc B.md" "$LOUT197"

# T-198: `knotlog links <yol>` sessiz-dışlama -- hedefi belirsiz olan bir
# bağlantı, ne adaylardan birinin ne ötekinin incoming bölümünde görünmüyor.
mkdir -p "$TMP/linkv198/.knotlog"
: > "$TMP/linkv198/.knotlog/config"
cat > "$TMP/linkv198/p.md" <<'EOF'
---
title: Shared Title
---
# Shared Title
P body.
EOF
cat > "$TMP/linkv198/q.md" <<'EOF'
---
title: Shared Title
---
# Shared Title
Q body.
EOF
cat > "$TMP/linkv198/r.md" <<'EOF'
# Doc R
See [[Shared Title]].
EOF
QUIPU_VAULT="$TMP/linkv198" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1
t; LIN198P=$(QUIPU_VAULT="$TMP/linkv198" QUIPU_LANG=en sh "$ROOT/knotlog" links p.md | awk -v h="$LINHDR" 'f{print} $0==h{f=1}')
assert_eq "T-198: an ambiguous target's link does not appear as p.md's incoming" '' "$LIN198P"
t; LIN198Q=$(QUIPU_VAULT="$TMP/linkv198" QUIPU_LANG=en sh "$ROOT/knotlog" links q.md | awk -v h="$LINHDR" 'f{print} $0==h{f=1}')
assert_eq "T-198: an ambiguous target's link does not appear as q.md's incoming" '' "$LIN198Q"

# ---- T-4xx: `knotlog links <hedef>` argument resolution -----------------------
#
# Before this fix `$1 == key` only matched the note's exact vault path — a
# title or bare filename argument silently matched nothing, so "this note
# has no links" and "you typed the wrong thing" looked identical (empty
# output either way). The argument now runs through the same mode=resolve
# staged lookup (exists -> title -> basename) N-4 already applies to
# links.tsv rows, and ambiguous/not-found are reported instead of dropped.

# T-4xx-a: a TITLE argument resolves to the same note as the literal path
# (reuses $TMP/linkv from T-194: a.md's frontmatter title is "Alfa Notu").
t; LOUT_TITLE=$(QUIPU_VAULT="$TMP/linkv" QUIPU_LANG=en sh "$ROOT/knotlog" links "Alfa Notu")
assert_eq "T-4xx: knotlog links <title> resolves to the same note as <path>" \
  "$LOUTHDR
Doc B
$LINHDR
Doc B.md" "$LOUT_TITLE"

# T-4xx-b: a bare BASENAME argument (reuses $TMP/linkv197: a.md has no
# frontmatter title, so its basename is "a").
t; LOUT_BASE=$(QUIPU_VAULT="$TMP/linkv197" QUIPU_LANG=en sh "$ROOT/knotlog" links "a")
assert_eq "T-4xx: knotlog links <basename> resolves to the same note as <path>" \
  "$LOUTHDR
Doc B
$LINHDR
Doc B.md" "$LOUT_BASE"

# T-4xx-c: an AMBIGUOUS argument (reuses $TMP/linkv198: p.md and q.md share
# title "Shared Title") lists both candidates on stderr and exits nonzero
# instead of printing empty sections.
t; QUIPU_VAULT="$TMP/linkv198" QUIPU_LANG=en sh "$ROOT/knotlog" links "Shared Title" \
  >"$TMP/linkv198-amb.out" 2>"$TMP/linkv198-amb.err"; RC=$?
assert_eq "T-4xx: ambiguous links argument exits 1" '1' "$RC"
assert_eq "T-4xx: ambiguous links argument prints nothing on stdout" '' "$(cat "$TMP/linkv198-amb.out")"
t; assert_eq "T-4xx: ambiguous links argument names the target on stderr" 'yes' \
  "$(grep -Fq 'Shared Title' "$TMP/linkv198-amb.err" && printf yes || printf no)"
t; assert_eq "T-4xx: ambiguous links argument lists p.md as a candidate" 'yes' \
  "$(grep -Fq 'p.md' "$TMP/linkv198-amb.err" && printf yes || printf no)"
t; assert_eq "T-4xx: ambiguous links argument lists q.md as a candidate" 'yes' \
  "$(grep -Fq 'q.md' "$TMP/linkv198-amb.err" && printf yes || printf no)"

# T-4xx-d: an unresolvable argument gets a clear "not found" error instead
# of empty output (reuses $TMP/linkv from T-194).
t; QUIPU_VAULT="$TMP/linkv" QUIPU_LANG=en sh "$ROOT/knotlog" links "No Such Note" \
  >"$TMP/linkv-nf.out" 2>"$TMP/linkv-nf.err"; RC=$?
assert_eq "T-4xx: not-found links argument exits 1" '1' "$RC"
assert_eq "T-4xx: not-found links argument prints nothing on stdout" '' "$(cat "$TMP/linkv-nf.out")"
t; assert_eq "T-4xx: not-found links argument names the target on stderr" 'yes' \
  "$(grep -Fq 'No Such Note' "$TMP/linkv-nf.err" && printf yes || printf no)"

# ---- FAZ 17: "noktaya bitişik terim" -- count_occ_bounded (T-270..T-282) ----
#
# docs/PLAN.md §7's one documented correctness bug: a query term that appears
# word-bounded (clean, space-separated) in at least one note made OTHER notes
# where the same term is glued to trailing punctuation (`term.`, `term,`)
# silently drop out of `search` results -- the term IS in the index (a
# literal `search "term."` finds it), only the query-time boundary check
# missed it. docs/FAZ17-SPEC.md AG-1 chose the search-side fix
# (count_occ_bounded() in lib/search.awk) over an index-side one specifically
# because it needs no `--full` reindex -- lib/index.awk is untouched by this
# phase (T-282 below is the direct proof).

# T-270 (AF-1..AF-3, the bug itself): a three-note vault where the SAME term
# appears dotted, comma-glued, and plain-spaced. Before this phase's fix only
# spaced.md came back; all three must now.
mkdir -p "$TMP/vt270/.knotlog"
cat > "$TMP/vt270/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt270/dotted.md" <<'EOF'
# dotted
sentence ending in ortakterim. right here.
EOF
cat > "$TMP/vt270/comma.md" <<'EOF'
# comma
list item ortakterim, then more.
EOF
cat > "$TMP/vt270/spaced.md" <<'EOF'
# spaced
ortakterim appears here plainly.
EOF
QUIPU_VAULT="$TMP/vt270" sh "$ROOT/knotlog" index >/dev/null 2>&1
T270=$(QUIPU_VAULT="$TMP/vt270" sh "$ROOT/knotlog" search ortakterim --paths | sort)
t; assert_eq "T-270: dotted/comma/spaced notes all match the clean query term" \
  "comma.md
dotted.md
spaced.md" "$T270"

# T-271 (regression): the ALREADY-working literal punctuated query
# ("ortakterim.") still finds dotted.md -- the fix must not break this path.
# S1 (2026-10-30): the query's trailing "." is now stripped, so it matches all three notes like T-270.
T271=$(QUIPU_VAULT="$TMP/vt270" sh "$ROOT/knotlog" search "ortakterim." --paths | sort)
t; assert_eq "T-271: punctuated query matches the same notes as the bare term" \
  "comma.md
dotted.md
spaced.md" "$T271"

# T-272 (word-boundary discipline preserved): "term" must never match inside
# "terminal", even now that trailing punctuation is tolerated. Vault has a
# genuine "term." match (keeps the primary word-bounded path active, total>0,
# so the imprecise substring fallback never engages) plus a "terminal"-only
# note that must stay excluded.
mkdir -p "$TMP/vt272/.knotlog"
cat > "$TMP/vt272/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt272/dotted-clean.md" <<'EOF'
# dotted clean
term. tek basina noktayla bitisik geciyor.
EOF
cat > "$TMP/vt272/only-terminal.md" <<'EOF'
# only terminal
yalnizca terminal kelimesi geciyor, baska hicbir sey yok.
EOF
QUIPU_VAULT="$TMP/vt272" sh "$ROOT/knotlog" index >/dev/null 2>&1
T272=$(QUIPU_VAULT="$TMP/vt272" sh "$ROOT/knotlog" search term --paths | sort)
t; assert_eq "T-272: 'term' never matches inside 'terminal'" 'dotted-clean.md' "$T272"

# T-273 (word-boundary discipline, glued case): "term.ly" -- punctuation
# immediately followed by more letters, no boundary space -- must NOT count
# as a match, and the command must exit cleanly (no hang/crash) even though
# the noisy note is full of other "term"-prefixed words with trailing text.
mkdir -p "$TMP/vt273/.knotlog"
cat > "$TMP/vt273/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt273/anchor.md" <<'EOF'
# anchor
genuine term. right here.
EOF
cat > "$TMP/vt273/noisy.md" <<'EOF'
# noisy
terminals, terminate. termite; terminology: term.ly all glued or extended,
never the bare word by itself.
EOF
QUIPU_VAULT="$TMP/vt273" sh "$ROOT/knotlog" index >/dev/null 2>&1
T273=$(QUIPU_VAULT="$TMP/vt273" sh "$ROOT/knotlog" search term --paths); RC273=$?
t; assert_eq "T-273: 'term.ly' (letters resume after punctuation) does not match" 'anchor.md' "$T273"
t; assert_eq "T-273: exit code 0, no hang/crash on the noisy note" '0' "$RC273"

# T-274: every character in is_trail_punct()'s set (. , ; : ! ? ) ' ") is
# individually recognized -- one note carries the term nine times, once per
# mark; a control note (plus three term-free fillers, to keep IDF positive
# so ranking reads intuitively) carries it once. The nine-mark note must
# outrank the one-mark note, proving tf counted all nine, not a subset.
mkdir -p "$TMP/vt274/.knotlog"
cat > "$TMP/vt274/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt274/heavy.md" <<'EOF'
# heavy
punctterm. one.
punctterm, two.
punctterm; three.
punctterm: four.
punctterm! five.
punctterm? six.
punctterm) seven.
punctterm' eight.
punctterm" nine.
EOF
cat > "$TMP/vt274/light.md" <<'EOF'
# light
punctterm appears only once here plainly.
EOF
printf 'unrelated content one with none of the query terms at all.\n' > "$TMP/vt274/filler1.md"
printf 'unrelated content two with none of the query terms at all.\n' > "$TMP/vt274/filler2.md"
printf 'unrelated content three with none of the query terms at all.\n' > "$TMP/vt274/filler3.md"
QUIPU_VAULT="$TMP/vt274" sh "$ROOT/knotlog" index >/dev/null 2>&1
T274=$(QUIPU_VAULT="$TMP/vt274" sh "$ROOT/knotlog" search punctterm)
t; assert_eq "T-274: all nine is_trail_punct() marks count -- nine-mark note outranks one-mark note" \
  "0.618${TAB}heavy.md${TAB}heavy${TAB}
0.392${TAB}light.md${TAB}light${TAB}" "$T274"

# T-275: stacked trailing punctuation (".)" and "!?") still matches -- the
# inner is_trail_punct() loop must walk past MORE than one mark before
# checking for the boundary space.
mkdir -p "$TMP/vt275/.knotlog"
cat > "$TMP/vt275/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt275/stacked.md" <<'EOF'
# stacked
quoted like this stackterm.) and also stackterm!? twice.
EOF
printf 'unrelated content one with none of the query terms at all.\n' > "$TMP/vt275/filler1.md"
printf 'unrelated content two with none of the query terms at all.\n' > "$TMP/vt275/filler2.md"
QUIPU_VAULT="$TMP/vt275" sh "$ROOT/knotlog" index >/dev/null 2>&1
T275=$(QUIPU_VAULT="$TMP/vt275" sh "$ROOT/knotlog" search stackterm --paths)
t; assert_eq "T-275: stacked trailing punctuation (.) and !?) still matches" 'stacked.md' "$T275"

# T-276 (precision improvement, not just recall): a term that appears ONLY
# glued to punctuation, in a vault that also has a DIFFERENT word sharing its
# prefix. Before this phase: no document word-bounded-matched, so the
# imprecise substring fallback engaged and wrongly returned BOTH notes.
# After: the primary path matches the punctuated note directly (total>0), the
# fallback never engages, and the look-alike prefix word is correctly
# excluded.
mkdir -p "$TMP/vt276/.knotlog"
cat > "$TMP/vt276/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt276/dotonly.md" <<'EOF'
# dotonly
only appears as onlydotted. here, glued to a period.
EOF
cat > "$TMP/vt276/lookalike.md" <<'EOF'
# lookalike
this note has onlydottedextra as one single different word, not the term.
EOF
QUIPU_VAULT="$TMP/vt276" sh "$ROOT/knotlog" index >/dev/null 2>&1
T276=$(QUIPU_VAULT="$TMP/vt276" sh "$ROOT/knotlog" search onlydotted --paths)
t; assert_eq "T-276: punctuation-only term no longer falls back to an imprecise prefix match" 'dotonly.md' "$T276"

# T-277 (score preservation, AG-2): a clean, multi-term query over a vault
# with NO punctuation-glued occurrences of the term anywhere -- score/order
# must be byte-identical to the pre-FAZ17 engine (verified by hand against
# the baseline `lib/search.awk`, docs/FAZ17-SPEC.md §7).
mkdir -p "$TMP/vt277/.knotlog"
cat > "$TMP/vt277/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt277/alpha.md" <<'EOF'
---
title: temizterim baslikta
tags: [temizterim, diger]
---

# Alpha

Bu notta temizterim kelimesi bir kez geciyor temiz bicimde.
EOF
cat > "$TMP/vt277/beta.md" <<'EOF'
# Beta

Bu notta temizterim once burada sonra baska yerde tekrar temizterim ve
uçuncu kez daha sonra temizterim geciyor uzun bir cumle icinde araya baska
kelimeler girerek.
EOF
cat > "$TMP/vt277/gamma.md" <<'EOF'
# Gamma

Bu not temizterim ile ilgisiz baska kelimeler iceriyor ama terimin
kendisi hic gecmiyor burada sadece benzer bir kelime var terimsel.
EOF
cat > "$TMP/vt277/delta.md" <<'EOF'
# Delta

Bu not tamamen alakasiz bir konu hakkinda hicbir ortak kelime icermiyor.
EOF
QUIPU_VAULT="$TMP/vt277" sh "$ROOT/knotlog" index >/dev/null 2>&1
T277=$(QUIPU_VAULT="$TMP/vt277" sh "$ROOT/knotlog" search "temizterim baska")
t; assert_eq "T-277: clean multi-term query score/order is byte-identical to the pre-FAZ17 engine" \
  "-0.818${TAB}gamma.md${TAB}Gamma${TAB}
-1.243${TAB}beta.md${TAB}Beta${TAB}
-3.557${TAB}alpha.md${TAB}temizterim baslikta${TAB}temizterim,diger" "$T277"

# T-278 (score preservation, --tag filtered): same vault, same regression --
# the --tag elimination filter (FAZ 10 Z-3) runs before either pass sees the
# term, so this exercises filter_ok() alongside count_occ_bounded().
T278=$(QUIPU_VAULT="$TMP/vt277" sh "$ROOT/knotlog" search temizterim --tag temizterim)
t; assert_eq "T-278: --tag filtered clean query score is byte-identical to the pre-FAZ17 engine" \
  "-4.532${TAB}alpha.md${TAB}temizterim baslikta${TAB}temizterim,diger" "$T278"

# T-279 (score preservation, negative IDF): single-doc vault -- the `matched`
# flag compensation (PLAN §7 "Negatif IDF") still returns the hit with the
# exact pre-FAZ17 score.
mkdir -p "$TMP/vt279/.knotlog"
cat > "$TMP/vt279/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
printf '# only\n\nonly document with unique words here.\n' > "$TMP/vt279/solo.md"
QUIPU_VAULT="$TMP/vt279" sh "$ROOT/knotlog" index >/dev/null 2>&1
T279=$(QUIPU_VAULT="$TMP/vt279" sh "$ROOT/knotlog" search unique)
t; assert_eq "T-279: single-doc negative-IDF score is byte-identical to the pre-FAZ17 engine" \
  "-1.099${TAB}solo.md${TAB}only${TAB}" "$T279"

# T-280 (score preservation, AF-4's pre-existing quirk pinned): three
# IMMEDIATELY adjacent repeats of the same clean word. count_occ()'s old
# substring-consume algorithm already undercounted this (2, not 3, because
# a matched occurrence's trailing space and the next occurrence's leading
# space are the SAME character, consumed once) -- count_occ_bounded()'s
# clean branch must reproduce that exact quirk, not "fix" it, so the score
# stays byte-identical to the pre-FAZ17 engine.
mkdir -p "$TMP/vt280/.knotlog"
cat > "$TMP/vt280/.knotlog/config" <<'EOF'
fold=tr
lang=en
EOF
cat > "$TMP/vt280/dup.md" <<'EOF'
# dup
dupword dupword dupword appear three times adjacently.
EOF
printf 'unrelated content one with none of the query terms at all.\n' > "$TMP/vt280/filler1.md"
printf 'unrelated content two with none of the query terms at all.\n' > "$TMP/vt280/filler2.md"
QUIPU_VAULT="$TMP/vt280" sh "$ROOT/knotlog" index >/dev/null 2>&1
T280=$(QUIPU_VAULT="$TMP/vt280" sh "$ROOT/knotlog" search dupword)
t; assert_eq "T-280: adjacent-triplicate undercount quirk (2, not 3) carries over unchanged" \
  "0.729${TAB}dup.md${TAB}dup${TAB}" "$T280"

# T-281 (AG-4): static check -- lib/search.awk, scanned with the SAME
# widened pattern T-163 uses for lib/index.awk (gsub/sub/match calls, `~`/
# `!~`, a regex-separated split), still shows zero `/.../` regex literals.
# T-178 already pins the narrower `~`-only count to 0; this is that check's
# T-163-equivalent superset, covering is_trail_punct()/count_occ_bounded()
# too.
REGEX_COUNT_SEARCH_WIDE=$(awk '/(gsub|sub|match)\(\// || /~ *\// || /split\([^)]*, *\// {n++} END{print n+0}' "$LIB/search.awk")
t; assert_eq "T-281: lib/search.awk has zero regex literals under T-163's widened pattern" '0' "$REGEX_COUNT_SEARCH_WIDE"

# T-282 (AG-1's central claim): lib/index.awk was NOT touched by this phase
# -- a plain `knotlog index` and a `knotlog index --full` over the SAME vault
# must produce a byte-identical index.tsv, proving no reindex is needed and
# no existing vault's index.tsv is invalidated by this fix.
cp "$TMP/vt270/.knotlog/index.tsv" "$TMP/vt270/.knotlog/index_before_full.tsv"
QUIPU_VAULT="$TMP/vt270" sh "$ROOT/knotlog" index --full >/dev/null 2>&1
T282=$(diff "$TMP/vt270/.knotlog/index_before_full.tsv" "$TMP/vt270/.knotlog/index.tsv")
t; assert_eq "T-282: knotlog index --full produces a byte-identical index.tsv (no reindex needed)" '' "$T282"

# T-283: _q_home() resolves through a true symlinked $0 (README's install
# contract). Git Bash can emulate plain `ln -s` with a copy or an unusable
# placeholder, so require a native symlink there; unsupported Windows hosts
# exercise the install command's explicit failure path below instead of
# pretending a copy is a link or skipping the platform.
make_true_symlink() {
  _ts_source=$1
  _ts_link=$2
  _ts_msys="${MSYS:+$MSYS }winsymlinks:nativestrict"
  if ! MSYS=$_ts_msys ln -s "$_ts_source" "$_ts_link"; then
    return 1
  fi
  if [ -L "$_ts_link" ] && [ -f "$_ts_link" ]; then
    return 0
  fi
  rm -f "$_ts_link"
  return 1
}

TRUE_SYMLINKS=0
mkvault v283
if make_true_symlink "$ROOT/knotlog" "$TMP/v283-quipu-link"; then
  TRUE_SYMLINKS=1
  t; QUIPU_VAULT="$TMP/v283" sh "$TMP/v283-quipu-link" init --plain --no-prompt \
    --user Ada --lang en >"$TMP/v283.out" 2>"$TMP/v283.err"; RC=$?
  assert_eq "T-283: init via true symlinked \$0 exits 0 (no layout/i18n crash)" '0' "$RC"
  t; # shellcheck disable=SC2059
  assert_eq "T-283: true symlinked \$0 resolves the real translated i18n directory" \
    "$(printf "$(i18n init_lang)\n" en)" \
    "$(grep '^language set:' "$TMP/v283.out")"
else
  if [ -e "$TMP/v283-quipu-link" ] || [ -L "$TMP/v283-quipu-link" ]; then
    T283_FAKE=yes
  else
    T283_FAKE=no
  fi
  t; assert_eq "T-283: unsupported native symlink host leaves no fake command" 'no' "$T283_FAKE"
fi

# ---- context identity line (ctx_identity_*, T-285..T-288) ----
# `knotlog context`'s _q_ctx_text() had no path that ever surfaced config's
# user=/companion= values: the ONLY content Claude Code's/Codex's SessionStart
# hook actually injects (`context --json SessionStart`) never named the
# companion or the user. Fixed by prepending an identity line, built from
# the same config-awk read pattern _q_lang() uses, ahead of the activity
# section -- covering all four presence combinations here.
#
# The line is phrased as a second-person directive ("You are X ... answer as
# X"), not third-person data ("identity: companion=X"): models were reading
# the old neutral-data phrasing as background info about the vault, not as
# an instruction to adopt the companion name, and kept introducing
# themselves as "Claude Code". Three keys cover the three combinations that
# assert an identity/carry a name; "user only" has no companion identity to
# assert, so it stays plain info about who it's talking to.

# T-285: both user= and companion= set -> exact identity line, right after
# the unconditional "now:" line (GÖREV 2 puts a date/time/weekday line at
# the very top of every context emission -- ahead of even identity -- so
# these positional checks moved from line 1 to line 2; `sed -n 2p` instead
# of `head -1`).
mkvault v285
printf 'lang=en\nuser=Ada\ncompanion=Sumi\n' >> "$TMP/v285/.knotlog/config"
t; CTX285=$(QUIPU_VAULT="$TMP/v285" sh "$ROOT/knotlog" context)
# shellcheck disable=SC2059
ID285=$(printf "$(i18n ctx_identity_both)" 'Sumi' 'Ada' 'Sumi')
assert_eq "T-285: both user=+companion= -> exact identity line" "$ID285" "$(printf '%s\n' "$CTX285" | sed -n 2p)"

# T-286: only companion= set -> identity line names just the companion.
mkvault v286
printf 'lang=en\ncompanion=Sumi\n' >> "$TMP/v286/.knotlog/config"
t; CTX286=$(QUIPU_VAULT="$TMP/v286" sh "$ROOT/knotlog" context)
# shellcheck disable=SC2059
ID286=$(printf "$(i18n ctx_identity_companion_only)" 'Sumi' 'Sumi')
assert_eq "T-286: companion= only -> identity line names just the companion" "$ID286" "$(printf '%s\n' "$CTX286" | sed -n 2p)"

# T-287: only user= set -> identity line names just the user.
mkvault v287
printf 'lang=en\nuser=Ada\n' >> "$TMP/v287/.knotlog/config"
t; CTX287=$(QUIPU_VAULT="$TMP/v287" sh "$ROOT/knotlog" context)
# shellcheck disable=SC2059
ID287=$(printf "$(i18n ctx_identity_user_only)" 'Ada')
assert_eq "T-287: user= only -> identity line names just the user" "$ID287" "$(printf '%s\n' "$CTX287" | sed -n 2p)"

# T-288: neither set (mkvault's bare empty config) -> no identity line at
# all, and the ctx_activity header stays first AFTER the "now:" line
# (existing behavior unchanged past line 1, matches T-284's --bridge
# regression check).
mkvault v288
printf 'lang=en\n' >> "$TMP/v288/.knotlog/config"
t; CTX288=$(QUIPU_VAULT="$TMP/v288" sh "$ROOT/knotlog" context)
assert_eq "T-288: no user=/companion= -> no identity line, ctx_activity header stays first (after now:)" 'yes' \
  "$(printf '%s\n' "$CTX288" | sed -n 2p | grep -qF "$(i18n ctx_activity)" \
     && ! printf '%s\n' "$CTX288" | grep -qE 'in this vault|is named' && printf yes || printf no)"

# T-289: --json SessionStart carries the identity line too -- this is the
# ONLY content Claude Code's SessionStart hook actually injects, so proving
# it here (not just on the plain `context` path) is the point of this fix.
mkvault v289
printf 'lang=en\nuser=Ada\ncompanion=Sumi\n' >> "$TMP/v289/.knotlog/config"
t; J289=$(QUIPU_VAULT="$TMP/v289" sh "$ROOT/knotlog" context --json SessionStart)
D289=$(printf '%s' "$J289" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "T-289: context --json SessionStart carries the identity line" 'yes' \
  "$(printf '%s\n' "$D289" | grep -qF "$ID285" && printf yes || printf no)"

# ---- context purpose line (ctx_purpose, T-290..T-292) ----
# purpose= (init --purpose) was only ever written into AGENTS.md's static
# quipu:start block (bridge_purpose) -- `knotlog context` (and thus the
# SessionStart hook) never carried it. Fixed symmetrically with the identity
# line above: same config-awk read pattern, placed right after identity.

# T-290: purpose= set -> exact purpose line, right after the identity line
# (which itself sits at line 2, after the unconditional "now:" line --
# `sed -n '2,3p'` instead of `head -2`).
mkvault v290
printf 'lang=en\nuser=Ada\ncompanion=Sumi\npurpose=ship quipu v2\n' >> "$TMP/v290/.knotlog/config"
t; CTX290=$(QUIPU_VAULT="$TMP/v290" sh "$ROOT/knotlog" context)
# shellcheck disable=SC2059
PURP290=$(printf "$(i18n ctx_purpose)" 'ship quipu v2')
assert_eq "T-290: purpose= set -> exact purpose line, right after identity" \
  "$ID285
$PURP290" "$(printf '%s\n' "$CTX290" | sed -n '2,3p')"

# T-291 (regression): purpose= NOT set -> no purpose line at all (existing
# tests already mostly assume this, but assert it explicitly here).
mkvault v291
printf 'lang=en\nuser=Ada\ncompanion=Sumi\n' >> "$TMP/v291/.knotlog/config"
t; CTX291=$(QUIPU_VAULT="$TMP/v291" sh "$ROOT/knotlog" context)
assert_eq "T-291: no purpose= -> no purpose line" 'yes' \
  "$(printf '%s\n' "$CTX291" | grep -q '^purpose:' && printf no || printf yes)"

# T-292: neither identity nor purpose set -> no purpose line, ctx_activity
# header stays first after identity/purpose (same baseline as T-288, and
# shifted to line 2 by the unconditional "now:" line the same way).
mkvault v292
printf 'lang=en\npurpose=alone, no identity\n' >> "$TMP/v292/.knotlog/config"
t; CTX292=$(QUIPU_VAULT="$TMP/v292" sh "$ROOT/knotlog" context)
# shellcheck disable=SC2059
PURP292=$(printf "$(i18n ctx_purpose)" 'alone, no identity')
assert_eq "T-292: purpose= without identity -> purpose line is first, no identity line" 'yes' \
  "$(printf '%s\n' "$CTX292" | sed -n 2p | grep -qF "$PURP292" \
     && ! printf '%s\n' "$CTX292" | grep -qE 'in this vault|is named' && printf yes || printf no)"


# ---- install command contract ----

# Build a deterministic command-search suffix from the real tool directories.
# Git Bash cannot reliably execute the raw `ln -s` aliases the old fixture
# created for every tool (the shell then returned 127 before install ran).
# Install scenarios put a dedicated writable temp bin first; the de-duplicated
# real-directory suffix supplies commands only and is never an install target.
mk_install_tool_path() {
  _it_path=
  for _it_tool in awk basename cat chmod dirname git grep ln ls mkdir mv rm sed sh; do
    _it_source=$(command -v "$_it_tool") || return 1
    _it_dir=$(CDPATH='' cd -- "$(dirname -- "$_it_source")" && pwd -P) || return 1
    case ":$_it_path:" in
      *":$_it_dir:"*) ;;
      *)
        if [ -n "$_it_path" ]; then
          _it_path="$_it_path:$_it_dir"
        else
          _it_path=$_it_dir
        fi
        ;;
    esac
  done
  printf '%s\n' "$_it_path"
}


assert_install_rc() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    not_ok "$1"
    printf '#    expected: [%s]\n#    got:      [%s]\n' "$2" "$3"
    sed 's/^/#    stderr: /' "$4"
  fi
}

INSTALL_TOOLS=$(mk_install_tool_path) || exit 1
INSTALL_SHELL=$(command -p -v sh) || exit 1
case "$INSTALL_SHELL" in
  /*) ;;
  *) printf '# install fixture could not capture an absolute shell: %s\n' "$INSTALL_SHELL" >&2; exit 1 ;;
esac

# Success, flag forwarding, PATH-order scanning, language-independent folder
# naming, spaces/apostrophes, git init, and executable command link.
IUSER="Ada O'Neil"
IPARENT="$TMP/install-success-parent"
IBIN="$TMP/install-success-bin"
ILATER="$TMP/install-success-later-bin"
mkdir -p "$IPARENT" "$IBIN" "$ILATER"
t; PATH=":$TMP/install-missing:$IBIN:$ILATER:$INSTALL_TOOLS" QUIPU_LANG=en \
  sh "$ROOT/knotlog" install --plain "$IPARENT" --git --no-prompt --lang tr \
  --user "$IUSER" --companion Kuz --purpose "Kalici hafiza" \
  >"$TMP/install-success.out" 2>"$TMP/install-success.err"; IRC=$?
ITARGET="$IPARENT/$IUSER's Knotlog"
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  assert_install_rc "install: complete flagged install exits 0" '0' "$IRC" "$TMP/install-success.err"
  t; assert_eq "install: generated folder is exactly <user>'s Knotlog" 'yes' \
    "$([ -d "$ITARGET" ] && printf yes || printf no)"
  t; assert_eq "install: forwards plain/lang/user/companion/purpose flags" 'yes' \
    "$(grep -q '^layout=plain$' "$ITARGET/.knotlog/config" \
       && grep -q '^lang=tr$' "$ITARGET/.knotlog/config" \
       && grep -q "^user=$IUSER$" "$ITARGET/.knotlog/config" \
       && grep -q '^companion=Kuz$' "$ITARGET/.knotlog/config" \
       && grep -q '^purpose=Kalici hafiza$' "$ITARGET/.knotlog/config" \
       && printf yes || printf no)"
  t; assert_eq "install: fresh Claude settings copy is byte-identical to adapter" 'yes' \
    "$(cmp -s "$ROOT/adapters/claude-code.json" \
            "$ITARGET/.claude/settings.json" && printf yes || printf no)"
  IGIT_WORK_TREE=$( (cd "$ITARGET" && git rev-parse --is-inside-work-tree) 2>&1)
  IGIT_RC=$?
  if [ "$IGIT_RC" -ne 0 ]; then
    IGIT_WORK_TREE="git exited $IGIT_RC: $IGIT_WORK_TREE"
  fi
  t; assert_eq "install: forwards --git and initializes a Git work tree" 'true' "$IGIT_WORK_TREE"
  t; assert_eq "install: creates a usable true symlink only in the first writable PATH entry" 'yes' \
    "$([ -L "$IBIN/knotlog" ] && [ -f "$IBIN/knotlog" ] \
       && [ -x "$IBIN/knotlog" ] && [ ! -e "$ILATER/knotlog" ] && printf yes || printf no)"
  t; IVERSION=$(PATH="$IBIN:$INSTALL_TOOLS" "$IBIN/knotlog" --version)
  assert_eq "install: installed symlink executes the real knotlog script" 'knotlog 1.2.0' "$IVERSION"

  # Existing matching vault/link is idempotent and preserves user-authored text.
  touch -t 200001010101 "$ITARGET/.claude/settings.json"
  t; ICLAUDE_M=$(mtime "$ITARGET/.claude/settings.json")
  printf 'install user marker\n' >> "$ITARGET/AGENTS.md"
  t; PATH="$IBIN:$ILATER:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install "$IPARENT" \
    --no-prompt --user "$IUSER" >"$TMP/install-idem.out" 2>"$TMP/install-idem.err"; IRC=$?
  assert_install_rc "install: second run with same vault and resolved link exits 0" '0' "$IRC" "$TMP/install-idem.err"
  t; assert_eq "install: idempotent run preserves vault text, usable link, and later PATH entry" 'yes' \
    "$(grep -q '^install user marker$' "$ITARGET/AGENTS.md" \
       && [ -L "$IBIN/knotlog" ] && [ -f "$IBIN/knotlog" ] \
       && [ -x "$IBIN/knotlog" ] && [ ! -e "$ILATER/knotlog" ] \
       && printf yes || printf no)"
  t; assert_eq "install: identical Claude settings incur no mtime churn" \
    "$ICLAUDE_M" "$(mtime "$ITARGET/.claude/settings.json")"

  # A user-owned differing Claude settings file is never overwritten or
  # merged. The warning must identify both files so the merge is actionable.
  printf '%s\n' '{"userSetting":"keep exactly"}' > "$TMP/install-claude-keep.json"
  cp "$TMP/install-claude-keep.json" "$ITARGET/.claude/settings.json"
  t; PATH="$IBIN:$ILATER:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install "$IPARENT" \
    --no-prompt --user "$IUSER" >"$TMP/install-claude-diff.out" \
    2>"$TMP/install-claude-diff.err"; IRC=$?
  assert_install_rc "install: differing Claude settings reinstall exits 0" '0' "$IRC" "$TMP/install-claude-diff.err"
  t; assert_eq "install: differing Claude settings are preserved byte-for-byte" 'yes' \
    "$(cmp -s "$TMP/install-claude-keep.json" \
            "$ITARGET/.claude/settings.json" && printf yes || printf no)"
  t; assert_eq "install: Claude preservation warning names destination and source" 'yes' \
    "$(grep -qF "$ICLAUDE_DEST_RESOLVED" "$TMP/install-claude-diff.out" \
       && grep -qF "$ICLAUDE_SRC_RESOLVED" "$TMP/install-claude-diff.out" \
       && printf yes || printf no)"
  # install resolves the parent with `pwd -P`, so on macOS and Git Bash it
  # prints the physically resolved path; grep that form, not $TMP verbatim.
  ICLAUDE_DEST_RESOLVED="$(CDPATH='' cd -- "$ITARGET" && pwd -P)/.claude/settings.json"
  ICLAUDE_SRC_RESOLVED="$(CDPATH='' cd -- "$ROOT/adapters" && pwd -P)/claude-code.json"
else
  assert_install_rc "install: unsupported true-symlink host exits 2 clearly" '2' "$IRC" "$TMP/install-success.err"
  # shellcheck disable=SC2059
  IUNSUPPORTED_LINK_MSG=$(printf "$(i18n err_install_link_unusable)" \
    "$IBIN/knotlog.quipu-link-test-PID")
  t; assert_eq "install: unsupported true-symlink host leaves neither vault nor fake command" 'yes' \
    "$(sed 's/-[0-9][0-9]*$/-PID/' "$TMP/install-success.err" \
       | grep -qF "$IUNSUPPORTED_LINK_MSG" \
       && [ ! -e "$ITARGET" ] && [ -z "$(find "$IBIN" -mindepth 1 -print)" ] \
       && [ ! -e "$ILATER/knotlog" ] && printf yes || printf no)"

  # Repeating the unsupported operation remains clean rather than accepting a
  # copy or stale probe as an idempotent command.
  t; PATH="$IBIN:$ILATER:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install "$IPARENT" \
    --no-prompt --user "$IUSER" >"$TMP/install-idem.out" 2>"$TMP/install-idem.err"; IRC=$?
  assert_install_rc "install: repeated unsupported symlink attempt still exits 2" '2' "$IRC" "$TMP/install-idem.err"
  t; assert_eq "install: repeated unsupported attempt remains mutation-free" 'yes' \
    "$([ ! -e "$ITARGET" ] && [ -z "$(find "$IBIN" -mindepth 1 -print)" ] \
       && [ ! -e "$ILATER/knotlog" ] && printf yes || printf no)"
fi

# A lying `ln` that exits 0 after copying the source must not let install
# report success. The copied artifact is owned by this attempt and is removed
# before init; the test-owned fake tool itself and all real tools stay intact.
IFAKE_PARENT="$TMP/install-fake-ln-parent"
IFAKE_BIN="$TMP/install-fake-ln-bin"
IFAKE_TOOLS="$TMP/install-fake-ln-tools"
mkdir -p "$IFAKE_PARENT" "$IFAKE_BIN" "$IFAKE_TOOLS"
IFAKE_BIN_CANON=$(CDPATH='' cd -- "$IFAKE_BIN" && pwd -P) || exit 1
cat > "$IFAKE_TOOLS/ln" <<'EOF'
#!/bin/sh
cat "$2" > "$3"
chmod +x "$3"
exit 0
EOF
chmod +x "$IFAKE_TOOLS/ln"
t; PATH="$IFAKE_BIN:$IFAKE_TOOLS:$INSTALL_TOOLS" QUIPU_LANG=en \
  sh "$ROOT/knotlog" install "$IFAKE_PARENT" --no-prompt --user "Copy Trap" \
  >"$TMP/install-fake-ln.out" 2>"$TMP/install-fake-ln.err"; IRC=$?
assert_install_rc "install: copied command masquerading as symlink exits 2" '2' "$IRC" "$TMP/install-fake-ln.err"
IFAKE_ERROR=$(cat "$TMP/install-fake-ln.err")
# Compare the localized semantic text independently from the attempted path.
# A sentinel removes only the format argument, without GNU/BSD sed or PID
# assumptions; pwd -P gives the same canonical bindir used by install.
# shellcheck disable=SC2059
IFAKE_LINK_SENTINEL=QUIPU-LINK-PATH
# shellcheck disable=SC2059
IFAKE_LINK_EXPECT=$(printf "$(i18n err_install_link_unusable)" "$IFAKE_LINK_SENTINEL")
IFAKE_LINK_TEXT=${IFAKE_LINK_EXPECT%"$IFAKE_LINK_SENTINEL"}
case "$IFAKE_ERROR" in
  *"$IFAKE_LINK_TEXT"*) IFAKE_LINK_ACTUAL=$IFAKE_LINK_TEXT ;;
  *) IFAKE_LINK_ACTUAL=$IFAKE_ERROR ;;
esac
t; assert_eq "install: rejected copy emits the localized unusable-link diagnostic" \
  "$IFAKE_LINK_TEXT" "$IFAKE_LINK_ACTUAL"

IFAKE_PROBE_PREFIX="$IFAKE_BIN_CANON/knotlog.quipu-link-test-"
case "$IFAKE_ERROR" in
  *"$IFAKE_PROBE_PREFIX"*) IFAKE_PROBE_ACTUAL=$IFAKE_PROBE_PREFIX ;;
  *) IFAKE_PROBE_ACTUAL=$IFAKE_ERROR ;;
esac
t; assert_eq "install: unusable-link diagnostic identifies the concrete attempted probe path" \
  "$IFAKE_PROBE_PREFIX" "$IFAKE_PROBE_ACTUAL"

IFAKE_BIN_CONTENTS=$(ls -A "$IFAKE_BIN" 2>&1)
t; assert_eq "install: rejected probe is removed and no command is created" '' "$IFAKE_BIN_CONTENTS"

IFAKE_TARGET="$IFAKE_PARENT/Copy Trap's Knotlog"
if [ -e "$IFAKE_TARGET" ] || [ -L "$IFAKE_TARGET" ]; then
  IFAKE_VAULT_STATE=$(ls -ld "$IFAKE_TARGET" 2>&1)
else
  IFAKE_VAULT_STATE=absent
fi
t; assert_eq "install: rejected copied command leaves the vault unmutated" \
  'absent' "$IFAKE_VAULT_STATE"

if [ -x "$IFAKE_TOOLS/ln" ]; then
  IFAKE_TOOL_STATE=executable
else
  IFAKE_TOOL_STATE=$(ls -ld "$IFAKE_TOOLS/ln" 2>&1)
fi
t; assert_eq "install: rejected copied command preserves the fake ln tool" \
  'executable' "$IFAKE_TOOL_STATE"

# Non-interactive omitted parent preserves the legacy PWD default.
IDEFAULT="$TMP/install-default-parent"
IDEFAULT_BIN="$TMP/install-default-bin"
mkdir -p "$IDEFAULT" "$IDEFAULT_BIN"
t; (cd "$IDEFAULT" && PATH="$IDEFAULT_BIN:$INSTALL_TOOLS" QUIPU_LANG=en \
  sh "$ROOT/knotlog" install --no-prompt --user Default) \
  >"$TMP/install-default.out" 2>"$TMP/install-default.err"; IRC=$?
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  IDEFAULT_EXPECT=0
  IDEFAULT_STATE=$([ -f "$IDEFAULT/Default's Knotlog/.knotlog/config" ] && printf yes || printf no)
else
  IDEFAULT_EXPECT=2
  IDEFAULT_STATE=$(grep -q 'could not create a usable symbolic link' "$TMP/install-default.err" \
    && [ ! -e "$IDEFAULT/Default's Knotlog" ] && printf yes || printf no)
fi
assert_install_rc "install: omitted parent returns the platform symlink result" "$IDEFAULT_EXPECT" "$IRC" "$TMP/install-default.err"
t; assert_eq "install: omitted parent preserves the supported or unsupported contract" 'yes' "$IDEFAULT_STATE"

# With positional PATH supplied, the guided flow skips the location question.
# install itself gathers the user and both optional answers before init.
IASK_PARENT="$TMP/install-ask-parent"
IASK_BIN="$TMP/install-ask-bin"
mkdir -p "$IASK_PARENT" "$IASK_BIN"
# The language question is the FIRST interaction; the leading 'en' line
# answers it, then the user prompt consumes the next line.
t; printf 'en\nPrompted User\n\n\n' | PATH="$IASK_BIN:$INSTALL_TOOLS" QUIPU_LANG=en \
  QUIPU_FORCE_TTY=1 sh "$ROOT/knotlog" install "$IASK_PARENT" \
  >"$TMP/install-ask.out" 2>"$TMP/install-ask.err"; IRC=$?
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  IASK_EXPECT=0
  IASK_STATE=$([ -f "$IASK_PARENT/Prompted User's Knotlog/.knotlog/config" ] \
    && grep -q '^user=Prompted User$' "$IASK_PARENT/Prompted User's Knotlog/.knotlog/config" \
    && printf yes || printf no)
else
  IASK_EXPECT=2
  IASK_STATE=$(grep -q 'could not create a usable symbolic link' "$TMP/install-ask.err" \
    && [ ! -e "$IASK_PARENT/Prompted User's Knotlog" ] && printf yes || printf no)
fi
assert_install_rc "install: interactive user reaches the platform symlink result" "$IASK_EXPECT" "$IRC" "$TMP/install-ask.err"
t; assert_eq "install: prompted user is installed or rejected before mutation" 'yes' "$IASK_STATE"

# QUIPU_FORCE_TTY opens the prompts over this pipe, but it is not a real stdout
# terminal: pages must remain linear and contain no ANSI control bytes.
IASK_OUT=$(cat "$TMP/install-ask.out")
case "$IASK_OUT" in
  *'[1/5]'*'[2/5]'*'[3/5]'*'[4/5]'*'[5/5]'*) IASK_PAGES=yes ;;
  *) IASK_PAGES=no ;;
esac
t; assert_eq "install: forced-tty transcript keeps the four page headers in order" \
  'yes' "$IASK_PAGES"
IASK_ESC=$(awk 'BEGIN { printf "%c", 27 }')
t; assert_eq "install: forced-tty pipe transcript contains no ANSI escape bytes" \
  'no' "$(grep -q "$IASK_ESC" "$TMP/install-ask.out" && printf yes || printf no)"

# CI has no portable pseudo-TTY across its three shells, so source-check the
# real-stdout gate and codepoint-built clear sequence while the transcript
# assertion above covers the observable forced-TTY fallback.
IPAGE_SOURCE=$(sed -n '/^_q_install_page()/,/^}/p' "$ROOT/knotlog")
t; assert_eq "install: page clear is stdout-gated and built from codepoints" 'yes' \
  "$(printf '%s\n' "$IPAGE_SOURCE" | grep -Fq '[ -t 1 ]' \
     && printf '%s\n' "$IPAGE_SOURCE" | grep -Fq 'awk ' \
     && printf '%s\n' "$IPAGE_SOURCE" | grep -Fq '27, 27' \
     && printf '%s\n' "$IPAGE_SOURCE" | grep -Fq '[2J' && printf yes || printf no)"

# --no-prompt without a user cannot derive a target and changes nothing.
INOP_PARENT="$TMP/install-noprompt-parent"
INOP_BIN="$TMP/install-noprompt-bin"
mkdir -p "$INOP_PARENT" "$INOP_BIN"
t; PATH="$INOP_BIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
  "$INOP_PARENT" --no-prompt >"$TMP/install-noprompt.out" \
  2>"$TMP/install-noprompt.err"; IRC=$?
assert_install_rc "install: --no-prompt without --user exits 2" '2' "$IRC" "$TMP/install-noprompt.err"
t; assert_eq "install: missing-user preflight creates neither vault nor symlink" 'yes' \
  "$([ -z "$(find "$INOP_PARENT" -mindepth 1 -print)" ] \
     && [ ! -e "$INOP_BIN/knotlog" ] && printf yes || printf no)"

# An existing empty target is accepted.
IEMPTY_PARENT="$TMP/install-empty-parent"
IEMPTY_BIN="$TMP/install-empty-bin"
IEMPTY_TARGET="$IEMPTY_PARENT/Empty User's Knotlog"
mkdir -p "$IEMPTY_TARGET" "$IEMPTY_BIN"
t; PATH="$IEMPTY_BIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
  --no-prompt --user "Empty User" "$IEMPTY_PARENT" \
  >"$TMP/install-empty.out" 2>"$TMP/install-empty.err"; IRC=$?
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  IEMPTY_EXPECT=0
  IEMPTY_STATE=$([ -f "$IEMPTY_TARGET/.knotlog/config" ] \
    && [ -L "$IEMPTY_BIN/knotlog" ] && [ -x "$IEMPTY_BIN/knotlog" ] \
    && printf yes || printf no)
else
  IEMPTY_EXPECT=2
  IEMPTY_STATE=$(grep -q 'could not create a usable symbolic link' "$TMP/install-empty.err" \
    && [ -z "$(find "$IEMPTY_TARGET" -mindepth 1 -print)" ] \
    && [ -z "$(find "$IEMPTY_BIN" -mindepth 1 -print)" ] \
    && printf yes || printf no)
fi
assert_install_rc "install: existing empty target returns the platform symlink result" "$IEMPTY_EXPECT" "$IRC" "$TMP/install-empty.err"
t; assert_eq "install: existing empty target is initialized or preserved empty" 'yes' "$IEMPTY_STATE"

# An existing valid Quipu vault is accepted and user text is preserved while a
# missing command link is installed.
IVALID_PARENT="$TMP/install-valid-parent"
IVALID_BIN="$TMP/install-valid-bin"
IVALID_TARGET="$IVALID_PARENT/Valid User's Knotlog"
mkdir -p "$IVALID_PARENT" "$IVALID_BIN"
QUIPU_VAULT="$IVALID_TARGET" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain \
  --no-prompt --user "Valid User" >/dev/null 2>&1
printf 'valid vault marker\n' >> "$IVALID_TARGET/AGENTS.md"
t; PATH="$IVALID_BIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
  "$IVALID_PARENT" --plain --no-prompt --user "Valid User" \
  >"$TMP/install-valid.out" 2>"$TMP/install-valid.err"; IRC=$?
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  IVALID_EXPECT=0
  IVALID_STATE=$(grep -q '^valid vault marker$' "$IVALID_TARGET/AGENTS.md" \
    && [ -L "$IVALID_BIN/knotlog" ] && [ -x "$IVALID_BIN/knotlog" ] \
    && printf yes || printf no)
else
  IVALID_EXPECT=2
  IVALID_STATE=$(grep -q 'could not create a usable symbolic link' "$TMP/install-valid.err" \
    && grep -q '^valid vault marker$' "$IVALID_TARGET/AGENTS.md" \
    && [ -z "$(find "$IVALID_BIN" -mindepth 1 -print)" ] \
    && printf yes || printf no)
fi
assert_install_rc "install: existing Quipu vault returns the platform symlink result" "$IVALID_EXPECT" "$IRC" "$TMP/install-valid.err"
t; assert_eq "install: existing Quipu vault stays non-destructive across symlink capability" 'yes' "$IVALID_STATE"

# A non-empty non-vault target is rejected before the command link is made.
IOCC_PARENT="$TMP/install-occupied-parent"
IOCC_BIN="$TMP/install-occupied-bin"
IOCC_TARGET="$IOCC_PARENT/Occupied User's Knotlog"
mkdir -p "$IOCC_TARGET" "$IOCC_BIN"
printf 'keep\n' > "$IOCC_TARGET/existing.txt"
t; PATH="$IOCC_BIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
  "$IOCC_PARENT" --no-prompt --user "Occupied User" \
  >"$TMP/install-occupied.out" 2>"$TMP/install-occupied.err"; IRC=$?
assert_install_rc "install: non-empty non-vault target exits 2" '2' "$IRC" "$TMP/install-occupied.err"
t; assert_eq "install: target collision preserves contents and creates no link" 'yes' \
  "$([ "$(cat "$IOCC_TARGET/existing.txt")" = keep ] \
     && [ ! -e "$IOCC_BIN/knotlog" ] && printf yes || printf no)"

# An occupied command is never overwritten, the later PATH directories are
# not used as a fallback, and no vault is created. Where true symlinks are
# supported the fixture is a wrong-source link; otherwise it is a regular
# command collision, while the unsupported-link path is covered above.
ILINK_PARENT="$TMP/install-link-parent"
ILINK_BIN="$TMP/install-link-bin"
mkdir -p "$ILINK_PARENT" "$ILINK_BIN"
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  make_true_symlink "$ROOT/i18n/en.txt" "$ILINK_BIN/knotlog" || exit 1
  ILINK_WAS_LINK=1
else
  printf 'occupied command\n' > "$ILINK_BIN/knotlog"
  ILINK_WAS_LINK=0
fi
ILINK_BEFORE=$(sed -n '1p' "$ILINK_BIN/knotlog")
t; PATH="$ILINK_BIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
  "$ILINK_PARENT" --no-prompt --user "Link User" \
  >"$TMP/install-link.out" 2>"$TMP/install-link.err"; IRC=$?
assert_install_rc "install: occupied command exits 2" '2' "$IRC" "$TMP/install-link.err"
if [ "$ILINK_WAS_LINK" -eq 1 ]; then
  ILINK_UNCHANGED=$([ -L "$ILINK_BIN/knotlog" ] \
    && [ "$(sed -n '1p' "$ILINK_BIN/knotlog")" = "$ILINK_BEFORE" ] \
    && printf yes || printf no)
else
  ILINK_UNCHANGED=$([ ! -L "$ILINK_BIN/knotlog" ] \
    && [ "$(sed -n '1p' "$ILINK_BIN/knotlog")" = "$ILINK_BEFORE" ] \
    && printf yes || printf no)
fi
t; assert_eq "install: occupied command is unchanged and preflight creates no vault" 'yes' \
  "$([ "$ILINK_UNCHANGED" = yes ] \
     && [ ! -e "$ILINK_PARENT/Link User's Knotlog" ] && printf yes || printf no)"
# ---- install language selection, localized layouts, omp hook + icon ----

# --lang tr without a tty: no prompt, tr layout forwarded to init.
ILANG_TR_PARENT="$TMP/install-lang-tr-parent"
ILANG_TR_BIN="$TMP/install-lang-tr-bin"
mkdir -p "$ILANG_TR_PARENT" "$ILANG_TR_BIN"
t; PATH="$ILANG_TR_BIN:$INSTALL_TOOLS" QUIPU_LANG=en \
  sh "$ROOT/knotlog" install "$ILANG_TR_PARENT" --no-prompt --lang tr \
  --user "Ada O'Neil" \
  >"$TMP/install-lang-tr.out" 2>"$TMP/install-lang-tr.err"; IRC=$?
ILANG_TR_TARGET="$ILANG_TR_PARENT/Ada O'Neil's Knotlog"
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  assert_install_rc "install: --lang tr non-interactive exits 0" '0' "$IRC" "$TMP/install-lang-tr.err"
  t; assert_eq "install: --lang tr records lang=tr and layout=tr" 'yes' \
    "$(grep -q '^lang=tr$' "$ILANG_TR_TARGET/.knotlog/config" \
       && grep -q '^layout=tr$' "$ILANG_TR_TARGET/.knotlog/config" \
       && printf yes || printf no)"
  t; TRINBOX=$(awk -F"$TAB" '$1=="inbox"{print $2}' "$ROOT/layout/tr.txt")
  assert_eq "install: --lang tr creates the Turkish inbox folder" 'yes' \
    "$([ -d "$ILANG_TR_TARGET/$TRINBOX" ] && printf yes || printf no)"
  t; assert_eq "install: omp hook copied and byte-identical to the repo source" 'yes' \
    "$(cmp -s "$ROOT/adapters/omp/hooks/pre/knotlog.ts" \
            "$ILANG_TR_TARGET/.omp/hooks/pre/knotlog.ts" && printf yes || printf no)"
  t; assert_eq "install: folder icon copied and byte-identical to the repo source" 'yes' \
    "$(cmp -s "$ROOT/icon/Knotlog.png" "$ILANG_TR_TARGET/.icon/knotlog.png" && printf yes || printf no)"
  t; ILANG_CANON=$(CDPATH='' cd -- "$ILANG_TR_PARENT" && pwd -P)
  assert_eq "install: .directory Icon line names the absolute icon path" 'yes' \
    "$(awk -v want="Icon=$ILANG_CANON/Ada O'Neil's Knotlog/.icon/knotlog.png" \
        'index($0, want) == 1 { found = 1 } END { exit !found }' \
        "$ILANG_TR_TARGET/.directory" && printf yes || printf no)"
  t; assert_eq "install: Turkish next guidance is static, clear, and unescaped" 'yes' \
    "$(grep -qxF 'Sıradaki: yukarıdaki kasa klasörünü aç ve çalıştır: knotlog doctor' \
         "$TMP/install-lang-tr.out" \
       && ! grep -qF "'\\''" "$TMP/install-lang-tr.out" \
       && printf yes || printf no)"

  # Idempotent reinstall: hook/icon stay byte-stable and unchurned, the
  # existing layout=tr config never conflicts with the en default.
  t; IHOOK_M=$(mtime "$ILANG_TR_TARGET/.omp/hooks/pre/knotlog.ts")
  t; IICON_M=$(mtime "$ILANG_TR_TARGET/.icon/knotlog.png")
  t; PATH="$ILANG_TR_BIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
    "$ILANG_TR_PARENT" --no-prompt --user "Ada O'Neil" \
    >"$TMP/install-lang-tr2.out" 2>"$TMP/install-lang-tr2.err"; IRC=$?
  assert_install_rc "install: idempotent reinstall over a tr vault exits 0" '0' "$IRC" "$TMP/install-lang-tr2.err"
  t; assert_eq "install: reinstall leaves hook and icon untouched" 'yes' \
    "$([ "$(mtime "$ILANG_TR_TARGET/.omp/hooks/pre/knotlog.ts")" = "$IHOOK_M" ] \
       && [ "$(mtime "$ILANG_TR_TARGET/.icon/knotlog.png")" = "$IICON_M" ] \
       && [ "$(find "$ILANG_TR_TARGET/.omp" -name knotlog.ts | wc -l | tr -d ' ')" = 1 ] \
       && grep -q '^layout=tr$' "$ILANG_TR_TARGET/.knotlog/config" \
       && printf yes || printf no)"
else
  assert_install_rc "install: --lang tr non-interactive exits 2 clearly" '2' "$IRC" "$TMP/install-lang-tr.err"
fi

# --lang en: en layout, lang=en recorded.
ILEN_PARENT="$TMP/install-lang-en-parent"
ILEN_BIN="$TMP/install-lang-en-bin"
mkdir -p "$ILEN_PARENT" "$ILEN_BIN"
t; PATH="$ILEN_BIN:$INSTALL_TOOLS" QUIPU_LANG=tr \
  sh "$ROOT/knotlog" install "$ILEN_PARENT" --no-prompt --lang en --user "En User" \
  >"$TMP/install-lang-en.out" 2>"$TMP/install-lang-en.err"; IRC=$?
ILEN_TARGET="$ILEN_PARENT/En User's Knotlog"
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  assert_install_rc "install: --lang en non-interactive exits 0" '0' "$IRC" "$TMP/install-lang-en.err"
  t; IENINBOX=$(awk -F"$TAB" '$1=="inbox"{print $2}' "$ROOT/layout/en.txt")
  assert_eq "install: --lang en records lang=en, layout=en, English folders" 'yes' \
    "$(grep -q '^lang=en$' "$ILEN_TARGET/.knotlog/config" \
       && grep -q '^layout=en$' "$ILEN_TARGET/.knotlog/config" \
       && [ -d "$ILEN_TARGET/$IENINBOX" ] && printf yes || printf no)"
else
  assert_install_rc "install: --lang en non-interactive exits 2 clearly" '2' "$IRC" "$TMP/install-lang-en.err"
fi

# No --lang and no tty: the question gate stays shut, en layout is the default,
# and no lang= line is invented.
IDEFT_PARENT="$TMP/install-lang-default-parent"
IDEFT_BIN="$TMP/install-lang-default-bin"
mkdir -p "$IDEFT_PARENT" "$IDEFT_BIN"
t; PATH="$IDEFT_BIN:$INSTALL_TOOLS" \
  sh "$ROOT/knotlog" install "$IDEFT_PARENT" --no-prompt --user "Def User" \
  >"$TMP/install-lang-default.out" 2>"$TMP/install-lang-default.err"; IRC=$?
IDEFT_TARGET="$IDEFT_PARENT/Def User's Knotlog"
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  assert_install_rc "install: non-interactive default exits 0" '0' "$IRC" "$TMP/install-lang-default.err"
  t; IDEFINBOX=$(awk -F"$TAB" '$1=="inbox"{print $2}' "$ROOT/layout/en.txt")
  assert_eq "install: default non-interactive gets layout=en, no lang= line" 'yes' \
    "$(grep -q '^layout=en$' "$IDEFT_TARGET/.knotlog/config" \
       && ! grep -q '^lang=' "$IDEFT_TARGET/.knotlog/config" \
       && [ -d "$IDEFT_TARGET/$IDEFINBOX" ] && printf yes || printf no)"
else
  assert_install_rc "install: non-interactive default exits 2 clearly" '2' "$IRC" "$TMP/install-lang-default.err"
fi

# Interactive: the bilingual language question is asked BEFORE the user prompt;
# answering tr yields a Turkish vault.
IASK_TR_PARENT="$TMP/install-ask-tr-parent"
IASK_TR_BIN="$TMP/install-ask-tr-bin"
mkdir -p "$IASK_TR_PARENT" "$IASK_TR_BIN"
t; printf 'tr\nAda\n\n\n' | PATH="$IASK_TR_BIN:$INSTALL_TOOLS" \
  QUIPU_FORCE_TTY=1 sh "$ROOT/knotlog" install "$IASK_TR_PARENT" \
  >"$TMP/install-ask-tr.out" 2>"$TMP/install-ask-tr.err"; IRC=$?
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  assert_install_rc "install: interactive tr answer exits 0" '0' "$IRC" "$TMP/install-ask-tr.err"
  t; IASK_TR_TRASH=$(awk -F"$TAB" '$1=="dump"{print $2}' "$ROOT/layout/tr.txt")
  assert_eq "install: interactive tr forwards the tr layout" 'yes' \
    "$(grep -q '^layout=tr$' "$IASK_TR_PARENT/Ada's Knotlog/.knotlog/config" \
       && grep -q '^user=Ada$' "$IASK_TR_PARENT/Ada's Knotlog/.knotlog/config" \
       && [ -d "$IASK_TR_PARENT/Ada's Knotlog/$IASK_TR_TRASH" ] \
       && printf yes || printf no)"
else
  assert_install_rc "install: interactive tr answer exits 2 clearly" '2' "$IRC" "$TMP/install-ask-tr.err"
fi

# The prompt folds case and the locale underscore like --lang does.
IASK_PT_PARENT="$TMP/install-ask-pt-parent"
IASK_PT_BIN="$TMP/install-ask-pt-bin"
mkdir -p "$IASK_PT_PARENT" "$IASK_PT_BIN"
t; printf 'PT_BR\nAda\n\n\n' | PATH="$IASK_PT_BIN:$INSTALL_TOOLS" \
  QUIPU_FORCE_TTY=1 sh "$ROOT/knotlog" install "$IASK_PT_PARENT" \
  >"$TMP/install-ask-pt.out" 2>"$TMP/install-ask-pt.err"; IRC=$?
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  assert_install_rc "install: interactive PT_BR answer exits 0" '0' "$IRC" "$TMP/install-ask-pt.err"
  t; assert_eq "install: interactive PT_BR answer stores lang=pt-br" 'yes' \
    "$(grep -rq '^lang=pt-br$' "$IASK_PT_PARENT"/*/.knotlog/config && printf yes || printf no)"
else
  assert_install_rc "install: interactive PT_BR answer exits 2 clearly" '2' "$IRC" "$TMP/install-ask-pt.err"
fi

# Garbage at the language prompt fails clearly before anything is created.
IBAD_PARENT="$TMP/install-ask-bad-parent"
IBAD_BIN="$TMP/install-ask-bad-bin"
mkdir -p "$IBAD_PARENT" "$IBAD_BIN"
t; printf 'de\nX Y\n\n\n' | PATH="$IBAD_BIN:$INSTALL_TOOLS" \
  QUIPU_FORCE_TTY=1 sh "$ROOT/knotlog" install "$IBAD_PARENT" \
  >"$TMP/install-ask-bad.out" 2>"$TMP/install-ask-bad.err"; IRC=$?
assert_install_rc "install: invalid language answer exits 2" '2' "$IRC" "$TMP/install-ask-bad.err"
t; assert_eq "install: invalid language answer creates neither vault nor command" 'yes' \
  "$([ -z "$(find "$IBAD_PARENT" -mindepth 1 -print)" ] \
     && [ ! -e "$IBAD_BIN/knotlog" ] && printf yes || printf no)"


# No writable PATH entry is actionable and leaves the target untouched. Invoke
# a pre-captured absolute shell with only empty/missing PATH entries; QUIPU_HOME
# avoids startup command lookup, and the diagnostic may fall back to its key
# when awk is deliberately unavailable.
INOWRITE_PARENT="$TMP/install-nowrite-parent"
INOWRITE_MISSING="$TMP/install-nowrite-missing"
mkdir -p "$INOWRITE_PARENT"
t; PATH=":$INOWRITE_MISSING" QUIPU_HOME="$ROOT" QUIPU_LANG=en \
  "$INSTALL_SHELL" "$ROOT/knotlog" install "$INOWRITE_PARENT" \
  --no-prompt --user "No Write" \
  >"$TMP/install-nowrite.out" 2>"$TMP/install-nowrite.err"; IRC=$?
assert_install_rc "install: no writable PATH directory exits 2" '2' "$IRC" "$TMP/install-nowrite.err"
t; assert_eq "install: no-writable-PATH preflight creates no vault or link" 'yes' \
  "$([ ! -e "$INOWRITE_PARENT/No Write's Knotlog" ] \
     && [ ! -e "$INOWRITE_MISSING" ] && printf yes || printf no)"

# Unsafe path-component users are rejected, including empty/dot/dotdot/slash,
# while legitimate spaces and apostrophes were proven by the success case.
IUNSAFE_PARENT="$TMP/install-unsafe-parent"
IUNSAFE_BIN="$TMP/install-unsafe-bin"
mkdir -p "$IUNSAFE_PARENT" "$IUNSAFE_BIN"
for IUNSAFE in '' . .. 'A/B'; do
  t; PATH="$IUNSAFE_BIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
    "$IUNSAFE_PARENT" --no-prompt --user "$IUNSAFE" \
    >"$TMP/install-unsafe.out" 2>"$TMP/install-unsafe.err"; IRC=$?
  assert_install_rc "install: unsafe user [$IUNSAFE] exits 2" '2' "$IRC" "$TMP/install-unsafe.err"
done
t; assert_eq "install: unsafe-user preflights create no vault or symlink" 'yes' \
  "$([ -z "$(find "$IUNSAFE_PARENT" -mindepth 1 -print)" ] \
     && [ ! -e "$IUNSAFE_BIN/knotlog" ] && printf yes || printf no)"

# Unknown flags and a second positional argument are diagnosed before either
# destination changes.
IARG_PARENT="$TMP/install-arg-parent"
IARG_BIN="$TMP/install-arg-bin"
mkdir -p "$IARG_PARENT" "$IARG_BIN"
t; PATH="$IARG_BIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
  "$IARG_PARENT" --no-prompt --user Arg --bogus \
  >"$TMP/install-arg-flag.out" 2>"$TMP/install-arg-flag.err"; IRC=$?
assert_install_rc "install: unknown flag exits 2" '2' "$IRC" "$TMP/install-arg-flag.err"
t; PATH="$IARG_BIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
  "$IARG_PARENT" "$TMP/extra-parent" --no-prompt --user Arg \
  >"$TMP/install-arg-extra.out" 2>"$TMP/install-arg-extra.err"; IRC=$?
assert_install_rc "install: extra positional path exits 2" '2' "$IRC" "$TMP/install-arg-extra.err"
t; assert_eq "install: argument preflight errors create neither destination" 'yes' \
  "$([ ! -e "$IARG_PARENT/Arg's Knotlog" ] && [ ! -e "$IARG_BIN/knotlog" ] \
     && printf yes || printf no)"

# Direct init keeps its historical progress/success transcript; only the
# narrowly scoped internal call made by install is quiet.
IDIRECT="$TMP/install-direct-init"
mkdir -p "$IDIRECT"
t; QUIPU_VAULT="$IDIRECT" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain \
  --no-prompt --user Direct >"$TMP/install-direct-init.out" \
  2>"$TMP/install-direct-init.err"; IRC=$?
assert_install_rc "install: direct init still exits 0" '0' "$IRC" "$TMP/install-direct-init.err"
t; assert_eq "install: direct init progress output is unchanged" 'yes' \
  "$(grep -q '^knotlog vault initialized:' "$TMP/install-direct-init.out" \
     && grep -q '^layout: plain$' "$TMP/install-direct-init.out" \
     && grep -q '^AGENTS.md bridge block ensured$' "$TMP/install-direct-init.out" \
     && grep -q '^next: knotlog index$' "$TMP/install-direct-init.out" \
     && printf yes || printf no)"

# A missing Claude adapter is a preflight failure: no vault or command may be
# created before the required source has been proved readable.
ICMISS_HOME="$TMP/install-claude-source-missing"
ICMISS_PARENT="$TMP/install-claude-source-parent"
ICMISS_BIN="$TMP/install-claude-source-bin"
mkdir -p "$ICMISS_HOME" "$ICMISS_PARENT" "$ICMISS_BIN"
t; PATH="$ICMISS_BIN:$INSTALL_TOOLS" QUIPU_HOME="$ICMISS_HOME" QUIPU_LANG=en \
  sh "$ROOT/knotlog" install "$ICMISS_PARENT" --no-prompt --user "Missing Claude" \
  >"$TMP/install-claude-source.out" 2>"$TMP/install-claude-source.err"; IRC=$?
assert_install_rc "install: missing Claude adapter exits 2 before mutation" '2' "$IRC" "$TMP/install-claude-source.err"
t; assert_eq "install: missing Claude adapter leaves vault and command absent" 'yes' \
  "$([ ! -e "$ICMISS_PARENT/Missing Claude's Knotlog" ] \
     && [ ! -e "$ICMISS_BIN/knotlog" ] && printf yes || printf no)"

if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  # Full guided answer order: language, location, user, companion. The
  # purpose question is gone from the interactive flow, so the trailing
  # "Kalici hafiza" line (after the three Style Enters) is fed deliberately and must remain unconsumed --
  # nothing may write purpose= without an explicit --purpose flag.
  # Blank location must choose this test-scoped HOME, never the checkout PWD.
  IGUIDED_HOME="$TMP/install-guided-home"
  IGUIDED_BIN="$TMP/install-guided-bin"
  mkdir -p "$IGUIDED_HOME" "$IGUIDED_BIN"
  t; printf 'tr\n\nAda\nSumi\n\n\n\nKalici hafiza\n' | \
    HOME="$IGUIDED_HOME" PATH="$IGUIDED_BIN:$INSTALL_TOOLS" QUIPU_FORCE_TTY=1 \
    sh "$ROOT/knotlog" install >"$TMP/install-guided.out" \
    2>"$TMP/install-guided.err"; IRC=$?
  assert_install_rc "install: complete guided flow exits 0" '0' "$IRC" "$TMP/install-guided.err"
  IGUIDED_TARGET="$IGUIDED_HOME/Ada's Knotlog"
  t; assert_eq "install: guided blank location defaults to test HOME" 'yes' \
    "$([ -f "$IGUIDED_TARGET/.knotlog/config" ] && printf yes || printf no)"
  t; assert_eq "install: guided answers record language and identity, never purpose" 'yes' \
    "$(grep -q '^lang=tr$' "$IGUIDED_TARGET/.knotlog/config" \
       && grep -q '^layout=tr$' "$IGUIDED_TARGET/.knotlog/config" \
       && grep -q '^user=Ada$' "$IGUIDED_TARGET/.knotlog/config" \
       && grep -q '^companion=Sumi$' "$IGUIDED_TARGET/.knotlog/config" \
       && ! grep -q '^purpose=' "$IGUIDED_TARGET/.knotlog/config" \
       && printf yes || printf no)"
  IGUIDED_OUT=$(cat "$TMP/install-guided.out")
  case "$IGUIDED_OUT" in
    *'[1/5]'*'[2/5]'*'[3/5]'*'[4/5]'*'[5/5]'*) IGUIDED_STEPS=yes ;;
    *) IGUIDED_STEPS=no ;;
  esac
  t; assert_eq "install: transcript orders language, location, identity, install" \
    'yes' "$IGUIDED_STEPS"
  case "$IGUIDED_OUT" in
    *'Language / Dil'*'Üst dizin'*'Adın:'*'Asistan adı:'*) IGUIDED_ANSWERS=yes ;;
    *) IGUIDED_ANSWERS=no ;;
  esac
  t; assert_eq "install: transcript consumes language/location/user/companion" \
    'yes' "$IGUIDED_ANSWERS"
  t; assert_eq "install: purpose question is never asked anymore" 'yes' \
    "$(! grep -qF 'ne için kullanılacak' "$TMP/install-guided.out" \
       && ! grep -qF 'Kalici hafiza' "$TMP/install-guided.out" && printf yes || printf no)"
  t; assert_eq "install: transcript omits optional intro and raw init progress" 'yes' \
    "$(! grep -Eq 'A few optional|Birkaç opsiyonel|knotlog vault initialized|knotlog vault kuruldu|knotlog kasası kuruldu|AGENTS.md bridge|AGENTS.md köprü|next: knotlog index|sıradaki: knotlog index' \
         "$TMP/install-guided.out" && printf yes || printf no)"
  t; assert_eq "install: guided vault has both Claude and omp hooks byte-identical" 'yes' \
    "$(cmp -s "$ROOT/adapters/claude-code.json" \
            "$IGUIDED_TARGET/.claude/settings.json" \
       && cmp -s "$ROOT/adapters/omp/hooks/pre/knotlog.ts" \
                "$IGUIDED_TARGET/.omp/hooks/pre/knotlog.ts" \
       && printf yes || printf no)"

  # Literal ~/ expansion supports spaces and apostrophes without evaluation.
  ITILDE_HOME="$TMP/install-tilde-home"
  ITILDE_PARENT="$ITILDE_HOME/Vault Parent O'Clock"
  ITILDE_BIN="$TMP/install-tilde-bin"
  mkdir -p "$ITILDE_PARENT" "$ITILDE_BIN"
  t; printf "en\n~/Vault Parent O'Clock\nTilde User\n\n\n" | \
    HOME="$ITILDE_HOME" PATH="$ITILDE_BIN:$INSTALL_TOOLS" QUIPU_FORCE_TTY=1 \
    sh "$ROOT/knotlog" install >"$TMP/install-tilde.out" \
    2>"$TMP/install-tilde.err"; IRC=$?
  assert_install_rc "install: guided ~/ path with spaces/apostrophe exits 0" '0' "$IRC" "$TMP/install-tilde.err"
  t; assert_eq "install: guided ~/ path expands under HOME exactly" 'yes' \
    "$([ -f "$ITILDE_PARENT/Tilde User's Knotlog/.knotlog/config" ] \
       && printf yes || printf no)"

  # Positional PATH skips only the question and still reports the selected
  # parent under step 2.
  IPOS_PARENT="$TMP/install-positional-parent"
  IPOS_BIN="$TMP/install-positional-bin"
  mkdir -p "$IPOS_PARENT" "$IPOS_BIN"
  t; printf 'en\nPositional User\n\n\n' | \
    PATH="$IPOS_BIN:$INSTALL_TOOLS" QUIPU_FORCE_TTY=1 \
    sh "$ROOT/knotlog" install "$IPOS_PARENT" >"$TMP/install-positional.out" \
    2>"$TMP/install-positional.err"; IRC=$?
  assert_install_rc "install: guided positional PATH exits 0" '0' "$IRC" "$TMP/install-positional.err"
  # install prints the physically resolved parent (`pwd -P`); on macOS/Git Bash
  # $TMP itself resolves differently, so grep the physical form.
  IPOS_RESOLVED="$(CDPATH='' cd -- "$IPOS_PARENT" && pwd -P)"
  t; assert_eq "install: positional PATH skips location question but shows selection" 'yes' \
    "$(! grep -q 'Parent path \[' "$TMP/install-positional.out" \
       && grep -qF "Parent: $IPOS_RESOLVED" "$TMP/install-positional.out" \
       && printf yes || printf no)"
  # Relative interactive location is anchored to the original PWD.
  IREL_ORIGIN="$TMP/install-relative-origin"
  IREL_PARENT="$IREL_ORIGIN/relative parent"
  IREL_BIN="$TMP/install-relative-bin"
  mkdir -p "$IREL_PARENT" "$IREL_BIN"
  t; (cd "$IREL_ORIGIN" && printf 'en\nrelative parent\nRelative User\n\n\n' | \
    PATH="$IREL_BIN:$INSTALL_TOOLS" QUIPU_FORCE_TTY=1 \
    sh "$ROOT/knotlog" install) >"$TMP/install-relative.out" \
    2>"$TMP/install-relative.err"; IRC=$?
  assert_install_rc "install: guided relative location exits 0" '0' "$IRC" "$TMP/install-relative.err"
  t; assert_eq "install: relative location resolves from original PWD" 'yes' \
    "$([ -f "$IREL_PARENT/Relative User's Knotlog/.knotlog/config" ] \
       && printf yes || printf no)"

  # Empty HOME falls back to original PWD for a blank interactive location.
  IHOMELESS_ORIGIN="$TMP/install-homeless-origin"
  IHOMELESS_BIN="$TMP/install-homeless-bin"
  mkdir -p "$IHOMELESS_ORIGIN" "$IHOMELESS_BIN"
  t; (cd "$IHOMELESS_ORIGIN" && printf 'en\n\nNo Home\n\n\n' | \
    HOME='' PATH="$IHOMELESS_BIN:$INSTALL_TOOLS" QUIPU_FORCE_TTY=1 \
    sh "$ROOT/knotlog" install) >"$TMP/install-homeless.out" \
    2>"$TMP/install-homeless.err"; IRC=$?
  assert_install_rc "install: guided empty HOME fallback exits 0" '0' "$IRC" "$TMP/install-homeless.err"
  t; assert_eq "install: blank location with empty HOME uses original PWD" 'yes' \
    "$([ -f "$IHOMELESS_ORIGIN/No Home's Knotlog/.knotlog/config" ] \
       && printf yes || printf no)"

  # A matching command link and a brand-new vault have independent statuses.
  ISEPARATE_PARENT="$TMP/install-separate-status-parent"
  mkdir -p "$ISEPARATE_PARENT"
  t; PATH="$IBIN:$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" install \
    "$ISEPARATE_PARENT" --no-prompt --user "Link Ready" \
    >"$TMP/install-separate-status.out" 2>"$TMP/install-separate-status.err"; IRC=$?
  assert_install_rc "install: new vault with existing matching command exits 0" '0' "$IRC" "$TMP/install-separate-status.err"
  t; assert_eq "install: summary separates created vault from available command" 'yes' \
    "$(grep -q '^  ✔ Vault: created at ' "$TMP/install-separate-status.out" \
       && grep -q '^  ✔ Command: already on PATH at ' "$TMP/install-separate-status.out" \
       && ! grep -q 'Quipu already installed' "$TMP/install-separate-status.out" \
       && printf yes || printf no)"
  t; assert_eq "install: English next guidance is static, clear, and unescaped" 'yes' \
    "$(grep -qxF 'Next: open the vault folder above and run: knotlog doctor' \
         "$TMP/install-separate-status.out" \
       && ! grep -qF "'\\''" "$TMP/install-separate-status.out" \
       && printf yes || printf no)"
fi

# ---- approved 2.1.7 commands: no-link, scopes, digest, import, repair ----

# `--no-link` must avoid all PATH probing while still creating the vault and
# integrations. Use a deliberately missing first PATH entry and verify that no
# command artifact is created in the writable test bin.
# ---- T-436/T-437: the git default respects vaults that already exist ----
# Finding (2026-09-03, measured right after the default landed): reinstalling
# over an EXISTING non-repository vault silently converted it -- .git,
# core.hooksPath and a commit appeared in a vault the user already had, and
# may have deliberately kept outside git. "install makes the vault a git
# repository by default" has to mean the vault install creates. Explicit
# --git still converts; that is the user asking.
REGIT_HOME="$TMP/regit-home"
REGIT_PARENT="$TMP/regit-parent"
mkdir -p "$REGIT_HOME" "$REGIT_PARENT"
REGIT_TARGET="$REGIT_PARENT/Regit's Knotlog"
regit_install() {
  PATH="$INSTALL_TOOLS" QUIPU_HOME="$ROOT" HOME="$REGIT_HOME" \
    GIT_CONFIG_GLOBAL="$REGIT_HOME/.gitconfig" GIT_CONFIG_SYSTEM=/dev/null \
    GIT_AUTHOR_NAME="Regit" GIT_AUTHOR_EMAIL="regit@example.com" \
    GIT_COMMITTER_NAME="Regit" GIT_COMMITTER_EMAIL="regit@example.com" \
    sh "$ROOT/knotlog" install --no-link "$REGIT_PARENT" --no-prompt \
    --user "Regit" --lang en "$@" >/dev/null 2>&1
}
regit_install --no-git
t; assert_eq "T-436: --no-git leaves the first install outside git" 'no' \
  "$([ -e "$REGIT_TARGET/.git" ] && printf yes || printf no)"
regit_install
t; assert_eq "T-436: a default reinstall does not convert an existing vault" 'no' \
  "$([ -e "$REGIT_TARGET/.git" ] && printf yes || printf no)"
regit_install --git
t; assert_eq "T-436: an explicit --git converts it" 'yes' \
  "$([ -e "$REGIT_TARGET/.git" ] && printf yes || printf no)"

# T-437: uninstall reports what Quipu left in the vault. Under-reporting is
# the one failure this section exists to prevent, and the git default added
# two new leftovers.
REGIT_UNINST=$(cd "$REGIT_TARGET" && PATH="$INSTALL_TOOLS" QUIPU_HOME="$ROOT" \
  QUIPU_VAULT="$REGIT_TARGET" HOME="$REGIT_HOME" QUIPU_LANG=en \
  sh "$ROOT/knotlog" uninstall --dry-run 2>&1)
t; assert_eq "T-437: uninstall names .githooks and .gitignore as leftovers" 'yes' \
  "$(printf '%s\n' "$REGIT_UNINST" | grep -q '\.githooks' \
     && printf '%s\n' "$REGIT_UNINST" | grep -q '\.gitignore' \
     && printf yes || printf no)"

# ---- T-435: doctor's path scan ignores shell snippets ----
# Finding (2026-09-03): D2/D7 counted every backticked thing containing a
# slash as a vault path. On this project's own vault 33 of 43 "missing paths"
# were commands, git branch names and repo slugs; a virgin vault reproduces it
# with three lines. The filter tests shell SHAPE, never spaces: vault folder
# names legitimately contain them ("Command Center/Dashboard.md"), so a space
# test would blind the check to the very paths it exists to catch -- and a
# drift detector that silently misses a broken path is worse than one that
# over-reports. That asymmetry is why the remaining noise (paths belonging to
# another repository, two-segment branch names) is deliberately left in.
PSCAN_HOME="$TMP/pathscan-home"
PSCAN_VAULT="$TMP/pathscan-vault"
mkdir -p "$PSCAN_HOME" "$PSCAN_VAULT"
( cd "$PSCAN_VAULT" && QUIPU_VAULT="$PSCAN_VAULT" HOME="$PSCAN_HOME" QUIPU_LANG=en \
  sh "$ROOT/knotlog" init >/dev/null 2>&1 )
# One real broken path plus four shapes that are not paths at all.
# T-435: backticks below are markdown delimiters inside a fixture, not
# command substitution.
# shellcheck disable=SC2016
{
  printf -- '- Install: `curl -fsSL https://example.test/i.sh | sh`\n'
  printf -- '- Branch: `feat/some-branch`\n'
  printf -- '- Redirect: `2>/dev/null`\n'
  printf -- '- Prompt: `Language / Dil (en/tr):`\n'
  printf -- '- Really missing: `Knowledge/nope.md`\n'
} >> "$PSCAN_VAULT/Rules.md"
PSCAN_OUT=$(QUIPU_VAULT="$PSCAN_VAULT" QUIPU_HOME="$ROOT" HOME="$PSCAN_HOME" QUIPU_LANG=en \
  sh "$ROOT/knotlog" doctor 2>&1 | awk '/paths/ && /not found/ { print; exit }')
# Two candidates survive: the genuinely missing note, and the branch name --
# which this test asserts ON PURPOSE. Filtering `feat/some-branch` would need
# a "two segments, no extension" rule that also matches real vault paths like
# `Knowledge/nope`, so it stays reported. The count is the contract: the four
# shell shapes above are gone, these two remain.
t; assert_eq "T-435: shell snippets are filtered, real and ambiguous paths are not" '2' \
  "$(printf '%s\n' "$PSCAN_OUT" | awk '{ for (i = 1; i <= NF; i++) if ($i + 0 == $i) { print $i; exit } }')"

# ---- T-535..T-537: the remaining path-scan noise (plan D2/D7, 2026-09-25) ----
# Measured on a real vault: 14 "missing" paths, of which 8 were bare
# folder names (`lib/`, `i18n/`) that exist elsewhere in the vault and 2 were
# a vault file invoked as a command (`./knotlog context`). Each fix keeps a
# control case that must still be reported, so the scan cannot go blind.
PSCAN2_HOME="$TMP/pathscan2-home"
PSCAN2_VAULT="$TMP/pathscan2-vault"
mkdir -p "$PSCAN2_HOME" "$PSCAN2_VAULT"
( cd "$PSCAN2_VAULT" && QUIPU_VAULT="$PSCAN2_VAULT" HOME="$PSCAN2_HOME" QUIPU_LANG=en \
  sh "$ROOT/knotlog" init >/dev/null 2>&1 )
printf 'echo hi\n' > "$PSCAN2_VAULT/run-me"
mkdir -p "$PSCAN2_VAULT/Tools/lib"
# T-535..T-537: backticks below are markdown code spans in a fixture, not
# command substitution.
# shellcheck disable=SC2016
{
  printf -- '- Command: `./run-me build`\n'
  printf -- '- Folder elsewhere: `lib/`\n'
  printf -- '- Folder nowhere: `gone/`\n'
  printf -- '- Really missing: `Knowledge/nope.md`\n'
} >> "$PSCAN2_VAULT/Rules.md"
PSCAN2_ALL=$(QUIPU_VAULT="$PSCAN2_VAULT" QUIPU_HOME="$ROOT" HOME="$PSCAN2_HOME" QUIPU_LANG=en \
  sh "$ROOT/knotlog" doctor 2>&1)
PSCAN2_OUT=$(printf '%s\n' "$PSCAN2_ALL" | awk '/paths/ && /not found/ { print; exit }')
# T-535: `./run-me build` is a vault file plus an argument -- a command. The
# head before the first space must exist as a regular file for this to apply;
# a folder name with a space in it ("Command Center/x.md") has no such head.
# T-536: a single-segment folder name resolves if a folder of that name exists
# anywhere in the vault; `gone/` exists nowhere and must still be reported.
# Survivors: `gone/` and `Knowledge/nope.md`.
t; assert_eq "T-535/T-536: commands and elsewhere-folders are filtered, controls are not" '2' \
  "$(printf '%s\n' "$PSCAN2_OUT" | awk '{ for (i = 1; i <= NF; i++) if ($i + 0 == $i) { print $i; exit } }')"
# T-537: every missing path is listed on its own row under the count row, so
# the user sees WHAT is missing, not only how many. The listing rows carry an
# empty status column and do not add to the warning total.
t; assert_eq "T-537: each missing path is listed on its own row" 'yes' \
  "$(printf '%s\n' "$PSCAN2_ALL" | awk -F"$TAB" '$1 == "" && $3 == "gone/" { a = 1 } $1 == "" && $3 == "Knowledge/nope.md" { b = 1 } END { exit !(a && b) }' \
    && printf yes || printf no)"
t; assert_eq "T-537: only the count row carries a status (listing rows are not warnings)" '1' \
  "$(printf '%s\n' "$PSCAN2_ALL" | awk -F"$TAB" '$2 == "paths" && $1 != "" && $3 ~ /not found/ { c++ } END { print c + 0 }')"
t; assert_eq "T-537: filtered candidates are not listed" 'no' \
  "$(printf '%s\n' "$PSCAN2_ALL" | awk -F"$TAB" '$3 == "lib/" || $3 == "./run-me build" { f = 1 } END { exit !f }' \
    && printf yes || printf no)"

# ---- T-434: the link scanner ignores code ----
# Finding (2026-09-03, reproduced on a virgin vault): a TOML table-array
# written inside backticks was indexed as a wikilink and reported by doctor as
# a broken target. Documentation about a syntax is not a link to it. Fenced
# blocks have the same problem. The unpaired-backtick case is deliberate: a
# stray backtick must not swallow the rest of the line, or real links would
# vanish silently -- the worse failure of the two.
LNK_DIR="$TMP/linkscan"
mkdir -p "$LNK_DIR"
# T-434: the backticks below are markdown code-span delimiters written into a
# fixture file, not command substitution.
# shellcheck disable=SC2016
{
  printf '# Scan\n\n'
  printf 'Inline code: `[[table.array.form]]` is syntax, not a link.\n\n'
  printf 'A real one: [[Rules]]\n\n'
  printf '```\n'
  printf '[[fenced-not-a-link]]\n'
  printf '```\n\n'
  printf 'After a stray backtick ` there is [[still-a-link]]\n'
} > "$LNK_DIR/scan.md"
# T-434: single-quoted $2 below is an awk field reference, not a shell variable.
# shellcheck disable=SC2016
LNK_OUT=$(QUIPU_HOME="$ROOT" awk -v mode=links -f "$ROOT/lib/index.awk" "$LNK_DIR/scan.md" \
  | awk -F'\t' '{ print $2 }' | sort | tr '\n' ' ')
t; assert_eq "T-434: code spans and fences are not scanned for wikilinks" \
  'Rules still-a-link ' "$LNK_OUT"

# ---- T-433: message helpers must not scribble on shared scratch names ----
# Finding (2026-09-03): POSIX sh has no locals, and both _q_lang and _q_msg
# used `_q_v` -- the vault path variable nearly every command holds -- as
# their own scratch. Any message call could therefore rewrite its caller's
# vault path, and one did: init's baseline commit tried to `cd` into a
# translated sentence. Static check, because the failure is silent at runtime
# and only shows up as a nonsense path in whichever command happens to read
# `_q_v` after a message.
t; assert_eq "T-433: _q_lang and _q_msg do not assign to the shared _q_v" 'no' \
  "$(awk '
      /^_q_lang\(\)/ || /^_q_msg\(\)/ { f = 1 }
      f && /^}/ { f = 0 }
      f && /^[ \t]*_q_v=/ { hit = 1 }
      END { print (hit ? "yes" : "no") }
    ' "$ROOT/knotlog")"

# ---- T-429..T-432: the baseline commit ----
# Finding (2026-09-03): making git the default left the vault as a repository
# with ZERO commits, so a brand-new user's first `doctor` already warned about
# uncommitted memory (24 untracked entries) and the history that justifies the
# default was empty. init/install now make one baseline commit at their own
# end. Guards: unborn HEAD only (an existing history is the user's), git
# identity required (never forge authorship), never fatal.
#
# Two ordering facts this locks, both found by measurement:
#   * the commit must run after install writes .claude/.omp/.icon/repair-hooks
#     -- committing at init's end captured a half-built vault (5 entries left
#     untracked);
#   * `_q_msg` uses `_q_v` as its own scratch variable, so the vault path must
#     be carried in a name messages cannot clobber (the first attempt tried to
#     `cd` into a translated sentence).
BASE_HOME="$TMP/baseline-home"
BASE_PARENT="$TMP/baseline-parent"
mkdir -p "$BASE_HOME" "$BASE_PARENT"
t; PATH="$INSTALL_TOOLS" QUIPU_HOME="$ROOT" HOME="$BASE_HOME" \
  GIT_CONFIG_GLOBAL="$BASE_HOME/.gitconfig" GIT_CONFIG_SYSTEM=/dev/null \
  GIT_AUTHOR_NAME="Base" GIT_AUTHOR_EMAIL="base@example.com" \
  GIT_COMMITTER_NAME="Base" GIT_COMMITTER_EMAIL="base@example.com" \
  sh "$ROOT/knotlog" install --no-link "$BASE_PARENT" --no-prompt \
  --user "Base" --lang en >"$TMP/baseline.out" 2>&1; RC=$?
BASE_TARGET="$BASE_PARENT/Base's Knotlog"
assert_eq "T-429: install with a baseline commit exits 0" '0' "$RC"
t; assert_eq "T-429: install leaves exactly one commit and a clean tree" 'yes' \
  "$( [ "$(cd "$BASE_TARGET" && git rev-list --count HEAD 2>/dev/null)" = 1 ] \
     && [ -z "$(cd "$BASE_TARGET" && git status --porcelain 2>/dev/null)" ] \
     && printf yes || printf no)"

# T-430: the baseline must not swallow machine state -- activity.log and both
# derived indexes rewrite on every session, so tracking them would turn each
# `knotlog index` into a diff. A .gitignore is seeded for exactly that.
t; assert_eq "T-430: baseline seeds .gitignore and tracks no machine state" 'yes' \
  "$( [ -f "$BASE_TARGET/.gitignore" ] \
     && [ -z "$(cd "$BASE_TARGET" && git ls-files | grep -E '\.knotlog/(index|links|activity)')" ] \
     && printf yes || printf no)"

# T-430b: the integrations install writes AFTER init must be inside the commit.
t; assert_eq "T-430: the baseline commit covers install's integrations" 'yes' \
  "$(cd "$BASE_TARGET" && git ls-files \
     | grep -q '^.claude/settings.json$' \
     && (cd "$BASE_TARGET" && git ls-files | grep -q '^repair-hooks$') \
     && printf yes || printf no)"

# T-431: a vault that already has history is the user's; never commit into it.
BASE_EXIST="$TMP/baseline-existing"
mkdir -p "$BASE_EXIST"
( cd "$BASE_EXIST" && git init -q . \
  && printf 'x\n' > theirs.txt && git add -A \
  && GIT_AUTHOR_NAME=U GIT_AUTHOR_EMAIL=u@example.com \
     GIT_COMMITTER_NAME=U GIT_COMMITTER_EMAIL=u@example.com \
     git commit -q -m "their own commit" ) >/dev/null 2>&1
t; PATH="$INSTALL_TOOLS" QUIPU_HOME="$ROOT" QUIPU_VAULT="$BASE_EXIST" \
  HOME="$BASE_HOME" GIT_CONFIG_GLOBAL="$BASE_HOME/.gitconfig" \
  GIT_AUTHOR_NAME="Base" GIT_AUTHOR_EMAIL="base@example.com" \
  GIT_COMMITTER_NAME="Base" GIT_COMMITTER_EMAIL="base@example.com" \
  sh "$ROOT/knotlog" init --git --lang en >/dev/null 2>&1
assert_eq "T-431: init leaves an existing history at one commit" '1' \
  "$(cd "$BASE_EXIST" && git rev-list --count HEAD 2>/dev/null)"

# T-432: the baseline is convenience on top of a finished install, so it must
# never be able to fail one. Asserting "exits 0 and the vault exists" is
# deliberately what this locks -- asserting "no commit was made" would depend
# on no identity leaking in from the runner's environment, which is exactly
# the kind of ambient dependency that made T-299 flaky before.
NOID_HOME="$TMP/baseline-noid-home"
NOID_PARENT="$TMP/baseline-noid-parent"
mkdir -p "$NOID_HOME" "$NOID_PARENT"
t; PATH="$INSTALL_TOOLS" QUIPU_HOME="$ROOT" HOME="$NOID_HOME" \
  GIT_CONFIG_GLOBAL="$NOID_HOME/.gitconfig" GIT_CONFIG_SYSTEM=/dev/null \
  GIT_AUTHOR_NAME='' GIT_AUTHOR_EMAIL='' GIT_COMMITTER_NAME='' GIT_COMMITTER_EMAIL='' \
  sh "$ROOT/knotlog" install --no-link "$NOID_PARENT" --no-prompt \
  --user "Noid" --lang en >"$TMP/baseline-noid.out" 2>&1; RC=$?
assert_eq "T-432: the baseline commit can never fail an install" '0' "$RC"
t; assert_eq "T-432: the vault is complete regardless of the baseline outcome" 'yes' \
  "$([ -f "$NOID_PARENT/Noid's Knotlog/.knotlog/config" ] && printf yes || printf no)"

# ---- T-426/T-427/T-428: install makes the vault a git repo by default ----
# Finding (2026-09-03, measured on a fresh install): `knotlog install` did NOT
# git-init the vault, so B1's secret gate -- v2.6.0's headline security
# feature -- never reached a new user. The whole design assumes the memory
# lives in a repository (D4's uncommitted-memory check, `capture --git`,
# `remember --git`, the pre-commit gate), and README sells that assumption,
# while install left the vault outside git. `--git` is now the default for
# install only; `init` keeps its opt-in flag so existing scripts do not shift
# under it. Verified by hand before landing: reverting the default turns
# T-426 red and leaves T-427 green.
GITDEF_PARENT="$TMP/git-default-parent"
mkdir -p "$GITDEF_PARENT"
t; PATH="$INSTALL_TOOLS" QUIPU_HOME="$ROOT" \
  sh "$ROOT/knotlog" install --no-link "$GITDEF_PARENT" --no-prompt \
  --user "Gitdef" --lang en >"$TMP/git-default.out" 2>&1; RC=$?
GITDEF_TARGET="$GITDEF_PARENT/Gitdef's Knotlog"
assert_eq "T-426: install exits 0 with the git default" '0' "$RC"
t; assert_eq "T-426: install makes the vault a git repo and installs the secret gate" 'yes' \
  "$( { [ -d "$GITDEF_TARGET/.git" ] || [ -f "$GITDEF_TARGET/.git" ]; } \
     && [ -f "$GITDEF_TARGET/.githooks/pre-commit" ] && printf yes || printf no)"

# T-427: `--no-git` is the deliberate way out and still produces a vault.
GITOFF_PARENT="$TMP/git-off-parent"
mkdir -p "$GITOFF_PARENT"
t; PATH="$INSTALL_TOOLS" QUIPU_HOME="$ROOT" \
  sh "$ROOT/knotlog" install --no-link "$GITOFF_PARENT" --no-prompt --no-git \
  --user "Gitoff" --lang en >"$TMP/git-off.out" 2>&1; RC=$?
GITOFF_TARGET="$GITOFF_PARENT/Gitoff's Knotlog"
assert_eq "T-427: install --no-git exits 0" '0' "$RC"
t; assert_eq "T-427: install --no-git leaves the vault outside git, no gate" 'yes' \
  "$([ ! -e "$GITOFF_TARGET/.git" ] && [ ! -e "$GITOFF_TARGET/.githooks/pre-commit" ] \
     && [ -f "$GITOFF_TARGET/.knotlog/config" ] && printf yes || printf no)"

# T-428: the default must not hard-depend on git being installed. init's
# `git init` call is unguarded, so under `set -e` a machine without git would
# have its install killed by a feature it never asked for. Static check: the
# --git handoff sits behind a `command -v git` test.
t; assert_eq "T-428: install guards the git default behind a command -v git test" 'yes' \
  "$(awk '/_q_i_git.*-eq 1.*command -v git/ { f = 1 } END { print (f ? "yes" : "no") }' "$ROOT/knotlog")"

NOLINK_PARENT="$TMP/no-link-parent"
NOLINK_BIN="$TMP/no-link-bin"
mkdir -p "$NOLINK_PARENT" "$NOLINK_BIN"
t; PATH="$TMP/no-link-missing:$NOLINK_BIN:$INSTALL_TOOLS" QUIPU_HOME="$ROOT" \
  sh "$ROOT/knotlog" install --no-link "$NOLINK_PARENT" --no-prompt \
  --user "No Link" --lang en >"$TMP/no-link.out" 2>"$TMP/no-link.err"; RC=$?
assert_eq "install --no-link creates vault without PATH probing" '0' "$RC"
NOLINK_TARGET="$NOLINK_PARENT/No Link's Knotlog"
t; assert_eq "install --no-link creates hooks, icon metadata, and no command" 'yes' \
  "$([ -f "$NOLINK_TARGET/.knotlog/config" ] \
     && [ -f "$NOLINK_TARGET/.claude/settings.json" ] \
     && [ -f "$NOLINK_TARGET/.omp/hooks/pre/knotlog.ts" ] \
     && [ -f "$NOLINK_TARGET/repair-hooks" ] \
     && [ -f "$NOLINK_TARGET/repair-hooks.ps1" ] \
     && [ -f "$NOLINK_TARGET/.icon/Knotlog.ico" ] \
     && [ -f "$NOLINK_TARGET/desktop.ini" ] \
     && grep -q '^IconResource=.*Knotlog.ico,0$' "$NOLINK_TARGET/desktop.ini" \
     && [ ! -e "$NOLINK_BIN/knotlog" ] && printf yes || printf no)"
NOLINK_MOVED="$TMP/no-link-moved-vault"
mv "$NOLINK_TARGET" "$NOLINK_MOVED"
t; sh "$NOLINK_MOVED/repair-hooks" --quipu "$ROOT" \
  >"$TMP/repair-hooks.out" 2>"$TMP/repair-hooks.err"; RC=$?
assert_eq "vault-local repair-hooks repairs a moved vault" '0' "$RC"
t; assert_eq "vault-local repair-hooks rewrites all Quipu hooks idempotently" 'yes' \
  "$(grep -c 'QUIPU_HOOK=1 \"/' "$NOLINK_MOVED/.claude/settings.json" | awk '$1 == 4 {print "yes"}' \
     && before=$(cat "$NOLINK_MOVED/.claude/settings.json") \
     && sh "$NOLINK_MOVED/repair-hooks" --quipu "$ROOT" >/dev/null \
     && after=$(cat "$NOLINK_MOVED/.claude/settings.json") \
     && [ "$before" = "$after" ] && printf yes || printf no)"

# ---- regression: checkout directory literally named "quipu" ----
#
# repair-hooks used to special-case any --quipu path ending in "/quipu" as
# the *quipu script's* own path and strip that trailing segment to find the
# checkout root. When the checkout DIRECTORY itself is named "quipu" (the
# name a plain `git clone` produces), that string-pattern heuristic strips
# one directory too many, repair-hooks goes looking for lib/icon assets in
# the checkout's *parent*, and `knotlog install` dies with a misleading
# "metadata.awk unreadable" error even though the checkout is intact. Prove
# the fix by staging a full checkout under a directory literally named
# "quipu" and driving `install` through it end to end; this must fail (with
# the old string-pattern logic) if the fix is reverted.
DIRNAME_HOME="$TMP/checkout-parent/quipu"
mkdir -p "$DIRNAME_HOME"
for _dirname_asset in knotlog repair-hooks repair-hooks.ps1 adapters fold hooks i18n icon layout lib persona templates; do
  cp -r "$ROOT/$_dirname_asset" "$DIRNAME_HOME/$_dirname_asset"
done
chmod +x "$DIRNAME_HOME/knotlog" "$DIRNAME_HOME/repair-hooks"
DIRNAME_PARENT="$TMP/dirname-install-parent"
mkdir -p "$DIRNAME_PARENT"
t; QUIPU_HOME="$DIRNAME_HOME" PATH="$INSTALL_TOOLS" \
  sh "$DIRNAME_HOME/knotlog" install "$DIRNAME_PARENT" --no-prompt --no-link \
  --user "Dirname Quipu" --lang en \
  >"$TMP/dirname-install.out" 2>"$TMP/dirname-install.err"; RC=$?
assert_install_rc "install succeeds when the checkout directory is literally named quipu" \
  '0' "$RC" "$TMP/dirname-install.err"
DIRNAME_TARGET="$DIRNAME_PARENT/Dirname Quipu's Knotlog"
t; assert_eq "install from a quipu-named checkout still repairs icon/metadata assets" 'yes' \
  "$([ -f "$DIRNAME_TARGET/.icon/knotlog.png" ] \
     && [ -f "$DIRNAME_TARGET/.icon/Knotlog.ico" ] \
     && printf yes || printf no)"

# repair-hooks --quipu must accept both forms: the checkout directory itself
# (even when that directory is named "quipu") and the quipu script's own
# path inside it (dirname of a file argument).
t; sh "$DIRNAME_HOME/repair-hooks" --quipu "$DIRNAME_HOME" \
  >"$TMP/repair-hooks-dirname.out" 2>"$TMP/repair-hooks-dirname.err"; RC=$?
assert_install_rc "repair-hooks --quipu accepts a checkout directory named quipu" \
  '0' "$RC" "$TMP/repair-hooks-dirname.err"
t; sh "$DIRNAME_HOME/repair-hooks" --quipu "$DIRNAME_HOME/knotlog" \
  >"$TMP/repair-hooks-scriptpath.out" 2>"$TMP/repair-hooks-scriptpath.err"; RC=$?
assert_install_rc "repair-hooks --quipu accepts the knotlog script's own path" \
  '0' "$RC" "$TMP/repair-hooks-scriptpath.err"
t; sh "$DIRNAME_HOME/repair-hooks" --quipu "$TMP/checkout-parent/does-not-exist" \
  >"$TMP/repair-hooks-missing.out" 2>"$TMP/repair-hooks-missing.err"; RC=$?
assert_eq "repair-hooks --quipu rejects a nonexistent path" '2' "$RC"

# repair-hooks writes the checkout path into hook commands, so it refuses a
# path with a quote, a backslash or a control byte. The control-byte arm once
# matched a literal backslash-n instead of a newline, so a newline got through.
rh_bad_checkout() { # dir -> a checkout copy with just the assets repair-hooks reads
  mkdir -p "$1/lib" "$1/icon"
  cp "$ROOT/knotlog" "$1/knotlog"
  cp "$ROOT/lib/repair.awk" "$ROOT/lib/metadata.awk" "$1/lib/"
  cp "$ROOT/icon/Knotlog.png" "$ROOT/icon/Knotlog.ico" "$1/icon/"
}
case $(uname -s) in
MINGW*|MSYS*|CYGWIN*)
  # NTFS forbids control bytes in names and reads a backslash as a separator.
  t; skip "repair-hooks rejects a checkout path with a newline" "Windows file names cannot hold a newline"
  t; skip "repair-hooks rejects a checkout path with a backslash" "a backslash is a path separator on Windows" ;;
*)
  RH_NL="$TMP/rh-nl
checkout"
  rh_bad_checkout "$RH_NL"
  t; sh "$DIRNAME_HOME/repair-hooks" --quipu "$RH_NL" >/dev/null 2>"$TMP/repair-hooks-nl.err"; RC=$?
  assert_eq "repair-hooks rejects a checkout path with a newline" '2 yes' \
    "$RC $(grep -q 'unsupported quote or control bytes' "$TMP/repair-hooks-nl.err" && printf yes || printf no)"
  RH_BS="$TMP/rh-back\\slash"
  rh_bad_checkout "$RH_BS"
  t; sh "$DIRNAME_HOME/repair-hooks" --quipu "$RH_BS" >/dev/null 2>"$TMP/repair-hooks-bs.err"; RC=$?
  assert_eq "repair-hooks rejects a checkout path with a backslash" '2 yes' \
    "$RC $(grep -q 'unsupported quote or control bytes' "$TMP/repair-hooks-bs.err" && printf yes || printf no)" ;;
esac

# ---- regression: install surfaces the real repair-hooks failure ----
#
# `knotlog install` used to run repair-hooks with `>/dev/null 2>&1` and, on
# any failure, always blame a fixed "metadata.awk unreadable" message --
# discarding whatever repair-hooks actually said on stderr. Build a source
# tree that passes every install preflight check (so install proceeds to
# create the vault) but has no `quipu` script for repair-hooks to find --
# with --no-link, install's own $_q_HOME/knotlog executable check is skipped,
# so this failure is only caught inside repair-hooks itself. Assert the
# user sees repair-hooks' real reason, not a canned message. The folder-icon
# metadata step is cosmetic and non-fatal (see the next block), so this must
# now exit 0, not 2.
BADREPAIR_HOME="$TMP/checkout-no-quipu-script"
mkdir -p "$BADREPAIR_HOME"
for _badrepair_asset in repair-hooks repair-hooks.ps1 adapters fold hooks i18n icon layout lib persona templates; do
  cp -r "$ROOT/$_badrepair_asset" "$BADREPAIR_HOME/$_badrepair_asset"
done
chmod +x "$BADREPAIR_HOME/repair-hooks"
BADREPAIR_PARENT="$TMP/badrepair-parent"
BADREPAIR_BIN="$TMP/badrepair-bin"
mkdir -p "$BADREPAIR_PARENT" "$BADREPAIR_BIN"
t; QUIPU_HOME="$BADREPAIR_HOME" PATH="$BADREPAIR_BIN:$INSTALL_TOOLS" QUIPU_LANG=en \
  sh "$ROOT/knotlog" install --no-link "$BADREPAIR_PARENT" --no-prompt \
  --user "Bad Repair" --lang en \
  >"$TMP/badrepair.out" 2>"$TMP/badrepair.err"; IRC=$?
assert_install_rc "install: repair-hooks failure past preflight is a warning, not fatal (exits 0)" \
  '0' "$IRC" "$TMP/badrepair.err"
t; assert_eq "install: repair-hooks failure surfaces the real reason, not a fixed metadata.awk blame" 'yes' \
  "$(grep -q 'folder icon metadata could not be finished' "$TMP/badrepair.err" \
     && grep -q 'checkout does not contain knotlog' "$TMP/badrepair.err" \
     && ! grep -q 'install asset is missing or unreadable' "$TMP/badrepair.err" \
     && printf yes || printf no)"

# ---- regression: metadata failure at repair-hooks runtime does not cost
#      the user the vault or the `quipu` command ----
#
# `repair-hooks --metadata-only` used to run before the PATH symlink was
# created, and its failure was fatal (`_q_die`, exit 2) even though nothing
# functional depends on it — `doctor` never checks the folder-icon metadata
# and install had already finished every other step. Worse, a runtime-only
# break in lib/metadata.awk (readable, so it passes every preflight check,
# but broken once awk actually runs it) was completely untested: the only
# prior regression (above) hits a preflight failure *inside* repair-hooks
# itself, before metadata.awk ever executes. Build a checkout with an
# intact `quipu` script but a metadata.awk that fails only when awk runs
# it, and prove install still exits 0, still prints its summary, still
# warns on stderr with repair-hooks' real text, still leaves a fully
# functional vault, and — where this host supports true symlinks — still
# links the `quipu` command. Revert the fix and this whole block goes red.
METAFAIL_HOME="$TMP/checkout-broken-metadata-awk"
mkdir -p "$METAFAIL_HOME"
for _metafail_asset in knotlog repair-hooks repair-hooks.ps1 adapters fold hooks i18n icon layout lib persona templates; do
  cp -r "$ROOT/$_metafail_asset" "$METAFAIL_HOME/$_metafail_asset"
done
chmod +x "$METAFAIL_HOME/knotlog" "$METAFAIL_HOME/repair-hooks"
# Readable and syntactically fine, so every preflight [-r] check passes;
# it only blows up once awk actually interprets it.
printf '%s\n' 'BEGIN { print "quipu-test-metadata-awk-boom" > "/dev/stderr"; exit 7 }' \
  > "$METAFAIL_HOME/lib/metadata.awk"

METAFAIL_PARENT="$TMP/metafail-parent"
METAFAIL_BIN="$TMP/metafail-bin"
mkdir -p "$METAFAIL_PARENT" "$METAFAIL_BIN"
t; QUIPU_HOME="$METAFAIL_HOME" PATH="$METAFAIL_BIN:$INSTALL_TOOLS" QUIPU_LANG=en \
  sh "$METAFAIL_HOME/knotlog" install --no-link "$METAFAIL_PARENT" --no-prompt \
  --user "Meta Fail" --lang en \
  >"$TMP/metafail.out" 2>"$TMP/metafail.err"; MRC=$?
assert_install_rc "install: metadata.awk failing at runtime exits 0, not fatal" \
  '0' "$MRC" "$TMP/metafail.err"
t; assert_eq "install: runtime metadata failure warns with repair-hooks' real stderr" 'yes' \
  "$(grep -q 'folder icon metadata could not be finished' "$TMP/metafail.err" \
     && grep -q 'quipu-test-metadata-awk-boom' "$TMP/metafail.err" \
     && printf yes || printf no)"
t; assert_eq "install: runtime metadata failure still prints the full summary" 'yes' \
  "$(grep -q 'Next: open the vault folder above and run: knotlog doctor' "$TMP/metafail.out" \
     && printf yes || printf no)"
METAFAIL_TARGET="$METAFAIL_PARENT/Meta Fail's Knotlog"
t; assert_eq "install: runtime metadata failure leaves the vault fully functional" 'yes' \
  "$([ -f "$METAFAIL_TARGET/.knotlog/config" ] \
     && [ -f "$METAFAIL_TARGET/.claude/settings.json" ] \
     && [ -f "$METAFAIL_TARGET/.omp/hooks/pre/knotlog.ts" ] \
     && [ -f "$METAFAIL_TARGET/repair-hooks" ] \
     && [ -f "$METAFAIL_TARGET/.icon/knotlog.png" ] \
     && printf yes || printf no)"
t; assert_eq "install: runtime metadata failure summary admits the icon step did not finish" 'yes' \
  "$(grep -q 'Folder icon: files staged' "$TMP/metafail.out" \
     && ! grep -q 'Folder icon: ready at' "$TMP/metafail.out" \
     && printf yes || printf no)"

# The symlink step runs before the (now non-fatal) metadata step, so a
# broken metadata.awk must not stop the `quipu` command from being linked.
# Only provable where this host supports true symlinks (see TRUE_SYMLINKS
# above) — on hosts without that support, a non---no-link install dies at
# the earlier symlink-capability probe for unrelated reasons, before it
# ever reaches vault creation or the metadata step, so the two concerns
# can't be isolated here.
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  METAFAIL_LINK_PARENT="$TMP/metafail-link-parent"
  METAFAIL_LINK_BIN="$TMP/metafail-link-bin"
  mkdir -p "$METAFAIL_LINK_PARENT" "$METAFAIL_LINK_BIN"
  t; QUIPU_HOME="$METAFAIL_HOME" PATH="$METAFAIL_LINK_BIN:$INSTALL_TOOLS" QUIPU_LANG=en \
    sh "$METAFAIL_HOME/knotlog" install "$METAFAIL_LINK_PARENT" --no-prompt \
    --user "Meta Fail Link" --lang en \
    >"$TMP/metafail-link.out" 2>"$TMP/metafail-link.err"; MLRC=$?
  assert_install_rc "install: metadata.awk failing at runtime still links the command" \
    '0' "$MLRC" "$TMP/metafail-link.err"
  t; assert_eq "install: symlink is usable despite the metadata warning" 'yes' \
    "$([ -L "$METAFAIL_LINK_BIN/knotlog" ] && [ -f "$METAFAIL_LINK_BIN/knotlog" ] \
       && [ -x "$METAFAIL_LINK_BIN/knotlog" ] && printf yes || printf no)"
fi

t; assert_eq "install.ps1 discovers Git and provides both Windows/Bash shims" 'yes' \
  "$(grep -qF "install' '--no-link'" "$ROOT/install.ps1" \
     && grep -qF "\$forward = @()" "$ROOT/install.ps1" \
     && grep -qF 'Read-Host $langPrompt' "$ROOT/install.ps1" \
     && grep -qF "Read-Host \$userPrompt" "$ROOT/install.ps1" \
     && grep -qF 'function Find-GitExecutable' "$ROOT/install.ps1" \
     && grep -qF 'GitForWindows' "$ROOT/install.ps1" \
     && grep -qF "\$posixShim = Join-Path \$bin 'knotlog'" "$ROOT/install.ps1" \
     && grep -qF 'chmod.exe' "$ROOT/install.ps1" \
     && grep -qF 'LOCALAPPDATA' "$ROOT/install.ps1" \
     && grep -qF "SetEnvironmentVariable('Path', \$newPath, 'User')" "$ROOT/install.ps1" \
     && printf yes || printf no)"

# Scopes are additive and idempotent; full expands all optional localized
# folders without removing a previously selected scope.
SCOPE_VAULT="$TMP/scope-vault"
t; QUIPU_VAULT="$SCOPE_VAULT" QUIPU_HOME="$ROOT" sh "$ROOT/knotlog" init \
  --no-prompt --user "Scope User" --lang tr --layout tr \
  --scope goals --scope goals \
  >"$TMP/scope-1.out" 2>"$TMP/scope-1.err"; RC=$?
assert_eq "init --scope goals is idempotent" '0' "$RC"
SCOPE_GOALS=$(awk -F"$TAB" '$1=="goals"{print $2}' "$ROOT/layout/scope-tr.txt")
t; assert_eq "init --scope goals creates localized folder and persists config" 'yes' \
  "$([ -d "$SCOPE_VAULT/$SCOPE_GOALS" ] \
     && grep -q '^scope=goals$' "$SCOPE_VAULT/.knotlog/config" \
     && printf yes || printf no)"
t; QUIPU_VAULT="$SCOPE_VAULT" QUIPU_HOME="$ROOT" sh "$ROOT/knotlog" init \
  --no-prompt --user "Scope User" --scope full \
  >"$TMP/scope-2.out" 2>"$TMP/scope-2.err"; RC=$?
assert_eq "init --scope full adds optional folders to existing scope" '0' "$RC"
SCOPE_OK=yes
for SCOPE_KEY in goals money body mind; do
  SCOPE_NAME=$(awk -F"$TAB" -v k="$SCOPE_KEY" '$1==k{print $2}' "$ROOT/layout/scope-tr.txt")
  if [ ! -d "$SCOPE_VAULT/$SCOPE_NAME" ]; then SCOPE_OK=no; fi
done
t; assert_eq "init scopes preserve goals and add money/body/mind" 'yes' "$SCOPE_OK"

# Digest is date-scoped, deterministic, and does not touch remember's
# watermark. Dry-run writes no note; normal mode writes the layout dump note.
DIGEST_VAULT="$TMP/digest-vault"
mkdir -p "$DIGEST_VAULT/.knotlog"
printf '%s\n' 'layout=plain' > "$DIGEST_VAULT/.knotlog/config"
printf '%s\n' \
  '2026-08-27T10:00 | PostToolUse | Edit | today-a.md' \
  '2026-08-27T10:01 | PostToolUse | Read | today-b.md' \
  '2026-08-26T10:00 | PostToolUse | Edit | yesterday.md' \
  > "$DIGEST_VAULT/.knotlog/activity.log"
t; QUIPU_VAULT="$DIGEST_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest \
  --date 2026-08-27 --dry-run --limit 1 >"$TMP/digest-dry.out" 2>"$TMP/digest-dry.err"; RC=$?
assert_eq "digest dry-run succeeds for selected date" '0' "$RC"
t; assert_eq "digest dry-run excludes other dates and watermark writes" 'yes' \
  "$(grep -q '2026-08-27T10:00' "$TMP/digest-dry.out" \
     && ! grep -q yesterday.md "$TMP/digest-dry.out" \
     && [ ! -e "$DIGEST_VAULT/.knotlog/remembered" ] \
     && [ ! -e "$DIGEST_VAULT/000-Inbox/Dump/2026-08-27-digest.md" ] \
     && printf yes || printf no)"
t; QUIPU_VAULT="$DIGEST_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest \
  --date 2026-08-27 --limit 1 >"$TMP/digest-write.out" 2>"$TMP/digest-write.err"; RC=$?
assert_eq "digest writes selected date note" '0' "$RC"
t; assert_eq "digest note is deterministic and date-scoped" 'yes' \
  "$([ -f "$DIGEST_VAULT/000-Inbox/Dump/2026-08-27-digest.md" ] \
     && grep -q 'Range: 2026-08-27T10:00' "$DIGEST_VAULT/000-Inbox/Dump/2026-08-27-digest.md" \
     && ! grep -q yesterday.md "$DIGEST_VAULT/000-Inbox/Dump/2026-08-27-digest.md" \
     && printf yes || printf no)"

EMPTY_DIGEST="$TMP/digest-empty"
mkdir -p "$EMPTY_DIGEST/.knotlog"
printf '%s\n' 'layout=plain' > "$EMPTY_DIGEST/.knotlog/config"
t; QUIPU_VAULT="$EMPTY_DIGEST" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest \
  --date 2026-08-27 >"$TMP/digest-empty.out" 2>"$TMP/digest-empty.err"; RC=$?
assert_eq "digest without activity log names the requested date" 'no activity events for 2026-08-27' \
  "$(cat "$TMP/digest-empty.out")"
assert_eq "digest without activity log exits successfully" '0' "$RC"

# Import supports the ChatGPT mapping/author shape as well as ordinary
# role/content messages and always writes locally under the sessions folder.
IMPORT_VAULT="$TMP/import-vault"
IMPORT_FILE="$TMP/conversation.json"
mkdir -p "$IMPORT_VAULT/.knotlog"
printf '%s\n' 'layout=plain' > "$IMPORT_VAULT/.knotlog/config"
printf '%s' '[{"mapping":{"u":{"message":{"author":{"role":"user"},"content":{"content_type":"text","parts":["Hello from user"]}}},"a":{"message":{"author":{"role":"assistant"},"content":{"parts":["Hello from assistant"]}}}}}]' > "$IMPORT_FILE"
t; QUIPU_VAULT="$IMPORT_VAULT" QUIPU_HOME="$ROOT" sh "$ROOT/knotlog" import \
  "$IMPORT_FILE" --date 2026-08-27 >"$TMP/import.out" 2>"$TMP/import.err"; RC=$?
assert_eq "import accepts local ChatGPT JSON export" '0' "$RC"
IMPORT_NOTE="$IMPORT_VAULT/700-Sessions/2026-08-27-import-conversation.json.md"
t; assert_eq "import writes both mapped messages into a local session note" 'yes' \
  "$([ -f "$IMPORT_NOTE" ] \
     && grep -q '^### user$' "$IMPORT_NOTE" \
     && grep -q 'Hello from user' "$IMPORT_NOTE" \
     && grep -q '^### assistant$' "$IMPORT_NOTE" \
     && grep -q 'Hello from assistant' "$IMPORT_NOTE" \
     && printf yes || printf no)"

# ---- user-facing polish: no dev jargon, seeded templates, richer Dashboard ----

# Regression gate: internal planning references (PLAN 4.x, FAZ N) must never
# leak into i18n message VALUES -- those strings land verbatim in the
# user's own AGENTS.md, doctor output, and companion.md. Key names are
# exempt (never renamed, tests elsewhere depend on them); only the text
# after "=" on each line is checked.
t; JARGON_EN=$(awk -F= '{ $1=""; print }' "$ROOT/i18n/en.txt" | grep -Ei 'PLAN [0-9]|FAZ [0-9]' || true)
assert_eq "i18n/en.txt values carry no PLAN/FAZ references" '' "$JARGON_EN"
t; JARGON_TR=$(awk -F= '{ $1=""; print }' "$ROOT/i18n/tr.txt" | grep -Ei 'plan [0-9]|FAZ [0-9]' || true)
assert_eq "i18n/tr.txt values carry no plan/FAZ references" '' "$JARGON_TR"

# persona/<lang>.md's first line is shipped verbatim as companion.md's first
# line (quipu writes the file's raw content through printf). It must be the
# note's own YAML frontmatter, not a developer comment about placeholder
# order.
t; assert_eq "persona/en.md starts with its own frontmatter, not a dev comment" '---' \
  "$(head -n1 "$ROOT/persona/en.md")"
t; assert_eq "persona/tr.md starts with its own frontmatter, not a dev comment" '---' \
  "$(head -n1 "$ROOT/persona/tr.md")"

# The persona seed writes the file's content as a printf FORMAT string
# (SC2059, by design -- it carries %s placeholders). Since the file now
# starts with "---", that leading '-' must never reach a real printf as an
# unguarded first argument, or some printf builtins misparse it as an
# option. This is an end-to-end check, not a grep: it exercises the actual
# init code path.
mkvault vperscomp
QUIPU_VAULT="$TMP/vperscomp" QUIPU_LANG=en sh "$ROOT/knotlog" init >"$TMP/vperscomp.out" 2>"$TMP/vperscomp.err"; RC=$?
t; assert_eq "init seeding companion.md from persona/en.md exits 0" '0' "$RC"
t; assert_eq "init seeding companion.md from persona/en.md prints nothing to stderr" '' \
  "$(cat "$TMP/vperscomp.err")"
t; COMPANION_EN=$(awk -F"$TAB" '$1=="companion"{print $2}' "$ROOT/layout/emoji.txt")
assert_eq "companion.md's first line is its own frontmatter delimiter" '---' \
  "$(head -n1 "$TMP/vperscomp/$COMPANION_EN/companion.md")"

# Templates: init copies three shipped skeletons (note/project/session) into
# the templates folder, only-if-missing, in the vault's content language.
mkvault vtplen
QUIPU_VAULT="$TMP/vtplen" QUIPU_LANG=en sh "$ROOT/knotlog" init >/dev/null 2>&1; RC=$?
t; assert_eq "init --lang en exits 0 (templates setup)" '0' "$RC"
TPLEN_DIR="$TMP/vtplen/$(awk -F"$TAB" '$1=="templates"{print $2}' "$ROOT/layout/emoji.txt")"
t; assert_eq "init seeds note/project/session templates under English layout" 'yes' \
  "$([ -f "$TPLEN_DIR/note.md" ] && [ -f "$TPLEN_DIR/project.md" ] && [ -f "$TPLEN_DIR/session.md" ] \
     && cmp -s "$TPLEN_DIR/note.md" "$ROOT/templates/en/note.md" \
     && cmp -s "$TPLEN_DIR/project.md" "$ROOT/templates/en/project.md" \
     && cmp -s "$TPLEN_DIR/session.md" "$ROOT/templates/en/session.md" \
     && printf yes || printf no)"
t; assert_eq "seeded note.md carries quipu's frontmatter fields" 'yes' \
  "$(awk '/^---$/{n++; next} n==1' "$TPLEN_DIR/note.md" \
       | grep -q '^title:' \
       && awk '/^---$/{n++; next} n==1' "$TPLEN_DIR/note.md" | grep -q '^created:' \
       && awk '/^---$/{n++; next} n==1' "$TPLEN_DIR/note.md" | grep -q '^modified:' \
       && awk '/^---$/{n++; next} n==1' "$TPLEN_DIR/note.md" | grep -q '^type:' \
       && awk '/^---$/{n++; next} n==1' "$TPLEN_DIR/note.md" | grep -q '^status:' \
       && awk '/^---$/{n++; next} n==1' "$TPLEN_DIR/note.md" | grep -q '^tags:' \
       && printf yes || printf no)"

# Turkish content language: same three templates, Turkish text, still under
# the emoji layout's Templates folder name (layout and content language are
# independent choices).
mkvault vtpltr
# No QUIPU_LANG override here: it outranks --lang in _q_lang()'s chain
# (env -> vault config -> LC_ALL/LANG -> en), so forcing it to en would
# defeat the point of this check.
QUIPU_VAULT="$TMP/vtpltr" sh "$ROOT/knotlog" init --lang tr >/dev/null 2>&1; RC=$?
t; assert_eq "init --lang tr exits 0 (templates setup)" '0' "$RC"
TPLTR_DIR="$TMP/vtpltr/$(awk -F"$TAB" '$1=="templates"{print $2}' "$ROOT/layout/emoji.txt")"
t; assert_eq "init --lang tr seeds Turkish template content" 'yes' \
  "$(cmp -s "$TPLTR_DIR/note.md" "$ROOT/templates/tr/note.md" \
     && cmp -s "$TPLTR_DIR/project.md" "$ROOT/templates/tr/project.md" \
     && cmp -s "$TPLTR_DIR/session.md" "$ROOT/templates/tr/session.md" \
     && printf yes || printf no)"

# Only-if-missing: a user's own edit to a seeded template survives a rerun.
printf '%s\n' 'user edit' >> "$TPLEN_DIR/note.md"
QUIPU_VAULT="$TMP/vtplen" QUIPU_LANG=en sh "$ROOT/knotlog" init >/dev/null 2>&1
t; assert_eq "rerunning init never overwrites a user-edited template" 'yes' \
  "$(tail -n1 "$TPLEN_DIR/note.md" | grep -qx 'user edit' && printf yes || printf no)"

# Dashboard: the seed now points somewhere (companion, templates, inbox,
# Threads.md) instead of being two inert lines, and every wikilink it plants
# actually resolves -- `knotlog index` + `knotlog doctor` must report zero
# broken/ambiguous links for a freshly seeded vault.
mkvault vdashen
QUIPU_VAULT="$TMP/vdashen" QUIPU_LANG=en sh "$ROOT/knotlog" init >/dev/null 2>&1
DASHEN_DIR="$TMP/vdashen/$(awk -F"$TAB" '$1=="command"{print $2}' "$ROOT/layout/emoji.txt")"
t; assert_eq "Dashboard.md links to the companion note" 'yes' \
  "$(grep -q '\[\[companion\]\]' "$DASHEN_DIR/Dashboard.md" && printf yes || printf no)"
t; assert_eq "Dashboard.md links to Threads.md" 'yes' \
  "$(grep -q '\[\[Threads.md\]\]' "$DASHEN_DIR/Dashboard.md" && printf yes || printf no)"
t; assert_eq "Dashboard.md stays within one screen (<= 20 lines)" 'yes' \
  "$([ "$(wc -l < "$DASHEN_DIR/Dashboard.md")" -le 20 ] && printf yes || printf no)"
QUIPU_VAULT="$TMP/vdashen" QUIPU_HOME="$ROOT" sh "$ROOT/knotlog" index >/dev/null 2>&1
DASHEN_DOC=$(QUIPU_VAULT="$TMP/vdashen" QUIPU_HOME="$ROOT" sh "$ROOT/knotlog" doctor 2>&1)
t; assert_eq "a freshly seeded vault has no broken or ambiguous wikilinks" 'yes' \
  "$(printf '%s\n' "$DASHEN_DOC" | grep -qi 'broken\|ambiguous' && printf no || printf yes)"

# Same guarantee in Turkish content, under the localized tr layout. No
# QUIPU_LANG override here either, for the same reason as vtpltr above.
mkvault vdashtr
QUIPU_VAULT="$TMP/vdashtr" sh "$ROOT/knotlog" init --layout tr --lang tr >/dev/null 2>&1
DASHTR_DIR="$TMP/vdashtr/$(awk -F"$TAB" '$1=="command"{print $2}' "$ROOT/layout/tr.txt")"
t; assert_eq "Turkish Dashboard.md links to the companion note" 'yes' \
  "$(grep -q '\[\[companion\]\]' "$DASHTR_DIR/Dashboard.md" && printf yes || printf no)"
t; assert_eq "Turkish Dashboard.md content is actually Turkish, not English" 'yes' \
  "$(grep -q '^## Buradan başla$' "$DASHTR_DIR/Dashboard.md" && printf yes || printf no)"
QUIPU_VAULT="$TMP/vdashtr" QUIPU_HOME="$ROOT" sh "$ROOT/knotlog" index >/dev/null 2>&1
DASHTR_DOC=$(QUIPU_VAULT="$TMP/vdashtr" QUIPU_HOME="$ROOT" sh "$ROOT/knotlog" doctor 2>&1)
t; assert_eq "a freshly seeded Turkish vault has no broken or ambiguous wikilinks" 'yes' \
  "$(printf '%s\n' "$DASHTR_DOC" | grep -qi 'bulunamadı\|birden çok' && printf no || printf yes)"

# T-299: README's "A first session, end to end:" block prints a literal
# `knotlog doctor` summary line. Finding 6 caught it drifted (README said
# "27 ok", a real run said "44 ok") with nothing pinning it to the actual
# command surface -- unlike docs/USAGE.md, this block was never locked by a
# test. Reproduce the block's exact steps (bare `init`, the same note.md
# content, `index`, then `doctor`) over a fresh vault and assert the
# `summary:` line README prints matches what `doctor` really emits, so a
# future drift turns this test red instead of sitting silently stale.
#
# BULGU 7 (2026-09-01): doctor's "agent surfaces" section probes
# $HOME/.codex/config.toml, $HOME/.claude/settings.json, etc. -- so the "ok"
# count this test computes depended on which agent CLIs happen to be
# installed on the developer's own machine, not on quipu itself. README's
# "44 ok" was measured on a machine with no such extras; a developer who
# later installs e.g. Codex gets 45 and this test goes red for a reason
# that has nothing to do with their change. Route HOME to an empty
# directory for this one doctor invocation (same isolation pattern as the
# HOME="$TMP/fakeh"/home293 doctor tests above) so the count reflects only
# what quipu itself puts there (the vault-local claude hooks check), never
# the ambient machine.
README_DOCTOR_LINE=$(grep -A1 '^\$ knotlog doctor; echo \$?$' "$ROOT/README.md" | tail -n1)
mkdir -p "$TMP/v299" "$TMP/home299"
(
  cd "$TMP/v299" || exit 1
  QUIPU_VAULT="$TMP/v299" HOME="$TMP/home299" QUIPU_LANG=en sh "$ROOT/knotlog" init >/dev/null 2>&1
  printf '# Work note\n\nAbout Istanbul.\n' > note.md
  QUIPU_VAULT="$TMP/v299" QUIPU_HOME="$ROOT" HOME="$TMP/home299" sh "$ROOT/knotlog" index >/dev/null 2>&1
)
# README's reader installed knotlog, so it is on PATH; without it doctor's
# PATH row warns (1.2.0 shadowing check) and the count drifts from README.
mkdir -p "$TMP/bin299" && ln -sf "$ROOT/knotlog" "$TMP/bin299/knotlog"
V299_DOCTOR=$(PATH="$TMP/bin299:$PATH" QUIPU_VAULT="$TMP/v299" QUIPU_HOME="$ROOT" HOME="$TMP/home299" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1)
V299_DOCTOR_LINE=$(printf '%s\n' "$V299_DOCTOR" | grep '^summary:')
t; assert_eq "T-299: README's doctor summary line matches a real knotlog doctor run" \
  "$README_DOCTOR_LINE" "$V299_DOCTOR_LINE"

# ---- T-424/T-425: the rest of README's "first session" block ----
# Finding (2026-09-03): T-299 locked only the `doctor` summary line, so the
# two blocks around it drifted silently when v2.6.0 landed. B1 appended a
# secret-gate line to `init`'s output and README's sample still stopped at
# "next: knotlog index"; B3/B5 seeded Rules.md and Facts.md, which are indexed
# like any other note, so `search work --paths` really returns four paths
# where README showed one. Same isolation as T-299 (empty HOME, fresh vault,
# QUIPU_LANG=en) and the same shape of assertion, extended to the two blocks
# a reader actually copies. Verified by hand before landing: reverting either
# README block turns exactly its own test red.
mkdir -p "$TMP/v424" "$TMP/home424"
V424_INIT=$(cd "$TMP/v424" && QUIPU_VAULT="$TMP/v424" HOME="$TMP/home424" QUIPU_LANG=en \
  sh "$ROOT/knotlog" init 2>&1)
(
  cd "$TMP/v424" || exit 1
  printf '# Work note\n\nAbout Istanbul.\n' > note.md
  QUIPU_VAULT="$TMP/v424" QUIPU_HOME="$ROOT" HOME="$TMP/home424" QUIPU_LANG=en \
    sh "$ROOT/knotlog" index >/dev/null 2>&1
)
V424_SEARCH=$(cd "$TMP/v424" && QUIPU_VAULT="$TMP/v424" QUIPU_HOME="$ROOT" \
  HOME="$TMP/home424" QUIPU_LANG=en sh "$ROOT/knotlog" search work --paths 2>&1)

# T-424: README's last `init` output line is the secret-gate line a real run
# prints. Compared as the final line only -- the vault path above it is
# machine-specific and cannot be pinned.
README_INIT_LAST=$(awk '/^next: knotlog index$/{getline; print; exit}' "$ROOT/README.md")
t; assert_eq "T-424: README's init block carries the real secret-gate line" \
  "$README_INIT_LAST" "$(printf '%s\n' "$V424_INIT" | tail -n1)"

# T-425: README's `search work --paths` sample matches a real run, seeded
# scaffolding included.
README_SEARCH=$(awk '/^\$ knotlog search work --paths$/{f=1;next} f&&/^\$/{exit} f' "$ROOT/README.md")
t; assert_eq "T-425: README's search sample matches a real knotlog search run" \
  "$README_SEARCH" "$V424_SEARCH"

# ---- T-300/T-301/T-302: install.ps1 POSIX shim line-ending self-heal ----
# Finding (2026-09-01): install.ps1's POSIX shim here-string carries this
# file's own on-disk line endings. .gitattributes had no *.ps1 rule, so
# core.autocrlf=true checked it out CRLF; the here-string then compared
# CRLF against a previously-installed LF shim byte-for-byte, failed, and
# called Fail() -- AFTER the vault had already been created. These are
# static/textual checks (no pwsh on Linux/macOS CI runners): they inspect
# install.ps1's and .gitattributes' source text rather than executing
# PowerShell. Blindly reverting the install.ps1 or .gitattributes fix turns
# all three red (verified by hand before landing).

# T-300: the POSIX shim text is normalized to LF (`-replace "`r`n", "`n"`)
# BEFORE it is ever compared against an existing on-disk shim or written --
# not after, and not only inside one branch of the if/else.
# T-300: single-quoted $ below is a literal match against install.ps1
# source text, not an unexpanded shell variable.
# shellcheck disable=SC2016
L300_NORM=$(grep -Fn '$posixShimText = $posixShimText -replace' "$ROOT/install.ps1" | head -1 | cut -d: -f1)
# T-300: single-quoted $ below is a literal match against install.ps1
# source text, not an unexpanded shell variable.
# shellcheck disable=SC2016
L300_CHECK=$(grep -Fn 'if (Test-Path -LiteralPath $posixShim -PathType Leaf) {' "$ROOT/install.ps1" | head -1 | cut -d: -f1)
t; assert_eq "T-300: install.ps1 defines a posixShimText LF-normalization line" 'yes' \
  "$([ -n "$L300_NORM" ] && printf yes || printf no)"
t; assert_eq "T-300: the normalization runs before the existing-shim comparison" 'yes' \
  "$([ -n "$L300_NORM" ] && [ -n "$L300_CHECK" ] && [ "$L300_NORM" -lt "$L300_CHECK" ] && printf yes || printf no)"

# T-301: the POSIX shim's comparison against an existing on-disk file is
# line-ending-insensitive (compares normalized/normalized, i.e. uses an
# $existingNormalized variable), so a pre-existing LF shim from an earlier,
# correctly-checked-out install does not trip the "foreign file" Fail()
# guard. The sibling quipu.cmd shim block is intentionally left untouched --
# it is a native Windows batch file and stays CRLF-sensitive -- so this test
# also pins that block has NOT grown the same normalization.
POSIX_SHIM_BLOCK=$(awk '/^\$posixShim = Join-Path \$bin/,/^\$posixPath = \$posixShim -replace/' "$ROOT/install.ps1")
CMD_SHIM_BLOCK=$(awk '/^\$shim = Join-Path \$bin/,/^# Git Bash does not apply/' "$ROOT/install.ps1")
t; assert_eq "T-301: the POSIX shim comparison uses a normalized existing-content variable" 'yes' \
  "$(printf '%s\n' "$POSIX_SHIM_BLOCK" | grep -Fq 'existingNormalized' && printf yes || printf no)"
t; assert_eq "T-301: the quipu.cmd shim comparison is untouched (no normalization)" 'yes' \
  "$(printf '%s\n' "$CMD_SHIM_BLOCK" | grep -Fq 'existingNormalized' && printf no || printf yes)"

# T-302: .gitattributes pins *.ps1 to a deterministic line ending, so
# install.ps1's own checkout (and thus its here-string's raw content) no
# longer depends on the installing machine's core.autocrlf setting.
t; assert_eq "T-302: .gitattributes pins *.ps1 to a deterministic eol" 'yes' \
  "$(grep -Fq '*.ps1 text eol=crlf' "$ROOT/.gitattributes" && printf yes || printf no)"

# ---- T-303/T-304/T-305: repair-hooks attrib gets a Windows path ----
# Finding (2026-09-01): repair-hooks called `attrib` (a native Windows exe)
# with the POSIX vault path it had just computed via `pwd -P`. MSYS/Git Bash
# auto-translates a *plain* POSIX path in argv for native exes, which
# happened to mask the bug for simple paths -- but the translation breaks on
# a path containing an apostrophe (e.g. "Ada's Knotlog", a real vault name
# produced by `<Name>'s Knotlog` layout), and `attrib` then no-ops silently:
# exit 0, "Parameter format not correct -" on stderr, no attribute set, and
# the folder icon never appears in Explorer since Explorer only honors
# desktop.ini on a folder carrying the System attribute. Measured by hand:
# running repair-hooks unpatched against a real "Ada's Knotlog"-style vault
# left it with no System attribute; the patched version left it `S` (and
# desktop.ini `SH`). These are static/textual checks (no Windows attrib.exe
# assumed on Linux/macOS CI runners): they inspect repair-hooks' source text
# rather than executing it. Blindly reverting the attrib block turns all
# three red (verified by hand before landing: reverting to
# `attrib +s "$_q_vault"` / `attrib +h +s "$_q_vault/desktop.ini"` with no
# cygpath conversion and no post-check removed the cygpath calls and the
# `case`/warning below, failing T-303 and T-305).
ATTRIB_BLOCK=$(awk '/^if command -v attrib/,/^fi$/' "$ROOT/repair-hooks")

# T-303: the folder attrib call is made against a cygpath-converted Windows
# path, not the raw POSIX $_q_vault -- so it isn't at the mercy of MSYS's
# argv auto-translation, which is known to break on paths with an
# apostrophe.
# T-303: single-quoted $ below is a literal match against repair-hooks
# source text, not an unexpanded shell variable.
t
# shellcheck disable=SC2016
assert_eq "T-303: repair-hooks converts the vault path with cygpath before calling attrib" 'yes' \
  "$(printf '%s\n' "$ATTRIB_BLOCK" | grep -Fq 'attrib +s "$_q_attrib_vault"' && printf '%s\n' "$ATTRIB_BLOCK" | grep -Fq '_q_attrib_vault=$(cygpath -w "$_q_vault")' && printf yes || printf no)"

# T-304: the desktop.ini attrib call gets the same cygpath conversion as the
# folder itself, not just the folder.
# T-304: single-quoted $ below is a literal match against repair-hooks
# source text, not an unexpanded shell variable.
t
# shellcheck disable=SC2016
assert_eq "T-304: repair-hooks converts the desktop.ini path with cygpath before calling attrib" 'yes' \
  "$(printf '%s\n' "$ATTRIB_BLOCK" | grep -Fq 'attrib +h +s "$_q_attrib_ini"' && printf '%s\n' "$ATTRIB_BLOCK" | grep -Fq '_q_attrib_ini=$(cygpath -w' && printf yes || printf no)"

# T-305: since `attrib` exits 0 even when it silently failed, repair-hooks
# re-queries the attribute and warns (without aborting -- the icon is
# cosmetic) when the System attribute did not actually land, instead of
# unconditionally claiming success.
# T-305: single-quoted $ below is a literal match against repair-hooks
# source text, not an unexpanded shell variable.
t
# shellcheck disable=SC2016
assert_eq "T-305: repair-hooks verifies the System attribute landed and warns (non-fatally) if not" 'yes' \
  "$(printf '%s\n' "$ATTRIB_BLOCK" | grep -Fq 'case $(attrib "$_q_attrib_vault"' && printf '%s\n' "$ATTRIB_BLOCK" | grep -Fq 'warning: could not set the folder icon attribute' && printf yes || printf no)"


# ---- uninstall (T-306..T-315) ------------------------------------------------
#
# uninstall's whole contract is about what it must NOT delete: the user's
# vault, and any `quipu` on PATH that isn't ours. Each case below builds a
# real PATH entry and a real vault, runs the command, and checks the
# filesystem afterwards rather than trusting the printed summary.

UN="$TMP/uninstall"
mkdir -p "$UN/bin" "$UN/home"

# A vault is needed for the "left in place" half of the report.
UN_VAULT="$UN/home/unuser's Knotlog"
QUIPU_VAULT="$UN_VAULT" sh "$ROOT/knotlog" init --no-prompt --lang en --user unuser \
  >/dev/null 2>&1 || true

un_link() { # a v2-style install: $UN/bin/quipu -> a pre-rename checkout's quipu
  rm -f "$UN/bin/quipu"
  mkdir -p "$UN/v2/lib" "$UN/v2/i18n"
  : > "$UN/v2/quipu"; : > "$UN/v2/lib/jsonfield.awk"; : > "$UN/v2/i18n/en.txt"
  MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -s "$UN/v2/quipu" "$UN/bin/quipu" 2>/dev/null
}
un_run() { # run uninstall with only $UN/bin on the front of a minimal PATH
  ( cd "$UN_VAULT" 2>/dev/null || cd "$UN" || exit 1
    PATH="$UN/bin:/usr/bin:/bin" QUIPU_LANG=en \
      sh "$ROOT/knotlog" uninstall "$@" 2>&1 )
}

if un_link && [ -L "$UN/bin/quipu" ]; then

  # T-306: --dry-run reports the link but leaves it on disk. A preview that
  # already deleted something is not a preview.
  UN_OUT=$(un_run --dry-run)
  t
  assert_eq "T-306: uninstall --dry-run names the link without removing it" 'yes' \
    "$(printf '%s\n' "$UN_OUT" | grep -q 'Would remove' && [ -L "$UN/bin/quipu" ] && printf yes || printf no)"

  # T-307: the real run removes the link it just previewed.
  UN_OUT=$(un_run)
  t
  assert_eq "T-307: uninstall removes the Knotlog link from PATH" 'yes' \
    "$([ ! -e "$UN/bin/quipu" ] && [ ! -L "$UN/bin/quipu" ] && printf yes || printf no)"

  # T-308: the vault survives. This is the guarantee the command is built
  # around -- notes are the user's data, uninstall only removes machinery.
  t
  assert_eq "T-308: uninstall leaves the vault on disk" 'yes' \
    "$([ -f "$UN_VAULT/.knotlog/config" ] && printf yes || printf no)"
  # T-309: and it says where the vault is, so the user is never left hunting
  # for the notes an uninstall did not delete.
  #
  # Compare against the path the SHELL reports after cd, not the $UN_VAULT
  # string: macOS sets TMPDIR with a trailing slash, so $TMP (and every path
  # built on it) carries a doubled slash that `cd` normalizes away. quipu
  # prints the normalized form, so matching the raw variable failed on macOS
  # only -- a flaw in this test, not in the command.
  UN_VAULT_SEEN=$( cd "$UN_VAULT" 2>/dev/null && pwd )
  t
  assert_eq "T-309: uninstall reports the vault it left in place" 'yes' \
    "$([ -n "$UN_VAULT_SEEN" ] && printf '%s\n' "$UN_OUT" | grep -Fq "$UN_VAULT_SEEN" && printf yes || printf no)"

  # T-310: a second run is a clean no-op, not an error.
  UN_OUT=$(un_run)
  UN_RC=$?
  t
  assert_eq "T-310: uninstall on an already-uninstalled machine is a no-op" 'yes' \
    "$([ "$UN_RC" -eq 0 ] && printf '%s\n' "$UN_OUT" | grep -q 'nothing to remove' && printf yes || printf no)"

  # T-311: a plain file named `quipu` on PATH is someone else's command (or
  # the checkout itself). It is reported, never deleted.
  printf '#!/bin/sh\necho not quipu\n' > "$UN/bin/quipu"
  chmod +x "$UN/bin/quipu"
  UN_OUT=$(un_run)
  t
  assert_eq "T-311: uninstall never deletes a plain file named quipu on PATH" 'yes' \
    "$([ -f "$UN/bin/quipu" ] && [ ! -L "$UN/bin/quipu" ] && printf '%s\n' "$UN_OUT" | grep -q 'not a Knotlog link' && printf yes || printf no)"
  rm -f "$UN/bin/quipu"

  # T-312: a SYMLINK named `quipu` that resolves outside a Quipu checkout is
  # also not ours. Matching on the name alone would delete a stranger's tool.
  mkdir -p "$UN/other"
  printf '#!/bin/sh\necho not quipu\n' > "$UN/other/quipu"
  chmod +x "$UN/other/quipu"
  if MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -s "$UN/other/quipu" "$UN/bin/quipu" 2>/dev/null; then
    UN_OUT=$(un_run)
    t
    assert_eq "T-312: uninstall never deletes a foreign symlink named quipu" 'yes' \
      "$([ -L "$UN/bin/quipu" ] && printf '%s\n' "$UN_OUT" | grep -q 'not a Knotlog link' && printf yes || printf no)"
  else
    t; skip "T-312: uninstall never deletes a foreign symlink named quipu" "no symlink support"
  fi
  rm -f "$UN/bin/quipu"

  # T-313: run from outside any vault, uninstall still works and says plainly
  # that it found no vault -- rather than silently implying it removed one.
  UN_OUT=$( cd "$TMP" && PATH="$UN/bin:/usr/bin:/bin" QUIPU_LANG=en QUIPU_VAULT='' \
    sh "$ROOT/knotlog" uninstall 2>&1 )
  t
  assert_eq "T-313: uninstall outside a vault reports no vault instead of guessing" 'yes' \
    "$(printf '%s\n' "$UN_OUT" | grep -q 'not found from here' && printf yes || printf no)"

else
  for UN_N in 306 307 308 309 310 311 312 313; do
    t; skip "T-$UN_N: uninstall behavior" "symlink creation unavailable"
  done
fi

# T-314: uninstall is listed in usage. A command nobody can discover is the
# same as a command that does not exist -- the gap this closes is precisely
# that a user could not find the way out.
t
assert_eq "T-314: usage lists the uninstall command" 'yes' \
  "$(QUIPU_LANG=en sh "$ROOT/knotlog" 2>&1 | grep -q '^  uninstall' && printf yes || printf no)"

# T-315: uninstall.ps1 exists and never removes the vault. The POSIX command
# cannot see the Windows shims, so the two halves must both be shipped.
t
assert_eq "T-315: uninstall.ps1 ships and contains no vault deletion" 'yes' \
  "$([ -f "$ROOT/uninstall.ps1" ] && ! grep -Eq 'Remove-Item[^\n]*vault' "$ROOT/uninstall.ps1" && printf yes || printf no)"

# T-316: a real Windows run showed install.ps1 asking for the user name
# before quipu's own wizard ever gets to ask language, breaking "language is
# the first interaction". install.ps1 must now ask language itself, first,
# and forward it -- so the language prompt line has to appear before the
# user-name prompt line in the file.
t
assert_eq "T-316: install.ps1 asks language before user name" 'yes' \
  "$(_LANG_LINE=$(grep -nF 'Read-Host $langPrompt' "$ROOT/install.ps1" | cut -d: -f1) \
     && _USER_LINE=$(grep -n "Read-Host \$userPrompt" "$ROOT/install.ps1" | cut -d: -f1) \
     && [ -n "$_LANG_LINE" ] && [ -n "$_USER_LINE" ] && [ "$_LANG_LINE" -lt "$_USER_LINE" ] \
     && printf yes || printf no)"

# T-317: the Turkish install wizard's companion-name question and the
# identity injected into a live session must say "asistan", not the English
# "companion" leaking into a Turkish sentence (found on a real Windows run).
t
assert_eq "T-317: tr.txt companion-facing strings say asistan, not companion" 'yes' \
  "$(! grep -Eq "Companion (adı|:)|companion'(ısın|ı)|Companion persona|companion personası|^persona_default_companion=Companion$" "$ROOT/i18n/tr.txt" \
     && grep -qF 'init_ask_companion=Asistan adı:' "$ROOT/i18n/tr.txt" \
     && printf yes || printf no)"

# T-318: the language question got an optional arrow-key menu, but
# QUIPU_FORCE_TTY (the test-only escape hatch that opens prompts over a
# pipe) must never open it -- raw mode reading from a pipe would just hang
# or misread bytes as keystrokes. Feed an invalid answer over that pipe and
# require the exact same validation error as the plain-text path always
# gave: if the menu were entered instead, this line would be consumed as
# keystrokes and no err_install_lang_invalid would ever fire.
IT318_PARENT="$TMP/install-t318-parent"
mkdir -p "$IT318_PARENT"
t; printf 'xx\n' | PATH="$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" install "$IT318_PARENT" \
  >"$TMP/install-t318.out" 2>"$TMP/install-t318.err"; IT318_RC=$?
assert_eq "T-318: QUIPU_FORCE_TTY still takes the plain-text language path" '2 yes' \
  "$IT318_RC $(grep -q 'invalid language: xx' "$TMP/install-t318.err" && printf yes || printf no)"

# T-319: a --lang flag skips the language question entirely, menu included --
# no prompt text and no menu title should ever reach the transcript.
IT319_PARENT="$TMP/install-t319-parent"
IT319_BIN="$TMP/install-t319-bin"
mkdir -p "$IT319_PARENT" "$IT319_BIN"
t; PATH="$IT319_BIN:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" install "$IT319_PARENT" --lang en --no-prompt --user T319 \
  >"$TMP/install-t319.out" 2>"$TMP/install-t319.err"
assert_eq "T-319: --lang skips the language question (no ask/menu text emitted)" 'yes' \
  "$(! grep -qF "$(i18n install_ask_lang)" "$TMP/install-t319.out" \
     && ! grep -qF "$(i18n install_menu_lang_title)" "$TMP/install-t319.out" \
     && printf yes || printf no)"

# T-320: the arrow-key menu function must restore the terminal's stty state
# on the way out, including on Ctrl+C/TERM/HUP mid-menu -- otherwise a user
# who interrupts the wizard (or whose terminal hangs up) is left with a
# broken, echo-less shell. Source check only: this suite has no portable
# pseudo-TTY across its three CI shells.
IMENU_SOURCE=$(sed -n '/^_q_install_menu_pick()/,/^}/p;/^_q_install_menu_lang()/,/^}/p' "$ROOT/knotlog")
t; assert_eq "T-320: the language menu traps EXIT/HUP/INT/TERM to restore stty" 'yes' \
  "$(printf '%s\n' "$IMENU_SOURCE" | grep -Fq "trap 'stty \"\$_q_menu_saved\"" \
     && printf '%s\n' "$IMENU_SOURCE" | grep -Fq 'EXIT' \
     && printf '%s\n' "$IMENU_SOURCE" | grep -Fq 'HUP INT TERM' \
     && printf yes || printf no)"

# T-320b: up and down must move in opposite directions through the actual
# option count, not both toggle by a hardcoded `% 2` -- a fixed modulo of 2
# would silently break "up" the moment a third language profile is added
# (README promises "other languages via profiles").
t; assert_eq "T-320b: menu up/down move in opposite directions, sized by option count" 'yes' \
  "$(printf '%s\n' "$IMENU_SOURCE" | grep -Fq '_q_menu_sel - 1 + _q_menu_n' \
     && printf '%s\n' "$IMENU_SOURCE" | grep -Fq '_q_menu_sel + 1) % _q_menu_n' \
     && ! printf '%s\n' "$IMENU_SOURCE" | grep -Fq '% 2' \
     && printf yes || printf no)"

# T-320c: menu option labels come from i18n (install_menu_lang_name_<code>),
# not hardcoded English spellings baked into the sh source -- the earlier
# version shipped 'Turkce' as a typo. Maintainer decision (2026-09-02, live
# Windows run) kept 'Turkish'; 1.2.0 shows every language by its own
# name ('Türkçe', 'Español', ...) in every i18n file -- and the menu screen
# itself carries no question line or hint line any more, just a bare
# "Language" title, so install_menu_lang_hint is now a dead key that must
# not linger in either i18n file or the menu source.
t; assert_eq "T-320c: menu labels come from i18n as English-only; hint key retired" 'yes' \
  "$(printf '%s\n' "$IMENU_SOURCE" | grep -Fq 'install_menu_lang_name_' \
     && printf '%s\n' "$IMENU_SOURCE" | grep -Fq 'install_menu_lang_title' \
     && ! printf '%s\n' "$IMENU_SOURCE" | grep -Fq 'Turkce' \
     && ! printf '%s\n' "$IMENU_SOURCE" | grep -Fq 'install_menu_lang_hint' \
     && grep -qF 'install_menu_lang_name_tr=Türkçe' "$ROOT/i18n/en.txt" \
     && grep -qF 'install_menu_lang_name_tr=Türkçe' "$ROOT/i18n/tr.txt" \
     && grep -qF 'install_menu_lang_title=Language' "$ROOT/i18n/en.txt" \
     && grep -qF 'install_menu_lang_title=Language' "$ROOT/i18n/tr.txt" \
     && ! grep -q '^install_menu_lang_hint=' "$ROOT/i18n/en.txt" \
     && ! grep -q '^install_menu_lang_hint=' "$ROOT/i18n/tr.txt" \
     && printf yes || printf no)"

# T-321: install.ps1's ReadKey path must be wrapped in try/catch, since
# ReadKey throws whenever stdin is redirected or no console is attached --
# without the catch, a non-interactive Windows run would crash instead of
# falling back to the original Read-Host question. pwsh is not installed on
# this machine, so this is a source check, not an execution.
IPS1_MENU_SOURCE=$(sed -n '/^function Read-LanguageMenu/,/^}/p' "$ROOT/install.ps1")
t; assert_eq "T-321: install.ps1 wraps ReadKey in try/catch and falls back on failure" 'yes' \
  "$(printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq 'try {' \
     && printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq '[Console]::ReadKey' \
     && printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq 'catch {' \
     && printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq "return \$null" \
     && printf yes || printf no)"

# T-321b: UpArrow and DownArrow must move the selection in opposite
# directions -- an earlier version incremented on both, which happened to
# look like a toggle with exactly two options but would break the instant a
# third language profile is added. Maintainer decision (2026-09-02, live
# Windows run): both option labels stay in English ('Turkish', not
# 'Türkçe') since the language is not chosen yet -- and 'Turkce' (the
# original typo) must never come back either.
t; assert_eq "T-321b: install.ps1 UpArrow/DownArrow move opposite ways; label is Turkish" 'yes' \
  "$(printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq "'UpArrow'   { \$sel = (\$sel - 1 + \$options.Count) % \$options.Count }" \
     && printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq "'DownArrow' { \$sel = (\$sel + 1) % \$options.Count }" \
     && grep -qF "tr = 'Turkish'" "$ROOT/install.ps1" \
     && printf '%s\n' "$IPS1_MENU_SOURCE" | grep -qF '$options = $langCodes' \
     && ! printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq 'Türkçe' \
     && ! printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq 'Turkce' \
     && printf yes || printf no)"

# T-321c: the menu screen itself stays bare -- no "Language / Dil" question
# line, no arrow-key hint line -- matching quipu's own POSIX menu screen
# (maintainer decision). The fallback plain-text question further down (used
# when ReadKey fails) is a SEPARATE code path and keeps its own
# 'Language / Dil (<codes>)' question -- this check is scoped to the menu
# function's source only, not the whole file.
t; assert_eq "T-321c: install.ps1 menu screen has no question/hint line" 'yes' \
  "$(! printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq 'Language / Dil' \
     && ! printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq 'arrows' \
     && printf '%s\n' "$IPS1_MENU_SOURCE" | grep -Fq "Write-Host 'Language'" \
     && printf yes || printf no)"

# T-322/T-322b: a .ps1 file with non-ASCII bytes and no UTF-8 BOM is read as
# the system ANSI codepage by Windows PowerShell 5.1 (still the default on
# most Windows machines, unlike PS7 which assumes UTF-8) -- so any Turkish
# text in the file mojibakes on exactly the audience it's meant for. The
# rule is an implication, not an unconditional BOM requirement: a .ps1 file
# is only required to carry a BOM if it actually has non-ASCII content, so
# an all-ASCII file (uninstall.ps1 today) is correctly left alone. Written
# as an implication so it goes red both ways: BOM removed while Turkish
# text stays, or Turkish text added without a BOM.
ps1_has_nonascii() {
  # Strip CR/LF/TAB first -- CRLF's \r is itself outside the printable
  # ASCII range and would otherwise flag every line of every file.
  [ "$(LC_ALL=C tr -d '\r\n\t' < "$1" | LC_ALL=C grep -c '[^ -~]')" -gt 0 ]
}
ps1_has_utf8_bom() {
  [ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')" = efbbbf ]
}

t; assert_eq "T-322: install.ps1 has non-ASCII content and therefore requires (and has) a UTF-8 BOM" 'yes' \
  "$(ps1_has_nonascii "$ROOT/install.ps1" && ps1_has_utf8_bom "$ROOT/install.ps1" && printf yes || printf no)"

t; assert_eq "T-322b: any .ps1 with non-ASCII content must start with a UTF-8 BOM (PS 5.1 codepage rule)" 'yes' \
  "$(for _p in "$ROOT/install.ps1" "$ROOT/uninstall.ps1"; do
       if ps1_has_nonascii "$_p" && ! ps1_has_utf8_bom "$_p"; then printf no; exit 0; fi
     done
     printf yes)"

# T-322c: adding the BOM must not disturb .gitattributes' `*.ps1 eol=crlf`
# pin -- every line in install.ps1 must still end in CRLF (no bare LF)
# after the 3-byte BOM prefix. Counted at the BYTE level via od, not by
# awk reading the file: gawk on Windows opens files in text mode and
# silently strips the \r\n pairs this test exists to guard (T-322c failed
# exactly that way on windows-latest while the file itself was CRLF-clean
# in the git blob). od never translates line endings, and the collect-all
# numbers loop is indifferent to how od wraps bytes across lines.
T322C_CRLF=$(od -An -tu1 -v "$ROOT/install.ps1" |
  awk '{
    for (i = 1; i <= NF; i++) b[++m] = $i
  }
  END {
    lf = 0; crlf = 0
    for (i = 1; i <= m; i++) {
      if (b[i] == 10) { lf++; if (i > 1 && b[i - 1] == 13) crlf++ }
    }
    print (lf > 0 && lf == crlf) ? "yes" : "no"
  }')
t; assert_eq "T-322c: install.ps1 stays fully CRLF (no bare LF) after the BOM was added" 'yes' "$T322C_CRLF"

# T-323: a plain POSIX install (Linux/macOS, no install.ps1 in the picture)
# is unaffected by the Windows single-wizard work -- it must still show all
# 5 wizard pages, [1/5] Language included, each one drawn as an ASCII box
# (border lines present, not the old un-boxed plain text).
IT323_PARENT="$TMP/install-t323-parent"
IT323_BIN="$TMP/install-t323-bin"
mkdir -p "$IT323_PARENT" "$IT323_BIN"
printf 'en\nT323User\n\n\n' | PATH="$IT323_BIN:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" install "$IT323_PARENT" \
  >"$TMP/install-t323.out" 2>"$TMP/install-t323.err"
t; assert_eq "T-323: pure-bash install still shows [1/5]..[5/5], each page boxed" 'yes' \
  "$(grep -qF '[1/5] Language' "$TMP/install-t323.out" \
     && grep -qF '[2/5] Vault location' "$TMP/install-t323.out" \
     && grep -qF '[3/5] Identity' "$TMP/install-t323.out" \
     && grep -qF '[4/5] Style' "$TMP/install-t323.out" \
     && grep -qF '[5/5] Install' "$TMP/install-t323.out" \
     && [ "$(grep -o '+-*+' "$TMP/install-t323.out" | wc -l | tr -d ' ')" -ge 8 ] \
     && printf yes || printf no)"

# T-324: KNOTLOG_INSTALL_HANDOFF (set only by install.ps1, never a documented
# public flag) must make quipu's own wizard skip the language page it would
# otherwise show for a --lang-preset language, and renumber every page
# after it so the total is exactly how many pages are actually left (4:
# location, identity, style, install) -- never a stale [x/4] left over from the
# page that was skipped, and never an invented count.
IT324_PARENT="$TMP/install-t324-parent"
IT324_BIN="$TMP/install-t324-bin"
mkdir -p "$IT324_PARENT" "$IT324_BIN"
printf 'T324User\n\n\n' | PATH="$IT324_BIN:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  KNOTLOG_INSTALL_HANDOFF=1 sh "$ROOT/knotlog" install "$IT324_PARENT" --lang en \
  >"$TMP/install-t324.out" 2>"$TMP/install-t324.err"
IT324_OUT=$(cat "$TMP/install-t324.out")
t; assert_eq "T-324: KNOTLOG_INSTALL_HANDOFF skips the language page and renumbers honestly" 'yes' \
  "$(! printf '%s\n' "$IT324_OUT" | grep -qF '] Language' \
     && printf '%s\n' "$IT324_OUT" | grep -qF '[1/4] Vault location' \
     && printf '%s\n' "$IT324_OUT" | grep -qF '[2/4] Identity' \
     && printf '%s\n' "$IT324_OUT" | grep -qF '[3/4] Style' \
     && printf '%s\n' "$IT324_OUT" | grep -qF '[4/4] Install' \
     && ! printf '%s\n' "$IT324_OUT" | grep -qF '/5]' \
     && printf yes || printf no)"

# The pre-rename QUIPU_INSTALL_HANDOFF is still honoured.
IT324B_PARENT="$TMP/install-t324b-parent"
mkdir -p "$IT324B_PARENT"
printf 'T324User\n\n\n' | PATH="$IT324_BIN:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  QUIPU_INSTALL_HANDOFF=1 sh "$ROOT/knotlog" install "$IT324B_PARENT" --lang en \
  >"$TMP/install-t324b.out" 2>"$TMP/install-t324b.err"
t; assert_eq "T-324b: the old QUIPU_INSTALL_HANDOFF still skips the language page" 'yes' \
  "$(! grep -qF '] Language' "$TMP/install-t324b.out" \
     && grep -qF '[1/4] Vault location' "$TMP/install-t324b.out" && printf yes || printf no)"

# T-325: box alignment must hold with multibyte UTF-8 content, not just
# ASCII -- feed a companion name with Turkish characters (ş, ğ) through the
# wizard and verify every box in the transcript (border-top, every content
# line, border-bottom) has the IDENTICAL display width in true UTF-8
# characters, computed as bytes minus continuation bytes. `wc -m` cannot
# be the ruler here: it counts characters on a UTF-8 macOS/Linux but
# degenerates to bytes in a C-locale Git Bash, so the same box would
# measure aligned on one platform and broken on another. The wizard itself
# pads to this same character count (quipu's _q_disp_width).
IT325_PARENT="$TMP/install-t325-parent"
IT325_BIN="$TMP/install-t325-bin"
mkdir -p "$IT325_PARENT" "$IT325_BIN"
printf 'en\nT325User\nÖğretmen\n\n' | PATH="$IT325_BIN:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" install "$IT325_PARENT" \
  >"$TMP/install-t325.out" 2>"$TMP/install-t325.err"
# Every content line ends with its own "\n" (each is its own printf call),
# and the border that closes a box is always printed right after -- so a
# CLOSING border always lands on its own clean line, even though the
# OPENING border can end up glued onto the previous unanswered prompt's
# trailing text (FORCE_TTY over a pipe, no real terminal to clear -- a
# transcript artifact, not a box-drawing bug; the same artifact the older
# IASK_PAGES check above works around with substring matching instead of
# per-line anchoring). So this walks anchored lines only: a run of
# consecutive "| ... |" content lines immediately followed by an anchored
# "+---+" close border must all share that border's exact character width.
IT325_OK=yes
IT325_RUN_OPEN=0
IT325_RUN_W=0
IT325_BOXES=0
while IFS= read -r _t325_line; do
  case "$_t325_line" in
    '| '*' |')
      _t325_w=$(printf '%s' "$_t325_line" | LC_ALL=C awk '{c = 0; for (i = 1; i <= length($0); i++) {ch = substr($0, i, 1); if (ch < "\200" || ch >= "\300") c++} print c + 0}')
      if [ "$IT325_RUN_OPEN" -eq 0 ]; then
        IT325_RUN_W=$_t325_w
        IT325_RUN_OPEN=1
      elif [ "$_t325_w" -ne "$IT325_RUN_W" ]; then
        IT325_OK=no
      fi
      ;;
    +-*+)
      if [ "$IT325_RUN_OPEN" -eq 1 ]; then
        _t325_w=$(printf '%s' "$_t325_line" | LC_ALL=C awk '{c = 0; for (i = 1; i <= length($0); i++) {ch = substr($0, i, 1); if (ch < "\200" || ch >= "\300") c++} print c + 0}')
        [ "$_t325_w" -eq "$IT325_RUN_W" ] || IT325_OK=no
        IT325_BOXES=$((IT325_BOXES + 1))
        IT325_RUN_OPEN=0
      fi
      ;;
    *)
      IT325_RUN_OPEN=0
      ;;
  esac
done < "$TMP/install-t325.out"
t; assert_eq "T-325: box alignment holds with multibyte Turkish content (Öğretmen)" 'yes' \
  "$(grep -qF 'Öğretmen' "$TMP/install-t325.out" \
     && [ "$IT325_OK" = yes ] && [ "$IT325_BOXES" -ge 1 ] \
     && printf yes || printf no)"

# T-326: the location step got a three-part question and a fully
# Turkish page title. The question is printed OUTSIDE the box as four keys
# (head / default-with-placeholder / move hint / bare ": " prompt); the
# [%s] default-path placeholder must survive since Enter-to-accept-default
# still depends on it, and the old single-line key must be gone from both
# languages (clean cutover, no dead key left behind).
t; assert_eq "T-326: the location page title is fully Turkish (Kasa Konumu) in tr, English in en" 'yes' \
  "$(grep -qF 'install_step_location=[%d/%d] Kasa Konumu' "$ROOT/i18n/tr.txt" \
     && grep -qF 'install_step_location=[%d/%d] Vault location' "$ROOT/i18n/en.txt" \
     && printf yes || printf no)"
t; assert_eq "T-326: the three-part location question carries the agreed TR wording and [%s]" 'yes' \
  "$(grep -qF 'install_ask_location_head=Kasanız nereye kurulsun?' "$ROOT/i18n/tr.txt" \
     && grep -qF 'install_ask_location_default=Hiçbir şey yazmadan Enter tuşuna basarsanız varsayılan dizinde kurulacaktır. [%s]' "$ROOT/i18n/tr.txt" \
     && grep -qF 'install_ask_location_move=İsterseniz kasayı istediğiniz bir yere taşıyabilirsiniz.' "$ROOT/i18n/tr.txt" \
     && printf yes || printf no)"
t; assert_eq "T-326: the EN counterparts keep the same three-part shape and [%s]" 'yes' \
  "$(grep -qF 'install_ask_location_head=Where should your vault be installed?' "$ROOT/i18n/en.txt" \
     && grep -qF 'install_ask_location_default=Press Enter without typing anything to install in the default directory. [%s]' "$ROOT/i18n/en.txt" \
     && grep -qF 'install_ask_location_move=If you like, you can move the vault wherever you want.' "$ROOT/i18n/en.txt" \
     && grep -qF 'install_ask_location_prompt=: ' "$ROOT/i18n/en.txt" \
     && printf yes || printf no)"
t; assert_eq "T-326: the retired single-line location key is gone from both languages" 'yes' \
  "$(! grep -q '^install_ask_location=' "$ROOT/i18n/en.txt" \
     && ! grep -q '^install_ask_location=' "$ROOT/i18n/tr.txt" \
     && ! grep -q '^init_ask_purpose=' "$ROOT/i18n/en.txt" \
     && ! grep -q '^init_ask_purpose=' "$ROOT/i18n/tr.txt" \
     && printf yes || printf no)"

# T-327: found live (PTY measurement, not the FORCE_TTY fallback path --
# FORCE_TTY always disables the arrow-key menu, so a T-323-style test can
# never reach this branch): when the interactive menu itself answers the
# language question, it is bare and uncounted (maintainer decision) -- so
# the pages that follow must renumber to [1/3]/[2/3]/[3/3], never jump
# from an uncounted screen straight to a stale "[2/4]". This is a source
# check because CI has no portable pseudo-TTY across its three shells (see
# T-320's own note); a real PTY run confirming the actual on-screen
# sequence is in this task's report, not in the shipped suite.
IMENU_SUCCESS_BLOCK=$(sed -n '/elif _q_install_menu_lang; then/,/^    else$/p' "$ROOT/knotlog")
t; assert_eq "T-327: the menu-success branch renumbers remaining pages (total 3, not 4)" 'yes' \
  "$(printf '%s\n' "$IMENU_SUCCESS_BLOCK" | grep -Fq '_q_install_set_step_totals 0' \
     && ! printf '%s\n' "$IMENU_SUCCESS_BLOCK" | grep -Fq '_q_install_set_step_totals 1' \
     && printf yes || printf no)"

# T-328: the box-width cap mechanism exists in source -- min(detected
# terminal width, 76) -- with the safe 80-column fallback when neither
# `stty size` nor `tput cols` is available. Functional coverage (T-329)
# proves this actually holds a real box under 80 columns; this just locks
# the mechanism in so it cannot silently be deleted with source intact.
t; assert_eq "T-328: quipu's box has a terminal-width cap with an 80-column fallback" 'yes' \
  "$(grep -Fq '_q_term_cols()' "$ROOT/knotlog" \
     && grep -Fq 'stty size' "$ROOT/knotlog" \
     && grep -Fq 'tput cols' "$ROOT/knotlog" \
     && grep -Fq '_q_tc_cols=80' "$ROOT/knotlog" \
     && grep -Fq "\"\$_q_pf_cap\" -le 76" "$ROOT/knotlog" \
     && printf yes || printf no)"

# T-329: functional proof that a long vault path does not stretch the box
# past 80 columns -- every border in the transcript must be <=76 columns
# (the cap), and the overflowing line (the only realistic offender: a
# long path) must be visibly elided with a leading "...". Without the
# cap, this specific box would run to 100+ columns and wrap on any
# standard terminal, which is exactly the confusion the box exists to
# prevent.
IT329_LONGDIR="$TMP/install-t329-averyverylongdirectorynamethatwillcertainlyoverflowanyreasonableboxwidthlimitxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/p"
IT329_BIN="$TMP/install-t329-bin"
mkdir -p "$IT329_LONGDIR" "$IT329_BIN"
printf 'en\nT329User\n\n\n' | PATH="$IT329_BIN:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" install "$IT329_LONGDIR" \
  >"$TMP/install-t329.out" 2>"$TMP/install-t329.err"
IT329_MAXW=0
grep -o '+-*+' "$TMP/install-t329.out" > "$TMP/install-t329.borders"
while IFS= read -r _t329_b; do
  _t329_w=$(printf '%s' "$_t329_b" | wc -m | tr -d ' ')
  [ "$_t329_w" -le "$IT329_MAXW" ] || IT329_MAXW=$_t329_w
done < "$TMP/install-t329.borders"
t; assert_eq "T-329: a long vault path keeps every box border <=76 columns, elided with '...'" 'yes' \
  "$([ "$IT329_MAXW" -le 76 ] && [ "$IT329_MAXW" -gt 0 ] \
     && grep -qF '| ...' "$TMP/install-t329.out" \
     && printf yes || printf no)"

# T-330: the same eliding must never split a multibyte UTF-8 character --
# use a long path FULL of Turkish characters (ş, ç, ü, ğ, ö, ı) right up
# against the truncation point, then verify the transcript is still
# well-formed UTF-8 top to bottom. A byte cut that ignores character
# boundaries would corrupt exactly this. `iconv` round-tripping the
# transcript UTF-8 -> UTF-8 through stdin/stdout fails loudly on any
# illegal sequence; skipped if iconv is not on PATH rather than assumed
# present (three-CI-shell zero-dependency rule). The check deliberately
# does NOT use `iconv -o`: GNU iconv has it, but macOS's BSD iconv and
# Git Bash's libiconv do not -- there the option is a usage error (exit
# non-zero, stderr silenced), which failed this test on green transcripts.
if command -v iconv >/dev/null 2>&1; then
  IT330_TRDIR="$TMP/install-t330-ÖğretmenlerGünüKutluOlsunTürkçeKarakterTestBuÇokUzunBirYolAdıOlmalıŞimdiTamamdır/p"
  IT330_BIN="$TMP/install-t330-bin"
  mkdir -p "$IT330_TRDIR" "$IT330_BIN"
  printf 'en\nT330User\n\n\n' | PATH="$IT330_BIN:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
    sh "$ROOT/knotlog" install "$IT330_TRDIR" \
    >"$TMP/install-t330.out" 2>"$TMP/install-t330.err"
  t; assert_eq "T-330: Turkish-character eliding never breaks UTF-8 well-formedness" 'yes' \
    "$(grep -qF '| ...' "$TMP/install-t330.out" \
       && iconv -f UTF-8 -t UTF-8 < "$TMP/install-t330.out" > /dev/null 2>/dev/null \
       && printf yes || printf no)"
else
  t; skip "T-330: Turkish-character eliding never breaks UTF-8 well-formedness" "iconv not on PATH"
fi

# T-331: install.ps1's box must apply the same terminal-width cap and
# character-safe (not byte-based) eliding as the POSIX side -- statically
# checked, pwsh is not installed on this machine.
IPS1_BOX_SOURCE=$(sed -n '/^function Write-Box/,/^}/p' "$ROOT/install.ps1")
t; assert_eq "T-331: install.ps1's box caps width at 76 and elides with a leading '...'" 'yes' \
  "$(printf '%s\n' "$IPS1_BOX_SOURCE" | grep -Fq '[Math]::Min' \
     && printf '%s\n' "$IPS1_BOX_SOURCE" | grep -Fq '76' \
     && printf '%s\n' "$IPS1_BOX_SOURCE" | grep -Fq "'...'" \
     && printf '%s\n' "$IPS1_BOX_SOURCE" | grep -Fq '.Substring(' \
     && grep -Fq 'function Get-TerminalWidth' "$ROOT/install.ps1" \
     && grep -Fq 'WindowWidth' "$ROOT/install.ps1" \
     && printf yes || printf no)"

# ---- T-332/T-333/T-334: _q_term_cols under a degraded/adversarial width
# probe -- found live (a real PTY whose winsize was never set reports
# "stty size" = "0 0"), and this is FUNCTIONAL, not a source grep: a
# fallback-path test alone would have missed that a naive fix (accept the
# probe's answer once it merely looks numeric) still crashes, because
# `_q_tc_cols=$(tput cols ...)` is an unguarded command substitution under
# this script's `set -eu` -- a tput that exits non-zero (unset TERM, a
# broken/missing terminfo, or -- as built here -- a stub that fails on
# purpose) previously aborted the ENTIRE install with no output at all,
# which is worse than the cosmetic bug being fixed. Shadowing real
# stty/tput with tiny stub scripts, prepended on PATH, exercises the exact
# probe path quipu's own _q_term_cols walks.
mk_stub_stty_zero() {
  # $1 = directory to receive the stub
  cat > "$1/stty" << 'STUBEOF'
#!/bin/sh
if [ "$1" = size ]; then printf '0 0\n'; exit 0; fi
exit 1
STUBEOF
  chmod +x "$1/stty"
}

# T-332: stty reports "0 0" (winsize unset) AND tput is broken outright
# (always exits 1, no output) -- must NOT crash the install, and must
# fall all the way through to the 80-column default. This is the crash
# regression: before the `|| true` guard on the tput substitution, this
# exact combination made the install exit 1 with silently empty stdout
# AND stderr, before printing a single page.
IT332_DIR="$TMP/install-t332-bin"
mkdir -p "$IT332_DIR"
mk_stub_stty_zero "$IT332_DIR"
cat > "$IT332_DIR/tput" << 'STUBEOF'
#!/bin/sh
exit 1
STUBEOF
chmod +x "$IT332_DIR/tput"
IT332_PARENT="$TMP/install-t332-parent"
mkdir -p "$IT332_PARENT"
printf 'en\nT332User\n\n\n' | PATH="$IT332_DIR:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" install "$IT332_PARENT" \
  >"$TMP/install-t332.out" 2>"$TMP/install-t332.err"
IT332_RC=$?
t; assert_eq "T-332: stty=0 + broken tput does not crash install, falls back to 80 cols" 'yes' \
  "$([ "$IT332_RC" -eq 0 ] \
     && grep -qF '[1/5] Language' "$TMP/install-t332.out" \
     && grep -qF '[2/5] Vault location' "$TMP/install-t332.out" \
     && grep -qF '[5/5] Install' "$TMP/install-t332.out" \
     && printf yes || printf no)"

# T-333: stty reports "0 0", tput reports a real "80" -- the exact
# combination a PTY measurement found. Must fall through stty to
# tput correctly (not get stuck on the rejected 0), keeping every page
# title and step counter intact.
IT333_DIR="$TMP/install-t333-bin"
mkdir -p "$IT333_DIR"
mk_stub_stty_zero "$IT333_DIR"
cat > "$IT333_DIR/tput" << 'STUBEOF'
#!/bin/sh
if [ "$1" = cols ]; then printf '80\n'; exit 0; fi
exit 1
STUBEOF
chmod +x "$IT333_DIR/tput"
IT333_PARENT="$TMP/install-t333-parent"
mkdir -p "$IT333_PARENT"
printf 'en\nT333User\n\n\n' | PATH="$IT333_DIR:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" install "$IT333_PARENT" \
  >"$TMP/install-t333.out" 2>"$TMP/install-t333.err"
t; assert_eq "T-333: stty=0 falls through to a valid tput cols, pages stay intact" 'yes' \
  "$(grep -qF '[1/5] Language' "$TMP/install-t333.out" \
     && grep -qF '[3/5] Identity' "$TMP/install-t333.out" \
     && grep -qF '[5/5] Install' "$TMP/install-t333.out" \
     && printf yes || printf no)"

# T-334: a genuinely narrow but POSITIVE terminal (10 columns -- a real,
# not adversarial, answer) must not be accepted as-is either: the 40-col
# floor must kick in, and the page title / step counter on the longest
# page (Identity, which also carries the long location review line) must
# still read intact -- only the long path value line may be elided.
IT334_DIR="$TMP/install-t334-bin"
mkdir -p "$IT334_DIR"
cat > "$IT334_DIR/stty" << 'STUBEOF'
#!/bin/sh
if [ "$1" = size ]; then printf '24 10\n'; exit 0; fi
exit 1
STUBEOF
chmod +x "$IT334_DIR/stty"
IT334_PARENT="$TMP/install-t334-parent"
mkdir -p "$IT334_PARENT"
printf 'en\nT334User\n\n\n' | PATH="$IT334_DIR:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" install "$IT334_PARENT" \
  >"$TMP/install-t334.out" 2>"$TMP/install-t334.err"
IT334_MAXBORDER=0
grep -o '+-*+' "$TMP/install-t334.out" > "$TMP/install-t334.borders"
while IFS= read -r _t334_b; do
  _t334_w=$(printf '%s' "$_t334_b" | wc -m | tr -d ' ')
  [ "$_t334_w" -le "$IT334_MAXBORDER" ] || IT334_MAXBORDER=$_t334_w
done < "$TMP/install-t334.borders"
# The identity/install pages carry the long location-path review line, so
# their box grows to the 40-column floor -- language/location's own pages
# stay naturally narrower (their content never needed 40 columns). The
# WIDEST box in the transcript is therefore the one to check against the
# floor, not the narrowest.
t; assert_eq "T-334: a 10-column terminal still floors the box at 40, titles unclipped" 'yes' \
  "$([ "$IT334_MAXBORDER" -eq 40 ] \
     && grep -qF '[3/5] Identity' "$TMP/install-t334.out" \
     && grep -qF '[5/5] Install' "$TMP/install-t334.out" \
     && grep -qF '| ...' "$TMP/install-t334.out" \
     && printf yes || printf no)"

# T-335: the guard that fixed T-332's crash (an unguarded `var=$(tput ...)`
# under `set -eu` aborting the whole install) must not silently regress --
# source check pinning the `|| true` on that specific substitution.
t; assert_eq "T-335: the tput cols substitution in _q_term_cols is set -e-safe" 'yes' \
  "$(sed -n '/^_q_term_cols()/,/^}/p' "$ROOT/knotlog" | grep -Fq 'tput cols 2>/dev/null) || true' \
     && printf yes || printf no)"

# T-336: icon/Knotlog.ico is a REAL multi-image 32-bit ICO, not the old
# single-image 16-color (4bpp palette) file that turned into a black square
# in Explorer. Pure POSIX byte-level check (od/awk; no ImageMagick at test
# time): the header names >=1 image, and every directory entry carries
# bitcount=32, colors=0 (palette-less), and a BITMAPINFOHEADER-sized DIB
# with a doubled biHeight (XOR+AND masks) at its own offset.
# The image count is parsed with a collect-all-numbers awk, NOT '$1 + $2':
# macOS od may split even a 2-byte dump across lines, which fed a newline
# into `-v n=` of the awks below and killed them with BWK awk's
# "newline in string" before T-336 could assert anything.
ICO_N=$(od -An -tu1 -j4 -N2 "$ROOT/icon/Knotlog.ico" |
  awk '{
    for (i = 1; i <= NF; i++) b[++m] = $i
  }
  END {
    print b[1] + b[2] * 256
  }')
ICO_SIZES=$(od -An -tu1 -v -j6 -N$((16 * ICO_N)) "$ROOT/icon/Knotlog.ico" |
  awk -v n="$ICO_N" '
    {
      for (i = 1; i <= NF; i++) b[++m] = $i
    }
    END {
      for (i = 0; i < n; i++) {
        e = i * 16
        w = b[e + 1]; bc = b[e + 7] + b[e + 8] * 256; cc = b[e + 3]
        sz = b[e + 9] + b[e + 10] * 256 + b[e + 11] * 65536 + b[e + 12] * 16777216
        off = b[e + 13] + b[e + 14] * 256 + b[e + 15] * 65536 + b[e + 16] * 16777216
        if (bc != 32 || cc != 0) { print "bad"; exit }
        sizes = sizes (i ? "," : "") ((w == 0) ? 256 : w)
      }
      print sizes
    }')
t; assert_eq "T-336: every ICO entry is 32bpp and palette-less, sizes 16..256" \
  '16,24,32,48,64,128,256' "$ICO_SIZES"
ICO_HDR_OK=$(od -An -tu1 -v "$ROOT/icon/Knotlog.ico" |
  awk -v n="$ICO_N" '
    {
      for (i = 1; i <= NF; i++) b[++m] = $i
    }
    END {
      for (i = 0; i < n; i++) {
        e = 6 + i * 16
        off = b[e + 13] + b[e + 14] * 256 + b[e + 15] * 65536 + b[e + 16] * 16777216
        # DIB header: biSize=40, biPlanes=1, biBitCount=32, biCompression=0.
        if (b[off + 1] != 40 || b[off + 13] != 1 || b[off + 15] != 32 || b[off + 17] != 0) {
          print "bad"; exit
        }
      }
      print "ok"
    }')
t; assert_eq "T-336: every ICO image is an uncompressed 40-byte-header 32bpp DIB" 'ok' "$ICO_HDR_OK"

# T-337: the install progress animation and the green closing title share
# one real-terminal gate -- exactly the menu's fallback discipline. Source
# checks pin the three conditions so none can be silently deleted.
IBUSY_SRC=$(sed -n '/^_q_install_tty()/,/^}/p' "$ROOT/knotlog")
t; assert_eq "T-337: the install tty gate requires stdout tty, TERM, and no FORCE_TTY" 'yes' \
  "$(printf '%s\n' "$IBUSY_SRC" | grep -Fq '[ -t 1 ]' \
     && printf '%s\n' "$IBUSY_SRC" | grep -Fq 'QUIPU_FORCE_TTY' \
     && printf '%s\n' "$IBUSY_SRC" | grep -Fq "'' | dumb" \
     && printf yes || printf no)"
t; assert_eq "T-337: the busy animation runs in background and is trapped for cleanup" 'yes' \
  "$(grep -Fq '_q_install_busy_start' "$ROOT/knotlog" \
     && grep -Fq "( _q_install_busy_loop ) &" "$ROOT/knotlog" \
     && grep -Fq "trap '_q_install_busy_stop' EXIT" "$ROOT/knotlog" \
     && printf yes || printf no)"

# T-338: functional proof for the closing screen on the FORCED-TTY pipe
# path (the only path CI can drive): the plain-text closing block must be
# present, and the transcript must still contain ZERO ANSI escape bytes --
# no green escape, no clear, no leftovers from the (unstarted) animation.
IT338_PARENT="$TMP/install-t338-parent"
IT338_BIN="$TMP/install-t338-bin"
mkdir -p "$IT338_PARENT" "$IT338_BIN"
printf 'en\nT338User\n\n\n' | PATH="$IT338_BIN:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
  sh "$ROOT/knotlog" install "$IT338_PARENT" \
  >"$TMP/install-t338.out" 2>"$TMP/install-t338.err"
IT338_RC=$?
IASK_ESC338=$(awk 'BEGIN { printf "%c", 27 }')
t; assert_eq "T-338: forced-tty pipe install ends with the plain closing screen, no escapes" 'yes' \
  "$([ "$IT338_RC" -eq 0 ] \
     && grep -qF 'Installation Complete' "$TMP/install-t338.out" \
     && grep -qF 'Your assistant is waiting for you.' "$TMP/install-t338.out" \
     && grep -qF 'claude code or omp' "$TMP/install-t338.out" \
     && ! grep -q "$IASK_ESC338" "$TMP/install-t338.out" \
     && ! grep -q 'Installing' "$TMP/install-t338.out" \
     && printf yes || printf no)"
# The product resolves the parent through `cd && pwd -P` before printing
# (quipu's _q_cmd_install does this so every screen shows one physical
# path), and the runners' paths are exactly where that bites: macOS's
# TMPDIR lives under the /var -> /private/var symlink, and Git Bash's
# /tmp is a mount that pwd -P resolves below a Windows TEMP directory.
# The invariant under test is unchanged -- the closing screen must name
# the REAL installed directory in full, never elided, never a placeholder
# -- so the expectation is derived through the same resolution.
t; assert_eq "T-338: the closing screen names the installed directory in full" 'yes' \
  "$(T338_CANON=$(CDPATH='' cd -- "$IT338_PARENT" && pwd -P) &&
     grep -qF "installed ($T338_CANON/T338User's Knotlog)" "$TMP/install-t338.out" \
     && printf yes || printf no)"

# T-339: the green closing title exists ONLY behind the shared tty gate --
# source check that the raw escape is inside the _q_install_tty branch and
# that the plain-text fallback branch exists right beside it.
t; assert_eq "T-339: green closing title is gated on _q_install_tty with a plain fallback" 'yes' \
  "$(grep -Fq '\033[32m%s\033[0m\n' "$ROOT/knotlog" \
     && grep -B2 -F '\033[32m%s\033[0m\n' "$ROOT/knotlog" | grep -Fq 'if _q_install_tty && [ -z "${NO_COLOR:-}" ]; then' \
     && grep -A2 -F 'if _q_install_tty && [ -z "${NO_COLOR:-}" ]; then' "$ROOT/knotlog" | grep -Fq 'install_done_title' \
     && printf yes || printf no)"
t; assert_eq "T-339: the wizard closing keys exist in both languages" 'yes' \
  "$(for _k in install_busy install_done_title install_done_waiting install_done_body_1 install_done_body_2; do
       for _f in en tr; do
         grep -q "^$_k=" "$ROOT/i18n/$_f.txt" || { printf 'missing:%s:%s' "$_k" "$_f"; exit 0; }
       done
     done
     printf yes)"

# T-340: `context --bridge` writes the context into BOTH bridge files. This is
# the hook-less path, and it is the only way a Codex session -- whose hooks do
# not fire under a live install -- learns what a Claude session did, and the
# other way round. Writing only AGENTS.md left one side of that exchange blind.
mkvault vbr2
QUIPU_VAULT="$TMP/vbr2" QUIPU_LANG=en sh "$ROOT/knotlog" init --no-prompt --layout en \
  --user Sel --companion Sum >/dev/null 2>&1
printf '# n\n' > "$TMP/vbr2/n.md"
QUIPU_VAULT="$TMP/vbr2" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path n.md >/dev/null 2>&1
QUIPU_VAULT="$TMP/vbr2" QUIPU_LANG=en sh "$ROOT/knotlog" context --bridge >/dev/null 2>&1
t; assert_eq "T-340: context --bridge writes the context block to both files" 'yes' \
  "$(grep -q 'knotlog:context:start' "$TMP/vbr2/AGENTS.md" \
     && grep -q 'knotlog:context:start' "$TMP/vbr2/CLAUDE.md" \
     && printf yes || printf no)"
t; assert_eq "T-340: both context blocks are byte-identical" 'yes' \
  "$(sed -n '/context:start/,/context:end/p' "$TMP/vbr2/AGENTS.md" > "$TMP/ctx-a.txt"
     sed -n '/context:start/,/context:end/p' "$TMP/vbr2/CLAUDE.md" > "$TMP/ctx-c.txt"
     cmp -s "$TMP/ctx-a.txt" "$TMP/ctx-c.txt" && printf yes || printf no)"
# The context block must never eat the static init block in either file.
t; assert_eq "T-340: the static knotlog:start block survives in both files" 'yes' \
  "$([ "$(grep -c 'knotlog:start' "$TMP/vbr2/AGENTS.md")" = 1 ] \
     && [ "$(grep -c 'knotlog:start' "$TMP/vbr2/CLAUDE.md")" = 1 ] \
     && printf yes || printf no)"
# Re-running must stay idempotent in both files (block.awk's contract).
QUIPU_VAULT="$TMP/vbr2" QUIPU_LANG=en sh "$ROOT/knotlog" context --bridge >/dev/null 2>&1
t; assert_eq "T-340: a second --bridge run adds no duplicate blocks" 'yes' \
  "$([ "$(grep -c 'knotlog:context:start' "$TMP/vbr2/CLAUDE.md")" = 1 ] \
     && [ "$(grep -c 'knotlog:context:start' "$TMP/vbr2/AGENTS.md")" = 1 ] \
     && printf yes || printf no)"

# T-341: user-written text outside the markers survives in CLAUDE.md. This is
# the file most likely to hold hand-written project instructions (a real
# vault has a 38 KB one), so the bridge must never clobber it.
printf '\n## my own notes\nkeep me\n' >> "$TMP/vbr2/CLAUDE.md"
QUIPU_VAULT="$TMP/vbr2" QUIPU_LANG=en sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
QUIPU_VAULT="$TMP/vbr2" QUIPU_LANG=en sh "$ROOT/knotlog" context --bridge >/dev/null 2>&1
t; assert_eq "T-341: hand-written CLAUDE.md content survives init + --bridge" 'yes' \
  "$(grep -q '^keep me$' "$TMP/vbr2/CLAUDE.md" && printf yes || printf no)"

# T-342: the dead bridge_claude pointer key is gone from both i18n files -- a
# key nothing reads is a lie waiting for a translator to maintain.
t; assert_eq "T-342: the retired bridge_claude key is gone from both i18n files" 'yes' \
  "$(! grep -q '^bridge_claude=' "$ROOT/i18n/en.txt" \
     && ! grep -q '^bridge_claude=' "$ROOT/i18n/tr.txt" \
     && ! grep -q 'bridge_claude' "$ROOT/knotlog" \
     && printf yes || printf no)"

# T-343: the threads file's NAME follows the vault language, from i18n --
# not a hardcoded string and not a config field. A Turkish vault writes its
# threads to Konular.md; an English one to Threads.md.
mkvault vthtr
QUIPU_VAULT="$TMP/vthtr" QUIPU_LANG=tr sh "$ROOT/knotlog" init --no-prompt --layout tr \
  --user S --companion Su >/dev/null 2>&1
QUIPU_VAULT="$TMP/vthtr" QUIPU_LANG=tr sh "$ROOT/knotlog" remember >/dev/null 2>&1
t; assert_eq "T-343: a Turkish vault names its threads file Konular.md" 'yes' \
  "$([ -f "$TMP/vthtr/Konular.md" ] && [ ! -f "$TMP/vthtr/Threads.md" ] && printf yes || printf no)"
mkvault vthen
QUIPU_VAULT="$TMP/vthen" QUIPU_LANG=en sh "$ROOT/knotlog" init --no-prompt --layout en \
  --user S --companion Su >/dev/null 2>&1
QUIPU_VAULT="$TMP/vthen" QUIPU_LANG=en sh "$ROOT/knotlog" remember >/dev/null 2>&1
t; assert_eq "T-343: an English vault names its threads file Threads.md" 'yes' \
  "$([ -f "$TMP/vthen/Threads.md" ] && [ ! -f "$TMP/vthen/Konular.md" ] && printf yes || printf no)"

# T-344: the legacy name always wins over the localized one. A Turkish vault
# created before T-343 keeps its history in Threads.md; picking the localized
# name blindly would seed an empty Konular.md beside it and every reader --
# doctor, context, the bridge -- would report an empty vault while the real
# history sat untouched on disk. This is the regression that matters.
mkvault vthleg
QUIPU_VAULT="$TMP/vthleg" QUIPU_LANG=tr sh "$ROOT/knotlog" init --no-prompt --layout tr \
  --user S --companion Su >/dev/null 2>&1
mv "$TMP/vthleg/Konular.md" "$TMP/vthleg/Threads.md"
printf '\n### LEGACY HISTORY\n' >> "$TMP/vthleg/Threads.md"
QUIPU_VAULT="$TMP/vthleg" QUIPU_LANG=tr sh "$ROOT/knotlog" remember >/dev/null 2>&1
t; assert_eq "T-344: a legacy Turkish vault keeps writing to Threads.md" 'yes' \
  "$([ ! -f "$TMP/vthleg/Konular.md" ] && grep -q 'LEGACY HISTORY' "$TMP/vthleg/Threads.md" \
     && printf yes || printf no)"
t; assert_eq "T-344: context reads the legacy file, not an empty new one" 'yes' \
  "$(QUIPU_VAULT="$TMP/vthleg" QUIPU_LANG=tr sh "$ROOT/knotlog" context 2>/dev/null \
     | grep -q 'LEGACY HISTORY' && printf yes || printf no)"
# doctor must judge the same file context does, or the two disagree about
# whether the vault has threads at all. Filling the legacy file's scaffold
# block has to silence doctor's warning -- if doctor were looking at a
# freshly seeded Konular.md instead, it would keep warning forever while the
# user stared at a threads file they had just filled in.
# doctor must reach the same verdict as it would for an identically-filled
# vault that uses the localized name -- the resolver may change WHICH file is
# read, never WHAT is concluded from it. (Whether a `###` heading counts as
# "filled" is doctor's own rule and is asserted elsewhere; this test only pins
# that the legacy and localized names are judged alike.)
mkvault vthloc
QUIPU_VAULT="$TMP/vthloc" QUIPU_LANG=tr sh "$ROOT/knotlog" init --no-prompt --layout tr \
  --user S --companion Su >/dev/null 2>&1
printf '\n### LEGACY HISTORY\n' >> "$TMP/vthloc/Konular.md"
VTH_LEG=$(QUIPU_VAULT="$TMP/vthleg" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>/dev/null | grep -c 'has not been updated yet')
VTH_LOC=$(QUIPU_VAULT="$TMP/vthloc" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>/dev/null | grep -c 'has not been updated yet')
t; assert_eq "T-344: doctor judges the legacy and localized names alike" "$VTH_LOC" "$VTH_LEG"

# T-345: threads_file is a real key in both i18n files, and nothing hardcodes
# a threads filename in the source any more (comments excepted).
t; assert_eq "T-345: threads_file exists in both i18n files" 'yes' \
  "$(grep -q '^threads_file=Threads.md$' "$ROOT/i18n/en.txt" \
     && grep -q '^threads_file=Konular.md$' "$ROOT/i18n/tr.txt" \
     && printf yes || printf no)"
t; assert_eq "T-345: no code line builds a threads path from a literal name" '0' \
  "$(grep -n 'Threads\.md' "$ROOT/knotlog" | grep -v '^[0-9]*: *#' \
     | grep -c "\$_q_v/Threads\.md" || true)"

# ---- ctx_max in .knotlog/config (T-346..T-352) ----
# QUIPU_CTX_MAX was env-only; a vault moved to another machine lost the
# setting and silently fell back to 4096. Chain: QUIPU_CTX_MAX (env) ->
# .knotlog/config ctx_max= -> 4096, same read pattern as lang=/fold=.

# T-346: config-only ctx_max= actually changes context's truncation budget
# (functional, not just doctor's label) -- a config value smaller than the
# default forces truncation that would not happen at 4096.
mkvault v346
printf 'lang=en\nctx_max=200\n' >> "$TMP/v346/.knotlog/config"
: > "$TMP/v346/.knotlog/index.tsv"
: > "$TMP/v346/.knotlog/activity.log"
awk 'BEGIN { for (i=1; i<=80; i++) printf "thread line %03d padding padding padding\n", i }' > "$TMP/v346/Threads.md"
t; CTX346=$(env -u QUIPU_CTX_MAX QUIPU_VAULT="$TMP/v346" sh "$ROOT/knotlog" context)
SIZE346=$(printf '%s' "$CTX346" | LC_ALL=C wc -c | tr -d ' ')
assert_eq "T-346: config-only ctx_max=200 bounds context output" 'yes' \
  "$([ "$SIZE346" -le 200 ] && printf yes || printf no)"

# T-347: env overrides config -- same vault, env raises the cap far above
# config's 200, output grows past what config alone allowed (proves
# precedence functionally, not just via doctor's label).
t; CTX347=$(QUIPU_CTX_MAX=4000 QUIPU_VAULT="$TMP/v346" sh "$ROOT/knotlog" context)
SIZE347=$(printf '%s' "$CTX347" | LC_ALL=C wc -c | tr -d ' ')
assert_eq "T-347: env ctx_max overrides config's smaller value" 'yes' \
  "$([ "$SIZE347" -gt 200 ] && printf yes || printf no)"

# T-348: doctor's ctx_max row names the winning source: env / config /
# default, in that priority order, across three vaults.
mkvault v348e
printf 'lang=en\nctx_max=555\n' >> "$TMP/v348e/.knotlog/config"
t; assert_eq "T-348: doctor reports env as the source when env is set" 'yes' \
  "$(QUIPU_CTX_MAX=777 QUIPU_VAULT="$TMP/v348e" QUIPU_LANG=en sh "$ROOT/knotlog" doctor \
     | awk -F"$TAB" '$2=="ctx_max"{print $3}' | grep -qF 'env: 777' && printf yes || printf no)"
t; assert_eq "T-348: doctor reports config as the source when only config is set" 'yes' \
  "$(env -u QUIPU_CTX_MAX QUIPU_VAULT="$TMP/v348e" QUIPU_LANG=en sh "$ROOT/knotlog" doctor \
     | awk -F"$TAB" '$2=="ctx_max"{print $3}' | grep -qF 'config: 555' && printf yes || printf no)"
mkvault v348d
printf 'lang=en\n' >> "$TMP/v348d/.knotlog/config"
t; assert_eq "T-348: doctor reports default when neither env nor config is set" 'yes' \
  "$(env -u QUIPU_CTX_MAX QUIPU_VAULT="$TMP/v348d" QUIPU_LANG=en sh "$ROOT/knotlog" doctor \
     | awk -F"$TAB" '$2=="ctx_max"{print $3}' | grep -qF 'default: 4096' && printf yes || printf no)"

# T-349: a config ctx_max= that is not a positive integer (abc, 0, -5, empty)
# is ignored at that link and the chain falls through to the default --
# `context` must not crash on any of them (exit 0), and doctor must report
# the fallback (4096), never the bad value.
for _bad in abc 0 -5 ''; do
  mkvault "v349_$_bad"
  printf 'lang=en\nctx_max=%s\n' "$_bad" >> "$TMP/v349_$_bad/.knotlog/config"
  t; env -u QUIPU_CTX_MAX QUIPU_VAULT="$TMP/v349_$_bad" QUIPU_LANG=en sh "$ROOT/knotlog" context >/dev/null 2>&1
  RC349=$?
  assert_eq "T-349: ctx_max='$_bad' does not crash context (exit 0)" '0' "$RC349"
  if [ -n "$_bad" ]; then
    # a non-empty-but-invalid value must resolve to the 4096 default AND
    # doctor must warn (empty is treated as "key not set", ok/default --
    # same tolerance init/doctor give an absent layout=/fold=).
    t; assert_eq "T-349: ctx_max='$_bad' falls back to the 4096 default" 'yes' \
      "$(env -u QUIPU_CTX_MAX QUIPU_VAULT="$TMP/v349_$_bad" QUIPU_LANG=en sh "$ROOT/knotlog" doctor \
         | awk -F"$TAB" '$2=="ctx_max"{print $3}' | grep -qF '4096' && printf yes || printf no)"
    t; assert_eq "T-349: ctx_max='$_bad' makes doctor warn, not fail" 'yes' \
      "$(env -u QUIPU_CTX_MAX QUIPU_VAULT="$TMP/v349_$_bad" QUIPU_LANG=en sh "$ROOT/knotlog" doctor \
         | awk -F"$TAB" '$1=="warn" && $2=="ctx_max"{print "yes"; exit}')"
  fi
done

# T-350: `init` never writes ctx_max= itself -- it has a working default, so
# (unlike layout=/fold=) the config should not be inflated with it unasked.
mkvault v350
rm -rf "$TMP/v350"
t; QUIPU_VAULT="$TMP/v350" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --user Ada --companion Sumi >/dev/null 2>&1
assert_eq "T-350: init does not write ctx_max= to config" 'no' \
  "$(grep -q '^ctx_max=' "$TMP/v350/.knotlog/config" && printf yes || printf no)"

# ---- "now:" line in context output (T-351..T-356) ----
# knotlog context never told the model what time it is, so a model writing
# memory guessed at session headings. A fixed-format date/time/weekday line
# now leads every context emission; the weekday name is i18n data (day_1..
# day_7, POSIX `date +%u`, Monday=1), never a hardcoded English array.
#
# A fake `date` shim ahead of PATH makes the line's content deterministic
# (2024-01-01 was a real Monday) without touching the system clock, so the
# weekday-name lookup itself -- not just the format -- is under test.
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/date" <<'EOF'
#!/bin/sh
case "$1" in
  +%Y-%m-%d) printf '2024-01-01\n' ;;
  +%H:%M) printf '09:41\n' ;;
  +%u) printf '1\n' ;;
  *) printf '\n' ;;
esac
EOF
chmod +x "$TMP/fakebin/date"

mkvault v351
printf 'lang=en\n' >> "$TMP/v351/.knotlog/config"
t; CTX351=$(PATH="$TMP/fakebin:$PATH" QUIPU_VAULT="$TMP/v351" QUIPU_LANG=en sh "$ROOT/knotlog" context)
assert_eq "T-351: now line format (date + time + Monday from a known 2024-01-01)" \
  'now: 2024-01-01 09:41 Monday' "$(printf '%s\n' "$CTX351" | head -1)"

mkvault v352
printf 'lang=en\n' >> "$TMP/v352/.knotlog/config"
t; CTX352=$(PATH="$TMP/fakebin:$PATH" QUIPU_VAULT="$TMP/v352" QUIPU_LANG=tr sh "$ROOT/knotlog" context)
assert_eq "T-352: now line in Turkish uses şimdi: and the Turkish day name" \
  'şimdi: 2024-01-01 09:41 Pazartesi' "$(printf '%s\n' "$CTX352" | head -1)"

# T-353: day_1..day_7 exist in both i18n files (i18n data, not a hardcoded
# array) and are non-empty in each.
t; assert_eq "T-353: day_1..day_7 exist and are non-empty in both languages" 'yes' \
  "$(_ok=yes
     for _n in 1 2 3 4 5 6 7; do
       for _f in "$ROOT/i18n/en.txt" "$ROOT/i18n/tr.txt"; do
         # awk gotcha: a bare `exit` inside the main body still runs END --
         # found=1/0 decides the outcome there, instead of a body-side exit
         # code that END would silently override.
         awk -F= -v k="day_$_n" '$1==k{v=$0; sub(/^[^=]*=/,"",v); found=(v!=""); exit} END{exit !found}' "$_f" || _ok=no
       done
     done
     printf '%s' "$_ok")"

# T-354: the now line also appears in --json (hook envelope) output, so any
# hook-driven agent (Claude Code's SessionStart included) sees the time too.
mkvault v354
printf 'lang=en\n' >> "$TMP/v354/.knotlog/config"
t; J354=$(PATH="$TMP/fakebin:$PATH" QUIPU_VAULT="$TMP/v354" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart)
D354=$(printf '%s' "$J354" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "T-354: --json envelope carries the now line" 'now: 2024-01-01 09:41 Monday' "$(printf '%s\n' "$D354" | head -1)"

# T-355: the now line also lands in --bridge output (AGENTS.md/CLAUDE.md),
# the hook-less path a Codex/omp session reads.
mkvault v355
printf 'lang=en\n' >> "$TMP/v355/.knotlog/config"
: > "$TMP/v355/AGENTS.md"
: > "$TMP/v355/CLAUDE.md"
t; PATH="$TMP/fakebin:$PATH" QUIPU_VAULT="$TMP/v355" QUIPU_LANG=en sh "$ROOT/knotlog" context --bridge >/dev/null 2>&1
assert_eq "T-355: --bridge writes the now line into AGENTS.md" 'yes' \
  "$(grep -qF 'now: 2024-01-01 09:41 Monday' "$TMP/v355/AGENTS.md" && printf yes || printf no)"
t; assert_eq "T-355: --bridge writes the now line into CLAUDE.md" 'yes' \
  "$(grep -qF 'now: 2024-01-01 09:41 Monday' "$TMP/v355/CLAUDE.md" && printf yes || printf no)"

# T-356: the now line appears even in a brand-new, wholly empty vault (no
# activity.log, no index.tsv, no Threads.md) -- it names no vault state.
mkvault v356
printf 'lang=en\n' >> "$TMP/v356/.knotlog/config"
t; CTX356=$(PATH="$TMP/fakebin:$PATH" QUIPU_VAULT="$TMP/v356" QUIPU_LANG=en sh "$ROOT/knotlog" context)
assert_eq "T-356: now line present in a wholly empty vault" 'now: 2024-01-01 09:41 Monday' "$(printf '%s\n' "$CTX356" | head -1)"

# T-357: the now line is counted in the FIXED part of the Threads.md budget
# (quipu ~2436's _q_fixed), not left out of it -- a tiny QUIPU_CTX_MAX still
# keeps total output within budget even though a "now:" line was added
# ahead of everything else. Reuses T-346's oversized Threads.md.
t; CTX357=$(PATH="$TMP/fakebin:$PATH" QUIPU_CTX_MAX=150 QUIPU_VAULT="$TMP/v346" QUIPU_LANG=en sh "$ROOT/knotlog" context)
SIZE357=$(printf '%s' "$CTX357" | LC_ALL=C wc -c | tr -d ' ')
assert_eq "T-357: now line is charged against the ctx_max budget, not free" 'yes' \
  "$([ "$SIZE357" -le 150 ] && printf yes || printf no)"
t; assert_eq "T-357: now line still present under a tiny budget" 'yes' \
  "$(printf '%s\n' "$CTX357" | head -1 | grep -qF 'now: 2024-01-01 09:41 Monday' && printf yes || printf no)"


# ---- B2 + B8: persona templates and the amnesia test (T-358..T-363) ----
#
# B2: persona/tr.md and persona/en.md are the printf FORMAT strings that seed
# companion.md (quipu ~1167). They used to hand the user empty angle-bracket
# placeholders nobody filled, so the persona was dead on arrival. The new
# template ships a working default, a "do not fill by hand — tell the agent
# 'interview me'" directive, and a per-heading "what this asks of the agent:"
# line. These tests lock all three properties; T-228/T-264 (exactly two %s)
# and the frontmatter/backslash gates above keep locking the printf contract.

# T-358: no empty angle-bracket placeholder survives in either persona file.
# Persona carries no HTML comments, so ANY <...> match is a leftover
# placeholder -- the grep must find nothing at all.
t; assert_eq "B2 T-358: persona/en.md has no empty <> placeholder" 'yes' \
  "$(! grep -Eq '<[^<>]*>' "$ROOT/persona/en.md" && printf yes || printf no)"
t; assert_eq "B2 T-358: persona/tr.md has no empty <> placeholder" 'yes' \
  "$(! grep -Eq '<[^<>]*>' "$ROOT/persona/tr.md" && printf yes || printf no)"

# T-359: the interview directive is present verbatim in both languages --
# the anchor strings are the template's own words, so a rewritten directive
# fails here until the test is consciously updated too.
t; assert_eq "B2 T-359: persona/tr.md says 'bana mülakat yap'" 'yes' \
  "$(grep -qF 'bana mülakat yap' "$ROOT/persona/tr.md" && printf yes || printf no)"
t; assert_eq "B2 T-359: persona/en.md says 'interview me'" 'yes' \
  "$(grep -qF 'interview me' "$ROOT/persona/en.md" && printf yes || printf no)"

# T-360: one "asks of the agent" line per heading -- Rol/Üslup/Sınırlar/
# Kontrol noktaları and Role/Tone/Boundaries/Checkpoints each carry exactly
# one; zero or two turns the persona back into decoration. (D6 added the
# checkpoint heading WITH its own asks-of-the-agent line, so the pin moves
# 3 -> 4 consciously -- the same "update the test when the data changes"
# contract T-359's anchors carry above.)
t; assert_eq "B2 T-360: persona/tr.md has one asks-of-the-agent line per heading" '4' \
  "$(grep -cF 'Bunun ajana yüklediği:' "$ROOT/persona/tr.md")"
t; assert_eq "B2 T-360: persona/en.md has one asks-of-the-agent line per heading" '4' \
  "$(grep -cF 'What this asks of the agent:' "$ROOT/persona/en.md")"

# T-361: the shipped project templates had the same disease -- an empty
# <"bitti" nasıl görünüyor> / <what does "done" look like> under Hedef/Goal.
# Both now carry a working default plus the interview directive. The guard is
# '<' not followed by '!', so the HTML-comment guidance lines never count as
# placeholders.
t; assert_eq "B2 T-361: templates/tr/project.md has no empty <> placeholder" 'yes' \
  "$(! grep -Eq '<[^!]' "$ROOT/templates/tr/project.md" && printf yes || printf no)"
t; assert_eq "B2 T-361: templates/en/project.md has no empty <> placeholder" 'yes' \
  "$(! grep -Eq '<[^!]' "$ROOT/templates/en/project.md" && printf yes || printf no)"
t; assert_eq "B2 T-361: templates/tr/project.md carries the interview directive" 'yes' \
  "$(grep -qF 'bana mülakat yap' "$ROOT/templates/tr/project.md" && printf yes || printf no)"
t; assert_eq "B2 T-361: templates/en/project.md carries the interview directive" 'yes' \
  "$(grep -qF 'interview me' "$ROOT/templates/en/project.md" && printf yes || printf no)"

# B8: the README's amnesia test is announcement material -- the section must
# exist, name the restart step, and quote the one question, because a section
# that drifts into vagueness stops being a reproducible proof.

# T-362: README.md carries the amnesia test section with its three steps.
t; assert_eq "B8 T-362: README has the amnesia test section" 'yes' \
  "$(grep -qF '## The amnesia test' "$ROOT/README.md" && printf yes || printf no)"
t; assert_eq "B8 T-362: amnesia test names the restart step" 'yes' \
  "$(grep -qF 'Restart the machine' "$ROOT/README.md" && printf yes || printf no)"
t; assert_eq "B8 T-362: amnesia test quotes the one question" 'yes' \
  "$(grep -qF 'What did we do yesterday?' "$ROOT/README.md" && printf yes || printf no)"

# T-363: the Turkish guide carries the same section (numbered, so the manual's
# 10->11 renumber is part of the lock) and quotes the Turkish question.
t; assert_eq "B8 T-363: GUIDE.tr.md has the amnezi testi section" 'yes' \
  "$(grep -qF '## 10. Amnezi testi' "$ROOT/docs/GUIDE.tr.md" && printf yes || printf no)"
t; assert_eq "B8 T-363: GUIDE.tr.md quotes the Turkish question" 'yes' \
  "$(grep -qF 'Dün ne yapmıştık?' "$ROOT/docs/GUIDE.tr.md" && printf yes || printf no)"
t; assert_eq "B8 T-363: GUIDE.tr.md renumbered Ayrılmak to 11" 'yes' \
  "$(grep -qF '## 11. Ayrılmak' "$ROOT/docs/GUIDE.tr.md" && printf yes || printf no)"

# ---- B1: sır kapanı / secret gate (T-364..T-372) ----
#
# `knotlog init --git` (ve `install`) kasaya .githooks/pre-commit kurup
# core.hooksPath=.githooks ayarlar. Hook, staged eklenen (+) satırlarda
# bilinen sır desenlerini arar; bulursa commit'i reddeder. Kaçış:
# QUIPU_SKIP_SECRET_SCAN=1; PATH'te sir-tara varsa tarama ona devredilir.

mkrepo() {
  mkvault "$1"
  (cd "$TMP/$1" && git init -q && git config user.email test@example.test \
     && git config user.name test) >/dev/null 2>&1
}

# T-364: init --git the hook and hooksPath are installed together.
mkrepo v364
t; QUIPU_VAULT="$TMP/v364" QUIPU_LANG=en sh "$ROOT/knotlog" init --git --no-prompt \
  --user test >/dev/null 2>&1; RC364=$?
assert_eq "B1 T-364: init --git exits 0" '0' "$RC364"
t; assert_eq "B1 T-364: .githooks/pre-commit matches the shipped hook and is executable" 'yes' \
  "$(cmp -s "$ROOT/hooks/pre-commit" "$TMP/v364/.githooks/pre-commit" \
     && [ -x "$TMP/v364/.githooks/pre-commit" ] && printf yes || printf no)"
t; assert_eq "B1 T-364: core.hooksPath points at .githooks" '.githooks' \
  "$(cd "$TMP/v364" && git config core.hooksPath)"

# T-365: a vault that is not a git repository root still gets an informative
# line (never silent, never an error).
mkvault v365
t; O365=$(QUIPU_VAULT="$TMP/v365" QUIPU_LANG=en sh "$ROOT/knotlog" init --no-prompt \
  --user test 2>/dev/null); RC365=$?
assert_eq "B1 T-365: init on a non-git vault exits 0" '0' "$RC365"
t; assert_eq "B1 T-365: non-git vault is told the gate was skipped" 'yes' \
  "$(printf '%s\n' "$O365" | grep -qF 'Secret gate not installed' && printf yes || printf no)"

# T-366: the end-to-end gate — a clean baseline commit passes, a staged
# token line is rejected with the file name, a clean commit then passes.
mkrepo v366
QUIPU_VAULT="$TMP/v366" QUIPU_LANG=en sh "$ROOT/knotlog" init --git --no-prompt \
  --user test >/dev/null 2>&1
printf 'temiz not\n' > "$TMP/v366/Temiz.md"
t; (cd "$TMP/v366" && git add -A && git commit -qm base) >/dev/null 2>"$TMP/v366-base.err"; RC366=$?
assert_eq "B1 T-366: baseline clean commit passes" '0' "$RC366"
printf 'anahtar token=sk-abcdefghijklmnopqrstuvwxyz123456\n' > "$TMP/v366/Notlar.md"
t; (cd "$TMP/v366" && git add Notlar.md && git commit -qm leak) >/dev/null \
  2>"$TMP/v366-leak.err"; RC366L=$?
assert_eq "B1 T-366: staged token line is rejected" '1' "$RC366L"
t; assert_eq "B1 T-366: rejection names the offending file" 'yes' \
  "$(grep -qF 'Notlar.md' "$TMP/v366-leak.err" && printf yes || printf no)"
t; assert_eq "B1 T-366: rejection documents the --no-verify escape" 'yes' \
  "$(grep -qF -- '--no-verify' "$TMP/v366-leak.err" && printf yes || printf no)"
t; (cd "$TMP/v366" && git reset -q && printf 'ikinci temiz not\n' > Temiz2.md \
  && git add Temiz2.md && git commit -qm clean) >/dev/null 2>&1; RC366C=$?
assert_eq "B1 T-366: clean diff passes after the rejection" '0' "$RC366C"

# T-367: the single-commit escape hatch.
t; (cd "$TMP/v366" && git add Notlar.md && QUIPU_SKIP_SECRET_SCAN=1 git commit -qm esc) \
  >/dev/null 2>&1; RC367=$?
assert_eq "B1 T-367: QUIPU_SKIP_SECRET_SCAN=1 lets the commit through" '0' "$RC367"

# T-368: an external sir-tara on PATH takes the scan over entirely — its
# message and exit verdict replace quipu's own scan.
mkdir -p "$TMP/sirbin"
cat > "$TMP/sirbin/sir-tara" <<'EOF'
#!/bin/sh
printf 'sir-tara: kendi raporum\n' >&2
exit 3
EOF
chmod +x "$TMP/sirbin/sir-tara"
mkrepo v368
QUIPU_VAULT="$TMP/v368" QUIPU_LANG=en sh "$ROOT/knotlog" init --git --no-prompt \
  --user test >/dev/null 2>&1
printf 'token=abc12345678\n' > "$TMP/v368/Not.md"
t; (cd "$TMP/v368" && git add Not.md && PATH="$TMP/sirbin:$PATH" git commit -qm deleg) \
  >/dev/null 2>"$TMP/v368-deleg.err"; RC368=$?
assert_eq "B1 T-368: sir-tara's rejection blocks the commit" '1' "$RC368"
t; assert_eq "B1 T-368: sir-tara's own message surfaces" 'yes' \
  "$(grep -qF 'sir-tara: kendi raporum' "$TMP/v368-deleg.err" && printf yes || printf no)"
t; assert_eq "B1 T-368: quipu's own scan did not run" 'no' \
  "$(grep -qF 'secret gate' "$TMP/v368-deleg.err" && printf yes || printf no)"
printf '#!/bin/sh\nexit 0\n' > "$TMP/sirbin/sir-tara"
chmod +x "$TMP/sirbin/sir-tara"
t; (cd "$TMP/v368" && PATH="$TMP/sirbin:$PATH" git commit -qm deleg-ok) \
  >/dev/null 2>&1; RC368O=$?
assert_eq "B1 T-368: an approving sir-tara lets the commit through" '0' "$RC368O"

# T-369: re-running init is idempotent — the hook stays byte-identical.
mkrepo v369
QUIPU_VAULT="$TMP/v369" QUIPU_LANG=en sh "$ROOT/knotlog" init --git --no-prompt \
  --user test >/dev/null 2>&1
t; QUIPU_VAULT="$TMP/v369" QUIPU_LANG=en sh "$ROOT/knotlog" init --git --no-prompt \
  --user test >/dev/null 2>&1; RC369=$?
assert_eq "B1 T-369: re-init over an installed gate exits 0" '0' "$RC369"
t; assert_eq "B1 T-369: re-init keeps the hook byte-identical" 'yes' \
  "$(cmp -s "$ROOT/hooks/pre-commit" "$TMP/v369/.githooks/pre-commit" \
     && printf yes || printf no)"

# T-370: a marker-less, hand-edited pre-commit is never overwritten —
# quipu warns and passes, and does not touch hooksPath either.
mkrepo v370
QUIPU_VAULT="$TMP/v370" QUIPU_LANG=en sh "$ROOT/knotlog" init --git --no-prompt \
  --user test >/dev/null 2>&1
printf '# benim kendi hookum\necho merhaba\n' > "$TMP/v370/.githooks/pre-commit"
t; O370=$(QUIPU_VAULT="$TMP/v370" QUIPU_LANG=en sh "$ROOT/knotlog" init --no-prompt \
  --user test 2>&1); RC370=$?
assert_eq "B1 T-370: init over a hand-edited hook exits 0" '0' "$RC370"
t; assert_eq "B1 T-370: hand-edited hook is left byte-for-byte in place" 'yes' \
  "$(grep -qF 'benim kendi hookum' "$TMP/v370/.githooks/pre-commit" \
     && printf yes || printf no)"
t; assert_eq "B1 T-370: the preservation is reported, not silent" 'yes' \
  "$(printf '%s\n' "$O370" | grep -qF 'Secret gate preserved' && printf yes || printf no)"

# T-371: the same reporting is localized on the Turkish path.
mkvault v371
t; O371=$(QUIPU_VAULT="$TMP/v371" QUIPU_LANG=tr sh "$ROOT/knotlog" init --no-prompt \
  --user test 2>&1)
assert_eq "B1 T-371: Turkish init reports the skip in Turkish" 'yes' \
  "$(printf '%s\n' "$O371" | grep -qF 'Sır kapanı kurulmadı' && printf yes || printf no)"

# T-372: the shipped hook itself is disciplined — it carries the quipu
# marker (the idempotency key), both message languages, the escape knob,
# and never matches its own source.
t; assert_eq "B1 T-372: shipped hook carries the quipu marker" 'yes' \
  "$(grep -qF 'knotlog:secret-scan' "$ROOT/hooks/pre-commit" && printf yes || printf no)"
t; assert_eq "B1 T-372: shipped hook offers both message languages" 'yes' \
  "$(grep -qF 'sır kapanı' "$ROOT/hooks/pre-commit" \
     && grep -qF 'secret gate' "$ROOT/hooks/pre-commit" && printf yes || printf no)"
PAT372=$(sed -n "s/^_pat='\(.*\)'$/\1/p" "$ROOT/hooks/pre-commit")
t; assert_eq "B1 T-372: shipped hook never matches its own source" '0' \
  "$(LC_ALL=C grep -Eic "$PAT372" "$ROOT/hooks/pre-commit")"

# ---- B7: one-line installer (install.sh) ----

# T-373: static shape -- the Fornhere B7 security pattern: all logic lives in
# main(), the only top-level statement is the final call, set -eu is on, and
# the version anchor the verifier greps for is declared.
INST="$ROOT/install.sh"
t; assert_eq "B7 T-373: install.sh exists and is executable" 'yes' \
  "$([ -x "$INST" ] && printf yes || printf no)"
t; assert_eq "B7 T-373: set -eu guards the installer" 'yes' \
  "$(grep -qx 'set -eu' "$INST" && printf yes || printf no)"
t; assert_eq "B7 T-373: all logic lives in main()" 'yes' \
  "$(grep -q '^main() {' "$INST" && printf yes || printf no)"
t; assert_eq "B7 T-373: the only top-level statement is the final main() call" 'main "$@"' \
  "$(sed -n '$p' "$INST")"
B7ANCHOR=$(sed -n 's/^_q_anchor="\(.*\)"$/\1/p' "$INST")
t; assert_eq "B7 T-373: the version anchor is declared once and is greppable" 'yes' \
  "$(grep -qF -- "$B7ANCHOR" "$INST" && printf yes || printf no)"

# T-374: the happy path, fully offline -- a fake release tarball served from a
# file:// URL with the extracted quipu mocked; download, unpack, verify and
# hand-over are the real code under test.
B7="$TMP/b7"
mkdir -p "$B7/pkg/Knotlog-1.0.0"
cat > "$B7/pkg/Knotlog-1.0.0/knotlog" <<EOF
#!/bin/sh
# $B7ANCHOR
printf '%s\n' "\$*" >> "$B7/calls"
touch "$B7/mock-ran"
EOF
chmod +x "$B7/pkg/Knotlog-1.0.0/knotlog"
tar -czf "$B7/good.tar.gz" -C "$B7/pkg" Knotlog-1.0.0
# Native curl on Windows cannot open a POSIX file:// path; cygpath rewrites
# the staging dir as a drive path the real curl accepts. POSIX shells keep
# the plain form.
case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*) B7URL="file:///$(cygpath -m "$B7")" ;;
  *) B7URL="file://$B7" ;;
esac
B7PARENT="$TMP/b7parent"
mkdir -p "$B7PARENT"
t; GITHUB_RELEASE_URL="$B7URL/good.tar.gz" QUIPU_INSTALL_DIR="$B7PARENT/tool" \
  sh "$INST" --no-prompt --user Ada >/dev/null 2>"$B7/good.err"; RC374=$?
t; assert_eq "B7 T-374: the verified archive installs end to end" '0' "$RC374"
t; assert_eq "B7 T-374: arguments are forwarded to knotlog install" 'install --no-prompt --user Ada' \
  "$(cat "$B7/calls")"
t; assert_eq "B7 T-374: the unpacked quipu actually ran" 'yes' \
  "$([ -f "$B7/mock-ran" ] && printf yes || printf no)"
t; assert_eq "B7 T-374: the checkout lands in QUIPU_INSTALL_DIR" 'yes' \
  "$([ -x "$B7PARENT/tool/knotlog" ] && printf yes || printf no)"
t; assert_eq "B7 T-374: staging directories are swept" '.knotlog-install.*' \
  "$(cd "$B7PARENT" && printf '%s\n' .knotlog-install.*)"

# T-375: an archive whose quipu does not carry the anchor stops the install.
mkdir -p "$B7/badpkg/Knotlog-1.0.0"
printf '#!/bin/sh\necho impostor, no anchor here\n' > "$B7/badpkg/Knotlog-1.0.0/knotlog"
chmod +x "$B7/badpkg/Knotlog-1.0.0/knotlog"
tar -czf "$B7/bad.tar.gz" -C "$B7/badpkg" Knotlog-1.0.0
t; GITHUB_RELEASE_URL="$B7URL/bad.tar.gz" QUIPU_INSTALL_DIR="$B7PARENT/bad-dest" \
  sh "$INST" >/dev/null 2>"$B7/bad.err"; RC375=$?
t; assert_eq "B7 T-375: an archive without the anchor is refused" '1' "$RC375"
t; assert_eq "B7 T-375: the refusal names verification" 'yes' \
  "$(grep -qF 'verification failed' "$B7/bad.err" && printf yes || printf no)"
t; assert_eq "B7 T-375: nothing was unpacked into the install dir" 'no' \
  "$([ -e "$B7PARENT/bad-dest" ] && printf yes || printf no)"
# T-376: a truncated or failing download is a clean error, never an install.
mkdir -p "$B7/badcurl" "$B7/badcurl2"
dd if="$B7/good.tar.gz" of="$B7/trunc.tar.gz" bs=1 count=150 2>/dev/null
cat > "$B7/badcurl/curl" <<EOF
#!/bin/sh
cat "$B7/trunc.tar.gz"
EOF
chmod +x "$B7/badcurl/curl"
t; PATH="$B7/badcurl:$PATH" GITHUB_RELEASE_URL="$B7URL/good.tar.gz" \
  QUIPU_INSTALL_DIR="$B7PARENT/trunc-dest" sh "$INST" >/dev/null 2>"$B7/trunc.err"; RC376=$?
t; assert_eq "B7 T-376: a truncated download never installs" '1' "$RC376"
t; assert_eq "B7 T-376: the failure names the corrupt archive" 'yes' \
  "$(grep -qF 'truncated or corrupt' "$B7/trunc.err" && printf yes || printf no)"
t; assert_eq "B7 T-376: no checkout survives a truncated download" 'no' \
  "$([ -e "$B7PARENT/trunc-dest" ] && printf yes || printf no)"
printf '#!/bin/sh\nexit 1\n' > "$B7/badcurl2/curl"
chmod +x "$B7/badcurl2/curl"
t; PATH="$B7/badcurl2:$PATH" GITHUB_RELEASE_URL="$B7URL/good.tar.gz" \
  QUIPU_INSTALL_DIR="$B7PARENT/fail-dest" sh "$INST" >/dev/null 2>"$B7/fail.err"; RC376F=$?
t; assert_eq "B7 T-376: a failing download is reported as such" '1' "$RC376F"
t; assert_eq "B7 T-376: the download failure is named" 'yes' \
  "$(grep -qF 'download failed' "$B7/fail.err" && printf yes || printf no)"

# T-377: without curl on PATH, wget takes the download over -- the suite
# proves it with a restricted PATH holding only the tools install.sh needs
# plus a file://-capable wget shim, so no real curl can be found.
B7W="$B7/wbin"
mkdir -p "$B7W"
for b in sh tar gzip grep sed rm mkdir chmod ls dirname cat mv env touch; do
  # skip anything that resolves without a slash (a builtin): the restricted
  # PATH must hold real external binaries only. The suite wraps grep in a
  # shell function (LC_ALL=C), and `command -v` reports a function by its bare
  # name -- so drop any function of that name inside the lookup's subshell,
  # or grep is skipped and install.sh dies with "grep: command not found".
  p=$(unset -f "$b" 2>/dev/null; command -v "$b" 2>/dev/null) || continue
  case $p in
    */*)
      case $(uname -s) in
        # MSYS PATH search resolves name -> name.exe; an extensionless copy
        # of a PE binary is never found there (T-377 died with 127 on the
        # very first lookup), so on Windows the tools ship under .exe names.
        MINGW*|MSYS*|CYGWIN*) cp -f "$p" "$B7W/$b.exe" ;;
        *) ln -sf "$p" "$B7W/$b" ;;
      esac ;;
  esac
done
case $(uname -s) in
  # MSYS binaries load their runtime DLLs from the directory next to the
  # executable (the loader, not PATH); with a restricted PATH the copies in
  # B7W cannot see /usr/bin, so the runtime must ship with the tools
  # (T-377 died with 127 on the very first copied binary otherwise).
  MINGW*|MSYS*|CYGWIN*) for _dll in /usr/bin/msys-*.dll; do
      [ -f "$_dll" ] && cp -f "$_dll" "$B7W/"
    done ;;
  *) : ;;
esac
cat > "$B7W/wget" <<'EOF'
#!/bin/sh
# emulates: wget -qO <out> -- <file://url>; the drive-letter form (native
# curl on Windows) strips one slash more than the POSIX form
case $4 in
  file:///[A-Za-z]:/*) cat "${4#file:///}" > "$2" ;;
  file://*) cat "${4#file://}" > "$2" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$B7W/wget"
: > "$B7/calls"
rm -f "$B7/mock-ran"
t; PATH="$B7W" GITHUB_RELEASE_URL="$B7URL/good.tar.gz" \
  QUIPU_INSTALL_DIR="$B7PARENT/wget-dest" /bin/sh "$INST" --no-prompt --user Ada \
  >/dev/null 2>"$B7/wget.err"; RC377=$?
t; assert_eq "B7 T-377: without curl, wget takes the download over" '0' "$RC377"
if [ "$RC377" != 0 ]; then
  t; not_ok "B7 T-377 diagnostic: rc=$RC377 err=[$(cat "$B7/wget.err" 2>&1)] tools=[$(cd "$B7W" && find . -type f 2>&1 | tr '\n' ' ')]"
fi
t; assert_eq "B7 T-377: the wget path forwards arguments the same way" 'install --no-prompt --user Ada' \
  "$(cat "$B7/calls")"
t; assert_eq "B7 T-377: the wget install also lands in QUIPU_INSTALL_DIR" 'yes' \
  "$([ -x "$B7PARENT/wget-dest/knotlog" ] && printf yes || printf no)"

# T-378: the defaults are pinned where users can see them -- the release URL
# points at the GitHub archive and the README leads Install with the one line.
t; assert_eq "B7 T-378: the default URL is the pinned GitHub release archive" 'yes' \
  "$(grep -qF 'https://github.com/MSelmanSonmez/Knotlog/archive/refs/tags/' "$INST" \
     && printf yes || printf no)"
t; assert_eq "B7 T-378: README leads Install with the one-line command" 'yes' \
  "$(grep -qF 'curl -fsSL https://raw.githubusercontent.com/MSelmanSonmez/Knotlog/main/install.sh | sh' \
     "$ROOT/README.md" && printf yes || printf no)"
t; assert_eq "release 1.2.0: update defaults point at MSelmanSonmez/Knotlog" 'yes' \
  "$(grep -qF 'https://api.github.com/repos/MSelmanSonmez/Knotlog/releases/latest' "$ROOT/knotlog" \
     && grep -qF 'https://github.com/MSelmanSonmez/Knotlog/releases/download/v$_q_up_latest/knotlog-$_q_up_latest.tar.gz' "$ROOT/knotlog" \
     && grep -qF 'archive/refs/tags/v1.2.0.tar.gz' "$INST" && printf yes || printf no)"
t; assert_eq "release 1.1.1: no shipped file mentions SelmanBuilds" '' \
  "$(cd "$ROOT" && grep -rIil selmanbuilds . --exclude-dir=.git --exclude-dir=tests \
     --exclude=ORCHESTRATOR_LOG.md --exclude='CHANGELOG*' 2>/dev/null)"
t; assert_eq "release 1.1.1: the banner is icon/knotlog-banner.png" 'yes' \
  "$([ -f "$ROOT/icon/knotlog-banner.png" ] && [ ! -e "$ROOT/icon/quipu-banner.png" ] \
     && grep -qF 'icon/knotlog-banner.png' "$ROOT/README.md" && printf yes || printf no)"


# ---- Hafıza sapması denetimi (D1..D5, D7): T-379..T-397 --------------------
#
# Narrative memory drift audits, born from a real incident: the vault's
# memory files were renamed in the field and the hooks silently missed them
# for a whole session. Two invariants run through every test below. First,
# a vault with NO hand-written narrative memory (fresh init, remember-only)
# must keep doctor's exit code and row count exactly as before -- T-299 pins
# the fresh-vault summary line, T-77 pins the remember-chain vault at zero
# fails, and both stay green untouched. Second, the audits must work in BOTH
# directions: "the auditor says ok" is not verification (the same night the
# vault tool validated an invented widget name), so every positive finding
# here has a negative twin asserting the warning disappears again.
#
# doctor is invoked WITHOUT QUIPU_LANG on purpose: the vault's own
# config lang= must decide the expected file names (constraint: an English
# vault expects the English names, from config, not from the caller's env).

mi18n() { # lang key -> raw i18n value from that language's file
  awk -F= -v k="$2" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/$1.txt"
}
mtr() { # tr i18n value (row names/status words in the vault's language)
  mi18n tr "$1"
}
memfmt() { # lang key [args...] -> i18n value printf'd as the controlled format
  _mf_l=$1
  _mf_k=$2
  shift 2
  # shellcheck disable=SC2059 # i18n values are the project's controlled format strings
  printf "$(mi18n "$_mf_l" "$_mf_k")" "$@"
}
men() { # en i18n value (row names/status words for an en vault)
  mi18n en "$1"
}

mkenmem() { # name lang -- vault carrying the full narrative memory set
  mkdir -p "$TMP/$1/.knotlog"
  printf 'lang=%s\n' "$2" > "$TMP/$1/.knotlog/config"
  if [ "$2" = tr ]; then
    printf 'session\n' > "$TMP/$1/Son-Oturum.md"
    printf 'rules\n' > "$TMP/$1/Kurallar.md"
    printf 'core\n' > "$TMP/$1/Çekirdek.md"
    printf 'journal\n' > "$TMP/$1/Günlük.md"
    printf 'threads\n' > "$TMP/$1/Konular.md"
  else
    printf 'session\n' > "$TMP/$1/Last-Session.md"
    printf 'rules\n' > "$TMP/$1/Rules.md"
    printf 'core\n' > "$TMP/$1/Core.md"
    printf 'journal\n' > "$TMP/$1/Journal.md"
    printf 'threads\n' > "$TMP/$1/Threads.md"
  fi
  printf '# bridge\n' > "$TMP/$1/AGENTS.md"
  printf '# bridge\n' > "$TMP/$1/CLAUDE.md"
}

memfailcount() { # doctor-output-file -> the summary line's trailing fail number
  # The summary is the last line and its LAST number is the fail count; the
  # line's wording is i18n (summary:/özet:), so only the position is trusted.
  awk 'END { gsub(/[^0-9]/, " "); n = split($0, f, " "); print f[n] }' "$1"
}

# T-379 (D1): a Turkish vault with the full narrative set gets one ok row.
mkenmem td1ok tr
t; (cd "$TMP/td1ok" && "$ROOT/knotlog" doctor) >"$TMP/td1ok.out" 2>&1; RC=$?
assert_eq "D1 T-379: a full tr memory set exits 0" '0' "$RC"
t; assert_eq "D1 T-379: the full set prints exactly one ok row 5/5" 'yes' \
  "$(awk -F"$TAB" -v s="$(mtr doc_ok)" -v n="$(mtr doc_mem)" \
       -v d="$(memfmt tr doc_mem_full 5 5)" \
       '$1 == s && $2 == n && $3 == d { f = 1 } END { exit !f }' "$TMP/td1ok.out" \
    && printf yes || printf no)"

# T-380 (D1/SD2): a renamed Son-Oturum is a FAIL row and the exit code is 1.
# This is the binding decision: a missing mandatory memory file breaks
# scripts and CI on purpose, because the motor is crippled.
mkenmem td1miss tr
mv "$TMP/td1miss/Son-Oturum.md" "$TMP/td1miss/Depo.md"
t; (cd "$TMP/td1miss" && "$ROOT/knotlog" doctor) >"$TMP/td1miss.out" 2>&1; RC=$?
assert_eq "D1 T-380: a renamed memory file makes doctor exit 1" '1' "$RC"
t; assert_eq "D1 T-380: the summary counts exactly one fail" '1' "$(memfailcount "$TMP/td1miss.out")"
t; assert_eq "D1 T-380: the fail row names both the current and the legacy name" 'yes' \
  "$(grep -qF 'Son-Oturum.md | Last-Session.md' "$TMP/td1miss.out" && printf yes || printf no)"

# T-381 (D1b): the legacy English name is accepted -- vaults with history
# must not break. Kurallar.md -> Rules.md keeps doctor silent (exit 0, 0 fail).
mkenmem td1leg tr
mv "$TMP/td1leg/Kurallar.md" "$TMP/td1leg/Rules.md"
t; (cd "$TMP/td1leg" && "$ROOT/knotlog" doctor) >"$TMP/td1leg.out" 2>&1; RC=$?
assert_eq "D1b T-381: the legacy English name keeps doctor at exit 0" '0' "$RC"
t; assert_eq "D1b T-381: no fail is counted for the legacy name" '0' "$(memfailcount "$TMP/td1leg.out")"

# T-382 (D1): an English vault expects the English names (config lang=en
# decides, no QUIPU_LANG in play) and reports them in en-first order.
mkenmem td1en en
mv "$TMP/td1en/Last-Session.md" "$TMP/td1en/Taslak.md"
t; (cd "$TMP/td1en" && "$ROOT/knotlog" doctor) >"$TMP/td1en.out" 2>&1; RC=$?
assert_eq "D1 T-382: an en vault with a missing memory file exits 1" '1' "$RC"
t; assert_eq "D1 T-382: the en vault expects the en name first" 'yes' \
  "$(grep -qF 'Last-Session.md | Son-Oturum.md' "$TMP/td1en.out" && printf yes || printf no)"

# T-383 (D2): dead backtick paths inside the live scope warn -- and the
# warning carries the count. RC stays 0: paths warn, only D1 fails.
mkenmem td2 tr
cat > "$TMP/td2/Konular.md" <<'EOF'
Yakalama: `📥 Gelen Kutusu/Dump/` ve `🗂️ Projeler/OlmayanProje/not.md`
EOF
t; (cd "$TMP/td2" && "$ROOT/knotlog" doctor) >"$TMP/td2.out" 2>&1; RC=$?
assert_eq "D2 T-383: dead quoted paths keep the exit code at 0" '0' "$RC"
t; assert_eq "D2 T-383: two dead paths produce one warn with count 2" 'yes' \
  "$(awk -F"$TAB" -v s="$(mtr doc_warn)" -v n="$(mtr doc_paths)" \
       -v d="$(memfmt tr doc_paths_broken 2)" \
       '$1 == s && $2 == n && $3 == d { f = 1 } END { exit !f }' "$TMP/td2.out" \
    && printf yes || printf no)"

# T-384 (D2, körleştirme): removing the dead references silences the row.
# The auditor saying "valid" proves nothing; the negative twin does.
printf 'Temiz konu satiri\n' > "$TMP/td2/Konular.md"
t; (cd "$TMP/td2" && "$ROOT/knotlog" doctor) >"$TMP/td2b.out" 2>&1; RC=$?
assert_eq "D2 T-384: removing the dead paths exits 0" '0' "$RC"
t; assert_eq "D2 T-384: no path row remains after the fix" '0' \
  "$(awk -F"$TAB" -v n="$(mtr doc_paths)" '$2 == n { c++ } END { print c + 0 }' "$TMP/td2b.out")"

# T-385 (D2): the exclusion filter -- home-absolute, root-absolute, URL,
# Windows drive, glob and ellipsis paths never resolve as vault-relative,
# and an existing referenced path is no finding at all.
mkenmem td2x tr
mkdir -p "$TMP/td2x/🗂️ Projeler/Gerçek"
printf 'not\n' > "$TMP/td2x/🗂️ Projeler/Gerçek/not.md"
cat > "$TMP/td2x/Konular.md" <<'EOF'
ev: `~/belgeler/a.md`
kok: `/mutlak/a.md`
url: `https://ornek.com/a.md`
surucu: `C:\Users\x\a.md`
joker: `a/*/b.md`
elips: `a/../b.md`
var: `🗂️ Projeler/Gerçek/not.md`
EOF
t; (cd "$TMP/td2x" && "$ROOT/knotlog" doctor) >"$TMP/td2x.out" 2>&1; RC=$?
assert_eq "D2 T-385: excluded shapes and existing paths exit 0" '0' "$RC"
t; assert_eq "D2 T-385: no path row for excluded shapes or existing targets" '0' \
  "$(awk -F"$TAB" -v n="$(mtr doc_paths)" '$2 == n { c++ } END { print c + 0 }' "$TMP/td2x.out")"

# T-386 (D3): the live/historical split inside Son-Oturum. A dead path in an
# OLD block is history and stays silent; the same dead path in the NEWEST
# block (the last "## " section) warns. Both halves tested, in order.
mkenmem td3 tr
cat > "$TMP/td3/Son-Oturum.md" <<'EOF'
## 2026-09-01

eski blok `🗂️ Projeler/OlmayanProje/eski.md`

## 2026-09-02

yeni blok
EOF
t; (cd "$TMP/td3" && "$ROOT/knotlog" doctor) >"$TMP/td3a.out" 2>&1; RC=$?
assert_eq "D3 T-386: a dead path in the historical block exits 0" '0' "$RC"
t; assert_eq "D3 T-386: the historical block produces no path row" '0' \
  "$(awk -F"$TAB" -v n="$(mtr doc_paths)" '$2 == n { c++ } END { print c + 0 }' "$TMP/td3a.out")"
cat >> "$TMP/td3/Son-Oturum.md" <<'EOF'
ayni olumlu yol `🗂️ Projeler/OlmayanProje/eski.md` en yeni blokta
EOF
t; (cd "$TMP/td3" && "$ROOT/knotlog" doctor) >"$TMP/td3b.out" 2>&1; RC=$?
assert_eq "D3 T-386: the same path in the newest block warns, exit stays 0" '0' "$RC"
t; assert_eq "D3 T-386: the newest block's dead path is caught" 'yes' \
  "$(awk -F"$TAB" -v s="$(mtr doc_warn)" -v n="$(mtr doc_paths)" \
       -v d="$(memfmt tr doc_paths_broken 1)" \
       '$1 == s && $2 == n && $3 == d { f = 1 } END { exit !f }' "$TMP/td3b.out" \
    && printf yes || printf no)"

# T-387..T-389 (D4): uncommitted memory warns; committed memory is silent;
# a vault without git is silent in both the no-repo and the no-binary case.
mkenmem td4 en
git init -q "$TMP/td4"
git_commit td4 init
t; (cd "$TMP/td4" && "$ROOT/knotlog" doctor) >"$TMP/td4a.out" 2>&1; RC=$?
assert_eq "D4 T-387: a committed memory set prints no dirty row" '0' "$RC"
t; assert_eq "D4 T-387: no dirty row on a clean tree" '0' \
  "$(awk -F"$TAB" -v n="$(men doc_mem)" -v d="$(memfmt en doc_mem_dirty 1)" '$2 == n && $3 == d { c++ } END { print c + 0 }' "$TMP/td4a.out")"
printf 'commit edilmemis satir\n' >> "$TMP/td4/AGENTS.md"
t; (cd "$TMP/td4" && "$ROOT/knotlog" doctor) >"$TMP/td4b.out" 2>&1; RC=$?
assert_eq "D4 T-388: uncommitted memory still exits 0 (warn only)" '0' "$RC"
t; assert_eq "D4 T-388: one uncommitted memory file warns with count 1" 'yes' \
  "$(awk -F"$TAB" -v s="$(men doc_warn)" -v n="$(men doc_mem)" \
       -v d="$(memfmt en doc_mem_dirty 1)" \
       '$1 == s && $2 == n && $3 == d { f = 1 } END { exit !f }' "$TMP/td4b.out" \
    && printf yes || printf no)"
git_commit td4 committed
t; (cd "$TMP/td4" && "$ROOT/knotlog" doctor) >"$TMP/td4c.out" 2>&1
t; assert_eq "D4 T-388: committing silences the dirty row again" '0' \
  "$(awk -F"$TAB" -v n="$(men doc_mem)" -v d="$(memfmt en doc_mem_dirty 1)" '$2 == n && $3 == d { c++ } END { print c + 0 }' "$TMP/td4c.out")"
mkenmem td4n en
printf 'commit edilmemis ama git de yok\n' >> "$TMP/td4n/AGENTS.md"
t; (cd "$TMP/td4n" && "$ROOT/knotlog" doctor) >"$TMP/td4n.out" 2>&1; RC=$?
assert_eq "D4 T-389: a non-repo vault with dirty memory exits 0" '0' "$RC"
t; assert_eq "D4 T-389: a non-repo vault never prints the dirty row" '0' \
  "$(awk -F"$TAB" -v n="$(men doc_mem)" -v d="$(memfmt en doc_mem_dirty 1)" '$2 == n && $3 == d { c++ } END { print c + 0 }' "$TMP/td4n.out")"
NOGITBIN="$TMP/nogitbin"
mkdir -p "$NOGITBIN"
for _ngt in sh sed awk grep tr find date head stat mktemp cat wc dirname basename rm mv; do
  ln -sf "$(unset -f "$_ngt" 2>/dev/null; command -v "$_ngt")" "$NOGITBIN/$_ngt"
done
t; (cd "$TMP/td4n" && PATH="$NOGITBIN" "$ROOT/knotlog" doctor) >"$TMP/td4g.out" 2>&1; RC=$?
# The tools section already fails the run on a missing git binary (pre-
# existing behavior); the memory audit must not add a SECOND failure.
assert_eq "D4 T-389: without a git binary only the tools row fails (exit 1)" '1' "$RC"
t; assert_eq "D4 T-389: the fail is the tools git row, never a memory row" 'yes' \
  "$(awk -F"$TAB" -v s="$(men doc_fail)" '$1 == s && $2 != "git" { f = 1 } END { exit !f }' "$TMP/td4g.out" \
    && printf no || printf yes)"
t; assert_eq "D4 T-389: without a git binary the dirty row stays silent" '0' \
  "$(awk -F"$TAB" -v n="$(men doc_mem)" -v d="$(memfmt en doc_mem_dirty 1)" '$2 == n && $3 == d { c++ } END { print c + 0 }' "$TMP/td4g.out")"

# T-390..T-391 (D5): the midnight trap. A session block can open the
# previous day and cross midnight, so today's date is searched in the WHOLE
# newest block -- never just the heading.
mkenmem td5 en
git init -q "$TMP/td5"
printf '## 2026-01-01 23:50\n\nGece yarisini gecen oturum; kayit %s tarihine dustu.\n' "$(date +%F)" \
  > "$TMP/td5/Last-Session.md"
git_commit td5 init
t; (cd "$TMP/td5" && "$ROOT/knotlog" doctor) >"$TMP/td5a.out" 2>&1; RC=$?
assert_eq "D5 T-390: yesterday-headed block mentioning today exits 0" '0' "$RC"
t; assert_eq "D5 T-390: no stale-session row when the block body has today" '0' \
  "$(awk -F"$TAB" -v n="$(men doc_session)" '$2 == n { c++ } END { print c + 0 }' "$TMP/td5a.out")"
printf '## 2026-01-01 23:50\n\nBayat blok; icinde bugunun tarihi yok.\n' > "$TMP/td5/Last-Session.md"
t; (cd "$TMP/td5" && "$ROOT/knotlog" doctor) >"$TMP/td5b.out" 2>&1; RC=$?
assert_eq "D5 T-391: a stale newest block still exits 0 (warn only)" '0' "$RC"
t; assert_eq "D5 T-391: a block without today's date warns as stale" 'yes' \
  "$(awk -F"$TAB" -v s="$(men doc_warn)" -v n="$(men doc_session)" \
       -v d="$(memfmt en doc_session_stale "$(date +%F)")" \
       '$1 == s && $2 == n && $3 == d { f = 1 } END { exit !f }' "$TMP/td5b.out" \
    && printf yes || printf no)"
# ...and the flip side: with NO commit from today, the stale block is nobody's
# business (the freshness claim is "a commit from today exists").
mkenmem td5n en
git init -q "$TMP/td5n"
printf '## 2026-01-01\n\nBayat ama bugun commit de yok.\n' > "$TMP/td5n/Last-Session.md"
GIT_AUTHOR_DATE='2026-01-01T10:00:00' GIT_COMMITTER_DATE='2026-01-01T10:00:00' \
  git -C "$TMP/td5n" add -A
GIT_AUTHOR_DATE='2026-01-01T10:00:00' GIT_AUTHOR_EMAIL=t@t GIT_AUTHOR_NAME=t \
  GIT_COMMITTER_DATE='2026-01-01T10:00:00' GIT_COMMITTER_EMAIL=t@t GIT_COMMITTER_NAME=t \
  git -C "$TMP/td5n" commit -qm old
t; (cd "$TMP/td5n" && "$ROOT/knotlog" doctor) >"$TMP/td5n.out" 2>&1; RC=$?
assert_eq "D5 T-391: no commit from today exits 0" '0' "$RC"
t; assert_eq "D5 T-391: no commit from today means no stale row" '0' \
  "$(awk -F"$TAB" -v n="$(men doc_session)" '$2 == n { c++ } END { print c + 0 }' "$TMP/td5n.out")"

# T-392 (D7): a quoted reference into git-ignored territory warns separately
# ("works on this machine, breaks on clone"), alongside -- never instead of
# -- the dead-path warning.
mkenmem td7 en
mkdir -p "$TMP/td7/scratch"
printf 'x\n' > "$TMP/td7/scratch/n.md"
printf 'scratch/\n' > "$TMP/td7/.gitignore"
cat > "$TMP/td7/AGENTS.md" <<'EOF'
Cop kutusu: `scratch/n.md` ve olu yol: `olmayan/dizin/a.md`
EOF
git init -q "$TMP/td7"
git_commit td7 init
t; (cd "$TMP/td7" && "$ROOT/knotlog" doctor) >"$TMP/td7a.out" 2>&1; RC=$?
assert_eq "D7 T-392: an ignored-target reference exits 0" '0' "$RC"
t; assert_eq "D7 T-392: the ignored reference warns as breaks-on-clone" 'yes' \
  "$(awk -F"$TAB" -v s="$(men doc_warn)" -v n="$(men doc_paths)" \
       -v d="$(memfmt en doc_paths_ignored 1)" \
       '$1 == s && $2 == n && $3 == d { f = 1 } END { exit !f }' "$TMP/td7a.out" \
    && printf yes || printf no)"
t; assert_eq "D7 T-392: the dead reference still warns as broken, independently" 'yes' \
  "$(awk -F"$TAB" -v s="$(men doc_warn)" -v n="$(men doc_paths)" \
       -v d="$(memfmt en doc_paths_broken 1)" \
       '$1 == s && $2 == n && $3 == d { f = 1 } END { exit !f }' "$TMP/td7a.out" \
    && printf yes || printf no)"
printf 'Temiz satir\n' > "$TMP/td7/AGENTS.md"
git_commit td7 clean
t; (cd "$TMP/td7" && "$ROOT/knotlog" doctor) >"$TMP/td7b.out" 2>&1
t; assert_eq "D7 T-392: removing the references silences both rows" '0' \
  "$(awk -F"$TAB" -v n="$(men doc_paths)" '$2 == n { c++ } END { print c + 0 }' "$TMP/td7b.out")"

# T-393..T-394 (T-D-tasima): the vault is copied to another path and doctor
# must run there in ALL THREE invocation forms -- env override, no env, and
# from a foreign directory via the walk-up -- then a CLEAN CLONE must exit 0.
# The real fear: "kasayi tasidigimda sorun cikarmamali."
mkenmem tmove en
printf '## %s oturum\n\nbugunun kaydi: %s\n' "$(date +%F)" "$(date +%F)" > "$TMP/tmove/Last-Session.md"
git init -q "$TMP/tmove"
git_commit tmove init
cp -a "$TMP/tmove" "$TMP/tmove-copy"
mkdir -p "$TMP/tmove-copy/alt-klasor"
t; (cd "$TMP/tmove-copy" && "$ROOT/knotlog" doctor) >"$TMP/tmove1.out" 2>&1; RC=$?
assert_eq "T-D-tasima T-393: copied vault, no env, exits 0" '0' "$RC"
t; QUIPU_VAULT="$TMP/tmove-copy" "$ROOT/knotlog" doctor >"$TMP/tmove2.out" 2>&1; RC=$?
assert_eq "T-D-tasima T-393: copied vault, QUIPU_VAULT env, exits 0" '0' "$RC"
t; (cd "$TMP/tmove-copy/alt-klasor" && "$ROOT/knotlog" doctor) >"$TMP/tmove3.out" 2>&1; RC=$?
assert_eq "T-D-tasima T-393: copied vault from a foreign subdir, exits 0" '0' "$RC"
t; assert_eq "T-D-tasima T-393: the walk-up run still resolves the full memory set" 'yes' \
  "$(awk -F"$TAB" -v s="$(men doc_ok)" -v n="$(men doc_mem)" \
       -v d="$(memfmt en doc_mem_full 5 5)" \
       '$1 == s && $2 == n && $3 == d { f = 1 } END { exit !f }' "$TMP/tmove3.out" \
    && printf yes || printf no)"
git clone -q "$TMP/tmove" "$TMP/tmove-clone"
t; (cd "$TMP/tmove-clone" && "$ROOT/knotlog" doctor) >"$TMP/tmove4.out" 2>&1; RC=$?
assert_eq "T-D-tasima T-394: a clean clone exits 0" '0' "$RC"
t; assert_eq "T-D-tasima T-394: the clean clone reports zero fails" '0' "$(memfailcount "$TMP/tmove4.out")"



# ---- B3/B4/D6: the rules file (Kurallar.md / Rules.md) ----------------------
# The threads_file resolver pattern, applied to the behavior contract: the
# NAME is i18n data (rules_file), an existing file by either spelling wins
# over a fresh seed, and an old vault without the file stays silent.

# T-395: init seeds the localized rules file from the shipped template.
mkvault vr395
printf 'lang=tr\n' > "$TMP/vr395/.knotlog/config"
t; OUT395=$(QUIPU_VAULT="$TMP/vr395" sh "$ROOT/knotlog" init --no-prompt 2>&1); RC=$?
assert_eq "B3 T-395: init exits 0" '0' "$RC"
t; assert_eq "B3 T-395: init prints the rules line" 'yes' \
  "$(printf '%s\n' "$OUT395" | grep -qF "$(mtr init_rules)" && printf yes || printf no)"
t; assert_eq "B3 T-395: Kurallar.md exists at the vault root" 'yes' \
  "$([ -f "$TMP/vr395/Kurallar.md" ] && printf yes || printf no)"
t; assert_eq "B3 T-395: the seed is byte-identical to the tr template" 'yes' \
  "$(cmp -s "$TMP/vr395/Kurallar.md" "$ROOT/templates/tr/rules.md" && printf yes || printf no)"

# T-396: the seed is write-once -- a second init never overwrites it, and a
# user-edited file survives byte-for-byte.
printf 'kullanici kurali: her commit onayli olsun\n' >> "$TMP/vr395/Kurallar.md"
t; OUT396=$(QUIPU_VAULT="$TMP/vr395" sh "$ROOT/knotlog" init --no-prompt 2>&1)
t; assert_eq "B3 T-396: the second init is idempotent" "$(mtr init_idem)" \
  "$(printf '%s\n' "$OUT396" | head -n1)"
t; assert_eq "B3 T-396: the edited rules file is never overwritten" 'yes' \
  "$(grep -qF 'kullanici kurali' "$TMP/vr395/Kurallar.md" && printf yes || printf no)"

# T-397: the resolver tolerates the other language's spelling -- a tr vault
# already holding Rules.md keeps it; init must NOT seed a fresh Kurallar.md
# next to it (that would leave two live rule files, the exact disease the
# template's record-discipline block forbids).
mkvault vr397
printf 'lang=tr\n' > "$TMP/vr397/.knotlog/config"
printf '# Rules\n## Approval gates\n' > "$TMP/vr397/Rules.md"
t; OUT397=$(QUIPU_VAULT="$TMP/vr397" sh "$ROOT/knotlog" init --no-prompt 2>&1)
t; assert_eq "B3 T-397: an existing Rules.md wins over the localized seed" 'yes' \
  "$([ ! -f "$TMP/vr397/Kurallar.md" ] && printf yes || printf no)"
t; assert_eq "B3 T-397: no rules line when a rules file already exists" 'no' \
  "$(printf '%s\n' "$OUT397" | grep -qF "$(mtr init_rules)" && printf yes || printf no)"

# T-398: context injects the rules headings into the session feed, after the
# threads section.
t; CTX398=$(QUIPU_VAULT="$TMP/vr395" sh "$ROOT/knotlog" context)
t; assert_eq "B3 T-398: context carries the rules header" 'yes' \
  "$(printf '%s\n' "$CTX398" | grep -qF "$(mtr ctx_rules)" && printf yes || printf no)"
t; assert_eq "B3 T-398: context carries the gate headings" 'yes' \
  "$(printf '%s\n' "$CTX398" | grep -qF '## Onay kapıları' && printf yes || printf no)"
t; assert_eq "B3 T-398: the rules section follows the threads section" 'yes' \
  "$(printf '%s\n' "$CTX398" | awk -v t="$(mtr ctx_threads)" -v r="$(mtr ctx_rules)" \
     'index($0, t) == 1 { a = NR } index($0, r) == 1 { b = NR } END { print (a && b && b > a ? "yes" : "no") }')"

# T-399: the en mirror -- Rules.md seeded from the en template.
mkvault vr399
printf 'lang=en\n' > "$TMP/vr399/.knotlog/config"
t; QUIPU_VAULT="$TMP/vr399" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "B3 T-399: Rules.md is byte-identical to the en template" 'yes' \
  "$(cmp -s "$TMP/vr399/Rules.md" "$ROOT/templates/en/rules.md" && printf yes || printf no)"
t; assert_eq "B3 T-399: en context carries the en gate heading" 'yes' \
  "$(QUIPU_LANG=en QUIPU_VAULT="$TMP/vr399" sh "$ROOT/knotlog" context | grep -qF '## Approval gates' && printf yes || printf no)"

# T-400: D1 -- the rules file is part of the mandatory narrative set. A full
# tr memory set missing Kurallar.md fails doctor with the fallback pair named.
mkenmem vr400 tr
rm "$TMP/vr400/Kurallar.md"
t; DOUT400=$( (cd "$TMP/vr400" && "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
t; assert_eq "B3 T-400: a memory set missing Kurallar.md exits 1" '1' "$RC"
t; assert_eq "B3 T-400: the fail row names the Kurallar|Rules fallback pair" 'yes' \
  "$(printf '%s\n' "$DOUT400" | awk -F"$TAB" -v s="$(mtr doc_fail)" -v n="$(mtr doc_mem)" \
       -v d="$(memfmt tr doc_mem_missing "$(mtr mem_rules)" "$(men mem_rules)")" \
       '$1 == s && $2 == n && $3 == d { f = 1 } END { exit !f }' && printf yes || printf no)"

# T-401: the untouched seed does NOT wake the mandatory contract -- a fresh
# init vault still exits doctor clean (the "fresh vault exits doctor 0"
# invariant); the moment the user edits the file, it counts as hand-written
# and the contract wakes.
mkvault vr401
printf 'lang=tr\n' > "$TMP/vr401/.knotlog/config"
QUIPU_VAULT="$TMP/vr401" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; DOUT401=$( (cd "$TMP/vr401" && "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
t; assert_eq "B3 T-401: the untouched seed keeps a fresh vault at exit 0" '0' "$RC"
t; assert_eq "B3 T-401: the untouched seed reports zero fails" '0' \
  "$(printf '%s\n' "$DOUT401" | memfailcount /dev/stdin)"
printf 'elle yazilmis kural\n' >> "$TMP/vr401/Kurallar.md"
t; (cd "$TMP/vr401" && "$ROOT/knotlog" doctor) >/dev/null 2>&1; RC=$?
t; assert_eq "B3 T-401: editing the seed wakes the mandatory contract" '1' "$RC"

# T-402: backwards compatibility -- an old vault with no rules file at all
# errors nowhere: context emits no rules section, doctor stays silent.
mkvault vr402
printf 'lang=tr\n' > "$TMP/vr402/.knotlog/config"
printf 'oturum\n' > "$TMP/vr402/Son-Oturum.md"
printf 'konular\n' > "$TMP/vr402/Konular.md"
t; CTX402=$(QUIPU_VAULT="$TMP/vr402" sh "$ROOT/knotlog" context); RC=$?
t; assert_eq "B3 T-402: context exits 0 without a rules file" '0' "$RC"
t; assert_eq "B3 T-402: context emits no rules section" 'no' \
  "$(printf '%s\n' "$CTX402" | grep -qF "$(mtr ctx_rules)" && printf yes || printf no)"
t; (cd "$TMP/vr402" && "$ROOT/knotlog" doctor) >"$TMP/vr402.out" 2>&1; RC=$?
t; assert_eq "B3 T-402: doctor exits 0 without a rules file" '0' "$RC"
t; assert_eq "B3 T-402: doctor reports zero fails" '0' "$(memfailcount "$TMP/vr402.out")"

# T-538: a long threads file must not push the rules headings out. The rules
# section used to ride whatever slack the threads crop left, so a threads
# file big enough to fill the budget dropped the behaviour contract WHOLE
# (measured on a real vault, 2026-09-24: the rule headings vanished from
# every session). The headings' bytes are now reserved before the threads
# crop; the threads section is cut to what remains. Output order is
# unchanged (rules still follow threads, T-398).
mkvault vr538
printf 'lang=en\nctx_max=1200\n' >> "$TMP/vr538/.knotlog/config"
: > "$TMP/vr538/.knotlog/index.tsv"
: > "$TMP/vr538/.knotlog/activity.log"
awk 'BEGIN { for (i=1; i<=80; i++) printf "thread line %03d padding padding padding\n", i }' > "$TMP/vr538/Threads.md"
printf '# Rules\n## Approval gates\n## Zero-level protocols\n' > "$TMP/vr538/Rules.md"
t; CTX538=$(env -u QUIPU_CTX_MAX QUIPU_LANG=en QUIPU_VAULT="$TMP/vr538" sh "$ROOT/knotlog" context)
t; assert_eq "T-538: rule headings survive a threads file that fills the budget" 'yes' \
  "$(printf '%s\n' "$CTX538" | grep -qF '## Zero-level protocols' && printf yes || printf no)"
t; assert_eq "T-538: the threads section is the one that gets cut" 'yes' \
  "$(printf '%s\n' "$CTX538" | grep -qF "$(men ctx_truncated)" && printf yes || printf no)"
t; assert_eq "T-538: the output still honours ctx_max" 'yes' \
  "$([ "$(printf '%s' "$CTX538" | LC_ALL=C wc -c | tr -d ' ')" -le 1200 ] && printf yes || printf no)"
# Control: when even the headings cannot fit next to the fixed part, no
# reservation is made and the old whole-drop still applies -- the cap wins.
printf 'lang=en\nctx_max=200\n' > "$TMP/vr538/.knotlog/config"
t; CTX538S=$(env -u QUIPU_CTX_MAX QUIPU_LANG=en QUIPU_VAULT="$TMP/vr538" sh "$ROOT/knotlog" context)
t; assert_eq "T-538: a cap too small for the headings still bounds the output" 'yes' \
  "$([ "$(printf '%s' "$CTX538S" | LC_ALL=C wc -c | tr -d ' ')" -le 200 ] && printf yes || printf no)"

# T-403: D6 -- the checkpoint protocol rides the bridge, and the bridge body
# stays single-source: AGENTS.md and CLAUDE.md remain byte-equal in both
# languages.
mkvault vr403tr
printf 'lang=tr\n' > "$TMP/vr403tr/.knotlog/config"
QUIPU_VAULT="$TMP/vr403tr" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "D6 T-403: tr bridge AGENTS.md == CLAUDE.md byte-for-byte" 'yes' \
  "$(cmp -s "$TMP/vr403tr/AGENTS.md" "$TMP/vr403tr/CLAUDE.md" && printf yes || printf no)"
t; assert_eq "D6 T-403: the tr bridge carries the checkpoint protocol" 'yes' \
  "$(grep -qF "$(mtr bridge_checkpoint)" "$TMP/vr403tr/AGENTS.md" && printf yes || printf no)"
mkvault vr403en
printf 'lang=en\n' > "$TMP/vr403en/.knotlog/config"
QUIPU_VAULT="$TMP/vr403en" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "D6 T-403: en bridge AGENTS.md == CLAUDE.md byte-for-byte" 'yes' \
  "$(cmp -s "$TMP/vr403en/AGENTS.md" "$TMP/vr403en/CLAUDE.md" && printf yes || printf no)"
t; assert_eq "D6 T-403: the en bridge carries the checkpoint protocol" 'yes' \
  "$(grep -qF "$(men bridge_checkpoint)" "$TMP/vr403en/AGENTS.md" && printf yes || printf no)"

# T-404: D6 -- the persona templates carry the same three checkpoints (data
# presence; the asks-of-the-agent count stays pinned by T-360 above).
t; assert_eq "D6 T-404: persona/tr.md carries the checkpoint heading" 'yes' \
  "$(grep -qF '## Kontrol noktaları' "$ROOT/persona/tr.md" && printf yes || printf no)"
t; assert_eq "D6 T-404: persona/en.md carries the checkpoint heading" 'yes' \
  "$(grep -qF '## Checkpoints' "$ROOT/persona/en.md" && printf yes || printf no)"


# ---- B11: the plan command (knotlog plan, plans_dir, bridge line, doctor) -----
# The threads_file/rules_file resolver pattern applied to WHERE plans live:
# the plans directory's name is i18n data (plans_dir), an existing directory
# by either spelling wins, the bridge binds every agent, and a project
# folder is the USER's decision -- quipu never creates one.

_q_pl_pdir_tr=$(awk -F"$(printf '\t')" '$1=="projects"{print $2;exit}' "$ROOT/layout/tr.txt")
_q_pl_pdir_en=$(awk -F"$(printf '\t')" '$1=="projects"{print $2;exit}' "$ROOT/layout/en.txt")

# T-405: no vault -> the standard no-vault error, exit 1.
mkdir -p "$TMP/novault-pl"
t; (cd "$TMP/novault-pl" && QUIPU_LANG='tr' "$ROOT/knotlog" plan notum) >"$TMP/t405.out" 2>&1; RC=$?
t; assert_eq "B11 T-405: plan without a vault exits 1" '1' "$RC"
t; assert_eq "B11 T-405: plan without a vault prints the no-vault error" 'yes' \
  "$(printf '%s\n' "$(cat "$TMP/t405.out")" | grep -qF "$(mtr err_no_vault)" && printf yes || printf no)"

# T-406: no project resolved -> error, and NOTHING is created (no projects
# folder, no plans folder, no file -- creating things is not this path's job).
mkvault vpl6
printf 'lang=tr\n' > "$TMP/vpl6/.knotlog/config"
t; (cd "$TMP/vpl6" && "$ROOT/knotlog" plan notum) >"$TMP/t406.out" 2>&1; RC=$?
t; assert_eq "B11 T-406: unresolved project exits 2" '2' "$RC"
t; assert_eq "B11 T-406: unresolved project names the fix" 'yes' \
  "$(grep -qF "$(mtr err_plan_project_required)" "$TMP/t406.out" && printf yes || printf no)"
t; assert_eq "B11 T-406: unresolved project creates nothing" 'yes' \
  "$([ -z "$(find "$TMP/vpl6" -name '*.md' -not -path '*/.knotlog/*')" ] && printf yes || printf no)"

# T-407: missing project folder -> error, never auto-created (B11's
# deliberate edge: creating a project is the user's decision).
mkvault vpl7
printf 'lang=tr\n' > "$TMP/vpl7/.knotlog/config"
printf 'layout=tr\n' >> "$TMP/vpl7/.knotlog/config"
mkdir -p "$TMP/vpl7/$_q_pl_pdir_tr"
t; QUIPU_VAULT="$TMP/vpl7" "$ROOT/knotlog" plan notum --proje Yok 2>"$TMP/t407.out"; RC=$?
t; assert_eq "B11 T-407: missing project folder exits 2" '2' "$RC"
t; assert_eq "B11 T-407: the error names the project decision" 'yes' \
  "$(grep -qF "$(memfmt tr err_plan_project_missing "$TMP/vpl7/$_q_pl_pdir_tr/Yok")" "$TMP/t407.out" && printf yes || printf no)"
t; assert_eq "B11 T-407: the missing project stays missing" 'yes' \
  "$([ ! -d "$TMP/vpl7/$_q_pl_pdir_tr/Yok" ] && printf yes || printf no)"
t; assert_eq "B11 T-407: no plans folder appears anywhere" 'yes' \
  "$([ -z "$(find "$TMP/vpl7" -type d \( -name Planlar -o -name Plans \))" ] && printf yes || printf no)"

# T-408: the normal tr opening -- file under <Projeler>/<Proje>/Planlar/,
# front matter filled from the template (title WITHOUT the .md suffix,
# today's date, type: plan), path printed, no editor needed.
mkvault vpl8
printf 'lang=tr\n' > "$TMP/vpl8/.knotlog/config"
printf 'layout=tr\n' >> "$TMP/vpl8/.knotlog/config"
mkdir -p "$TMP/vpl8/$_q_pl_pdir_tr/Deneme"
t; PL80UT=$(QUIPU_VAULT="$TMP/vpl8" "$ROOT/knotlog" plan notum --proje Deneme 2>&1); RC=$?
t; assert_eq "B11 T-408: tr plan exits 0" '0' "$RC"
t; assert_eq "B11 T-408: the tr plan lands in Planlar" 'yes' \
  "$([ -f "$TMP/vpl8/$_q_pl_pdir_tr/Deneme/Planlar/notum.md" ] && printf yes || printf no)"
t; assert_eq "B11 T-408: the printed path is the written file" 'yes' \
  "$(printf '%s\n' "$PL80UT" | grep -qF "$(memfmt tr plan_written "$TMP/vpl8/$_q_pl_pdir_tr/Deneme/Planlar/notum.md")" && printf yes || printf no)"
t; assert_eq "B11 T-408: front matter title carries the name without .md" 'yes' \
  "$(grep -qF 'title: notum' "$TMP/vpl8/$_q_pl_pdir_tr/Deneme/Planlar/notum.md" && printf yes || printf no)"
t; assert_eq "B11 T-408: front matter dates are today" 'yes' \
  "$(grep -qF "created: $(date +%Y-%m-%d)" "$TMP/vpl8/$_q_pl_pdir_tr/Deneme/Planlar/notum.md" && grep -qF "modified: $(date +%Y-%m-%d)" "$TMP/vpl8/$_q_pl_pdir_tr/Deneme/Planlar/notum.md" && printf yes || printf no)"
t; assert_eq "B11 T-408: front matter type is plan" 'yes' \
  "$(grep -qF 'type: plan' "$TMP/vpl8/$_q_pl_pdir_tr/Deneme/Planlar/notum.md" && printf yes || printf no)"
t; assert_eq "B11 T-408: the H1 carries the name" 'yes' \
  "$(grep -qxF '# notum' "$TMP/vpl8/$_q_pl_pdir_tr/Deneme/Planlar/notum.md" && printf yes || printf no)"

# T-409: the en mirror -- Plans/ under Projects/, seeded from the en
# template.
mkvault vpl9
printf 'lang=en\n' > "$TMP/vpl9/.knotlog/config"
printf 'layout=en\n' >> "$TMP/vpl9/.knotlog/config"
mkdir -p "$TMP/vpl9/$_q_pl_pdir_en/Deneme"
t; QUIPU_VAULT="$TMP/vpl9" "$ROOT/knotlog" plan notes --proje Deneme >/dev/null 2>&1; RC=$?
t; assert_eq "B11 T-409: en plan exits 0" '0' "$RC"
t; assert_eq "B11 T-409: the en plan lands in Plans" 'yes' \
  "$([ -f "$TMP/vpl9/$_q_pl_pdir_en/Deneme/Plans/notes.md" ] && printf yes || printf no)"

# T-410: the resolver wins over creation -- a tr vault whose project already
# holds an English-named Plans/ directory keeps it (old vaults do not
# sprout a second plans folder next to the live one).
mkvault vpl10
printf 'lang=tr\n' > "$TMP/vpl10/.knotlog/config"
printf 'layout=tr\n' >> "$TMP/vpl10/.knotlog/config"
mkdir -p "$TMP/vpl10/$_q_pl_pdir_tr/Deneme/Plans"
t; QUIPU_VAULT="$TMP/vpl10" "$ROOT/knotlog" plan eski --proje Deneme >/dev/null 2>&1
t; assert_eq "B11 T-410: an existing Plans/ dir wins in a tr vault" 'yes' \
  "$([ -f "$TMP/vpl10/$_q_pl_pdir_tr/Deneme/Plans/eski.md" ] && printf yes || printf no)"
t; assert_eq "B11 T-410: no Planlar/ dir is created next to it" 'yes' \
  "$([ ! -d "$TMP/vpl10/$_q_pl_pdir_tr/Deneme/Planlar" ] && printf yes || printf no)"

# T-411: an existing plan is never overwritten -- warn, exit 1, bytes kept.
mkvault vpl11
printf 'lang=tr\n' > "$TMP/vpl11/.knotlog/config"
printf 'layout=tr\n' >> "$TMP/vpl11/.knotlog/config"
mkdir -p "$TMP/vpl11/$_q_pl_pdir_tr/Deneme/Planlar"
printf 'ellemis plan\n' > "$TMP/vpl11/$_q_pl_pdir_tr/Deneme/Planlar/notum.md"
t; PL11OUT=$(QUIPU_VAULT="$TMP/vpl11" "$ROOT/knotlog" plan notum --proje Deneme 2>&1); RC=$?
t; assert_eq "B11 T-411: overwriting is refused with exit 1" '1' "$RC"
t; assert_eq "B11 T-411: the refusal names the file" 'yes' \
  "$(printf '%s\n' "$PL11OUT" | grep -qF "$(memfmt tr err_plan_exists "$TMP/vpl11/$_q_pl_pdir_tr/Deneme/Planlar/notum.md")" && printf yes || printf no)"
t; assert_eq "B11 T-411: the existing plan keeps its bytes" 'yes' \
  "$(grep -qF 'ellemis plan' "$TMP/vpl11/$_q_pl_pdir_tr/Deneme/Planlar/notum.md" && printf yes || printf no)"

# T-412: the bridge line -- init writes the project-plans location into the
# bridge body, and AGENTS.md stays byte-equal to CLAUDE.md (single source).
mkvault vpl12tr
printf 'lang=tr\n' > "$TMP/vpl12tr/.knotlog/config"
printf 'layout=tr\n' >> "$TMP/vpl12tr/.knotlog/config"
QUIPU_VAULT="$TMP/vpl12tr" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "B11 T-412: the tr bridge carries the project-plans line" 'yes' \
  "$(grep -qF "$(memfmt tr bridge_plans "$_q_pl_pdir_tr" Planlar)" "$TMP/vpl12tr/AGENTS.md" && printf yes || printf no)"
t; assert_eq "B11 T-412: tr bridge AGENTS.md == CLAUDE.md byte-for-byte" 'yes' \
  "$(cmp -s "$TMP/vpl12tr/AGENTS.md" "$TMP/vpl12tr/CLAUDE.md" && printf yes || printf no)"
mkvault vpl12en
printf 'lang=en\n' > "$TMP/vpl12en/.knotlog/config"
printf 'layout=en\n' >> "$TMP/vpl12en/.knotlog/config"
QUIPU_VAULT="$TMP/vpl12en" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "B11 T-412: the en bridge carries the project-plans line" 'yes' \
  "$(grep -qF "$(memfmt en bridge_plans "$_q_pl_pdir_en" Plans)" "$TMP/vpl12en/AGENTS.md" && printf yes || printf no)"
t; assert_eq "B11 T-412: en bridge AGENTS.md == CLAUDE.md byte-for-byte" 'yes' \
  "$(cmp -s "$TMP/vpl12en/AGENTS.md" "$TMP/vpl12en/CLAUDE.md" && printf yes || printf no)"

# T-413: doctor -- plan files under a known tool location (~/.claude/plans/)
# warn as plans outside memory; an empty HOME stays silent; the warning
# never fails the audit.
mkvault vpl13
printf 'lang=tr\n' > "$TMP/vpl13/.knotlog/config"
mkdir -p "$TMP/vpl13home/.claude/plans"
printf '# kasa disi plan\n' > "$TMP/vpl13home/.claude/plans/kacan.md"
t; PL13OUT=$( (cd "$TMP/vpl13" && HOME="$TMP/vpl13home" "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
t; assert_eq "B11 T-413: doctor exits 0 with an outside plan" '0' "$RC"
t; assert_eq "B11 T-413: doctor warns about the outside plan" 'yes' \
  "$(printf '%s\n' "$PL13OUT" | awk -F"$TAB" -v d="$(memfmt tr doc_plans_outside "$TMP/vpl13home/.claude/plans" 1)" '$2 == "plans" && $3 == d { f = 1 } END { exit !f }' && printf yes || printf no)"
t; PL13N=$( (cd "$TMP/vpl13" && HOME="$TMP/vpl13empty" "$ROOT/knotlog" doctor) 2>&1 )
t; assert_eq "B11 T-413: a HOME with no plans location stays silent" 'no' \
  "$(printf '%s\n' "$PL13N" | awk -F"$TAB" '$2 == "plans" { f = 1 } END { print (f ? "yes" : "no") }')"

# T-414: no EDITOR -> the path is printed and nothing else happens; with
# EDITOR the file is opened and the editor's exit status is kept.
mkvault vpl14
printf 'lang=tr\n' > "$TMP/vpl14/.knotlog/config"
printf 'layout=tr\n' >> "$TMP/vpl14/.knotlog/config"
mkdir -p "$TMP/vpl14/$_q_pl_pdir_tr/Deneme"
t; PL14OUT=$(env -u EDITOR QUIPU_VAULT="$TMP/vpl14" "$ROOT/knotlog" plan duz --proje Deneme 2>&1); RC=$?
t; assert_eq "B11 T-414: plan without EDITOR exits 0" '0' "$RC"
t; assert_eq "B11 T-414: plan without EDITOR prints the path" 'yes' \
  "$(printf '%s\n' "$PL14OUT" | grep -qF "$TMP/vpl14/$_q_pl_pdir_tr/Deneme/Planlar/duz.md" && printf yes || printf no)"
t; QUIPU_VAULT="$TMP/vpl14" EDITOR=true "$ROOT/knotlog" plan duz --proje Deneme >/dev/null 2>&1; RC=$?
t; assert_eq "B11 T-414: plan refuses to re-open an existing file" '1' "$RC"
t; QUIPU_VAULT="$TMP/vpl14" EDITOR=true "$ROOT/knotlog" plan acik --proje Deneme >/dev/null 2>&1; RC=$?
t; assert_eq "B11 T-414: plan opens the editor and keeps its exit status" '0' "$RC"

# T-415: the command is listed in help/usage (both languages).
t; assert_eq "B11 T-415: tr usage lists plan" 'yes' \
  "$("$ROOT/knotlog" help --tr 2>&1 | grep -qF "$(mtr usage_plan)" && printf yes || printf no)"
t; assert_eq "B11 T-415: en usage lists plan" 'yes' \
  "$("$ROOT/knotlog" help 2>&1 | grep -qF "$(men usage_plan)" && printf yes || printf no)"


# ---- B5: the facts file (Gerçekler.md / Facts.md) ---------------------------
# The rules-file pattern (B3) applied to the persistent-facts layer: the
# NAME is i18n data (facts_file), init seeds once and never overwrites,
# an existing file by either spelling wins, an untouched seed is the
# skeleton -- not a record -- and context carries the tagged fact lines
# under the same ctx_max budget, dropped whole before threads are cut.

# T-416: init seeds the localized facts file from the shipped template; a
# second init is idempotent and never overwrites an edited file.
mkvault vf416
printf 'lang=tr\n' > "$TMP/vf416/.knotlog/config"
t; OUT416=$(QUIPU_VAULT="$TMP/vf416" sh "$ROOT/knotlog" init --no-prompt 2>&1); RC=$?
assert_eq "B5 T-416: init exits 0" '0' "$RC"
t; assert_eq "B5 T-416: init prints the facts line" 'yes' \
  "$(printf '%s\n' "$OUT416" | grep -qF "$(mtr init_facts)" && printf yes || printf no)"
t; assert_eq "B5 T-416: Gerçekler.md exists at the vault root" 'yes' \
  "$([ -f "$TMP/vf416/Gerçekler.md" ] && printf yes || printf no)"
t; assert_eq "B5 T-416: the seed is byte-identical to the tr template" 'yes' \
  "$(cmp -s "$TMP/vf416/Gerçekler.md" "$ROOT/templates/tr/facts.md" && printf yes || printf no)"
printf -- '- Karar: test gerçeği\n' >> "$TMP/vf416/Gerçekler.md"
t; OUT416B=$(QUIPU_VAULT="$TMP/vf416" sh "$ROOT/knotlog" init --no-prompt 2>&1)
assert_eq "B5 T-416: the second init is idempotent" "$(mtr init_idem)" \
  "$(printf '%s\n' "$OUT416B" | head -n1)"
t; assert_eq "B5 T-416: the edited facts file is never overwritten" 'yes' \
  "$(grep -qF 'test gerçeği' "$TMP/vf416/Gerçekler.md" && printf yes || printf no)"

# T-417: the resolver tolerates the other language's spelling -- a tr vault
# already holding Facts.md keeps it; init must NOT seed a fresh Gerçekler.md
# next to it (two live fact files are the disease the rules template's
# record-discipline block forbids).
mkvault vf417
printf 'lang=tr\n' > "$TMP/vf417/.knotlog/config"
printf '# Facts\n- Decision: kept\n' > "$TMP/vf417/Facts.md"
t; OUT417=$(QUIPU_VAULT="$TMP/vf417" sh "$ROOT/knotlog" init --no-prompt 2>&1)
assert_eq "B5 T-417: an existing Facts.md wins over the localized seed" 'yes' \
  "$([ ! -f "$TMP/vf417/Gerçekler.md" ] && printf yes || printf no)"
t; assert_eq "B5 T-417: no facts line when a facts file already exists" 'no' \
  "$(printf '%s\n' "$OUT417" | grep -qF "$(mtr init_facts)" && printf yes || printf no)"

# T-418: context injects the fact lines into the session feed, after the
# rules section, and never leaks the skeleton prose.
t; CTX418=$(QUIPU_VAULT="$TMP/vf416" sh "$ROOT/knotlog" context)
assert_eq "B5 T-418: context carries the facts header" 'yes' \
  "$(printf '%s\n' "$CTX418" | grep -qF "$(mtr ctx_facts)" && printf yes || printf no)"
t; assert_eq "B5 T-418: context carries the hand-written fact line" 'yes' \
  "$(printf '%s\n' "$CTX418" | grep -qF 'test gerçeği' && printf yes || printf no)"
t; assert_eq "B5 T-418: context never leaks the seed's prose" 'no' \
  "$(printf '%s\n' "$CTX418" | grep -qF 'kimlik geçer' && printf yes || printf no)"
t; assert_eq "B5 T-418: the facts section follows the rules section" 'yes' \
  "$(printf '%s\n' "$CTX418" | awk -v r="$(mtr ctx_rules)" -v f="$(mtr ctx_facts)" \
     'index($0, r) == 1 { a = NR } index($0, f) == 1 { b = NR } END { print (a && b && b > a ? "yes" : "no") }')"

# T-419: the untouched seed stays silent in context -- a fresh vault's facts
# section is absent until the user adds the first real line (b47c5d3's D1
# decision applied to the context feed).
mkvault vf419
printf 'lang=tr\n' > "$TMP/vf419/.knotlog/config"
QUIPU_VAULT="$TMP/vf419" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; CTX419=$(QUIPU_VAULT="$TMP/vf419" sh "$ROOT/knotlog" context); RC=$?
assert_eq "B5 T-419: context exits 0 on the untouched seed" '0' "$RC"
t; assert_eq "B5 T-419: the untouched seed emits no facts section" 'no' \
  "$(printf '%s\n' "$CTX419" | grep -qF "$(mtr ctx_facts)" && printf yes || printf no)"

# T-420: the en mirror -- Facts.md seeded from the en template, en context
# carries the en facts section.
mkvault vf420
printf 'lang=en\n' > "$TMP/vf420/.knotlog/config"
t; QUIPU_VAULT="$TMP/vf420" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "B5 T-420: Facts.md is byte-identical to the en template" 'yes' \
  "$(cmp -s "$TMP/vf420/Facts.md" "$ROOT/templates/en/facts.md" && printf yes || printf no)"
printf -- '- Decision: en smoke fact\n' >> "$TMP/vf420/Facts.md"
t; assert_eq "B5 T-420: en context carries the en facts section" 'yes' \
  "$(QUIPU_LANG=en QUIPU_VAULT="$TMP/vf420" sh "$ROOT/knotlog" context | grep -qF "$(men ctx_facts)" && printf yes || printf no)"
t; assert_eq "B5 T-420: en context carries the en fact line" 'yes' \
  "$(QUIPU_LANG=en QUIPU_VAULT="$TMP/vf420" sh "$ROOT/knotlog" context | grep -qF 'en smoke fact' && printf yes || printf no)"

# T-421: backwards compatibility -- an old vault with no facts file at all
# errors nowhere: context exits 0 without a facts section, doctor exits 0
# without a facts row.
mkvault vf421
printf 'lang=tr\n' > "$TMP/vf421/.knotlog/config"
printf 'oturum\n' > "$TMP/vf421/Son-Oturum.md"
printf 'konular\n' > "$TMP/vf421/Konular.md"
t; CTX421=$(QUIPU_VAULT="$TMP/vf421" sh "$ROOT/knotlog" context); RC=$?
assert_eq "B5 T-421: context exits 0 without a facts file" '0' "$RC"
t; assert_eq "B5 T-421: context emits no facts section" 'no' \
  "$(printf '%s\n' "$CTX421" | grep -qF "$(mtr ctx_facts)" && printf yes || printf no)"
t; DOUT421=$( (cd "$TMP/vf421" && "$ROOT/knotlog" doctor) 2>&1 ); RC=$?
assert_eq "B5 T-421: doctor exits 0 without a facts file" '0' "$RC"
t; assert_eq "B5 T-421: doctor prints no facts row" 'no' \
  "$(printf '%s\n' "$DOUT421" | awk -F"$TAB" '$2 == "facts" { f = 1 } END { print (f ? "yes" : "no") }')"

# T-422: doctor's facts row -- one ok row naming the tagged fact-line count
# when the file is present.
mkvault vf422
printf 'lang=tr\n' > "$TMP/vf422/.knotlog/config"
QUIPU_VAULT="$TMP/vf422" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "B5 T-422: doctor prints the seeded count" 'yes' \
  "$( (cd "$TMP/vf422" && "$ROOT/knotlog" doctor) 2>&1 | \
     awk -F"$TAB" -v s="$(mtr doc_ok)" -v d="$(memfmt tr doc_facts_n 2)" \
         '$1 == s && $2 == "facts" && $3 == d { f = 1 } END { exit !f }' && printf yes || printf no)"
printf -- '- Karar: bir gerçek daha\n' >> "$TMP/vf422/Gerçekler.md"
t; assert_eq "B5 T-422: the count follows the file" 'yes' \
  "$( (cd "$TMP/vf422" && "$ROOT/knotlog" doctor) 2>&1 | \
     awk -F"$TAB" -v d="$(memfmt tr doc_facts_n 3)" \
         '$2 == "facts" && $3 == d { f = 1 } END { exit !f }' && printf yes || printf no)"
# T-423: the ctx_max budget -- facts rides the slack the threads and rules
# budget leave and drops WHOLE when that slack is too small; threads are
# never cut by it. An oversized Threads.md plus a tiny budget fills the
# room entirely, so the adopted facts file must go missing from the feed
# while the threads section (and its truncation marker) survives.
#
# Budget recalibrated 800 (was 300) when the tone block (Fixed part 0c)
# joined the fixed part: companion.md's Tone section adds ~300 bytes to
# every fixed-part measurement (see the T-454..T-460 block below), so 300
# no longer leaves ANY room for a truncated threads section -- the fixed
# part alone now exceeds it. 800 is measured to reproduce the same shape
# this test always asserted (facts absent, threads present+truncated,
# total within budget) with the tone block now included in the fixed part.
mkvault vf423
printf 'lang=tr\n' > "$TMP/vf423/.knotlog/config"
QUIPU_VAULT="$TMP/vf423" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
printf -- '- Karar: %s\n' "$(printf 'a%.0s' $(seq 1 160))" >> "$TMP/vf423/Gerçekler.md"
awk 'BEGIN { for (i = 1; i <= 60; i++) printf "thread line %03d padding padding padding\n", i }' \
  > "$TMP/vf423/Konular.md"
t; CTX423=$(QUIPU_CTX_MAX=800 QUIPU_VAULT="$TMP/vf423" sh "$ROOT/knotlog" context); RC=$?
assert_eq "B5 T-423: context exits 0 under a tiny budget" '0' "$RC"
t; assert_eq "B5 T-423: the facts section drops whole" 'no' \
  "$(printf '%s\n' "$CTX423" | grep -qF "$(mtr ctx_facts)" && printf yes || printf no)"
t; assert_eq "B5 T-423: the threads section survives with its marker" 'yes' \
  "$(printf '%s\n' "$CTX423" | grep -qF "$(mtr ctx_threads)" \
     && printf '%s\n' "$CTX423" | grep -qF "$(mtr ctx_truncated)" && printf yes || printf no)"
t; SIZE423=$(printf '%s' "$CTX423" | LC_ALL=C wc -c | tr -d ' ')
assert_eq "B5 T-423: the feed stays within ctx_max" 'yes' \
  "$([ "$SIZE423" -le 800 ] && printf yes || printf no)"

# ---- T-439/T-440/T-441: doctor tells the truth about the Codex adapter ----
# Finding (2026-09-03, measured on this machine): the codex row printed
# "ok codex $HOME/.codex/config.toml" whenever that file existed -- which
# only proves Codex is installed. A machine with Codex present, NO hooks.json
# anywhere, and zero quipu memory reaching Codex still got a green row. The
# row has to look at the adapter, not the runtime. Trust cannot be read from
# disk (it lives in Codex's own state) and `codex exec` never dispatches
# hooks at all, so the ok row carries both caveats instead of promising the
# hooks will fire.
CXH="$TMP/cx-home"; mkdir -p "$CXH/.codex"
mkvault vcx
: > "$CXH/.codex/config.toml"
cxrow() { QUIPU_VAULT="$TMP/vcx" QUIPU_LANG=en HOME="$CXH" sh "$ROOT/knotlog" doctor 2>&1 \
  | awk -F'\t' '$2=="codex"{print $1"|"$3}'; }

# T-439: Codex installed, adapter absent -> warn, not ok.
t; assert_eq "T-439: doctor warns when the codex adapter is not installed" \
  'warn|hooks.json not found -- the adapter is not installed' "$(cxrow)"

# T-440: a hooks.json that is not ours must not be reported as ours.
printf '%s\n' '{"hooks":{}}' > "$CXH/.codex/hooks.json"
t; assert_eq "T-440: doctor warns when hooks.json carries no knotlog hooks" \
  "warn|$CXH/.codex/hooks.json -- hooks.json has no knotlog hooks" "$(cxrow)"

# T-441: our adapter -> ok, and the row must keep both caveats, because a
# green row that omits them is exactly the false reassurance T-439 fixes.
cp "$ROOT/adapters/codex/hooks.json" "$CXH/.codex/hooks.json"
t; assert_eq "T-441: doctor reports the quipu adapter with its caveats" \
  "ok|$CXH/.codex/hooks.json -- knotlog hooks wired; trust them once in the interactive TUI before use" \
  "$(cxrow)"

# T-441b: no Codex at all -> no row (never nag about an agent that is absent).
rm -rf "$CXH/.codex"
t; assert_eq "T-441: doctor prints no codex row when Codex is absent" '' "$(cxrow)"

# ---- T-442/T-443/T-444: Codex captures native apply_patch synchronously ----
# Codex 0.153.0 dispatches PostToolUse for apply_patch after trust. Its
# command is the native *** Begin/End Patch envelope; capture must complete
# before the next turn, while SessionEnd remains the remember + index boundary.
t; assert_eq "codex adapter: PostToolUse captures synchronously" 'yes' \
  "$(awk '/"PostToolUse"/,/\]/' "$ROOT/adapters/codex/hooks.json" | grep -q '"command": "KNOTLOG_HOOK=1 knotlog capture"' && printf yes || printf no)"
t; assert_eq "codex adapter: PostToolUse has no async capture" 'yes' \
  "$(awk '/"PostToolUse"/,/\]/' "$ROOT/adapters/codex/hooks.json" | { ! grep -q '"async": true'; } && printf yes || printf no)"
t; assert_eq "codex adapter: SessionEnd keeps remember + index without git workaround" 'yes' \
  "$(awk '/"SessionEnd"/,/\]/' "$ROOT/adapters/codex/hooks.json" | grep -q '"command": "KNOTLOG_HOOK=1 knotlog remember && KNOTLOG_HOOK=1 knotlog index"' && ! grep -q 'capture --git' "$ROOT/adapters/codex/hooks.json" && printf yes || printf no)"

# ---- T-445..T-453: zero-level protocols (rules templates + bridge) --------
# The 13-item behavior contract ("sozlesmen su dosyalar", "bitis
# tanimiyla al", ...) rides two surfaces: the rules file templates (full
# text + a "Neden:"/"Reason:" line under each item) and the bridge block
# (compact, no reason lines, DATA from i18n bridge_protocols/bridge_proto_NN).
# _q_rules_adopted() compares the on-disk rules file byte-for-byte against
# these same template files, so editing them here is exactly what keeps that
# write-once contract intact.

protoitems() { # file heading -> count of numbered items under that heading
  awk -v h="$2" '
    $0 == h { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside && /^[0-9]+\. / { n++ }
    END { print n + 0 }
  ' "$1"
}

# T-445: the tr rules template carries the protocols heading and all 13 items.
t; assert_eq "T-445: tr rules template has the zero-level protocols heading" 'yes' \
  "$(grep -qF '## Sıfır seviye protokoller' "$ROOT/templates/tr/rules.md" && printf yes || printf no)"
t; assert_eq "T-445: tr rules template carries all 13 protocol items" '13' \
  "$(protoitems "$ROOT/templates/tr/rules.md" '## Sıfır seviye protokoller')"

# T-446: the en rules template carries the protocols heading and all 13 items.
t; assert_eq "T-446: en rules template has the zero-level protocols heading" 'yes' \
  "$(grep -qF '## Zero-level protocols' "$ROOT/templates/en/rules.md" && printf yes || printf no)"
t; assert_eq "T-446: en rules template carries all 13 protocol items" '13' \
  "$(protoitems "$ROOT/templates/en/rules.md" '## Zero-level protocols')"

# T-447: both languages agree on the item count -- a translation that drops
# or adds an item is exactly the kind of drift D1's pri/sec pattern elsewhere
# in this file is built to catch, applied here to a hand-authored block.
t; assert_eq "T-447: tr and en protocol item counts match" 'yes' \
  "$( [ "$(protoitems "$ROOT/templates/tr/rules.md" '## Sıfır seviye protokoller')" \
     = "$(protoitems "$ROOT/templates/en/rules.md" '## Zero-level protocols')" ] \
     && printf yes || printf no)"

# T-448: each item under the heading carries a reason line -- "a rule
# without a reason is a suggestion" is the file's own stated philosophy
# (see the file's opening paragraph), so the protocols block must not be
# the one section that skips it.
t; assert_eq "T-448: tr protocol items each carry a Neden: line" '13' \
  "$(awk '/^## Sıfır seviye protokoller/{f=1;next} f&&/^## /{f=0} f&&/Neden:/{n++} END{print n+0}' "$ROOT/templates/tr/rules.md")"
t; assert_eq "T-448: en protocol items each carry a Reason: line" '13' \
  "$(awk '/^## Zero-level protocols/{f=1;next} f&&/^## /{f=0} f&&/Reason:/{n++} END{print n+0}' "$ROOT/templates/en/rules.md")"

# T-449: neither language leaves an unfilled [list]-style placeholder in
# items 1/2 -- the hafiza-os "persona is stillborn" failure mode this task
# was warned about (an empty bracket template nobody ever fills in).
t; assert_eq "T-449: tr protocol items 1/2 carry no empty placeholder brackets" 'no' \
  "$(grep -E '^(1|2)\. .*\[.*\]' "$ROOT/templates/tr/rules.md" >/dev/null && printf yes || printf no)"
t; assert_eq "T-449: en protocol items 1/2 carry no empty placeholder brackets" 'no' \
  "$(grep -E '^(1|2)\. .*\[.*\]' "$ROOT/templates/en/rules.md" >/dev/null && printf yes || printf no)"

# T-450: a fresh tr init seeds Kurallar.md with the protocols section --
# the whole file is copied from the template it was just measured against.
mkvault vp450tr
printf 'lang=tr\n' > "$TMP/vp450tr/.knotlog/config"
QUIPU_VAULT="$TMP/vp450tr" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "T-450: fresh tr vault's Kurallar.md carries the protocols section" 'yes' \
  "$(grep -qF '## Sıfır seviye protokoller' "$TMP/vp450tr/Kurallar.md" && printf yes || printf no)"

mkvault vp450en
printf 'lang=en\n' > "$TMP/vp450en/.knotlog/config"
QUIPU_VAULT="$TMP/vp450en" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "T-450: fresh en vault's Rules.md carries the protocols section" 'yes' \
  "$(grep -qF '## Zero-level protocols' "$TMP/vp450en/Rules.md" && printf yes || printf no)"

# T-451: the bridge block carries the compact protocol lines (DATA from
# i18n bridge_protocols/bridge_proto_NN), in BOTH AGENTS.md and CLAUDE.md,
# and the two files stay byte-identical (D6's single-source rule).
t; assert_eq "T-451: tr AGENTS.md bridge carries the protocols header" 'yes' \
  "$(grep -qF "$(mtr bridge_protocols)" "$TMP/vp450tr/AGENTS.md" && printf yes || printf no)"
t; assert_eq "T-451: tr CLAUDE.md bridge carries the protocols header" 'yes' \
  "$(grep -qF "$(mtr bridge_protocols)" "$TMP/vp450tr/CLAUDE.md" && printf yes || printf no)"
t; assert_eq "T-451: tr bridge AGENTS.md == CLAUDE.md byte-for-byte" 'yes' \
  "$(cmp -s "$TMP/vp450tr/AGENTS.md" "$TMP/vp450tr/CLAUDE.md" && printf yes || printf no)"
t; assert_eq "T-451: en AGENTS.md bridge carries the protocols header" 'yes' \
  "$(grep -qF "$(men bridge_protocols)" "$TMP/vp450en/AGENTS.md" && printf yes || printf no)"
t; assert_eq "T-451: en bridge AGENTS.md == CLAUDE.md byte-for-byte" 'yes' \
  "$(cmp -s "$TMP/vp450en/AGENTS.md" "$TMP/vp450en/CLAUDE.md" && printf yes || printf no)"

# T-452: all 13 bridge_proto_NN lines land in the bridge block, tr and en.
# The count also locks the emitter's loop bound in quipu -- shrinking it
# silently drops the last protocol from every vault's bridge.
t; assert_eq "T-452: tr bridge carries all 13 bridge_proto_NN lines" '13' \
  "$(_p452n=0; _p452i=1; while [ "$_p452i" -le 13 ]; do
       _p452k=$(printf 'bridge_proto_%02d' "$_p452i")
       grep -qF "$(mtr "$_p452k")" "$TMP/vp450tr/AGENTS.md" && _p452n=$((_p452n + 1))
       _p452i=$((_p452i + 1))
     done; printf '%d' "$_p452n")"
t; assert_eq "T-452: en bridge carries all 13 bridge_proto_NN lines" '13' \
  "$(_p452n=0; _p452i=1; while [ "$_p452i" -le 13 ]; do
       _p452k=$(printf 'bridge_proto_%02d' "$_p452i")
       grep -qF "$(men "$_p452k")" "$TMP/vp450en/AGENTS.md" && _p452n=$((_p452n + 1))
       _p452i=$((_p452i + 1))
     done; printf '%d' "$_p452n")"

# T-453: write-once holds -- a hand-edited rules file survives a second
# init untouched, protocols section included (same contract T-401 locks
# for the pre-existing blocks).
printf '\nelle eklenen kural\n' >> "$TMP/vp450tr/Kurallar.md"
QUIPU_VAULT="$TMP/vp450tr" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "T-453: a second init does not erase a hand-edited addition" 'yes' \
  "$(grep -qF 'elle eklenen kural' "$TMP/vp450tr/Kurallar.md" && printf yes || printf no)"
t; assert_eq "T-453: the hand-edited file still carries the seeded protocols section" 'yes' \
  "$(grep -qF '## Sıfır seviye protokoller' "$TMP/vp450tr/Kurallar.md" && printf yes || printf no)"

# ---- companion.md's Tone section reaches knotlog context -------------------
# The persona template's "## Üslup"/"## Tone" section is meaningful default
# behavior (brief answers, no filler, state assumptions), but until now it
# only ever reached a session through the model opening companion.md by
# hand. These tests lock: the body lands in context (Fixed part 0c), only
# the Tone body lands (not Role/Boundaries/Checkpoints), an absent file or
# absent heading stays silent, doctor warns when the heading itself is
# missing, and the block survives ctx_max pressure that the variable-part
# sections (threads/rules/facts) do not.

# T-454: a fresh tr init's context carries the tone header, its bullets and
# the priority note, in that order.
mkvault vt454tr
printf 'lang=tr\n' > "$TMP/vt454tr/.knotlog/config"
QUIPU_VAULT="$TMP/vt454tr" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; CTX454=$(QUIPU_VAULT="$TMP/vt454tr" sh "$ROOT/knotlog" context)
t; assert_eq "T-454: context carries the tone header" 'yes' \
  "$(printf '%s\n' "$CTX454" | grep -qF "$(mtr ctx_tone)" && printf yes || printf no)"
t; assert_eq "T-454: context carries a tone bullet from companion.md" 'yes' \
  "$(printf '%s\n' "$CTX454" | grep -qF 'Kısa cevap ver' && printf yes || printf no)"
t; assert_eq "T-454: context carries the tone priority note" 'yes' \
  "$(printf '%s\n' "$CTX454" | grep -qF "$(mtr ctx_tone_priority)" && printf yes || printf no)"
t; assert_eq "T-454: header, bullet and priority appear in that order" 'yes' \
  "$(printf '%s\n' "$CTX454" | awk -v h="$(mtr ctx_tone)" -v b='Kısa cevap ver' -v p="$(mtr ctx_tone_priority)" \
     'index($0,h)==1{a=NR} index($0,b){c=NR} index($0,p)==1{d=NR} END{print (a&&c&&d&&c>a&&d>c?"yes":"no")}')"

# T-455: only the Tone section's body lands -- Role/Boundaries/Checkpoints
# text (and their headings) never leak into context.
t; assert_eq "T-455: context does not carry the Role heading" 'no' \
  "$(printf '%s\n' "$CTX454" | grep -qF '## Rol' && printf yes || printf no)"
t; assert_eq "T-455: context does not carry a Boundaries bullet" 'no' \
  "$(printf '%s\n' "$CTX454" | grep -qF 'Para hareketi' && printf yes || printf no)"
t; assert_eq "T-455: context does not carry a Checkpoints bullet" 'no' \
  "$(printf '%s\n' "$CTX454" | grep -qF 'oturum sonunu bekleme' && printf yes || printf no)"

# T-456: the en mirror -- same header/bullet/priority contract.
mkvault vt456en
printf 'lang=en\n' > "$TMP/vt456en/.knotlog/config"
QUIPU_VAULT="$TMP/vt456en" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; CTX456=$(QUIPU_LANG=en QUIPU_VAULT="$TMP/vt456en" sh "$ROOT/knotlog" context)
t; assert_eq "T-456: en context carries the tone header" 'yes' \
  "$(printf '%s\n' "$CTX456" | grep -qF "$(men ctx_tone)" && printf yes || printf no)"
t; assert_eq "T-456: en context carries a tone bullet from companion.md" 'yes' \
  "$(printf '%s\n' "$CTX456" | grep -qF 'Answer briefly' && printf yes || printf no)"
t; assert_eq "T-456: en context carries the tone priority note" 'yes' \
  "$(printf '%s\n' "$CTX456" | grep -qF "$(men ctx_tone_priority)" && printf yes || printf no)"
t; assert_eq "T-456: en context does not carry the Role heading" 'no' \
  "$(printf '%s\n' "$CTX456" | grep -qF '## Role' && printf yes || printf no)"

# T-457: backwards compatibility -- an old vault with no companion.md at
# all stays silent, same contract the rules/facts sections keep.
mkvault vt457
printf 'lang=tr\n' > "$TMP/vt457/.knotlog/config"
t; CTX457=$(QUIPU_VAULT="$TMP/vt457" sh "$ROOT/knotlog" context); RC=$?
t; assert_eq "T-457: context exits 0 without a companion.md" '0' "$RC"
t; assert_eq "T-457: context emits no tone section without companion.md" 'no' \
  "$(printf '%s\n' "$CTX457" | grep -qF "$(mtr ctx_tone)" && printf yes || printf no)"
t; (cd "$TMP/vt457" && "$ROOT/knotlog" doctor) >"$TMP/vt457.out" 2>&1; RC=$?
t; assert_eq "T-457: doctor exits 0 without a companion.md" '0' "$RC"

# T-458: doctor warns when companion.md exists but the Tone heading was
# renamed/removed by hand -- the same silence class D1's mandatory-set
# warnings exist to prevent -- and context correspondingly drops the block.
CN458=$(comp_name emoji)
sed 's/^## Üslup$/## Kaldirildi/' "$TMP/vt454tr/$CN458/companion.md" > "$TMP/vt454tr/$CN458/companion.md.tmp"
cp "$TMP/vt454tr/$CN458/companion.md" "$TMP/vt454tr/$CN458/companion.md.orig"
mv "$TMP/vt454tr/$CN458/companion.md.tmp" "$TMP/vt454tr/$CN458/companion.md"
t; assert_eq "T-458: the heading is really gone from companion.md" 'no' \
  "$(grep -qF '## Üslup' "$TMP/vt454tr/$CN458/companion.md" && printf yes || printf no)"
t; (cd "$TMP/vt454tr" && "$ROOT/knotlog" doctor) >"$TMP/vt458.out" 2>&1; RC=$?
t; assert_eq "T-458: doctor still exits 0 (warn, not fail)" '0' "$RC"
t; assert_eq "T-458: doctor warns the tone heading is missing" 'yes' \
  "$(grep -qF "$(mtr doc_companion_tone_missing)" "$TMP/vt458.out" && printf yes || printf no)"
t; CTX458=$(QUIPU_VAULT="$TMP/vt454tr" sh "$ROOT/knotlog" context)
t; assert_eq "T-458: context drops the tone section once the heading is gone" 'no' \
  "$(printf '%s\n' "$CTX458" | grep -qF "$(mtr ctx_tone)" && printf yes || printf no)"
mv "$TMP/vt454tr/$CN458/companion.md.orig" "$TMP/vt454tr/$CN458/companion.md"

# T-459: the tone block rides the FIXED part -- it survives even when
# QUIPU_CTX_MAX is squeezed so tight the variable-part threads section gets
# truncated. This is the decision the whole feature rests on (C-16 drops
# variable sections silently; the tone block must never be one of them).
mkvault vt459
printf 'lang=tr\n' > "$TMP/vt459/.knotlog/config"
QUIPU_VAULT="$TMP/vt459" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
_p459i=1
while [ "$_p459i" -le 10 ]; do
  printf 'uzun bir konu satırı burada tekrar tekrar yaziliyor doldurmak icin\n' >> "$TMP/vt459/Konular.md"
  _p459i=$((_p459i + 1))
done
t; CTX459=$(QUIPU_CTX_MAX=80 QUIPU_VAULT="$TMP/vt459" sh "$ROOT/knotlog" context)
t; assert_eq "T-459: tiny ctx_max still carries the tone header" 'yes' \
  "$(printf '%s\n' "$CTX459" | grep -qF "$(mtr ctx_tone)" && printf yes || printf no)"
t; assert_eq "T-459: tiny ctx_max still carries the tone priority note" 'yes' \
  "$(printf '%s\n' "$CTX459" | grep -qF "$(mtr ctx_tone_priority)" && printf yes || printf no)"
t; assert_eq "T-459: tiny ctx_max truncates the threads section (control: it IS pressured)" 'yes' \
  "$(printf '%s\n' "$CTX459" | grep -qF "$(mtr ctx_truncated)" && printf yes || printf no)"

# T-460: a fresh, untouched init vault still exits doctor clean -- the tone
# feature adds no mandatory contract, only a warning for a heading a user
# actively removed.
t; (cd "$TMP/vt459" && "$ROOT/knotlog" doctor) >"$TMP/vt460.out" 2>&1; RC=$?
t; assert_eq "T-460: an untouched fresh vault keeps doctor at exit 0" '0' "$RC"
t; assert_eq "T-460: an untouched fresh vault gets no tone warning" 'no' \
  "$(grep -qF "$(mtr doc_companion_tone_missing)" "$TMP/vt460.out" && printf yes || printf no)"

# ---- T-461..T-471: tone presets (knotlog tone, tone/<lang>/<slug>.md, --tone) ----
#
# Nine shipped presets, chosen by the maintainer: varsayilan/profesyonel/dostane/
# icten/siradisi/etkili/sivridilli/ogretici/kaomoji. Priority: config's tone= (a
# shipped preset file) wins over companion.md's own Tone section; an unset
# or invalid tone= falls back to companion.md exactly as before presets
# existed (_q_tone_resolve is the single place both paths are decided).

TONE_SLUGS='varsayilan profesyonel dostane icten siradisi etkili sivridilli ogretici kaomoji'

# T-461: all nine presets ship in both languages, and the shipped slug set
# matches the hardcoded list `knotlog tone`/`init --tone` validate against
# (a drift here would mean a preset name typo silently becomes unselectable
# or a phantom slug validates but has no file to inject).
t; assert_eq "T-461: tone/tr has exactly the nine shipped slugs" 'yes' \
  "$(_t461=$(find "$ROOT/tone/tr" -maxdepth 1 -name '*.md' -exec basename {} .md \; | sort | tr '\n' ' ' | sed 's/ $//'); \
     # shellcheck disable=SC2086 # TONE_SLUGS is a deliberately unquoted word list
     _t461_want=$(printf '%s\n' $TONE_SLUGS | sort | tr '\n' ' ' | sed 's/ $//'); \
     [ "$_t461" = "$_t461_want" ] && printf yes || printf no)"
t; assert_eq "T-461: tone/en has exactly the same nine slugs as tone/tr" 'yes' \
  "$(_t461tr=$(find "$ROOT/tone/tr" -maxdepth 1 -name '*.md' -exec basename {} \; | sort); \
     _t461en=$(find "$ROOT/tone/en" -maxdepth 1 -name '*.md' -exec basename {} \; | sort); \
     [ "$_t461tr" = "$_t461en" ] && printf yes || printf no)"
t; assert_eq "T-461: none of the nine preset files are empty" 'yes' \
  "$(_t461ok=yes; for _t461l in tr en; do for _t461s in $TONE_SLUGS; do \
       [ -s "$ROOT/tone/$_t461l/$_t461s.md" ] || _t461ok=no; done; done; printf '%s' "$_t461ok")"

# T-462: tone=<valid slug> in config wins over companion.md's own Tone
# section -- context injects the PRESET's text, not companion.md's, even
# though companion.md still carries a Tone heading of its own.
mkvault vt462
printf 'lang=tr\n' > "$TMP/vt462/.knotlog/config"
QUIPU_VAULT="$TMP/vt462" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
printf 'tone=etkili\n' >> "$TMP/vt462/.knotlog/config"
t; CTX462=$(QUIPU_VAULT="$TMP/vt462" sh "$ROOT/knotlog" context)
t; assert_eq "T-462: context carries the etkili preset's distinctive line" 'yes' \
  "$(printf '%s\n' "$CTX462" | grep -qF 'Kullanıcının zaten bildiği bağlamı tekrar yazma' && printf yes || printf no)"
t; assert_eq "T-462: context does NOT carry companion.md's own default tone bullet" 'no' \
  "$(printf '%s\n' "$CTX462" | grep -qF 'Emin olmadığın yerde sessizce tahmin etme' && printf yes || printf no)"
t; assert_eq "T-462: the tone header and priority note still frame the preset" 'yes' \
  "$(printf '%s\n' "$CTX462" | grep -qF "$(mtr ctx_tone)" && printf '%s\n' "$CTX462" | grep -qF "$(mtr ctx_tone_priority)" && printf yes || printf no)"

# T-463: tone= unset falls back to companion.md's OWN (possibly hand-edited)
# Tone section -- a custom line the user wrote reaches context verbatim,
# proving the fallback reads the live file, not a cached/default copy.
CN463=$(comp_name emoji)
printf '## Üslup\n- Elle yazılmış özel bir üslup satırı burada.\n' >> "$TMP/vt462/$CN463/companion.md"
sed -n '/^## Üslup/,/^## /p' "$TMP/vt462/$CN463/companion.md" >/dev/null # sanity no-op
mkvault vt463
printf 'lang=tr\n' > "$TMP/vt463/.knotlog/config"
QUIPU_VAULT="$TMP/vt463" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
CN463b=$(comp_name emoji)
printf '\n## Üslup\n- Elle yazılmış özel bir üslup satırı burada.\n' > "$TMP/vt463.tone_append"
awk '/^## Üslup$/{print;print "- Elle yazılmış özel bir üslup satırı burada.";skip=1;next} skip && /^$/{skip=0} skip{next} {print}' \
  "$TMP/vt463/$CN463b/companion.md" > "$TMP/vt463/$CN463b/companion.md.tmp" && \
  mv "$TMP/vt463/$CN463b/companion.md.tmp" "$TMP/vt463/$CN463b/companion.md"
t; CTX463=$(QUIPU_VAULT="$TMP/vt463" sh "$ROOT/knotlog" context)
t; assert_eq "T-463: no tone= -- context carries the hand-edited companion line" 'yes' \
  "$(printf '%s\n' "$CTX463" | grep -qF 'Elle yazılmış özel bir üslup satırı burada' && printf yes || printf no)"
t; assert_eq "T-463: no tone= -- context does not carry any preset's distinctive line" 'no' \
  "$(printf '%s\n' "$CTX463" | grep -qF 'Kullanıcının zaten bildiği bağlamı tekrar yazma' && printf yes || printf no)"

# T-464: an invalid tone= (unknown slug) is NEVER a hard error -- context
# silently falls back to companion.md, and doctor surfaces the gap as a
# warning (this project's silent-fallback rule: never invisible).
printf 'tone=bilmedigim-bir-slug\n' >> "$TMP/vt463/.knotlog/config"
t; CTX464=$(QUIPU_VAULT="$TMP/vt463" sh "$ROOT/knotlog" context); RC=$?
t; assert_eq "T-464: context exits 0 on an invalid tone=" '0' "$RC"
t; assert_eq "T-464: context still carries the companion fallback text" 'yes' \
  "$(printf '%s\n' "$CTX464" | grep -qF 'Elle yazılmış özel bir üslup satırı burada' && printf yes || printf no)"
t; (cd "$TMP/vt463" && "$ROOT/knotlog" doctor) >"$TMP/vt464.out" 2>&1; RC=$?
t; assert_eq "T-464: doctor still exits 0 (warn, not fail) on invalid tone=" '0' "$RC"
t; assert_eq "T-464: doctor warns tone= names no shipped preset" 'yes' \
  "$(grep -qF "$(memfmt tr doc_tone_invalid bilmedigim-bir-slug)" "$TMP/vt464.out" && printf yes || printf no)"

# T-465: `knotlog tone` (no args) prints WHICH source is active -- preset,
# companion.md, or neither -- the "why is it talking like this" answer.
awk '!/^tone=/' "$TMP/vt463/.knotlog/config" > "$TMP/vt463/.knotlog/config.tmp" && \
  mv "$TMP/vt463/.knotlog/config.tmp" "$TMP/vt463/.knotlog/config"
t; assert_eq "T-465: no tone=, companion has a Tone heading -> source=companion" 'yes' \
  "$( (cd "$TMP/vt463" && "$ROOT/knotlog" tone) | grep -qF "$(mtr tone_current_companion)" && printf yes || printf no)"
t; assert_eq "T-465: tone=etkili -> source=preset, names the preset" 'yes' \
  "$( (cd "$TMP/vt462" && "$ROOT/knotlog" tone) | grep -qF "$(memfmt tr tone_current_preset "$(mtr tone_name_etkili)" etkili)" && printf yes || printf no)"
mkvault vt465none
printf 'lang=tr\n' > "$TMP/vt465none/.knotlog/config"
t; assert_eq "T-465: no companion.md at all -> source=none" 'yes' \
  "$( (cd "$TMP/vt465none" && "$ROOT/knotlog" tone) | grep -qF "$(mtr tone_current_none)" && printf yes || printf no)"

# T-466: `knotlog tone --list` prints all nine presets (name + description)
# and marks whichever one is currently active.
t; LIST466=$(cd "$TMP/vt462" && "$ROOT/knotlog" tone --list)
t; assert_eq "T-466: --list prints all nine slugs" 'yes' \
  "$(_t466ok=yes; for _t466s in $TONE_SLUGS; do printf '%s\n' "$LIST466" | grep -qF "$_t466s" || _t466ok=no; done; printf '%s' "$_t466ok")"
t; assert_eq "T-466: --list marks the active preset (etkili)" 'yes' \
  "$(printf '%s\n' "$LIST466" | awk -v m="$(mtr tone_list_marker)" -v s='etkili' 'index($0,m)==3 && index($0,s) { f = 1 } END { print (f ? "yes" : "no") }')"
t; assert_eq "T-466: --list prints each preset's description" 'yes' \
  "$(printf '%s\n' "$LIST466" | grep -qF "$(mtr tone_desc_ogretici)" && printf yes || printf no)"

# T-467: `knotlog tone <unknown-slug>` is a hard error (this is a user typing
# a command, not context reading a config file that might be stale) --
# nonzero exit, no config write.
cp "$TMP/vt462/.knotlog/config" "$TMP/vt467.config.before"
t; (cd "$TMP/vt462" && "$ROOT/knotlog" tone bilmiyorum) >"$TMP/vt467.out" 2>&1; RC=$?
t; assert_eq "T-467: an unknown slug exits nonzero" 'yes' "$([ "$RC" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-467: the error names the bad slug and lists valid ones" 'yes' \
  "$(grep -qF "$(memfmt tr err_tone_unknown bilmiyorum)" "$TMP/vt467.out" && printf yes || printf no)"
t; assert_eq "T-467: config is untouched after a rejected slug" 'yes' \
  "$(cmp -s "$TMP/vt467.config.before" "$TMP/vt462/.knotlog/config" && printf yes || printf no)"

# T-468: backward compatibility -- a vault with no tone= key produces a
# context whose tone block is decided purely by companion.md, unaffected
# by the tone-preset feature's own machinery (same shape T-454 already
# locks; this test additionally proves an UNRELATED config key does not
# change the outcome, isolating the fallback to tone= specifically).
mkvault vt468
printf 'lang=tr\n' > "$TMP/vt468/.knotlog/config"
QUIPU_VAULT="$TMP/vt468" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; CTX468A=$(QUIPU_VAULT="$TMP/vt468" sh "$ROOT/knotlog" context | grep -v "^$(mtr ctx_now | cut -d: -f1):")
printf 'ctx_max=5000\n' >> "$TMP/vt468/.knotlog/config"
t; CTX468B=$(QUIPU_VAULT="$TMP/vt468" sh "$ROOT/knotlog" context | grep -v "^$(mtr ctx_now | cut -d: -f1):")
t; assert_eq "T-468: an unrelated config key never changes the tone block (no tone=)" 'yes' \
  "$([ "$CTX468A" = "$CTX468B" ] && printf yes || printf no)"

# T-469: the preset block rides the FIXED part too -- it survives a
# QUIPU_CTX_MAX squeeze tight enough to truncate the variable-part threads
# section, the same guarantee T-459 locks for the companion-fallback path.
mkvault vt469
printf 'lang=tr\n' > "$TMP/vt469/.knotlog/config"
QUIPU_VAULT="$TMP/vt469" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
printf 'tone=profesyonel\n' >> "$TMP/vt469/.knotlog/config"
_p469i=1
while [ "$_p469i" -le 10 ]; do
  printf 'uzun bir konu satırı burada tekrar tekrar yaziliyor doldurmak icin\n' >> "$TMP/vt469/Konular.md"
  _p469i=$((_p469i + 1))
done
t; CTX469=$(QUIPU_CTX_MAX=80 QUIPU_VAULT="$TMP/vt469" sh "$ROOT/knotlog" context)
t; assert_eq "T-469: tiny ctx_max still carries the preset's tone header" 'yes' \
  "$(printf '%s\n' "$CTX469" | grep -qF "$(mtr ctx_tone)" && printf yes || printf no)"
t; assert_eq "T-469: tiny ctx_max still carries the preset's distinctive line" 'yes' \
  "$(printf '%s\n' "$CTX469" | grep -qF 'gerekçeyi sonuçtan sonra ver' && printf yes || printf no)"
t; assert_eq "T-469: tiny ctx_max truncates the threads section (control: it IS pressured)" 'yes' \
  "$(printf '%s\n' "$CTX469" | grep -qF "$(mtr ctx_truncated)" && printf yes || printf no)"

# T-470: doctor's shipped-files check names all eighteen tone/<lang>/<slug>.md
# paths (derived from the language list since T-1000) -- without this, an install missing tone/ would report a clean
# doctor while `knotlog tone --list` (and every preset) silently has nothing
# to show.
t; assert_eq "T-470: doctor derives the tone/ paths of every language from the language list" 'yes' \
  "$(_t470ok=yes; grep -qF 'for _q_ld in templates tone flair; do' "$ROOT/knotlog" || _t470ok=no; for _t470l in tr en; do for _t470s in $TONE_SLUGS; do \
       [ -f "$ROOT/tone/$_t470l/$_t470s.md" ] || _t470ok=no; done; done; printf '%s' "$_t470ok")"
t; assert_eq "T-470: doctor reports every shipped tone file ok on a stock checkout" 'yes' \
  "$( (cd "$TMP/vt469" && "$ROOT/knotlog" doctor) 2>&1 | \
     awk -F"$TAB" -v s="$(mtr doc_ok)" -v want="$(find "$ROOT/tone" -name "*.md" -type f | wc -l | tr -d ' ')" 'index($2,"tone/")==1 && $1==s{n++} END{print (n==want+0 && want>=18?"yes":"no")}')"

# T-471: `knotlog init --tone <slug>` writes tone= directly (no interactive
# question -- same precedent as --purpose), and `install`'s --no-prompt
# path forwards --tone through to init (static: install builds init's
# argv itself, so a missing forward line here is a silent feature loss,
# not a crash -- lock the forwarding in the source).
mkvault vt471
QUIPU_VAULT="$TMP/vt471" sh "$ROOT/knotlog" init --lang tr --tone icten --no-prompt >/dev/null 2>&1
t; assert_eq "T-471: init --tone writes tone= to config" 'yes' \
  "$(grep -qF 'tone=icten' "$TMP/vt471/.knotlog/config" && printf yes || printf no)"
t; assert_eq "T-471: knotlog tone confirms the preset init wrote" 'yes' \
  "$( (cd "$TMP/vt471" && "$ROOT/knotlog" tone) | grep -qF "$(mtr tone_name_icten)" && printf yes || printf no)"
t; assert_eq "T-471: init rejects an unknown --tone slug before writing anything" 'yes' \
  "$(if QUIPU_VAULT="$TMP/vt471b" sh "$ROOT/knotlog" init --lang tr --tone bogus --no-prompt >/dev/null 2>&1; then \
       printf no; \
     elif [ ! -d "$TMP/vt471b" ]; then printf yes; else printf no; fi)"
# Functional (not static): install's --no-prompt path must actually forward
# --tone through to the init call it makes internally -- a removed/typo'd
# forwarding line is a silent feature loss (install exits 0, the vault just
# never gets tone= written), so this has to run install for real and read
# the resulting vault's config, not just grep the source for the line.
TONE471_PARENT="$TMP/install-tone-parent"
mkdir -p "$TONE471_PARENT"
t; PATH="$INSTALL_TOOLS" sh "$ROOT/knotlog" install --no-link --no-git "$TONE471_PARENT" \
  --no-prompt --lang tr --user Tone471 --tone sivridilli \
  >"$TMP/install-tone.out" 2>"$TMP/install-tone.err"; RC=$?
TONE471_TARGET="$TONE471_PARENT/Tone471's Knotlog"
t; assert_eq "T-471: install --tone exits 0" '0' "$RC"
t; assert_eq "T-471: install forwards --tone to init (tone= lands in the installed vault)" 'yes' \
  "$(grep -qF 'tone=sivridilli' "$TONE471_TARGET/.knotlog/config" && printf yes || printf no)"
t; assert_eq "T-471: the installed vault's tone command confirms the forwarded preset" 'yes' \
  "$( (cd "$TONE471_TARGET" && "$ROOT/knotlog" tone) | grep -qF "$(mtr tone_name_sivridilli)" && printf yes || printf no)"

# ---- T-472..T-473: fix round -- invalid tone= must not read as "unset",
# and --list's columns must not corrupt on multi-byte names ----
#
# Independent orchestrator verification measured two defects in what
# T-461..T-471 shipped: (1) `knotlog tone` said "preset ayarlı değil"/"no
# preset set" for a tone= that WAS set but names no shipped preset -- the
# exact silent-fallback-reads-as-success class this whole feature exists
# to prevent, and the one thing the command's own doc comment (T-465)
# promises never to do; (2) `tone_list_row`'s `%-13s` padded the NAME
# column by BYTE count, so a Turkish name with İ/ı/ş/ğ (multi-byte in
# UTF-8) padded short and every following description drifted left.

# T-472: an invalid tone= is never silently read back as "no preset set" --
# `knotlog tone` and `--list`'s footer must name the bad slug and say it
# does not resolve, in BOTH shapes (companion.md still has a Tone section
# to fall back to; companion.md has none either).
mkvault vt472a
printf 'lang=tr\n' > "$TMP/vt472a/.knotlog/config"
QUIPU_VAULT="$TMP/vt472a" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
printf 'tone=uydurma-bir-slug\n' >> "$TMP/vt472a/.knotlog/config"
t; TONECMD472A=$(cd "$TMP/vt472a" && "$ROOT/knotlog" tone)
t; assert_eq "T-472: invalid tone= (companion has Tone) names the bad slug, not \"unset\"" 'yes' \
  "$(printf '%s\n' "$TONECMD472A" | grep -qF "$(memfmt tr tone_current_invalid_companion uydurma-bir-slug)" && printf yes || printf no)"
t; assert_eq "T-472: invalid tone= (companion has Tone) does NOT print the plain unset message" 'no' \
  "$(printf '%s\n' "$TONECMD472A" | grep -qF "$(mtr tone_current_companion)" && printf yes || printf no)"
t; LIST472A=$(cd "$TMP/vt472a" && "$ROOT/knotlog" tone --list)
t; assert_eq "T-472: --list's footer (companion has Tone) names the bad slug too" 'yes' \
  "$(printf '%s\n' "$LIST472A" | grep -qF "$(memfmt tr tone_list_footer_invalid_companion uydurma-bir-slug)" && printf yes || printf no)"

mkvault vt472b
printf 'lang=tr\ntone=baska-uydurma-slug\n' > "$TMP/vt472b/.knotlog/config"
t; TONECMD472B=$(cd "$TMP/vt472b" && "$ROOT/knotlog" tone)
t; assert_eq "T-472: invalid tone= (no companion.md at all) names the bad slug, not \"none\"" 'yes' \
  "$(printf '%s\n' "$TONECMD472B" | grep -qF "$(memfmt tr tone_current_invalid_none baska-uydurma-slug)" && printf yes || printf no)"
t; assert_eq "T-472: invalid tone= (no companion.md) does NOT print the plain none message" 'no' \
  "$(printf '%s\n' "$TONECMD472B" | grep -qF "$(mtr tone_current_none)" && printf yes || printf no)"
t; LIST472B=$(cd "$TMP/vt472b" && "$ROOT/knotlog" tone --list)
t; assert_eq "T-472: --list's footer (no companion.md) names the bad slug too" 'yes' \
  "$(printf '%s\n' "$LIST472B" | grep -qF "$(memfmt tr tone_list_footer_invalid_none baska-uydurma-slug)" && printf yes || printf no)"

# T-473: --list's columns survive multi-byte preset names -- lock the exact
# rendered line for three presets whose Turkish names carry multi-byte
# UTF-8 characters (İçten, Sıra Dışı, Öğretici) against the SAME row
# format the command itself uses (mtr tone_list_row), so a byte-counted
# %-Ns regression fails this the moment it's reintroduced.
t; LIST473=$(cd "$TMP/vt472a" && "$ROOT/knotlog" tone --list)
t; assert_eq "T-473: the icten row matches the controlled row format exactly" 'yes' \
  "$(printf '%s\n' "$LIST473" | grep -qxF "$(memfmt tr tone_list_row '' icten "$(mtr tone_name_icten)" "$(mtr tone_desc_icten)")" && printf yes || printf no)"
t; assert_eq "T-473: the siradisi row matches the controlled row format exactly" 'yes' \
  "$(printf '%s\n' "$LIST473" | grep -qxF "$(memfmt tr tone_list_row '' siradisi "$(mtr tone_name_siradisi)" "$(mtr tone_desc_siradisi)")" && printf yes || printf no)"
t; assert_eq "T-473: the ogretici row matches the controlled row format exactly" 'yes' \
  "$(printf '%s\n' "$LIST473" | grep -qxF "$(memfmt tr tone_list_row '' ogretici "$(mtr tone_name_ogretici)" "$(mtr tone_desc_ogretici)")" && printf yes || printf no)"
t; assert_eq "T-473: the description immediately follows an em dash, never a run of spaces" 'yes' \
  "$(printf '%s\n' "$LIST473" | awk -v d="$(mtr tone_desc_icten)" 'index($0,d){f = (index($0," — " d) > 0)} END{print (f?"yes":"no")}')"

# ---- B-K2: doc_threads_overflow -- doc_threads_empty's missing symmetric
# case. doc_threads_empty warns when Threads.md/Konular.md is empty; before
# this, nothing warned when the file OVERFLOWED knotlog context's own
# injection budget (the Konular-Butce-Tasmasi.md incident: a 100.6 KB file
# against a 10 KB budget silently dropped the oldest entries every session
# for months while doctor stayed green). QUIPU_CTX_MAX=1 is used to force
# the overflow deterministically regardless of today's date/weekday string
# or any other fixed-part content: the fixed part (the "now" line alone) is
# always far larger than 1 byte, so _q_budget is always negative and clamped
# to 0 in the doctor code -- making the dropped fraction exactly 100% and
# the reported budget exactly 0, independent of the day this suite runs.

# T-474: en vault, a MARKED and filled Threads.md, ctx_max squeezed to 1 ->
# doctor warns doc_threads_overflow with the exact file size, a 0 budget,
# and 100%, and does NOT also raise doc_threads_empty (the file is filled).
mkvault vt474
{
  printf '<!-- quipu:threads:start -->\n'
  printf 'a filled threads line, well past one byte\n'
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vt474/Threads.md"
T474SIZE=$(wc -c < "$TMP/vt474/Threads.md" | tr -d ' ')
t; DOUT474=$(QUIPU_CTX_MAX=1 QUIPU_LANG=en QUIPU_VAULT="$TMP/vt474" "$ROOT/knotlog" doctor 2>&1); RC=$?
assert_eq "T-474: doctor still exits 0 under a squeezed budget" '0' "$RC"
t; assert_eq "T-474: doctor warns doc_threads_overflow with the exact size/budget/percent" 'yes' \
  "$(printf '%s\n' "$DOUT474" | grep -qF "$(memfmt en doc_threads_overflow Threads.md "$T474SIZE" 0 100)" && printf yes || printf no)"
t; assert_eq "T-474: doctor does NOT also warn doc_threads_empty (the file is filled)" 'no' \
  "$(printf '%s\n' "$DOUT474" | grep -qF "$(men doc_threads_empty)" && printf yes || printf no)"

# T-475: same scenario in Turkish -- Konular.md, tr message, same numbers.
mkvault vt475
printf 'lang=tr\n' > "$TMP/vt475/.knotlog/config"
{
  printf '<!-- quipu:threads:start -->\n'
  printf 'bir bayttan çok daha uzun, doldurulmuş bir konu satırı\n'
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vt475/Konular.md"
T475SIZE=$(wc -c < "$TMP/vt475/Konular.md" | tr -d ' ')
t; DOUT475=$(QUIPU_CTX_MAX=1 QUIPU_LANG=tr QUIPU_VAULT="$TMP/vt475" "$ROOT/knotlog" doctor 2>&1); RC=$?
assert_eq "T-475: doctor still exits 0 under a squeezed budget (tr)" '0' "$RC"
t; assert_eq "T-475: doctor warns doc_threads_overflow with the exact size/budget/percent (tr)" 'yes' \
  "$(printf '%s\n' "$DOUT475" | grep -qF "$(memfmt tr doc_threads_overflow Konular.md "$T475SIZE" 0 100)" && printf yes || printf no)"

# T-476: false-positive lock -- a marked, filled Threads.md that comfortably
# fits inside a generous budget must NOT print doc_threads_overflow.
mkvault vt476
{
  printf '<!-- quipu:threads:start -->\n'
  printf 'a short line\n'
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vt476/Threads.md"
t; DOUT476=$(QUIPU_CTX_MAX=100000 QUIPU_LANG=en QUIPU_VAULT="$TMP/vt476" "$ROOT/knotlog" doctor 2>&1); RC=$?
assert_eq "T-476: doctor exits 0 with a generous budget" '0' "$RC"
OVFL476_STATIC=$(mi18n en doc_threads_overflow | awk -F'%[sd]' '{print $3}')
t; assert_eq "T-476: doctor prints no doc_threads_overflow row when the file fits" 'no' \
  "$(printf '%s\n' "$DOUT476" | grep -qF "$OVFL476_STATIC" && printf yes || printf no)"
t; assert_eq "T-476: doctor prints no doc_threads_empty row either (file is filled)" 'no' \
  "$(printf '%s\n' "$DOUT476" | grep -qF "$(men doc_threads_empty)" && printf yes || printf no)"

# ---- T-477..T-483: B-K1 pin block (<!-- quipu:pin:start/end -->) ----
#
# A block delimited by these markers inside Konular.md/Threads.md is
# guaranteed to survive `knotlog context`'s own truncation (the
# Konular-Butce-Tasmasi.md incident B-K1 fixes): its bytes are folded into
# the FIXED part of the ctx_max budget -- the same treatment the tone
# block gets (T-459/T-469) -- never the croppable threads section, and it
# is always emitted ABOVE the (possibly truncated) topics that follow it.
# A pin block that is by itself bigger than ctx_max cannot honor that
# guarantee without silently exceeding the configured budget, so doctor
# reports it as a FAIL (not a warn) rather than emit it and say nothing.

# T-477: tr vault, ctx_max squeezed to 80 -- the pin block still reaches
# context even though the ordinary threads content around it is truncated
# (the control half of the assertion: the budget IS under real pressure,
# same shape as T-459/T-469).
mkvault vt477
printf 'lang=tr\n' > "$TMP/vt477/.knotlog/config"
QUIPU_VAULT="$TMP/vt477" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
{
  printf '<!-- quipu:pin:start -->\n'
  printf 'SABIT: kritik bir randevu satırı\n'
  printf '<!-- quipu:pin:end -->\n'
  _p477i=1
  while [ "$_p477i" -le 10 ]; do
    printf 'uzun bir konu satırı burada tekrar tekrar yaziliyor doldurmak icin\n'
    _p477i=$((_p477i + 1))
  done
} > "$TMP/vt477/Konular.md"
t; CTX477=$(QUIPU_CTX_MAX=80 QUIPU_VAULT="$TMP/vt477" sh "$ROOT/knotlog" context)
t; assert_eq "T-477: tiny ctx_max still carries the pin block's start marker" 'yes' \
  "$(printf '%s\n' "$CTX477" | grep -qF '<!-- quipu:pin:start -->' && printf yes || printf no)"
t; assert_eq "T-477: tiny ctx_max still carries the pin block's own line" 'yes' \
  "$(printf '%s\n' "$CTX477" | grep -qF 'SABIT: kritik bir randevu satırı' && printf yes || printf no)"
t; assert_eq "T-477: tiny ctx_max truncates the ordinary threads content around it (control)" 'yes' \
  "$(printf '%s\n' "$CTX477" | grep -qF "$(mtr ctx_truncated)" && printf yes || printf no)"

# T-478: same shape in English -- Threads.md, lang=en, en i18n strings.
mkvault vt478
printf 'lang=en\n' > "$TMP/vt478/.knotlog/config"
QUIPU_VAULT="$TMP/vt478" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
{
  printf '<!-- quipu:pin:start -->\n'
  printf 'PINNED: a critical appointment line\n'
  printf '<!-- quipu:pin:end -->\n'
  _p478i=1
  while [ "$_p478i" -le 10 ]; do
    printf 'a long thread line repeated over and over just to fill space\n'
    _p478i=$((_p478i + 1))
  done
} > "$TMP/vt478/Threads.md"
t; CTX478=$(QUIPU_CTX_MAX=80 QUIPU_LANG=en QUIPU_VAULT="$TMP/vt478" sh "$ROOT/knotlog" context)
t; assert_eq "T-478: en, tiny ctx_max still carries the pin block's start marker" 'yes' \
  "$(printf '%s\n' "$CTX478" | grep -qF '<!-- quipu:pin:start -->' && printf yes || printf no)"
t; assert_eq "T-478: en, tiny ctx_max still carries the pin block's own line" 'yes' \
  "$(printf '%s\n' "$CTX478" | grep -qF 'PINNED: a critical appointment line' && printf yes || printf no)"
t; assert_eq "T-478: en, tiny ctx_max truncates the ordinary threads content (control)" 'yes' \
  "$(printf '%s\n' "$CTX478" | grep -qF "$(men ctx_truncated)" && printf yes || printf no)"

# T-479: ordering -- the pin block appears ABOVE the topics section, not
# interleaved or below it (the contract's "üstünde görünsün" clause).
mkvault vt479
printf 'lang=tr\n' > "$TMP/vt479/.knotlog/config"
QUIPU_VAULT="$TMP/vt479" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
{
  printf 'bir önceki konu satırı\n'
  printf '<!-- quipu:pin:start -->\n'
  printf 'SABIT: ara sabit satır\n'
  printf '<!-- quipu:pin:end -->\n'
  printf 'bir sonraki konu satırı\n'
} > "$TMP/vt479/Konular.md"
t; CTX479=$(QUIPU_VAULT="$TMP/vt479" sh "$ROOT/knotlog" context)
t; assert_eq "T-479: the pin start marker's line number precedes the topics header's" 'yes' \
  "$(printf '%s\n' "$CTX479" | awk -v hdr="$(mtr ctx_threads)" '
      /<!-- quipu:pin:start -->/ && !pin { pin = NR }
      $0 == hdr && !h { h = NR }
      END { print (pin && h && pin < h) ? "yes" : "no" }')"

# T-480: pin-less regression -- adding a pin block changes `knotlog context`,
# but removing it again reproduces the EXACT prior bytes (cmp). This is
# the "a vault that never uses this feature sees byte-identical output"
# guarantee proven at the CLI level, without depending on any external
# snapshot of the pre-B-K1 binary.
mkvault vt480
printf 'lang=tr\n' > "$TMP/vt480/.knotlog/config"
QUIPU_VAULT="$TMP/vt480" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
_p480i=1
while [ "$_p480i" -le 15 ]; do
  printf 'sıradan bir konu satırı %02d dolgu icin\n' "$_p480i"
  _p480i=$((_p480i + 1))
done > "$TMP/vt480/Konular.md"
cp "$TMP/vt480/Konular.md" "$TMP/vt480.konular.before"
t; QUIPU_CTX_MAX=300 QUIPU_VAULT="$TMP/vt480" sh "$ROOT/knotlog" context > "$TMP/vt480.ctx.before"
{
  printf '<!-- quipu:pin:start -->\n'
  printf 'gecici pin satiri\n'
  printf '<!-- quipu:pin:end -->\n'
  cat "$TMP/vt480.konular.before"
} > "$TMP/vt480/Konular.md"
t; QUIPU_CTX_MAX=300 QUIPU_VAULT="$TMP/vt480" sh "$ROOT/knotlog" context > "$TMP/vt480.ctx.withpin"
t; assert_eq "T-480: adding a pin block DOES change context (control)" 'no' \
  "$(cmp -s "$TMP/vt480.ctx.before" "$TMP/vt480.ctx.withpin" && printf yes || printf no)"
cp "$TMP/vt480.konular.before" "$TMP/vt480/Konular.md"
t; QUIPU_CTX_MAX=300 QUIPU_VAULT="$TMP/vt480" sh "$ROOT/knotlog" context > "$TMP/vt480.ctx.after"
t; assert_eq "T-480: removing the pin block again is byte-identical to before (cmp)" 'yes' \
  "$(ctx_same_body "$TMP/vt480.ctx.before" "$TMP/vt480.ctx.after" && printf yes || printf no)"

# T-481: doctor FAILS (not warns) when the pin block alone is bigger than
# ctx_max -- the "never truncated" guarantee has nowhere to come from, so
# this is an error, distinct in tone from doc_threads_overflow's warn.
mkvault vt481
{
  printf '<!-- quipu:pin:start -->\n'
  printf 'a pin line comfortably longer than one byte\n'
  printf '<!-- quipu:pin:end -->\n'
} > "$TMP/vt481/Threads.md"
T481SIZE=$(awk '/<!-- quipu:pin:start -->/{p=1} p{print} /<!-- quipu:pin:end -->/{if(p) exit}' "$TMP/vt481/Threads.md" | LC_ALL=C wc -c | tr -d ' ')
t; DOUT481=$(QUIPU_CTX_MAX=1 QUIPU_LANG=en QUIPU_VAULT="$TMP/vt481" "$ROOT/knotlog" doctor 2>&1); RC=$?
t; assert_eq "T-481: doctor exits NONZERO when the pin block alone overflows ctx_max" 'yes' \
  "$([ "$RC" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-481: doctor's fail row names the exact pin size and ctx_max" 'yes' \
  "$(printf '%s\n' "$DOUT481" | grep -qF "$(memfmt en doc_pin_oversize "$T481SIZE" 1)" && printf yes || printf no)"
t; assert_eq "T-481: the row is a FAIL row, not a WARN row" 'yes' \
  "$(printf '%s\n' "$DOUT481" | awk -F"$TAB" -v f="$(men doc_fail)" -v m="$(memfmt en doc_pin_oversize "$T481SIZE" 1)" '$1==f && $3==m{found=1} END{print (found?"yes":"no")}')"

# T-482: same scenario in Turkish -- Konular.md, tr message, same numbers.
mkvault vt482
printf 'lang=tr\n' > "$TMP/vt482/.knotlog/config"
{
  printf '<!-- quipu:pin:start -->\n'
  printf 'bir bayttan çok daha uzun bir sabit satır\n'
  printf '<!-- quipu:pin:end -->\n'
} > "$TMP/vt482/Konular.md"
T482SIZE=$(awk '/<!-- quipu:pin:start -->/{p=1} p{print} /<!-- quipu:pin:end -->/{if(p) exit}' "$TMP/vt482/Konular.md" | LC_ALL=C wc -c | tr -d ' ')
t; DOUT482=$(QUIPU_CTX_MAX=1 QUIPU_LANG=tr QUIPU_VAULT="$TMP/vt482" "$ROOT/knotlog" doctor 2>&1); RC=$?
t; assert_eq "T-482: doctor exits NONZERO (tr) when the pin block alone overflows ctx_max" 'yes' \
  "$([ "$RC" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-482: doctor's fail row names the exact pin size and ctx_max (tr)" 'yes' \
  "$(printf '%s\n' "$DOUT482" | grep -qF "$(memfmt tr doc_pin_oversize "$T482SIZE" 1)" && printf yes || printf no)"

# T-483: false-positive lock -- a pin block that comfortably fits inside a
# generous ctx_max must NOT raise doc_pin_oversize, and doctor stays at
# exit 0.
mkvault vt483
{
  printf '<!-- quipu:pin:start -->\n'
  printf 'a short pinned line\n'
  printf '<!-- quipu:pin:end -->\n'
} > "$TMP/vt483/Threads.md"
t; DOUT483=$(QUIPU_CTX_MAX=100000 QUIPU_LANG=en QUIPU_VAULT="$TMP/vt483" "$ROOT/knotlog" doctor 2>&1); RC=$?
t; assert_eq "T-483: doctor exits 0 with a generous budget" '0' "$RC"
OVSZ483_STATIC=$(mi18n en doc_pin_oversize | awk -F'%d' '{print $1}')
t; assert_eq "T-483: doctor prints no doc_pin_oversize row when the pin fits" 'no' \
  "$(printf '%s\n' "$DOUT483" | grep -qF "$OVSZ483_STATIC" && printf yes || printf no)"

# ---- T-504..T-507: B-K5 doc_threads_overflow excludes the pin block -------
#
# doc_threads_overflow (B-K2, above) compared the WHOLE threads file's size
# against $_q_budget -- but $_q_budget already had the pin block's bytes
# subtracted out of it (B-K1: pin joins $_q_fixed, never the croppable
# threads section). A vault with a pin block therefore had its pin bytes
# charged TWICE -- once against the budget, once against the size being
# measured -- so the warning always overstated the dropped percentage, and
# could even fire as a false positive on a vault whose actual croppable
# content fits comfortably. The fix subtracts the same pin footprint
# (_q_pin, the exact global _q_pin_extract/_q_ctx_text already computed)
# from the file size before comparing.

# T-504: en vault, pin block + threads content that together overflow a
# real (non-clamped) positive budget -- the warning's size/budget/percent
# must reflect the file size MINUS the pin block, not the raw file size.
mkvault vt504
{
  printf '<!-- quipu:threads:start -->\n'
  printf '<!-- quipu:pin:start -->\n'
  _p504i=1
  while [ "$_p504i" -le 120 ]; do
    printf 'dolgu pin satiri burada tekrar tekrar yaziliyor\n'
    _p504i=$((_p504i + 1))
  done
  printf '<!-- quipu:pin:end -->\n'
  _p504j=1
  while [ "$_p504j" -le 6 ]; do
    printf 'govde dolgu satiri burada uzunca yaziliyor numara %d\n' "$_p504j"
    _p504j=$((_p504j + 1))
  done
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vt504/Threads.md"
T504PIN=$(awk '/<!-- quipu:pin:start -->/{p=1} p{print} /<!-- quipu:pin:end -->/{if(p) exit}' "$TMP/vt504/Threads.md" | LC_ALL=C wc -c | tr -d ' ')
T504TOTAL=$(wc -c < "$TMP/vt504/Threads.md" | tr -d ' ')
T504CROP=$((T504TOTAL - T504PIN))
# The expected budget/percent below used to be the literal numbers 102/72,
# frozen at the moment this test was written (2026-09-08, a Tuesday). That
# baked in that day's weekday name -- ctx_now's third %s (day_2=Tuesday,
# 7 bytes) -- as part of the fixed-cost side of the budget arithmetic.
# _q_ctx_text's "now:" line (Fixed part -1) carries today's actual weekday
# name every run, so its byte length -- and therefore the whole
# budget/percent pair -- silently drifts with whatever day the suite
# happens to run on (Tuesday's 7-byte "Tuesday" vs e.g. Saturday's 8-byte
# "Saturday" already shifts the budget by 1 byte). That made the test
# flaky-by-construction rather than wrong-once: hardcoding today's numbers
# instead would just move the failure to a different weekday. Recomputing
# the fixed-cost pieces here the same way the file's own T504PIN/T504CROP
# above are derived from the raw fixture (independent arithmetic over the
# i18n data + live date, never by calling into quipu's own budget code)
# keeps this test exercising the real B-K5 pin-exclusion logic while being
# stable on every day of the week.
T504NOWLINE=$(memfmt en ctx_now "$(date +%Y-%m-%d)" "$(date +%H:%M)" "$(case $(date +%u) in (1) mi18n en day_1;; (2) mi18n en day_2;; (3) mi18n en day_3;; (4) mi18n en day_4;; (5) mi18n en day_5;; (6) mi18n en day_6;; (7) mi18n en day_7;; esac)")
T504NOW=$(printf '%s\n' "$T504NOWLINE" | LC_ALL=C wc -c | tr -d ' ')
T504ACT=$(printf '%s\n%s\n' "$(mi18n en ctx_activity)" "$(mi18n en ctx_empty)" | LC_ALL=C wc -c | tr -d ' ')
T504IDX=$(printf '%s\n0\n' "$(mi18n en ctx_index)" | LC_ALL=C wc -c | tr -d ' ')
T504MSIZE=$(printf '%s\n' "$(mi18n en ctx_truncated)" | LC_ALL=C wc -c | tr -d ' ')
T504FIXED=$((T504PIN + T504NOW + T504ACT + T504IDX))
T504BUD=$((6000 - T504FIXED - T504MSIZE))
T504DROP=$((T504CROP - T504BUD))
T504PCT=$((T504DROP * 100 / T504CROP))
t; DOUT504=$(QUIPU_CTX_MAX=6000 QUIPU_LANG=en QUIPU_VAULT="$TMP/vt504" "$ROOT/knotlog" doctor 2>&1); RC=$?
assert_eq "T-504: doctor still exits 0 (overflow is a warn, not a fail)" '0' "$RC"
t; assert_eq "T-504: the reported size is file-minus-pin (368), never the raw 6176-byte file" 'yes' \
  "$([ "$T504CROP" -eq 368 ] && printf yes || printf no)"
t; assert_eq "T-504: doctor warns doc_threads_overflow with the pin-excluded size/budget/percent" 'yes' \
  "$(printf '%s\n' "$DOUT504" | grep -qF "$(memfmt en doc_threads_overflow Threads.md "$T504CROP" "$T504BUD" "$T504PCT")" && printf yes || printf no)"
t; assert_eq "T-504: the warning never names the raw whole-file byte count" 'no' \
  "$(printf '%s\n' "$DOUT504" | grep -qF "$T504TOTAL bytes" && printf yes || printf no)"

# T-505: same shape in Turkish -- Konular.md, tr message, tr-specific
# fixed-part length (so a different budget number than T-504's).
mkvault vt505
printf 'lang=tr\n' > "$TMP/vt505/.knotlog/config"
{
  printf '<!-- quipu:threads:start -->\n'
  printf '<!-- quipu:pin:start -->\n'
  _p505i=1
  while [ "$_p505i" -le 120 ]; do
    printf 'dolgu pin satiri burada tekrar tekrar yaziliyor\n'
    _p505i=$((_p505i + 1))
  done
  printf '<!-- quipu:pin:end -->\n'
  _p505j=1
  while [ "$_p505j" -le 6 ]; do
    printf 'govde dolgu satiri burada uzunca yaziliyor numara %d\n' "$_p505j"
    _p505j=$((_p505j + 1))
  done
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vt505/Konular.md"
T505PIN=$(awk '/<!-- quipu:pin:start -->/{p=1} p{print} /<!-- quipu:pin:end -->/{if(p) exit}' "$TMP/vt505/Konular.md" | LC_ALL=C wc -c | tr -d ' ')
T505TOTAL=$(wc -c < "$TMP/vt505/Konular.md" | tr -d ' ')
T505CROP=$((T505TOTAL - T505PIN))
# Same weekday-drift issue as T-504 above, amplified here: tr weekday names
# vary by up to 6 bytes across the week (day_5 "Cuma"=4 bytes vs day_3
# "Çarşamba"=10 bytes, the ç/ş each costing an extra UTF-8 byte), so a
# number frozen on 2026-09-08 (Tuesday/"Salı"=5 bytes) drifts hard on other
# days -- e.g. Saturday/"Cumartesi"=9 bytes shifts the budget by 4 bytes,
# which is exactly the 85-vs-89 gap this fixture showed under investigation.
# Recomputed the same way as T-504: independent arithmetic over the i18n
# data + live date, not a call into quipu's own budget code.
T505NOWLINE=$(memfmt tr ctx_now "$(date +%Y-%m-%d)" "$(date +%H:%M)" "$(case $(date +%u) in (1) mi18n tr day_1;; (2) mi18n tr day_2;; (3) mi18n tr day_3;; (4) mi18n tr day_4;; (5) mi18n tr day_5;; (6) mi18n tr day_6;; (7) mi18n tr day_7;; esac)")
T505NOW=$(printf '%s\n' "$T505NOWLINE" | LC_ALL=C wc -c | tr -d ' ')
T505ACT=$(printf '%s\n%s\n' "$(mi18n tr ctx_activity)" "$(mi18n tr ctx_empty)" | LC_ALL=C wc -c | tr -d ' ')
T505IDX=$(printf '%s\n0\n' "$(mi18n tr ctx_index)" | LC_ALL=C wc -c | tr -d ' ')
T505MSIZE=$(printf '%s\n' "$(mi18n tr ctx_truncated)" | LC_ALL=C wc -c | tr -d ' ')
T505FIXED=$((T505PIN + T505NOW + T505ACT + T505IDX))
T505BUD=$((6000 - T505FIXED - T505MSIZE))
T505DROP=$((T505CROP - T505BUD))
T505PCT=$((T505DROP * 100 / T505CROP))
t; DOUT505=$(QUIPU_CTX_MAX=6000 QUIPU_LANG=tr QUIPU_VAULT="$TMP/vt505" "$ROOT/knotlog" doctor 2>&1); RC=$?
assert_eq "T-505: doctor still exits 0 (tr)" '0' "$RC"
t; assert_eq "T-505: doctor warns doc_threads_overflow with the pin-excluded size/budget/percent (tr)" 'yes' \
  "$(printf '%s\n' "$DOUT505" | grep -qF "$(memfmt tr doc_threads_overflow Konular.md "$T505CROP" "$T505BUD" "$T505PCT")" && printf yes || printf no)"
t; assert_eq "T-505: the warning never names the raw whole-file byte count (tr)" 'no' \
  "$(printf '%s\n' "$DOUT505" | grep -qF "$T505TOTAL bayt" && printf yes || printf no)"

# T-506: false-positive lock -- a SMALL body sitting next to a LARGE pin
# block. The pin dominates the raw file size, but the pin's bytes are
# already deducted from the budget (B-K1), so the actual croppable content
# (the small body) fits comfortably. Before the B-K5 fix, comparing the
# raw (body+pin) size against that same pin-adjusted budget would have
# raised doc_threads_overflow here even though nothing is really dropped --
# this is the false positive the fix exists to close.
mkvault vt506
{
  printf '<!-- quipu:threads:start -->\n'
  printf '<!-- quipu:pin:start -->\n'
  _p506i=1
  while [ "$_p506i" -le 120 ]; do
    printf 'dolgu pin satiri burada tekrar tekrar yaziliyor\n'
    _p506i=$((_p506i + 1))
  done
  printf '<!-- quipu:pin:end -->\n'
  printf 'kisa bir govde satiri\n'
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vt506/Threads.md"
t; DOUT506=$(QUIPU_CTX_MAX=6000 QUIPU_LANG=en QUIPU_VAULT="$TMP/vt506" "$ROOT/knotlog" doctor 2>&1); RC=$?
assert_eq "T-506: doctor exits 0" '0' "$RC"
OVFL506_STATIC=$(mi18n en doc_threads_overflow | awk -F'%[sd]' '{print $3}')
t; assert_eq "T-506: doctor prints no doc_threads_overflow row -- the small body fits once the pin is excluded" 'no' \
  "$(printf '%s\n' "$DOUT506" | grep -qF "$OVFL506_STATIC" && printf yes || printf no)"

# T-507: same false-positive-lock shape in Turkish.
mkvault vt507
printf 'lang=tr\n' > "$TMP/vt507/.knotlog/config"
{
  printf '<!-- quipu:threads:start -->\n'
  printf '<!-- quipu:pin:start -->\n'
  _p507i=1
  while [ "$_p507i" -le 120 ]; do
    printf 'dolgu pin satiri burada tekrar tekrar yaziliyor\n'
    _p507i=$((_p507i + 1))
  done
  printf '<!-- quipu:pin:end -->\n'
  printf 'kisa bir govde satiri\n'
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vt507/Konular.md"
t; DOUT507=$(QUIPU_CTX_MAX=6000 QUIPU_LANG=tr QUIPU_VAULT="$TMP/vt507" "$ROOT/knotlog" doctor 2>&1); RC=$?
assert_eq "T-507: doctor exits 0 (tr)" '0' "$RC"
OVFL507_STATIC=$(mi18n tr doc_threads_overflow | awk -F'%[sd]' '{print $3}')
t; assert_eq "T-507: doctor prints no doc_threads_overflow row (tr)" 'no' \
  "$(printf '%s\n' "$DOUT507" | grep -qF "$OVFL507_STATIC" && printf yes || printf no)"

# ---- B-K4 (a): activity-section budget cap ----------------------------------
# activity.log's digest table grows one line per EVER-SEEN path -- the
# Konular-Butce-Tasmasi.md incident: 52 of 185 digest lines were one
# session's /tmp screenshot paths, silently eating the whole fixed part of
# the context budget and starving the threads section with no warning,
# twice (2026-09-02 and 2026-09-06). $_q_act (activity: tail lines + digest
# table) must not exceed 20% of ctx_max; when it does, the digest table
# (whose per-path order is AWK's unspecified hash iteration, not real
# recency) is dropped WHOLE, never partially -- only the genuinely-newest
# raw tail lines (real timestamps, real order) are kept.

# T-484: 300 log lines / 60 distinct paths, short synthetic event/tool/path
# so the always-kept head (header + 10 tail lines) stays well under the
# cap. QUIPU_CTX_MAX=2000 -> cap = 400 bytes; the uncapped digest table
# alone (60 FILE rows) is far larger than that.
mkvault vact484
for i in $(seq 1 300); do
  printf '2026-09-01T00:%02d | Y | X | p%03d\n' "$((i % 60))" "$i"
done > "$TMP/vact484/.knotlog/activity.log"
t; CTX484=$(QUIPU_CTX_MAX=2000 QUIPU_LANG=en QUIPU_VAULT="$TMP/vact484" "$ROOT/knotlog" context)
ACT484=$(printf '%s\n' "$CTX484" | awk -v s="$(mi18n en ctx_activity)" -v e="$(mi18n en ctx_index)" '$0==s{f=1} $0==e{f=0} f')
ACT484_LEN=$(printf '%s' "$ACT484" | LC_ALL=C wc -c | tr -d ' ')
t; assert_eq "T-484: the activity section stays within 20% of ctx_max (<=400 bytes) even with a 60-path digest table" 'yes' \
  "$([ "$ACT484_LEN" -le 400 ] && printf yes || printf no)"
t; assert_eq "T-484: the newest raw tail line (p300) still survives the cap" 'yes' \
  "$(printf '%s\n' "$ACT484" | grep -qF 'p300' && printf yes || printf no)"

# T-485: same shape in Turkish -- Konular.md's own language, same numbers.
mkvault vact485
printf 'lang=tr\n' > "$TMP/vact485/.knotlog/config"
for i in $(seq 1 300); do
  printf '2026-09-01T00:%02d | Y | X | p%03d\n' "$((i % 60))" "$i"
done > "$TMP/vact485/.knotlog/activity.log"
t; CTX485=$(QUIPU_CTX_MAX=2000 QUIPU_LANG=tr QUIPU_VAULT="$TMP/vact485" "$ROOT/knotlog" context)
ACT485=$(printf '%s\n' "$CTX485" | awk -v s="$(mi18n tr ctx_activity)" -v e="$(mi18n tr ctx_index)" '$0==s{f=1} $0==e{f=0} f')
ACT485_LEN=$(printf '%s' "$ACT485" | LC_ALL=C wc -c | tr -d ' ')
t; assert_eq "T-485: (tr) the activity section stays within 20% of ctx_max (<=400 bytes)" 'yes' \
  "$([ "$ACT485_LEN" -le 400 ] && printf yes || printf no)"

# T-486: the payoff -- the SAME oversized activity.log (T-484's shape) next
# to a Threads.md that fits comfortably once the digest table is dropped.
# Hand-verified against the pre-B-K4 commit e509745: at this exact
# ctx_max, the old code drops all 15 thread lines to 0 (measured while
# writing this test, not asserted here -- this asserts the FIXED
# behavior).
mkvault vact486
for i in $(seq 1 300); do
  printf '2026-09-01T00:%02d | Y | X | p%03d\n' "$((i % 60))" "$i"
done > "$TMP/vact486/.knotlog/activity.log"
{
  printf '<!-- quipu:threads:start -->\n'
  for i in $(seq 1 15); do
    printf 'thread line %d that is reasonably long to add up bytes\n' "$i"
  done
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vact486/Threads.md"
t; CTX486=$(QUIPU_CTX_MAX=2000 QUIPU_LANG=en QUIPU_VAULT="$TMP/vact486" "$ROOT/knotlog" context)
t; assert_eq "T-486: none of the 15 threads lines are truncated away" '15' \
  "$(printf '%s\n' "$CTX486" | grep -c 'thread line')"
t; assert_eq "T-486: no truncation marker appears" 'no' \
  "$(printf '%s\n' "$CTX486" | grep -qF "$(mi18n en ctx_truncated)" && printf yes || printf no)"

# T-487 (regression): a small, well-under-cap activity section is
# byte-identical to a direct header+log+digest reconstruction built from
# the SAME digest.awk this feature reuses -- proving the cap is a true
# no-op below the threshold (the ordinary case for every existing vault).
mkvault vact487
QUIPU_VAULT="$TMP/vact487" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path a.md >/dev/null 2>&1
QUIPU_VAULT="$TMP/vact487" sh "$ROOT/knotlog" capture --event PostToolUse --tool Read --path b.md >/dev/null 2>&1
LOG487="$TMP/vact487/.knotlog/activity.log"
{
  mi18n en ctx_activity
  cat "$LOG487"
  awk -f "$ROOT/lib/digest.awk" "$LOG487"
} > "$TMP/vact487-expected.txt"
QUIPU_LANG=en QUIPU_VAULT="$TMP/vact487" "$ROOT/knotlog" context | \
  awk -v s="$(mi18n en ctx_activity)" -v e="$(mi18n en ctx_index)" '$0==s{f=1} $0==e{f=0} f' \
  > "$TMP/vact487-actual.txt"
t; assert_eq "T-487: a small, well-under-cap activity section is byte-identical to a direct reconstruction (cmp)" 'yes' \
  "$(cmp -s "$TMP/vact487-expected.txt" "$TMP/vact487-actual.txt" && printf yes || printf no)"

# ---- B-K4 (b): capture never logs temp/scratchpad paths ---------------------
# A /tmp, $TMPDIR, or scratchpad path is meaningless in a future session --
# it is one more entry activity.log's digest table has to carry forever
# (the very thing (a) above has to defend against). Filtered at
# _q_append_line, AFTER _q_norm_path has already made a vault-internal path
# relative -- so a vault that itself lives under /tmp (every vault in this
# suite does: $TMP is under ${TMPDIR:-/tmp}) is never caught by this
# filter; only paths that are STILL absolute (i.e. outside the vault) are
# checked.

# T-488: a /tmp path passed via --path is not written to activity.log at
# all (silent drop, same shape as other silent-no-op capture paths).
mkvault vact488
t; QUIPU_VAULT="$TMP/vact488" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path /tmp/cc/shot.png
t; assert_eq "T-488: a /tmp path is never written to activity.log" 'no' \
  "$([ -s "$TMP/vact488/.knotlog/activity.log" ] && grep -qF 'shot.png' "$TMP/vact488/.knotlog/activity.log" && printf yes || printf no)"

# T-489: a scratchpad path (not under /tmp) is also dropped.
mkvault vact489
t; QUIPU_VAULT="$TMP/vact489" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path /home/agent/scratchpad/notes.md
t; assert_eq "T-489: a /.../scratchpad/... path is never written to activity.log" 'no' \
  "$([ -s "$TMP/vact489/.knotlog/activity.log" ] && grep -qF 'notes.md' "$TMP/vact489/.knotlog/activity.log" && printf yes || printf no)"

# T-490: a path under $TMPDIR (not literally /tmp) is also dropped.
mkvault vact490
TMPDIR490="$TMP/customtmp490"
mkdir -p "$TMPDIR490"
t; TMPDIR="$TMPDIR490" QUIPU_VAULT="$TMP/vact490" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path "$TMPDIR490/shot.png"
t; assert_eq "T-490: a \$TMPDIR path is never written to activity.log" 'no' \
  "$([ -s "$TMP/vact490/.knotlog/activity.log" ] && grep -qF 'shot.png' "$TMP/vact490/.knotlog/activity.log" && printf yes || printf no)"

# T-491 (false-positive lock): when the VAULT ITSELF lives under /tmp
# (exactly this test suite's own layout), a path INSIDE that vault is
# still logged normally -- _q_norm_path strips the vault prefix first, so
# it never reaches _q_is_tmp_path as an absolute /tmp path.
mkvault vact491
t; QUIPU_VAULT="$TMP/vact491" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path "$TMP/vact491/Notes/inside.md"
t; assert_eq "T-491: a vault-internal path survives even though the vault itself lives under /tmp" 'yes' \
  "$(grep -qF 'Notes/inside.md' "$TMP/vact491/.knotlog/activity.log" && printf yes || printf no)"
t; assert_eq "T-491: the logged path is vault-relative, not the raw /tmp absolute path" 'PostToolUse | Edit | Notes/inside.md' \
  "$(log_line "$TMP/vact491")"

# T-492 (regression): a normal, non-temp absolute path outside the vault is
# still logged unchanged -- the filter targets only /tmp/$TMPDIR/scratchpad,
# not "any absolute path".
mkvault vact492
t; QUIPU_VAULT="$TMP/vact492" sh "$ROOT/knotlog" capture --event PostToolUse --tool Edit --path /home/user/notes/plain.md
t; assert_eq "T-492: a plain absolute non-temp path is still logged" 'yes' \
  "$(grep -qF '/home/user/notes/plain.md' "$TMP/vact492/.knotlog/activity.log" && printf yes || printf no)"

# ---- T-493..T-503: B-K3 `knotlog archive` --------------------------------
#
# Moves ONE closed heading (and everything under it, up to the next
# same-or-higher-level heading) out of the threads file into a separate,
# append-only archive file (Konular-Arsivi.md / Threads-Archive.md,
# resolved by _q_archive_path the same two-part way _q_threads_path/
# _q_rules_path already resolve their own files — layout dir from
# layout/*.txt's `archive` row, file name from i18n's `threads_archive_file`
# key). Never automatic: no hook or doctor call in this repo invokes it.

layoutdir() { # lang -> the `archive` folder name for that layout file
  TABC=$(printf '\t')
  awk -F"$TABC" -v k=archive '$1==k{print $2;exit}' "$ROOT/layout/$1.txt"
}

# T-493: the archived section survives BYTE-IDENTICAL inside the archive
# file (sözleşme #1's "birebir" requirement) -- built by reconstructing
# the exact expected bytes (the marker line archive prepends + the
# section's own lines, unchanged) and cmp-ing against what the command
# actually wrote.
mkvault vak493
printf 'lang=tr\nlayout=tr\n' > "$TMP/vak493/.knotlog/config"
{
  printf '### Aktif konular\n'
  printf '### Konu A\n'
  printf 'satır A1\n'
  printf '### Konu B — kapandı\n'
  printf 'satır B1\n'
  printf 'satır B2\n'
} > "$TMP/vak493/Konular.md"
t; QUIPU_VAULT="$TMP/vak493" sh "$ROOT/knotlog" archive "Konu B — kapandı" >/dev/null
AKDIR493=$(layoutdir tr)
AKFILE493=$(mtr threads_archive_file)
{
  printf '<!-- knotlog:archived %s from=Konular.md -->\n' "$(date +%Y-%m-%d)"
  printf '### Konu B — kapandı\n'
  printf 'satır B1\n'
  printf 'satır B2\n'
} > "$TMP/vak493-expected.txt"
t; assert_eq "T-493: archived section is byte-identical in the archive file (cmp)" 'yes' \
  "$(cmp -s "$TMP/vak493-expected.txt" "$TMP/vak493/$AKDIR493/$AKFILE493" && printf yes || printf no)"

# T-494: the archived section is REMOVED from the source file -- the rest
# of the file (everything not archived) is untouched.
t; assert_eq "T-494: the archived heading no longer appears in Konular.md" 'no' \
  "$(grep -qF 'Konu B — kapandı' "$TMP/vak493/Konular.md" && printf yes || printf no)"
t; assert_eq "T-494: the archived body lines are also gone from Konular.md" 'no' \
  "$(grep -qF 'satır B1' "$TMP/vak493/Konular.md" && printf yes || printf no)"
t; assert_eq "T-494: the untouched heading (Konu A) survives in Konular.md" 'yes' \
  "$(grep -qF 'satır A1' "$TMP/vak493/Konular.md" && printf yes || printf no)"

# T-495: the pin block is NEVER archived, even when its own heading text is
# passed as the target -- refused with a distinct error, and neither the
# source file's pin block nor the archive file are touched.
mkvault vak495
printf 'lang=tr\nlayout=tr\n' > "$TMP/vak495/.knotlog/config"
{
  printf '<!-- quipu:pin:start -->\n'
  printf '### SABİT randevu\n'
  printf 'kritik satır\n'
  printf '<!-- quipu:pin:end -->\n'
  printf '### Konu C\n'
  printf 'satır C1\n'
} > "$TMP/vak495/Konular.md"
cp "$TMP/vak495/Konular.md" "$TMP/vak495-before.md"
t; QUIPU_VAULT="$TMP/vak495" sh "$ROOT/knotlog" archive "SABİT randevu" >/dev/null 2>&1; RC495=$?
t; assert_eq "T-495: archiving a pinned heading exits nonzero" 'yes' \
  "$([ "$RC495" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-495: Konular.md is byte-identical to before the refused attempt (cmp)" 'yes' \
  "$(cmp -s "$TMP/vak495-before.md" "$TMP/vak495/Konular.md" && printf yes || printf no)"
t; assert_eq "T-495: no archive file was created by the refused attempt" 'no' \
  "$([ -e "$TMP/vak495/$(layoutdir tr)/$(mtr threads_archive_file)" ] && printf yes || printf no)"

# T-496: the archive file is never injected into `knotlog context`, even
# once it holds content and even when ctx_max is generous.
t; CTX496=$(QUIPU_VAULT="$TMP/vak493" QUIPU_LANG=tr sh "$ROOT/knotlog" context)
t; assert_eq "T-496: the archived line does not reach knotlog context" 'no' \
  "$(printf '%s\n' "$CTX496" | grep -qF 'satır B1' && printf yes || printf no)"

# T-497: `knotlog index`/`knotlog search` DO find the archive file (sözleşme
# #4: kept out of context, but not out of the index).
t; QUIPU_VAULT="$TMP/vak493" sh "$ROOT/knotlog" index --full >/dev/null
t; assert_eq "T-497: search finds the archived content's own file" 'yes' \
  "$(QUIPU_VAULT="$TMP/vak493" sh "$ROOT/knotlog" search 'kapandı' --paths | grep -qF "$AKFILE493" && printf yes || printf no)"

# T-498: archiving a SECOND heading appends after the first -- the archive
# file grows, the first entry is not overwritten (sözleşme #3, ekleme).
t; QUIPU_VAULT="$TMP/vak493" sh "$ROOT/knotlog" archive "Konu A" >/dev/null
t; assert_eq "T-498: the first archived entry (Konu B) still exists after a second archive call" 'yes' \
  "$(grep -qF 'Konu B — kapandı' "$TMP/vak493/$AKDIR493/$AKFILE493" && printf yes || printf no)"
t; assert_eq "T-498: the second archived entry (Konu A) was appended, not overwriting the first" 'yes' \
  "$(grep -qF 'satır A1' "$TMP/vak493/$AKDIR493/$AKFILE493" && printf yes || printf no)"

# T-499: a vault that never calls `archive` sees a byte-identical `quipu
# context` before/after another vault's ARCHIVE ACTIVITY -- proving there
# is no global/shared state: running archive on an unrelated vault does
# not change this vault's context at all.
mkvault vak499
printf 'lang=tr\n' > "$TMP/vak499/.knotlog/config"
printf '### konu\nsatır\n' > "$TMP/vak499/Konular.md"
t; QUIPU_VAULT="$TMP/vak499" sh "$ROOT/knotlog" context > "$TMP/vak499-ctx-before.txt"
QUIPU_VAULT="$TMP/vak493" sh "$ROOT/knotlog" archive --list >/dev/null 2>&1
t; QUIPU_VAULT="$TMP/vak499" sh "$ROOT/knotlog" context > "$TMP/vak499-ctx-after.txt"
t; assert_eq "T-499: an untouched vault's context is byte-identical (cmp) regardless of archive use elsewhere" 'yes' \
  "$(ctx_same_body "$TMP/vak499-ctx-before.txt" "$TMP/vak499-ctx-after.txt" && printf yes || printf no)"

# T-500: en vault -- same birebir + removal-from-source shape, English
# names throughout (Threads.md, Threads-Archive.md, Archive/).
mkvault vak500
printf 'lang=en\nlayout=en\n' > "$TMP/vak500/.knotlog/config"
{
  printf '### Active threads\n'
  printf '### Thread A\n'
  printf 'line A1\n'
  printf '### Thread B — closed\n'
  printf 'line B1\n'
} > "$TMP/vak500/Threads.md"
t; QUIPU_VAULT="$TMP/vak500" sh "$ROOT/knotlog" archive "Thread B — closed" >/dev/null
AKDIR500=$(layoutdir en)
AKFILE500=$(men threads_archive_file)
t; assert_eq "T-500 (en): archived line lands in the archive file" 'yes' \
  "$(grep -qF 'line B1' "$TMP/vak500/$AKDIR500/$AKFILE500" && printf yes || printf no)"
t; assert_eq "T-500 (en): archived heading is removed from Threads.md" 'no' \
  "$(grep -qF 'Thread B — closed' "$TMP/vak500/Threads.md" && printf yes || printf no)"
t; assert_eq "T-500 (en): untouched heading (Thread A) survives in Threads.md" 'yes' \
  "$(grep -qF 'line A1' "$TMP/vak500/Threads.md" && printf yes || printf no)"

# T-501: --list marks a pinned heading distinctly from an ordinary one, so
# the user can see, without opening the file, which headings archive will
# refuse.
t; LIST501=$(QUIPU_VAULT="$TMP/vak495" sh "$ROOT/knotlog" archive --list)
PINMARK501=$(mtr archive_list_row_pinned | awk -F'%s' '{print $2}')
t; assert_eq "T-501: --list marks the pinned heading" 'yes' \
  "$(printf '%s\n' "$LIST501" | grep -F 'SABİT randevu' | grep -qF "$PINMARK501" && printf yes || printf no)"
t; assert_eq "T-501: --list does NOT mark the ordinary heading" 'no' \
  "$(printf '%s\n' "$LIST501" | grep -F 'Konu C' | grep -qF "$PINMARK501" && printf yes || printf no)"

# T-502: --dry-run changes nothing on disk (neither source nor archive),
# even though it prints the same preview line a real run would.
mkvault vak502
printf 'lang=tr\nlayout=tr\n' > "$TMP/vak502/.knotlog/config"
printf '### Konu D\nsatır D1\n' > "$TMP/vak502/Konular.md"
cp "$TMP/vak502/Konular.md" "$TMP/vak502-before.md"
t; DRY502=$(QUIPU_VAULT="$TMP/vak502" sh "$ROOT/knotlog" archive --dry-run "Konu D")
t; assert_eq "T-502: --dry-run's own message is emitted" 'yes' \
  "$(printf '%s\n' "$DRY502" | grep -qF -- "$(mtr archive_dry_run_note)" && printf yes || printf no)"
t; assert_eq "T-502: --dry-run leaves Konular.md byte-identical (cmp)" 'yes' \
  "$(cmp -s "$TMP/vak502-before.md" "$TMP/vak502/Konular.md" && printf yes || printf no)"
t; assert_eq "T-502: --dry-run creates no archive file" 'no' \
  "$([ -e "$TMP/vak502/$(layoutdir tr)/$(mtr threads_archive_file)" ] && printf yes || printf no)"

# T-503: an unknown heading is a clean error (exit nonzero), not a silent
# no-op and not a partial write.
mkvault vak503
printf 'lang=tr\n' > "$TMP/vak503/.knotlog/config"
printf '### Konu E\nsatır\n' > "$TMP/vak503/Konular.md"
t; QUIPU_VAULT="$TMP/vak503" sh "$ROOT/knotlog" archive "Konu Yok" >/dev/null 2>&1; RC503=$?
t; assert_eq "T-503: archiving a nonexistent heading exits nonzero" 'yes' \
  "$([ "$RC503" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-503: Konular.md is untouched after the failed lookup" 'yes' \
  "$(grep -qF 'Konu E' "$TMP/vak503/Konular.md" && printf yes || printf no)"

# ---- K1/K3: manual deterministic compile + stale live topic ----------------
mkvault vcompile
printf 'lang=tr\nlayout=tr\n' > "$TMP/vcompile/.knotlog/config"
mkdir -p "$TMP/vcompile/🧠 Bilgi"
printf '# Alpha\n\n[[Beta]]\n' > "$TMP/vcompile/🧠 Bilgi/a.md"
printf '# Beta\n\n[[Alpha]]\n' > "$TMP/vcompile/🧠 Bilgi/b.md"
{
  printf '🧠 Bilgi/a.md\tAlpha\t\t1\talpha beta\t\t\n'
  printf '🧠 Bilgi/b.md\tBeta\t\t1\tbeta alpha\t\t\n'
} > "$TMP/vcompile/.knotlog/index.tsv"
: > "$TMP/vcompile/.knotlog/links.tsv"
printf '# Konular\n\n## Aktif konular\n### Alpha\n' > "$TMP/vcompile/Konular.md"
t; QUIPU_VAULT="$TMP/vcompile" sh "$ROOT/knotlog" context > "$TMP/vcompile-context-before.txt"
t; COMPILE1=$(QUIPU_VAULT="$TMP/vcompile" sh "$ROOT/knotlog" compile)
t; COMPILE2=$(QUIPU_VAULT="$TMP/vcompile" sh "$ROOT/knotlog" compile)
assert_eq "compile: Turkish derived directory is reported" '# bilgi klasörü altında 2 kavram derlendi' "$COMPILE1"
assert_eq "compile: rerun is deterministic" "$COMPILE1" "$COMPILE2"
assert_eq "compile: derived note has source band and line pointer" 'yes' \
  "$(grep -qF 'Kaynak olmayan, türetilmiş bilgi' "$TMP/vcompile/🧠 Bilgi/Derlenmiş/Alpha.md" && grep -qF '🧠 Bilgi/a.md:1' "$TMP/vcompile/🧠 Bilgi/Derlenmiş/Alpha.md" && printf yes || printf no)"
t; QUIPU_VAULT="$TMP/vcompile" sh "$ROOT/knotlog" context > "$TMP/vcompile-context-after.txt"
assert_eq "compile: context remains byte-identical" 'yes' "$(ctx_same_body "$TMP/vcompile-context-before.txt" "$TMP/vcompile-context-after.txt" && printf yes || printf no)"
# Long concepts must stay within filesystem filename limits; the full title
# remains in the derived note while the slug is safely truncated.
LONG_TITLE=$(awk 'BEGIN { for (i = 1; i <= 320; i++) printf "A"; print "" }')
printf '# %s\n' "$LONG_TITLE" > "$TMP/vcompile/🧠 Bilgi/long.md"
printf '🧠 Bilgi/long.md\t%s\t\t1\talpha\t\tnote\n' "$LONG_TITLE" >> "$TMP/vcompile/.knotlog/index.tsv"
t; LONG_COMPILE=$(QUIPU_VAULT="$TMP/vcompile" sh "$ROOT/knotlog" compile)
assert_eq "compile: long concept slug stays filesystem-safe" '# bilgi klasörü altında 3 kavram derlendi' "$LONG_COMPILE"
mkdir -p "$TMP/vcompile/.agents/skills"
printf '# 0.-BRIEF-INFERENCE\n# 01-17\n' > "$TMP/vcompile/.agents/skills/noise.md"
printf '.agents/skills/noise.md\t0.-BRIEF-INFERENCE\t\t1\tnoise\t\tnote\n' >> "$TMP/vcompile/.knotlog/index.tsv"
printf '# 01-17\n' > "$TMP/vcompile/🧠 Bilgi/01-17.md"
printf '🧠 Bilgi/01-17.md\t01-17\t\t1\tnumeric\t\tnote\n' >> "$TMP/vcompile/.knotlog/index.tsv"
t; FILTERED_COMPILE=$(QUIPU_VAULT="$TMP/vcompile" sh "$ROOT/knotlog" compile)
assert_eq "compile: skill and numeric headings are filtered" '# bilgi klasörü altında 3 kavram derlendi' "$FILTERED_COMPILE"
t; QUIPU_VAULT="$TMP/vcompile" sh "$ROOT/knotlog" context > "$TMP/vcompile-context-after.txt"
t; DSTALE=$(QUIPU_VAULT="$TMP/vcompile" sh "$ROOT/knotlog" doctor 2>&1)
STALEOK=no
printf '%s\n' "$DSTALE" | grep -qF 'Alpha' && printf '%s\n' "$DSTALE" | grep -qF 'gündür' && STALEOK=yes
assert_eq "doctor: live old topic warning is visible" 'yes' "$STALEOK"

# ---- K2: dated status timeline from indexed source rows --------------------
mkvault vk2timeline
printf 'lang=tr\nlayout=tr\n' > "$TMP/vk2timeline/.knotlog/config"
mkdir -p "$TMP/vk2timeline/🧠 Bilgi"
printf '# Alpha\n' > "$TMP/vk2timeline/🧠 Bilgi/2026-01-05.md"
printf '# Alpha\n' > "$TMP/vk2timeline/🧠 Bilgi/2026-01-02.md"
printf '# Alpha\n' > "$TMP/vk2timeline/🧠 Bilgi/current.md"
{
  printf '🧠 Bilgi/2026-01-05.md\tAlpha\t\t1\talpha\t🔴\tnote\n'
  printf '🧠 Bilgi/2026-01-02.md\tAlpha\t\t1\talpha\t🟢\tnote\n'
  printf '🧠 Bilgi/current.md\tAlpha\t\t1\talpha\t🟡\tnote\n'
} > "$TMP/vk2timeline/.knotlog/index.tsv"
: > "$TMP/vk2timeline/.knotlog/links.tsv"
printf '# Konular\n' > "$TMP/vk2timeline/Konular.md"
t; QUIPU_VAULT="$TMP/vk2timeline" sh "$ROOT/knotlog" context > "$TMP/vk2timeline-context-before.txt"
t; QUIPU_VAULT="$TMP/vk2timeline" sh "$ROOT/knotlog" compile >/dev/null
TLK2=$(awk '/^## zaman çizgisi$/{f=1;next}/^## kaynak işaretçileri$/{f=0} f' "$TMP/vk2timeline/🧠 Bilgi/Derlenmiş/Alpha.md")
EXPECTED_K2=$(printf '%s\n' '- 2026-01-02: 🟢' '- 2026-01-05: 🔴')
t; assert_eq "K2: timeline orders dated status marks" "$EXPECTED_K2" "$TLK2"
t; assert_eq "K2: source without a date does not invent a timeline event" 'no' \
  "$(printf '%s\n' "$TLK2" | grep -qF '🟡' && printf yes || printf no)"
t; QUIPU_VAULT="$TMP/vk2timeline" sh "$ROOT/knotlog" context > "$TMP/vk2timeline-context-after.txt"
assert_eq "K2: derived timeline stays out of context" 'yes' \
  "$(ctx_same_body "$TMP/vk2timeline-context-before.txt" "$TMP/vk2timeline-context-after.txt" && printf yes || printf no)"
cp "$TMP/vk2timeline/🧠 Bilgi/Derlenmiş/Alpha.md" "$TMP/vk2timeline-alpha-before.md"
t; QUIPU_VAULT="$TMP/vk2timeline" sh "$ROOT/knotlog" compile >/dev/null
assert_eq "K2: rerun keeps derived note byte-identical" 'yes' \
  "$(cmp -s "$TMP/vk2timeline-alpha-before.md" "$TMP/vk2timeline/🧠 Bilgi/Derlenmiş/Alpha.md" && printf yes || printf no)"

# ---- T-711: K2 under a byte-mode awk (LC_ALL=C) ----------------------------
# K2 passes on a UTF-8 Linux and fails on Windows (empty LANG, byte-mode
# awk). Forcing LC_ALL=C runs the same timeline on every platform, so the
# status-mark match is tested in byte mode everywhere.
mkvault vk2bytes
printf 'lang=tr\nlayout=tr\n' > "$TMP/vk2bytes/.knotlog/config"
mkdir -p "$TMP/vk2bytes/🧠 Bilgi"
printf '# Alpha\n' > "$TMP/vk2bytes/🧠 Bilgi/2026-01-05.md"
printf '# Alpha\n' > "$TMP/vk2bytes/🧠 Bilgi/2026-01-02.md"
{
  printf '🧠 Bilgi/2026-01-05.md\tAlpha\t\t1\talpha\t🔴\tnote\n'
  printf '🧠 Bilgi/2026-01-02.md\tAlpha\t\t1\talpha\t🟢\tnote\n'
} > "$TMP/vk2bytes/.knotlog/index.tsv"
: > "$TMP/vk2bytes/.knotlog/links.tsv"
printf '# Konular\n' > "$TMP/vk2bytes/Konular.md"
t; LC_ALL=C QUIPU_VAULT="$TMP/vk2bytes" sh "$ROOT/knotlog" compile >/dev/null
TLB=$(awk '/^## zaman çizgisi$/{f=1;next}/^## kaynak işaretçileri$/{f=0} f' "$TMP/vk2bytes/🧠 Bilgi/Derlenmiş/Alpha.md")
t; assert_eq "T-711: timeline orders dated status marks under LC_ALL=C" "$EXPECTED_K2" "$TLB"

# ---- T-508..T-516: `knotlog update --check` (G2, Update/Rollback research) ---
# QUIPU_RELEASE_API_URL points this at a file:// fixture instead of the
# network -- same offline shape as B7's GITHUB_RELEASE_URL override above.
# Only --check is in scope here: no download, no overwrite, no rollback.
#
# Fixtures are copied into $TMP first rather than referenced from
# tests/fixtures/ directly: curl's file:// URL parser rejects paths with
# unencoded spaces or non-ASCII characters (confirmed on this checkout,
# which sits under a directory containing both), so a repo checked out
# under such a path would otherwise fail every test below on a curl error
# that has nothing to do with update --check itself. $TMP is created a few
# lines above with a plain ASCII path and is exactly what B7 already
# relies on for the same reason.
UPDFIX="$TMP/release-fixtures"
mkdir -p "$UPDFIX"
cp "$FIX/release-current.json" "$FIX/release-newer.json" \
  "$FIX/release-doubledigit.json" "$FIX/release-no-tag.json" "$UPDFIX/"
case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*) FIXURL="file:///$(cygpath -m "$UPDFIX")" ;;
  *) FIXURL="file://$UPDFIX" ;;
esac

# T-508: a bare `knotlog update` (neither --check nor --apply) is refused on
# purpose -- no network-touching default -- and must say so, not silently
# no-op as though it had checked or updated.
t; UPD508=$(QUIPU_LANG=en sh "$ROOT/knotlog" update 2>&1); RC508=$?
t; assert_eq "T-508: bare update (no --check) exits non-zero" 'yes' \
  "$([ "$RC508" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-508: bare update names --check as the supported flag" 'yes' \
  "$(printf '%s\n' "$UPD508" | grep -qF -- '--check' && printf yes || printf no)"

# T-509: fixture reports the version already shipped -> noop, exit 0, and
# the message names both the current version and the checkout kind. This
# repo IS a git clone (its own .git), so $_q_HOME/.git exists here and the
# real detection path (not a stub) must call it "git".
t; UPD509=$(QUIPU_LANG=en QUIPU_RELEASE_API_URL="$FIXURL/release-current.json" \
  sh "$ROOT/knotlog" update --check); RC509=$?
t; assert_eq "T-509: already up to date exits 0" '0' "$RC509"
t; assert_eq "T-509: up-to-date names the current version" 'yes' \
  "$(printf '%s\n' "$UPD509" | grep -qF '1.2.0' && printf yes || printf no)"
t; assert_eq "T-509: up-to-date identifies this checkout as git" 'yes' \
  "$(printf '%s\n' "$UPD509" | grep -qF 'git' && printf yes || printf no)"

# T-723: a git worktree or submodule keeps `.git` as a FILE ("gitdir: ...").
# Detection used -d and called such a checkout a tarball, so --apply would
# have swapped it as one. A copy of this checkout with a .git file must be
# named git; the same copy without one must be named tarball.
WT723="$TMP/wt723"
mkdir -p "$WT723"
(cd "$ROOT" && tar cf - --exclude=.git --exclude=tests .) | (cd "$WT723" && tar xf -)
printf 'gitdir: /nonexistent/.git/worktrees/wt723\n' > "$WT723/.git"
t; UPD723=$(QUIPU_LANG=en QUIPU_RELEASE_API_URL="$FIXURL/release-current.json" \
  sh "$WT723/knotlog" update --check 2>&1)
assert_eq "T-723: a checkout whose .git is a file is named git" 'yes' \
  "$(printf '%s\n' "$UPD723" | grep -qF '(git checkout)' && printf yes || printf no)"
rm -f "$WT723/.git"
t; UPD723T=$(QUIPU_LANG=en QUIPU_RELEASE_API_URL="$FIXURL/release-current.json" \
  sh "$WT723/knotlog" update --check 2>&1)
assert_eq "T-723: the same checkout without .git is named tarball" 'yes' \
  "$(printf '%s\n' "$UPD723T" | grep -qF '(tarball checkout)' && printf yes || printf no)"

# T-510: fixture reports a newer release -> available, both versions named.
t; UPD510=$(QUIPU_LANG=en QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  sh "$ROOT/knotlog" update --check); RC510=$?
t; assert_eq "T-510: newer release exits 0" '0' "$RC510"
t; assert_eq "T-510: newer release names the current version" 'yes' \
  "$(printf '%s\n' "$UPD510" | grep -qF '1.2.0' && printf yes || printf no)"
t; assert_eq "T-510: newer release names the new version" 'yes' \
  "$(printf '%s\n' "$UPD510" | grep -qF '2.8.0' && printf yes || printf no)"

# T-511: the classic semver trap -- a plain string/lexicographic compare
# thinks "2.10.0" < "2.9.0" (because the character '1' sorts before '9'),
# which would wrongly report a newer 2.10.0 release as no update needed.
# Exercise the REAL code path (not a reimplementation of it): patch a
# scratch copy of quipu so ITS OWN current-version constant reads 2.9.0,
# then run that copy against a v2.10.0 fixture. QUIPU_HOME still points at
# $ROOT so lib/i18n resolve exactly as normal -- only the version literal
# in the scratch copy differs from the real script.
VERPATCH="$TMP/verpatch"
mkdir -p "$VERPATCH"
sed 's/^_q_version=1\.2\.0$/_q_version=2.9.0/' "$ROOT/knotlog" > "$VERPATCH/knotlog"
t; assert_eq "T-511 setup: the scratch copy's version constant was patched" 'yes' \
  "$(grep -qF '_q_version=2.9.0' "$VERPATCH/knotlog" && printf yes || printf no)"
t; UPD511=$(QUIPU_LANG=en QUIPU_HOME="$ROOT" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-doubledigit.json" sh "$VERPATCH/knotlog" update --check); RC511=$?
t; assert_eq "T-511: 2.9.0 vs 2.10.0 exits 0 (available, not noop)" '0' "$RC511"
t; assert_eq "T-511: double-digit component correctly compares as available" 'yes' \
  "$(printf '%s\n' "$UPD511" | grep -qF '2.10.0' && printf yes || printf no)"
t; UPD511B=$(QUIPU_LANG=en QUIPU_HOME="$ROOT" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-current.json" sh "$VERPATCH/knotlog" update --check)
t; assert_eq "T-511: 2.9.0 vs 1.1.1 correctly stays noop (older release)" 'yes' \
  "$(printf '%s\n' "$UPD511B" | grep -qF '2.9.0' && printf yes || printf no)"

# T-512: a tarball checkout (install.sh's shape, no .git) is identified as
# such. QUIPU_HOME overrides _q_home() outright, so pointing it at a copy of
# lib/ and i18n/ with no .git alongside is enough -- the running script
# itself can stay $ROOT/knotlog.
TARBALLHOME="$TMP/tarballhome"
mkdir -p "$TARBALLHOME"
cp -r "$ROOT/lib" "$TARBALLHOME/lib"
cp -r "$ROOT/i18n" "$TARBALLHOME/i18n"
t; assert_eq "T-512 setup: the scratch checkout has no .git" 'no' \
  "$([ -d "$TARBALLHOME/.git" ] && printf yes || printf no)"
t; UPD512=$(QUIPU_LANG=en QUIPU_HOME="$TARBALLHOME" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" sh "$ROOT/knotlog" update --check); RC512=$?
t; assert_eq "T-512: tarball checkout exits 0" '0' "$RC512"
t; assert_eq "T-512: tarball checkout is identified as tarball, not git" 'yes' \
  "$(printf '%s\n' "$UPD512" | grep -qF 'tarball' && printf yes || printf no)"

# T-513: the release source is unreachable (no such file) -> a clear error,
# never a silent noop that would hide a check that never actually happened.
t; QUIPU_LANG=en QUIPU_RELEASE_API_URL="file:///no/such/quipu-release-fixture.json" \
  sh "$ROOT/knotlog" update --check >"$TMP/upd513.out" 2>"$TMP/upd513.err"; RC513=$?
t; assert_eq "T-513: unreachable release source exits non-zero" 'yes' \
  "$([ "$RC513" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-513: unreachable release source reports on stderr, not silently" 'yes' \
  "$([ -s "$TMP/upd513.err" ] && printf yes || printf no)"

# T-514: the release source answers but carries no tag_name -> a parse
# error, distinct from T-513's fetch error, never a false noop.
t; QUIPU_LANG=en QUIPU_RELEASE_API_URL="$FIXURL/release-no-tag.json" \
  sh "$ROOT/knotlog" update --check >"$TMP/upd514.out" 2>"$TMP/upd514.err"; RC514=$?
t; assert_eq "T-514: missing tag_name exits non-zero" 'yes' \
  "$([ "$RC514" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-514: missing tag_name reports on stderr" 'yes' \
  "$([ -s "$TMP/upd514.err" ] && printf yes || printf no)"

# T-515: same noop shape in Turkish -- this project's messages are bilingual
# throughout (i18n/en.txt and i18n/tr.txt stay line-for-line matched), and
# update's messages are no exception.
t; UPD515=$(QUIPU_LANG=tr QUIPU_RELEASE_API_URL="$FIXURL/release-current.json" \
  sh "$ROOT/knotlog" update --check); RC515=$?
t; assert_eq "T-515: Turkish noop message exits 0" '0' "$RC515"
t; assert_eq "T-515: Turkish noop message uses the Turkish string" 'yes' \
  "$(printf '%s\n' "$UPD515" | grep -qF 'Güncel' && printf yes || printf no)"

# T-516: flag/argument validation matches the rest of the CLI (err_unknown_flag
# for an unrecognized flag, a dedicated extra-arg error for a stray positional).
t; QUIPU_LANG=en sh "$ROOT/knotlog" update --bogus >"$TMP/upd516a.out" 2>"$TMP/upd516a.err"; RC516A=$?
t; assert_eq "T-516: unknown update flag exits non-zero" 'yes' \
  "$([ "$RC516A" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-516: unknown update flag is reported as an unknown flag" 'yes' \
  "$(grep -qF -- '--bogus' "$TMP/upd516a.err" && printf yes || printf no)"
t; QUIPU_LANG=en sh "$ROOT/knotlog" update --check extra >"$TMP/upd516b.out" 2>"$TMP/upd516b.err"; RC516B=$?
t; assert_eq "T-516: stray positional argument exits non-zero" 'yes' \
  "$([ "$RC516B" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-516: stray positional argument is named in the error" 'yes' \
  "$(grep -qF 'extra' "$TMP/upd516b.err" && printf yes || printf no)"

# ---- T-517..T-524: `knotlog update --apply` (G3, real update / atomic swap) --
# Extends the read-only --check surface above (T-508..T-516, left completely
# untouched) with real file changes. Every fixture checkout below lives
# under $TMP (plain ASCII, no spaces) for the same reason $UPDFIX was copied
# out of $ROOT above: curl's file:// URL parser rejects this repo's own path
# (emoji + spaces), and --apply's tarball download goes through that exact
# same curl/wget code path (_q_update_download).

# _q_seed_checkout DEST VERSION: a minimal but COMPLETE quipu checkout --
# every shipped file _q_doctor's file-list section checks for (quipu:853),
# plus lib/ + i18n/ for update's own JSON parsing -- with _q_version patched
# to VERSION. Shared by every fixture checkout below so doctor/update never
# fail on a missing shipped file unrelated to what a given test checks.
_q_seed_checkout() {
  mkdir -p "$1"
  cp -r "$ROOT/fold" "$ROOT/i18n" "$ROOT/layout" "$ROOT/lib" "$ROOT/persona" \
    "$ROOT/templates" "$ROOT/tone" "$ROOT/icon" "$1/"
  cp "$ROOT/repair-hooks" "$ROOT/repair-hooks.ps1" "$1/"
  sed "s/^_q_version=.*\$/_q_version=$2/" "$ROOT/knotlog" > "$1/knotlog"
  chmod +x "$1/knotlog" "$1/repair-hooks"
}

# _q_mk_sha FILE: write FILE.sha256 as "<hex>  <basename>", the format the
# release workflow publishes and `update --apply` checks.
_q_mk_sha() {
  if command -v sha256sum >/dev/null 2>&1; then _mk_h=$(sha256sum "$1")
  elif command -v shasum >/dev/null 2>&1; then _mk_h=$(shasum -a 256 "$1")
  else _mk_h=$(openssl dgst -sha256 "$1" | sed 's/.* //')
  fi
  printf '%s  %s\n' "${_mk_h%% *}" "$(basename "$1")" > "$1.sha256"
}

# T-517: --check and --apply are mutually exclusive -- a clear error rather
# than one flag silently winning.
t; QUIPU_LANG=en sh "$ROOT/knotlog" update --check --apply \
  >"$TMP/upd517.out" 2>"$TMP/upd517.err"; RC517=$?
t; assert_eq "T-517: --check + --apply together exits non-zero" 'yes' \
  "$([ "$RC517" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-517: --check + --apply names both flags in the error" 'yes' \
  "$(grep -qF -- '--check' "$TMP/upd517.err" && grep -qF -- '--apply' "$TMP/upd517.err" \
     && printf yes || printf no)"

# Fixture "new release" tarball, reused by T-518..T-522 below.
UPDPKG="$TMP/updpkg"
_q_seed_checkout "$UPDPKG/Quipu-2.8.0" 2.8.0
tar -czf "$TMP/update-new.tar.gz" -C "$UPDPKG" Quipu-2.8.0
_q_mk_sha "$TMP/update-new.tar.gz"
case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*) UPDTARURL="file:///$(cygpath -m "$TMP")" ;;
  *) UPDTARURL="file://$TMP" ;;
esac

# T-518/T-519/T-520: happy path -- the checkout's files really change, the
# staging directory is cleaned up afterward, and the pre-update tree
# survives as a one-level backup (G5's rollback basis, not consumed here).
# A fixture "vault" sits next to the checkout and must come back byte-for-
# byte identical (bitiş tanımı #2): update never reads $_q_v/QUIPU_VAULT at
# all -- this is the black-box proof of that, not just a code inspection.
UPDHOME="$TMP/updhome/Quipu"
_q_seed_checkout "$UPDHOME" 2.7.3
UPDVAULT="$TMP/updhome/vault"
mkdir -p "$UPDVAULT/.knotlog"
printf 'layout=emoji\n' > "$UPDVAULT/.knotlog/config"
printf 'do not touch me\n' > "$UPDVAULT/marker.md"
VAULTSUM_BEFORE=$(cd "$TMP/updhome" && find vault -type f | sort | xargs cat | cksum)

t; UPD518=$(QUIPU_LANG=en QUIPU_HOME="$UPDHOME" QUIPU_VAULT="$UPDVAULT" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
  sh "$ROOT/knotlog" update --apply 2>"$TMP/upd518.err"); RC518=$?
t; assert_eq "T-518: tarball --apply exits 0" '0' "$RC518"
# "old" is the running script's own version (the root checkout here).
t; assert_eq "T-518: apply reports old -> new version" 'yes' \
  "$(printf '%s\n' "$UPD518" | grep -qF "$(sed -n 's/^_q_version=//p' "$ROOT/knotlog")" \
     && printf '%s\n' "$UPD518" | grep -qF '2.8.0' && printf yes || printf no)"
t; assert_eq "T-518: the checkout's own _q_version constant is now 2.8.0" 'yes' \
  "$(grep -qF '_q_version=2.8.0' "$UPDHOME/knotlog" && printf yes || printf no)"
t; assert_eq "T-519: staging directory is cleaned up after a successful apply" 'no' \
  "$([ -e "$UPDHOME.quipu-update-staging" ] && printf yes || printf no)"
t; assert_eq "T-520: previous version is kept as a one-level backup" 'yes' \
  "$([ -f "$UPDHOME.knotlog-previous/knotlog" ] \
     && grep -qF '_q_version=2.7.3' "$UPDHOME.knotlog-previous/knotlog" && printf yes || printf no)"
VAULTSUM_AFTER=$(cd "$TMP/updhome" && find vault -type f | sort | xargs cat | cksum)
t; assert_eq "T-518: the vault fixture is byte-for-byte untouched by update --apply" 'yes' \
  "$([ "$VAULTSUM_BEFORE" = "$VAULTSUM_AFTER" ] && printf yes || printf no)"

# T-521: --check on the same fixture shape never writes anything, even when
# a newer release is available -- a regression guard now that --apply
# exists alongside it (the read-only contract T-508..T-516 cover must not
# have grown a side effect).
CHKHOME="$TMP/chkhome/Quipu"
_q_seed_checkout "$CHKHOME" 2.7.3
CHKSUM_BEFORE=$(find "$TMP/chkhome" -type f | sort | xargs cat | cksum)
t; QUIPU_LANG=en QUIPU_HOME="$CHKHOME" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  sh "$ROOT/knotlog" update --check >/dev/null 2>&1; RC521=$?
CHKSUM_AFTER=$(find "$TMP/chkhome" -type f | sort | xargs cat | cksum)
t; assert_eq "T-521: --check exits 0 even with a newer release available" '0' "$RC521"
t; assert_eq "T-521: --check never writes to the checkout" 'yes' \
  "$([ "$CHKSUM_BEFORE" = "$CHKSUM_AFTER" ] && printf yes || printf no)"
t; assert_eq "T-521: --check leaves no staging directory behind" 'no' \
  "$([ -e "$CHKHOME.quipu-update-staging" ] && printf yes || printf no)"

# T-522/T-523: an update interrupted mid-download leaves its staging
# directory behind (simulated here by creating it by hand, standing in for
# a `kill -9` mid-curl -- the effect on disk is identical: a staging dir
# with partial contents and no successful swap). The NEXT --apply must
# refuse and say so; `doctor` must surface it too, as its own independent,
# no-flags-needed check.
STALEHOME="$TMP/stalehome/Quipu"
_q_seed_checkout "$STALEHOME" 2.7.3
mkdir -p "$STALEHOME.quipu-update-staging/src"
printf 'partial\n' > "$STALEHOME.quipu-update-staging/tarball"

t; QUIPU_LANG=en QUIPU_HOME="$STALEHOME" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
  sh "$ROOT/knotlog" update --apply >"$TMP/upd522.out" 2>"$TMP/upd522.err"; RC522=$?
t; assert_eq "T-522: a stale staging directory blocks a new --apply" 'yes' \
  "$([ "$RC522" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-522: the refusal names the stale staging path" 'yes' \
  "$(grep -qF 'quipu-update-staging' "$TMP/upd522.err" && printf yes || printf no)"
t; assert_eq "T-522: the stale staging directory is left exactly as found, not deleted" 'yes' \
  "$([ -f "$STALEHOME.quipu-update-staging/tarball" ] && printf yes || printf no)"
t; assert_eq "T-522: the old checkout is untouched by the refused apply" 'yes' \
  "$(grep -qF '_q_version=2.7.3' "$STALEHOME/knotlog" && printf yes || printf no)"

t; DOC523=$(QUIPU_LANG=en QUIPU_HOME="$STALEHOME" QUIPU_VAULT="$TMP/no-such-vault-523" \
  sh "$ROOT/knotlog" doctor 2>&1)
t; assert_eq "T-523: doctor reports the stale staging directory as a warn row" 'yes' \
  "$(printf '%s\n' "$DOC523" | awk -F'\t' '$1=="warn" && index($0,"quipu-update-staging"){f=1} END{exit !f}' \
     && printf yes || printf no)"

# T-524: a git-clone checkout applies via `git fetch` + checkout of the new
# tag -- not the tarball atomic-swap path above. A local "seed" repo stands
# in for the real GitHub remote (git needs no file:// URL encoding, unlike
# curl/wget, so this can live under $TMP directly).
GITSEED="$TMP/gitseed"
_q_seed_checkout "$GITSEED" 2.7.3
( cd "$GITSEED" && git init -q && git config user.email test@example.test \
    && git config user.name test && git add -A \
    && git commit -q -m base && git tag v2.7.3 ) >/dev/null 2>&1

GITHOME="$TMP/githome"
git clone -q "$GITSEED" "$GITHOME" >/dev/null 2>&1
t; assert_eq "T-524 setup: the cloned checkout carries its own .git" 'yes' \
  "$([ -d "$GITHOME/.git" ] && printf yes || printf no)"

# Bump the "upstream" (seed) to 2.8.0 and tag it -- what --apply is meant
# to fetch and check out.
sed "s/^_q_version=.*\$/_q_version=2.8.0/" "$GITSEED/knotlog" > "$GITSEED/knotlog.new"
mv "$GITSEED/knotlog.new" "$GITSEED/knotlog"
chmod +x "$GITSEED/knotlog"
( cd "$GITSEED" && git add -A && git commit -q -m bump && git tag v2.8.0 ) >/dev/null 2>&1

t; UPD524=$(QUIPU_LANG=en QUIPU_HOME="$GITHOME" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  sh "$ROOT/knotlog" update --apply 2>"$TMP/upd524.err"); RC524=$?
t; assert_eq "T-524: git-clone --apply exits 0" '0' "$RC524"
t; assert_eq "T-524: apply names the git checkout kind" 'yes' \
  "$(printf '%s\n' "$UPD524" | grep -qF 'git' && printf yes || printf no)"
t; assert_eq "T-524: the cloned checkout's _q_version constant is now 2.8.0" 'yes' \
  "$(grep -qF '_q_version=2.8.0' "$GITHOME/knotlog" && printf yes || printf no)"
t; assert_eq "T-524: HEAD now points at the v2.8.0 tag" 'yes' \
  "$(cd "$GITHOME" && [ "$(git rev-parse HEAD)" = "$(git rev-parse v2.8.0)" ] \
     && printf yes || printf no)"
t; assert_eq "T-524: the git-clone apply leaves no staging directory (not its mechanism)" 'no' \
  "$([ -e "$GITHOME.quipu-update-staging" ] && printf yes || printf no)"


# ---- T-525..T-534: `knotlog rollback` (G5, undo the last update --apply) -----
# Extends the update surface above (T-508..T-524, left completely untouched)
# with the ability to undo it. Reuses UPDPKG's already-built "new release"
# tarball and _q_seed_checkout from the T-517..T-524 block above -- rollback
# just walks the same backup/staging paths backwards, no new fixture shape.

# T-525: argument validation matches the rest of the CLI -- a stray
# positional is rejected, not silently ignored.
t; QUIPU_LANG=en sh "$ROOT/knotlog" rollback extra >"$TMP/rb525.out" 2>"$TMP/rb525.err"; RC525=$?
t; assert_eq "T-525: stray rollback argument exits non-zero" 'yes' \
  "$([ "$RC525" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-525: stray rollback argument is named in the error" 'yes' \
  "$(grep -qF 'extra' "$TMP/rb525.err" && printf yes || printf no)"

# T-526: a tarball checkout that was never updated (no .knotlog-previous next
# to it) has nothing to roll back to -- a clear error, never a silent no-op
# (bitis tanimi #2).
RBNOHOME="$TMP/rbnohome/Quipu"
_q_seed_checkout "$RBNOHOME" 2.7.3
t; QUIPU_LANG=en QUIPU_HOME="$RBNOHOME" sh "$ROOT/knotlog" rollback \
  >"$TMP/rb526.out" 2>"$TMP/rb526.err"; RC526=$?
t; assert_eq "T-526: no-backup rollback exits non-zero" 'yes' \
  "$([ "$RC526" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-526: no-backup rollback names the missing backup path" 'yes' \
  "$(grep -qF '.knotlog-previous' "$TMP/rb526.err" && printf yes || printf no)"
t; assert_eq "T-526: no-backup rollback leaves the checkout untouched" 'yes' \
  "$(grep -qF '_q_version=2.7.3' "$RBNOHOME/knotlog" && printf yes || printf no)"

# T-527..T-530: tarball happy path -- apply a real update, then roll it back,
# and check the checkout is BYTE-FOR-BYTE identical to before the update
# (bitis tanimi #1), the backup is consumed (design decision: no leftover
# backup for an update that has already been undone, so a confused re-run
# can't "undo" it a second time), no rollback-tmp dir survives, and the
# vault fixture next to it is never touched (bitis tanimi #3) -- same
# black-box shape T-518 already uses to prove update itself leaves the
# vault alone.
RBHOME="$TMP/rbhome/Quipu"
_q_seed_checkout "$RBHOME" 2.7.3
RBVAULT="$TMP/rbhome/vault"
mkdir -p "$RBVAULT/.knotlog"
printf 'layout=emoji\n' > "$RBVAULT/.knotlog/config"
printf 'do not touch me either\n' > "$RBVAULT/marker.md"
RBHOMESUM_BEFORE=$(cd "$TMP/rbhome" && find Quipu -type f | sort | xargs cat | cksum)
RBVAULTSUM_BEFORE=$(cd "$TMP/rbhome" && find vault -type f | sort | xargs cat | cksum)

t; QUIPU_LANG=en QUIPU_HOME="$RBHOME" QUIPU_VAULT="$RBVAULT" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
  sh "$ROOT/knotlog" update --apply >/dev/null 2>"$TMP/rb527-setup.err"
t; assert_eq "T-527 setup: update --apply reached 2.8.0" 'yes' \
  "$(grep -qF '_q_version=2.8.0' "$RBHOME/knotlog" && printf yes || printf no)"
t; assert_eq "T-527 setup: the backup exists before rollback" 'yes' \
  "$([ -d "$RBHOME.knotlog-previous" ] && printf yes || printf no)"

t; RB527=$(QUIPU_LANG=en QUIPU_HOME="$RBHOME" QUIPU_VAULT="$RBVAULT" \
  sh "$ROOT/knotlog" rollback 2>"$TMP/rb527.err"); RC527=$?
t; assert_eq "T-527: rollback exits 0" '0' "$RC527"
t; assert_eq "T-527: rollback reports 2.8.0 -> 2.7.3" 'yes' \
  "$(printf '%s\n' "$RB527" | grep -qF '2.8.0' \
     && printf '%s\n' "$RB527" | grep -qF '2.7.3' && printf yes || printf no)"
t; assert_eq "T-528: the checkout's own _q_version constant is 2.7.3 again" 'yes' \
  "$(grep -qF '_q_version=2.7.3' "$RBHOME/knotlog" && printf yes || printf no)"

RBHOMESUM_AFTER=$(cd "$TMP/rbhome" && find Quipu -type f | sort | xargs cat | cksum)
t; assert_eq "T-528: the checkout is byte-for-byte identical to before the update" 'yes' \
  "$([ "$RBHOMESUM_BEFORE" = "$RBHOMESUM_AFTER" ] && printf yes || printf no)"

t; assert_eq "T-529: rollback leaves no backup directory behind (design: single undo, no redo chain)" 'no' \
  "$([ -e "$RBHOME.knotlog-previous" ] && printf yes || printf no)"
t; assert_eq "T-529: rollback leaves no rollback-tmp directory behind" 'no' \
  "$([ -e "$RBHOME.quipu-rollback-tmp" ] && printf yes || printf no)"

RBVAULTSUM_AFTER=$(cd "$TMP/rbhome" && find vault -type f | sort | xargs cat | cksum)
t; assert_eq "T-530: the vault fixture is byte-for-byte untouched by rollback" 'yes' \
  "$([ "$RBVAULTSUM_BEFORE" = "$RBVAULTSUM_AFTER" ] && printf yes || printf no)"

# T-531: rolling back again right away (no new update since) has nothing left
# to undo -- same clear-error contract as T-526, now exercised on a checkout
# that DID have a backup a moment ago (regression guard: a consumed backup
# must not silently look reusable).
t; QUIPU_LANG=en QUIPU_HOME="$RBHOME" sh "$ROOT/knotlog" rollback \
  >"$TMP/rb531.out" 2>"$TMP/rb531.err"; RC531=$?
t; assert_eq "T-531: a second rollback with no new update exits non-zero" 'yes' \
  "$([ "$RC531" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-531: a second rollback names the missing backup path" 'yes' \
  "$(grep -qF '.knotlog-previous' "$TMP/rb531.err" && printf yes || printf no)"

# T-532: a git-clone checkout that has never been updated has no `@{-1}`
# reflog entry to fall back to -- same clear-error contract as the tarball
# side (T-526), reached through the OTHER checkout kind.
RBGITSEED="$TMP/rbgitseed"
_q_seed_checkout "$RBGITSEED" 2.7.3
( cd "$RBGITSEED" && git init -q && git config user.email test@example.test \
    && git config user.name test && git add -A \
    && git commit -q -m base && git tag v2.7.3 ) >/dev/null 2>&1
RBGITHOME_NEVER="$TMP/rbgithome-never"
git clone -q "$RBGITSEED" "$RBGITHOME_NEVER" >/dev/null 2>&1
t; QUIPU_LANG=en QUIPU_HOME="$RBGITHOME_NEVER" sh "$ROOT/knotlog" rollback \
  >"$TMP/rb532.out" 2>"$TMP/rb532.err"; RC532=$?
t; assert_eq "T-532: never-updated git clone rollback exits non-zero" 'yes' \
  "$([ "$RC532" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-532: never-updated git clone rollback is reported on stderr" 'yes' \
  "$([ -s "$TMP/rb532.err" ] && printf yes || printf no)"

# T-533: git-clone happy path -- apply an update (same fixture shape as
# T-524), then roll it back: HEAD returns to the pre-update tag/commit and
# the checkout's own _q_version constant reads the old version again.
RBGITHOME="$TMP/rbgithome"
git clone -q "$RBGITSEED" "$RBGITHOME" >/dev/null 2>&1
sed "s/^_q_version=.*\$/_q_version=2.8.0/" "$RBGITSEED/knotlog" > "$RBGITSEED/knotlog.new"
mv "$RBGITSEED/knotlog.new" "$RBGITSEED/knotlog"
chmod +x "$RBGITSEED/knotlog"
( cd "$RBGITSEED" && git add -A && git commit -q -m bump && git tag v2.8.0 ) >/dev/null 2>&1
PREVCOMMIT=$(cd "$RBGITSEED" && git rev-parse v2.7.3)

t; QUIPU_LANG=en QUIPU_HOME="$RBGITHOME" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  sh "$ROOT/knotlog" update --apply >/dev/null 2>"$TMP/rb533-setup.err"
t; assert_eq "T-533 setup: git-clone update --apply reached 2.8.0" 'yes' \
  "$(grep -qF '_q_version=2.8.0' "$RBGITHOME/knotlog" && printf yes || printf no)"

t; RB533=$(QUIPU_LANG=en QUIPU_HOME="$RBGITHOME" sh "$ROOT/knotlog" rollback 2>"$TMP/rb533.err"); RC533=$?
t; assert_eq "T-533: git-clone rollback exits 0" '0' "$RC533"
t; assert_eq "T-533: git-clone rollback names the git checkout kind" 'yes' \
  "$(printf '%s\n' "$RB533" | grep -qF 'git' && printf yes || printf no)"
t; assert_eq "T-533: the checkout's own _q_version constant is 2.7.3 again" 'yes' \
  "$(grep -qF '_q_version=2.7.3' "$RBGITHOME/knotlog" && printf yes || printf no)"
t; assert_eq "T-533: HEAD is back at the pre-update (v2.7.3) commit" 'yes' \
  "$([ "$(cd "$RBGITHOME" && git rev-parse HEAD)" = "$PREVCOMMIT" ] && printf yes || printf no)"

# T-534: same bilingual contract update's own messages keep (T-515) --
# rollback's success message uses the Turkish string under QUIPU_LANG=tr.
RBTRHOME="$TMP/rbtrhome/Quipu"
_q_seed_checkout "$RBTRHOME" 2.7.3
t; QUIPU_LANG=en QUIPU_HOME="$RBTRHOME" \
  QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
  sh "$ROOT/knotlog" update --apply >/dev/null 2>&1
t; assert_eq "T-534 setup: update --apply reached 2.8.0" 'yes' \
  "$(grep -qF '_q_version=2.8.0' "$RBTRHOME/knotlog" && printf yes || printf no)"
t; RB534=$(QUIPU_LANG=tr QUIPU_HOME="$RBTRHOME" sh "$ROOT/knotlog" rollback); RC534=$?
t; assert_eq "T-534: Turkish rollback message exits 0" '0' "$RC534"
t; assert_eq "T-534: Turkish rollback message uses the Turkish string" 'yes' \
  "$(printf '%s\n' "$RB534" | grep -qF 'Geri alındı' && printf yes || printf no)"

# ---- Block index: text past the 2000-character search field (T-540..T-575) ----

# index.tsv keeps only the first 2000 characters of a note in its search
# field, so a word further down a long note used to be unsearchable. Notes
# that hit that cap now also get rows in .knotlog/blocks.tsv (the whole text cut
# into blocks of at most 2000 characters, each with its heading path), and
# `search` scores those rows too and reports one row per note. These tests
# pin: tail words are found (6-7 KB, 66 KB, one 40 KB line, CRLF + Turkish),
# notes under the cap behave exactly as before, the file follows the same
# incremental plan as index.tsv, and doctor notices when the two drift.
BLK="$TMP/vblk"
mkdir -p "$BLK/.knotlog" "$BLK/sub"
printf 'fold=tr\nlang=en\n' > "$BLK/.knotlog/config"
blk_fill() { # count prefix -> that many distinct words, ten per line
  awk -v n="$1" -v p="$2" 'BEGIN { for (i = 1; i <= n; i++) printf "%s%d%s", p, i, (i % 10 == 0 ? "\n" : " "); print "" }'
}
blkq() { QUIPU_VAULT="$BLK" QUIPU_LANG=en sh "$ROOT/knotlog" "$@"; }

{ printf '# Long Seven\n\nintro sharedhead words here.\n\n'; blk_fill 600 fseven
  printf '\n## Late Section\n\nzyxtailseven appears here and repeatedtail too.\n\n'; blk_fill 20 fmore
  printf '## Another\n\nrepeatedtail again.\n\n### Deep\n\nrepeatedtail thrice.\n'; } > "$BLK/long7.md"
{ printf '# Long Sixty\n\n'; blk_fill 6000 fsixty; printf 'zzfarsixty is the very last word.\n'; } > "$BLK/long60.md"
awk 'BEGIN { printf "# Long Line\n\n"; for (i = 1; i <= 4000; i++) printf "fline%d ", i; print "zzfarline" }' > "$BLK/longline.md"
awk 'BEGIN { cr = sprintf("%c", 13)
  printf "# Türkçe Not%s\n%s\nİstanbul şehrinde öğrenci notları.%s\n", cr, cr, cr
  for (i = 1; i <= 400; i++) printf "doldurucu%d kelime%s\n", i, cr
  printf "%s\n## Sonuç%s\n%s\nÇığırtkan sözcüğü burada geçiyor.%s\n", cr, cr, cr, cr }' > "$BLK/trcrlf.md"
printf '# Small\n\nsmallonly sharedhead short note.\n' > "$BLK/small.md"
printf '# Small Two\n\nsharedhead only two.\n' > "$BLK/sub/small2.md"
printf '# Small Three\n\nzzexactwordextra lives here.\n' > "$BLK/small3.md"
: > "$BLK/empty.md"
{ printf '# Wordy\n\n'; blk_fill 300 fwordy; printf 'zzexactword sits past the cap.\n'; } > "$BLK/wordy.md"
{ printf '# Fence Note\n\nintro.\n\n'; blk_fill 300 ffence
  printf '\n## Real Section\n\n%s\n# fake heading inside fence\nfencedword\n%s\n\nafter the fence tailfence.\n' '```' '```'; }> "$BLK/fence.md"
{ printf '%s\n' '---' 'title: Tagged A' 'tags: [proj]' 'status: active' '---' ''; blk_fill 300 fta; printf '\nzztailtaga commonfilt\n'; } > "$BLK/tagA.md"
{ printf '%s\n' '---' 'title: Tagged B' 'tags: [other]' 'status: draft' '---' ''; blk_fill 300 ftb; printf '\nzztailtagb commonfilt\n'; } > "$BLK/tagB.md"
{ printf '%s\n' '---' 'title: Tagged C' 'tags: [proj]' 'status: draft' '---' ''; blk_fill 300 ftc; printf '\nzztailtagc commonfilt\n'; } > "$BLK/tagC.md"

blkq index > "$TMP/blk-idx1.out" 2>&1
t; assert_eq "T-540: first index counts all 13 notes stale" '13 0 13 0' "$(idx_nums "$TMP/blk-idx1.out")"
LONG7_BYTES=$(wc -c < "$BLK/long7.md" | tr -d ' ')
t; assert_eq "T-541: the 6-7 KB fixture really is 6-7 KB" 'yes' "$([ "$LONG7_BYTES" -ge 6000 ] && [ "$LONG7_BYTES" -le 7000 ] && printf yes || printf no)"
t; assert_eq "T-542: a word past the cap of a 6-7 KB note is found" 'long7.md' "$(blkq search zyxtailseven --paths)"
t; assert_eq "T-543: a word at the end of a 66 KB note is found" 'long60.md' "$(blkq search zzfarsixty --paths)"
t; assert_eq "T-544: a word in the middle of a 66 KB note is found" 'long60.md' "$(blkq search fsixty3000 --paths)"
t; assert_eq "T-545: a word after a 40 KB single line is found" 'longline.md' "$(blkq search zzfarline --paths)"
t; assert_eq "T-546: a word in the middle of that single line is found" 'longline.md' "$(blkq search fline2500 --paths)"
t; assert_eq "T-547: CRLF Turkish note: tail word found by its Turkish spelling" 'trcrlf.md' "$(blkq search çığırtkan --paths)"
t; assert_eq "T-548: CRLF Turkish note: tail word found by its folded spelling" 'trcrlf.md' "$(blkq search cigirtkan --paths)"
t; assert_eq "T-549: a word repeated in three blocks still yields ONE row" 'long7.md' "$(blkq search repeatedtail --limit 10 --paths)"
t; assert_eq "T-550: an exact tail word does not trigger the substring fallback" 'wordy.md' "$(blkq search zzexactword --limit 10 --paths)"
t; assert_eq "T-551: a prefix of a tail word still works through the fallback" 'long60.md' "$(blkq search zzfarsix --paths)"

# T-552: notes under the cap are untouched. `smallonly` occurs only in
# small.md, so n/avgdl/df -- and with them the score -- come from note rows
# alone; the expected rows below were produced by the pre-block build
# (c1bbc7d) on this same vault, and the result must also be identical with
# blocks.tsv taken away.
GOLD_SMALL="3.503${TAB}small.md${TAB}Small${TAB}"
GOLD_SMALL_BRIEF="3.503${TAB}small.md${TAB}Small${TAB}${TAB}# small  smallonly sharedhead short note."
t; assert_eq "T-552: under-cap hit is byte-identical to the pre-block output" "$GOLD_SMALL" "$(blkq search smallonly)"
t; assert_eq "T-553: under-cap --brief is byte-identical to the pre-block output" "$GOLD_SMALL_BRIEF" "$(blkq search smallonly --brief)"
mv "$BLK/.knotlog/blocks.tsv" "$TMP/blk-aside.tsv"
t; assert_eq "T-554: same rows with blocks.tsv taken away" "$GOLD_SMALL" "$(blkq search smallonly)"
t; assert_eq "T-555: same --brief rows with blocks.tsv taken away" "$GOLD_SMALL_BRIEF" "$(blkq search smallonly --brief)"
t; assert_eq "T-556: without blocks.tsv the tail word is (still) not found" '' "$(blkq search zzfarsixty --paths)"
mv "$TMP/blk-aside.tsv" "$BLK/.knotlog/blocks.tsv"

BR="$BLK/.knotlog/blocks.tsv"
t; assert_eq "T-557: no block rows for notes under the cap or empty" '0' "$(awk -F"$TAB" '$1=="small.md"||$1=="sub/small2.md"||$1=="small3.md"||$1=="empty.md"{n++} END{print n+0}' "$BR")"
t; assert_eq "T-558: every block row has 7 columns and a text of at most 2000 characters" 'yes' \
  "$(awk -F"$TAB" '{ if (NF != 7 || length($5) > 2000 || $5 == "") bad++ } END{print (bad ? "no" : "yes")}' "$BR")"
t; assert_eq "T-559: the 66 KB note is cut into many blocks, each with the note title" 'yes' \
  "$(awk -F"$TAB" '$1=="long60.md"{n++; if ($2 != "Long Sixty") bad++} END{print (n >= 30 && !bad ? "yes" : "no")}' "$BR")"

# T-560/T-561: --brief shows where a block hit sits, and only for block hits.
# The heading path is folded like the rest of the snippet.
t; assert_eq "T-560: --brief block hit carries the heading path (nested)" '[long seven > another > deep] deep repeatedtail thrice.' \
  "$(blkq search thrice --brief | awk -F"$TAB" '{print $5}')"
t; assert_eq "T-561: a '#' line inside a fenced block is not a heading" '[fence note > real section] ' \
  "$(blkq search tailfence --brief | awk -F"$TAB" '{print substr($5, 1, 28)}')"
t; assert_eq "T-562: --brief rows stay 5 columns, block or not" 'yes' \
  "$( { blkq search thrice --brief; blkq search smallonly --brief; } | awk -F"$TAB" '{ if (NF != 5) bad++ } END{print (bad ? "no" : "yes")}')"
t; assert_eq "T-563: plain rows stay 4 columns with a N.NNN score" 'yes' \
  "$( { blkq search thrice; blkq search zzfarsixty; } | awk -F"$TAB" '{ if (NF != 4 || $1 !~ /^-?[0-9]+[.][0-9][0-9][0-9]$/) bad++ } END{print (bad ? "no" : "yes")}')"
t; assert_eq "T-564: block-hit snippet starts near the match, not at the block start" 'yes' \
  "$(blkq search fsixty3000 --brief | awk -F"$TAB" '{ print (index($5, "fsixty3000") > 0 ? "yes" : "no") }')"

# T-565..T-568: --tag / --status apply to block hits too, alone and together.
t; assert_eq "T-565: three tail hits without a filter" 'tagA.md
tagB.md
tagC.md' "$(blkq search commonfilt --paths | sort)"
t; assert_eq "T-566: --tag filters block hits" 'tagA.md
tagC.md' "$(blkq search commonfilt --tag proj --paths | sort)"
t; assert_eq "T-567: --status filters block hits" 'tagB.md
tagC.md' "$(blkq search commonfilt --status draft --paths | sort)"
t; assert_eq "T-568: --tag and --status combine (AND) on block hits" 'tagC.md' "$(blkq search commonfilt --tag proj --status draft --paths)"
t; assert_eq "T-569: a filter nothing satisfies leaves no block hit" '' "$(blkq search commonfilt --tag nothere --paths)"

# T-570: incremental plan. An unchanged run reuses every note and leaves
# blocks.tsv byte-identical.
cp "$BR" "$TMP/blk-b1.tsv"
blkq index > "$TMP/blk-idx2.out" 2>&1
t; assert_eq "T-570: unchanged second run reuses all 13, stale 0" '13 13 0 0' "$(idx_nums "$TMP/blk-idx2.out")"
t; assert_eq "T-571: blocks.tsv is byte-identical after the unchanged run" 'yes' "$(cmp -s "$BR" "$TMP/blk-b1.tsv" && printf yes || printf no)"

# T-572: a changed note gets fresh rows (old ones gone), others keep theirs.
sleep 1
{ printf '# Long Seven\n\n'; blk_fill 500 fnew; printf '\n## Fresh\n\nzzreplacedseven now.\n'; } > "$BLK/long7.md"
blkq index > "$TMP/blk-idx3.out" 2>&1
t; assert_eq "T-572: one changed long note: reused 12, stale 1" '13 12 1 0' "$(idx_nums "$TMP/blk-idx3.out")"
t; assert_eq "T-573: the changed note's new tail word is found" 'long7.md' "$(blkq search zzreplacedseven --paths)"
t; assert_eq "T-574: the changed note's old tail word is gone" '' "$(blkq search zyxtailseven --paths)"
awk -F"$TAB" '$1 != "long7.md"' "$TMP/blk-b1.tsv" > "$TMP/blk-b1.rest"
awk -F"$TAB" '$1 != "long7.md"' "$BR" > "$TMP/blk-b3.rest"
t; assert_eq "T-575: other notes' block rows are carried over unchanged" 'yes' "$(cmp -s "$TMP/blk-b1.rest" "$TMP/blk-b3.rest" && printf yes || printf no)"

# T-576: a note that shrinks under the cap loses all its block rows.
sleep 1
printf '# Now Short\n\nzzshortnow\n' > "$BLK/long7.md"
blkq index > "$TMP/blk-idx4.out" 2>&1
t; assert_eq "T-576: shrunk note has no block rows" '0' "$(awk -F"$TAB" '$1=="long7.md"{n++} END{print n+0}' "$BR")"
t; assert_eq "T-577: shrunk note is still found by its remaining text" 'long7.md' "$(blkq search zzshortnow --paths)"
t; assert_eq "T-578: shrunk note's dropped tail is not found" '' "$(blkq search zzreplacedseven --paths)"

# T-579: a deleted note loses its block rows and stops matching.
rm "$BLK/long60.md"
blkq index > "$TMP/blk-idx5.out" 2>&1
t; assert_eq "T-579: deleting a long note drops it (dropped 1)" '1' "$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /dropped/) print $(i + 1) }' "$TMP/blk-idx5.out" | tr -d ')')"
t; assert_eq "T-580: deleted note has no block rows" '0' "$(awk -F"$TAB" '$1=="long60.md"{n++} END{print n+0}' "$BR")"
t; assert_eq "T-581: deleted note's tail word finds nothing" '' "$(blkq search zzfarsixty --paths)"

# T-582: --full rebuilds the same file (row order aside).
sort "$BR" > "$TMP/blk-before-full.tsv"
blkq index --full > "$TMP/blk-idx6.out" 2>&1
t; assert_eq "T-582: index --full leaves every note stale" '12 0 12 0' "$(idx_nums "$TMP/blk-idx6.out")"
sort "$BR" > "$TMP/blk-after-full.tsv"
t; assert_eq "T-583: index --full reproduces the same block rows" 'yes' "$(cmp -s "$TMP/blk-before-full.tsv" "$TMP/blk-after-full.tsv" && printf yes || printf no)"

# T-584: an index made before blocks.tsv existed upgrades by itself: no
# --full needed, everything is rebuilt, the tail words come back.
rm "$BR"
blkq index > "$TMP/blk-idx7.out" 2>&1
t; assert_eq "T-584: plain index without blocks.tsv rebuilds all 12 (reused 0)" '12 0 12 0' "$(idx_nums "$TMP/blk-idx7.out")"
sort "$BR" > "$TMP/blk-after-upg.tsv"
t; assert_eq "T-585: the rebuild restores the same block rows" 'yes' "$(cmp -s "$TMP/blk-before-full.tsv" "$TMP/blk-after-upg.tsv" && printf yes || printf no)"
t; assert_eq "T-586: after the upgrade tail words are found again" 'longline.md' "$(blkq search zzfarline --paths)"

# T-587..T-591: doctor reports drift between blocks.tsv and index.tsv as an
# `info` row and stays silent when they agree.
blk_doc() { blkq doctor 2>/dev/null | awk -F"$TAB" '$2 == "blocks"'; }
t; assert_eq "T-587: doctor is silent about blocks when consistent" '' "$(blk_doc)"
grep -v '^longline.md' "$BR" > "$TMP/blk-nolong.tsv" || true
cp "$TMP/blk-nolong.tsv" "$BR"
t; assert_eq "T-588: doctor: a long note without block rows is an info row" 'info	blocks	blocks.tsv out of step with index.tsv: 0 leftover note(s), 1 long note(s) without blocks (knotlog index)' "$(blk_doc)"
printf 'ghost.md\tGhost\t\tghost heading\tghost text\t\n' >> "$BR"
t; assert_eq "T-589: doctor: a leftover row is counted too" 'info	blocks	blocks.tsv out of step with index.tsv: 1 leftover note(s), 1 long note(s) without blocks (knotlog index)' "$(blk_doc)"
t; assert_eq "T-590: doctor reports it in Turkish under QUIPU_LANG=tr" 'info	blocks	blocks.tsv, index.tsv ile uyumsuz: 1 artık not, blok satırı olmayan 1 uzun not (knotlog index)' \
  "$(QUIPU_VAULT="$BLK" QUIPU_LANG=tr sh "$ROOT/knotlog" doctor 2>/dev/null | awk -F"$TAB" '$2 == "blocks"')"
rm "$BR"
t; assert_eq "T-591: doctor: blocks.tsv missing beside a filled index is an info row" 'info	blocks	blocks.tsv missing: the text past 2000 characters of long notes is not searchable yet (knotlog index)' "$(blk_doc)"
blkq index > /dev/null 2>&1
t; assert_eq "T-592: after knotlog index doctor is silent again" '' "$(blk_doc)"
t; assert_eq "T-593: the doctor messages exist in both languages" 'yes' \
  "$(for k in doc_blocks_absent doc_blocks_mismatch; do grep -q "^$k=" "$ROOT/i18n/en.txt" && grep -q "^$k=" "$ROOT/i18n/tr.txt" || echo no; done | grep -q no && printf no || printf yes)"

# T-594: the .gitignore seeded by the baseline install (T-429/T-430 above)
# keeps the new machine-state file out of git.
t; assert_eq "T-594: the seeded .gitignore lists .knotlog/blocks.tsv" 'yes' "$(grep -qx '.knotlog/blocks.tsv' "$BASE_TARGET/.gitignore" && printf yes || printf no)"

# ---- Frontmatter aliases: searchable anywhere, weighted like the title (T-596..) ----

# `aliases:` used to be found only by accident (when it sat inside the first
# 2000 characters), and then with body weight. It is now read from the
# frontmatter (inline list, block list, single value), folded like the note
# text, put at the front of the search field and weighted like the title.
ALI="$TMP/vali"
mkdir -p "$ALI/.knotlog"
printf 'fold=tr\nlang=en\n' > "$ALI/.knotlog/config"
aliq() { QUIPU_VAULT="$ALI" QUIPU_LANG=en sh "$ROOT/knotlog" "$@"; }
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '# Filler %d\n\nfiller text with some ordinary words %d.\n' "$i" "$i" > "$ALI/filler$i.md"; done
printf '%s\n' '---' 'title: Inline Alias' 'aliases: [zzalinl, "ses ofseti", Açık Ölçüm]' '---' '' 'ordinary words here.' > "$ALI/al-inline.md"
printf '%s\n' '---' 'title: Block Alias' 'aliases:' '  - zzalblk' '  - "audio offset"' 'tags: [x]' '---' '' 'ordinary words here.' > "$ALI/al-block.md"
printf '%s\n' '---' 'title: Single Alias' 'aliases: zzalone' '---' '' 'ordinary words here.' > "$ALI/al-single.md"
printf '%s\n' '---' 'title: Empty Alias' 'aliases:' '---' '' 'zzalemptybody ordinary words here.' > "$ALI/al-empty.md"
{ printf '%s\n' '---' 'title: Late Alias'; blk_fill 300 kpad | tr ' ' '_' | sed 's/^/pad: /'; printf '%s\n' 'aliases: [zzallate]' '---' '' 'ordinary words here.'; } > "$ALI/al-late.md"
{ printf '%s\n' '---' 'title: Long Alias' 'aliases: [zzalbig]' '---' ''; blk_fill 600 albig; printf '\nzzaltail is the last word.\n'; } > "$ALI/al-long.md"
printf '%s\n' '---' 'title: Rank Alias' 'aliases: [zzrank]' '---' '' 'ordinary words here for length.' > "$ALI/rk-alias.md"
printf '%s\n' '---' 'title: Rank Body' '---' '' 'aliases: zzrank' 'ordinary words here.' > "$ALI/rk-body.md"
printf '# Body Line\n\naliases: zzalbodyline\n' > "$ALI/al-bodyline.md"
aliq index > "$TMP/ali-idx1.out" 2>&1
t; assert_eq "T-596: first index counts all 21 notes stale" '21 0 21 0' "$(idx_nums "$TMP/ali-idx1.out")"
t; assert_eq "T-597: an inline-list alias is found" 'al-inline.md' "$(aliq search zzalinl --paths)"
t; assert_eq "T-598: a quoted multi-word alias is found by its words" 'al-inline.md' "$(aliq search 'ses ofseti' --paths)"
t; assert_eq "T-599: an unquoted alias with a space is found" 'al-inline.md' "$(aliq search 'olcum' --paths)"
t; assert_eq "T-600: alias search folds Turkish: acik and açık both find it" 'al-inline.md al-inline.md' "$(aliq search acik --paths | tr '\n' ' ' | sed 's/ $//') $(aliq search açık --paths)"
t; assert_eq "T-601: a block-list alias is found" 'al-block.md' "$(aliq search zzalblk --paths)"
t; assert_eq "T-602: a quoted block-list alias is found" 'al-block.md' "$(aliq search 'audio offset' --paths)"
t; assert_eq "T-603: a single-value alias is found" 'al-single.md' "$(aliq search zzalone --paths)"
t; assert_eq "T-604: an empty aliases: line breaks nothing (body still found)" 'al-empty.md' "$(aliq search zzalemptybody --paths)"
ALI_LATE_OFF=$(grep -b -o 'zzallate' "$ALI/al-late.md" | head -1 | cut -d: -f1)
t; assert_eq "T-605: the fixture alias really sits past character 2000" 'yes' "$([ "$ALI_LATE_OFF" -gt 2000 ] && printf yes || printf no)"
t; assert_eq "T-606: an alias past character 2000 of the note is found" 'al-late.md' "$(aliq search zzallate --paths)"
t; assert_eq "T-607: an alias of a long note is found, and so is its tail" 'al-long.md al-long.md' "$(aliq search zzalbig --paths) $(aliq search zzaltail --paths)"
t; assert_eq "T-608: an aliases: line in the body is not an alias" 'al-bodyline.md' "$(aliq search zzalbodyline --paths)"
t; assert_eq "T-609: a real alias ranks before the same word in a body aliases: line" 'rk-alias.md rk-body.md' "$(aliq search zzrank --paths | tr '\n' ' ' | sed 's/ $//')"
ali_boost() { # -> "yes" when rk-alias scores at least 1.5x rk-body for zzrank
  aliq search zzrank | awk -F"$TAB" '$2 == "rk-alias.md" { a = $1 } $2 == "rk-body.md" { b = $1 }
    END { print (b > 0 && a >= 1.5 * b) ? "yes" : "no" }'
}
t; assert_eq "T-610: the alias hit scores at least 1.5x the body hit" 'yes' "$(ali_boost)"
t; assert_eq "T-611: output columns are unchanged for an alias hit (4, 5 with --brief)" '4 5' "$(aliq search zzalinl | awk -F"$TAB" '{ printf "%d ", NF }' | sed 's/ $//') $(aliq search zzalinl --brief | awk -F"$TAB" '{ print NF }')"
t; assert_eq "T-612: the alias marker never reaches the output" '0' "$(aliq search zzalinl --brief | LC_ALL=C grep -c "$(printf '\037')" || true)"
t; assert_eq "T-613: only notes with aliases carry the marker in index.tsv" '6' "$(LC_ALL=C grep -c "$(printf '\037')" "$ALI/.knotlog/index.tsv")"
t; assert_eq "T-614: --tag still filters an alias hit" 'al-block.md' "$(aliq search zzalblk --tag x --paths)"
: > "$TMP/ali-idx2.out"
aliq index > "$TMP/ali-idx2.out" 2>&1
t; assert_eq "T-615: an unchanged vault reuses every row" '21 21 0 0' "$(idx_nums "$TMP/ali-idx2.out")"

# T-616..T-618: an index built before aliases went into the search field (no
# .knotlog/index.schema, rows without the marker) upgrades by itself.
awk -F"$TAB" -v OFS="$TAB" -v us="$(printf '\037')" '{ n = index($5, us); if (n > 0) $5 = substr($5, n + 2); print }' "$ALI/.knotlog/index.tsv" > "$TMP/ali-old.tsv"
cp "$TMP/ali-old.tsv" "$ALI/.knotlog/index.tsv"
rm -f "$ALI/.knotlog/index.schema"
t; assert_eq "T-616: the old-shape index gives the alias only body weight" 'no' "$(ali_boost)"
aliq index > "$TMP/ali-idx3.out" 2>&1
t; assert_eq "T-617: a plain index without index.schema rebuilds all 21" '21 0 21 0' "$(idx_nums "$TMP/ali-idx3.out")"
t; assert_eq "T-618: after that the alias is weighted again, and index.schema is 3" 'yes 3' "$(ali_boost) $(cat "$ALI/.knotlog/index.schema")"
t; assert_eq "T-619: the seeded .gitignore lists .knotlog/index.schema" 'yes' "$(grep -qx '.knotlog/index.schema' "$BASE_TARGET/.gitignore" && printf yes || printf no)"

# ---- CRLF frontmatter (T-620..) ----
# A Windows note starts with "---" + CR, which used to hide the whole
# frontmatter from the indexer. The CRLF notes are built with printf here (not
# committed as files) so no .gitattributes eol rule can turn them into LF.
CRV="$TMP/vcrlf"
mkdir -p "$CRV/.knotlog"
printf 'fold=tr\nlang=en\n' > "$CRV/.knotlog/config"
crq() { QUIPU_VAULT="$CRV" QUIPU_LANG=en sh "$ROOT/knotlog" "$@"; }
CRC=$(printf '\r')
tocrlf() { awk -v cr="$CRC" '{ print $0 cr }'; }
cr_note() { # name fmcr bodycr : the same content, frontmatter/body in LF or CRLF
  { printf '%s\n' '---' 'title: Kedi Notu' 'tags: [zzcra, zzcrb]' 'status: active' 'type: ref' 'aliases: [zzcralias, "Pisi Kedi"]' 'related: [[FmLink]]' '---'; } > "$TMP/cr-fm.txt"
  { printf '%s\n' '# Baslik' '' 'Govde zzcrbody #zzcrhash [[Hedef]]'; } > "$TMP/cr-body.txt"
  if [ "$2" = 1 ]; then tocrlf < "$TMP/cr-fm.txt"; else cat "$TMP/cr-fm.txt"; fi > "$CRV/$1.md"
  if [ "$3" = 1 ]; then tocrlf < "$TMP/cr-body.txt"; else cat "$TMP/cr-body.txt"; fi >> "$CRV/$1.md"
}
cr_note cr-lf 0 0
cr_note cr-crlf 1 1
cr_note cr-mixa 0 1
cr_note cr-mixb 1 0
tocrlf > "$CRV/cr-blk.md" <<'EOF'
---
title: Blok Alias
aliases:
  - zzcrblock
  - "Ikinci Ad"
tags: [zzcrblk]
---
body words
EOF
tocrlf > "$CRV/cr-single.md" <<'EOF'
---
title: Tek Alias
aliases: zzcrone
---
body words
EOF
tocrlf > "$CRV/cr-empty.md" <<'EOF'
---
---
# Bos Kapak
body words
EOF
crq index > "$TMP/cr-idx.out" 2>&1
cr_row() { awk -F"$TAB" -v p="$1" -v c="$2" '$1 == p { print $c }' "$CRV/.knotlog/index.tsv"; }
cr_meta() { # note -> title|tags|status|type from the index row
  printf '%s|%s|%s|%s' "$(cr_row "$1" 2)" "$(cr_row "$1" 3)" "$(cr_row "$1" 6)" "$(cr_row "$1" 7)"
}
t; assert_eq "T-620: the LF note reads title/tags/status/type from its frontmatter" 'Kedi Notu|zzcra,zzcrb,zzcrhash|active|ref' "$(cr_meta cr-lf.md)"
t; assert_eq "T-621: a CRLF note reads the same title/tags/status/type" 'Kedi Notu|zzcra,zzcrb,zzcrhash|active|ref' "$(cr_meta cr-crlf.md)"
t; assert_eq "T-622: LF frontmatter + CRLF body reads the same" 'Kedi Notu|zzcra,zzcrb,zzcrhash|active|ref' "$(cr_meta cr-mixa.md)"
t; assert_eq "T-623: CRLF frontmatter + LF body reads the same" 'Kedi Notu|zzcra,zzcrb,zzcrhash|active|ref' "$(cr_meta cr-mixb.md)"
t; assert_eq "T-624: index.tsv columns 2, 3, 6, 7 hold no CR anywhere" '0' "$(awk -F"$TAB" -v cr="$CRC" '{ for (i = 2; i <= 7; i++) if (i != 5 && index($i, cr) > 0) n++ } END { print n + 0 }' "$CRV/.knotlog/index.tsv")"
t; assert_eq "T-625: --tag and --status find the CRLF note like the LF one" 'cr-crlf.md cr-lf.md cr-mixa.md cr-mixb.md' "$(crq search Kedi --tag zzcra --status active --paths | sort | tr '\n' ' ' | sed 's/ $//')"
t; assert_eq "T-626: an alias in a CRLF note is found (inline, quoted item)" 'cr-crlf.md cr-lf.md cr-mixa.md cr-mixb.md' "$(crq search zzcralias --paths | sort | tr '\n' ' ' | sed 's/ $//')"
t; assert_eq "T-627: a block-list alias in a CRLF note is found, tags too" 'cr-blk.md cr-blk.md' "$(crq search zzcrblock --paths) $(crq search Blok --tag zzcrblk --paths)"
t; assert_eq "T-628: a single-value alias in a CRLF note is found and marked as an alias" 'cr-single.md yes' "$(crq search zzcrone --paths) $(cr_row cr-single.md 5 | LC_ALL=C grep -q "$(printf '\037')" && printf yes || printf no)"
t; assert_eq "T-629: the alias field of a CRLF note carries no CR" '0' "$(awk -F"$TAB" -v cr="$CRC" '$1 == "cr-blk.md" || $1 == "cr-single.md" { if (index($5, cr) > 0) n++ } END { print n + 0 }' "$CRV/.knotlog/index.tsv")"
t; assert_eq "T-630: (control, same before the fix) an empty CRLF frontmatter leaves the # line as title" 'Bos Kapak||' "$(cr_row cr-empty.md 2)|$(cr_row cr-empty.md 6)|$(cr_row cr-empty.md 7)"
t; assert_eq "T-631: mode=meta reads a CRLF note like the LF one" 'yes' "$(a=$(awk -v mode=meta -f "$ROOT/lib/index.awk" "$CRV/cr-lf.md"); b=$(awk -v mode=meta -f "$ROOT/lib/index.awk" "$CRV/cr-crlf.md"); [ -n "$a" ] && [ "$a" = "$b" ] && printf yes || printf no)"
t; assert_eq "T-632: a wikilink inside CRLF frontmatter is not a body link, the body one is" 'Hedef' "$(awk -v mode=links -f "$ROOT/lib/index.awk" "$CRV/cr-crlf.md" | awk -F"$TAB" '{ print $2 }')"
t; assert_eq "T-633: an LF note's row is unchanged by CRLF handling (single row, 8 columns)" '1 8' "$(awk -F"$TAB" '$1 == "cr-lf.md" { n++; c = NF } END { print n + 0, c }' "$CRV/.knotlog/index.tsv")"

# ---- T-634..T-664: a cropped threads section says so, and `knotlog compact` ----
#
# `context` used to drop the bottom of an overgrown Threads.md silently; it now
# adds one line after the marker with the dropped byte count (only when the
# section is actually cut). `compact` moves the OLD "Closed threads" entries
# into the archive: dry run by default, and --apply is append -> verify ->
# cut, so a failure before the cut leaves the source untouched.
cpq() { # vault lang args... -> run quipu against that vault
  _cp_v=$1
  _cp_l=$2
  shift 2
  QUIPU_LANG=$_cp_l QUIPU_VAULT="$_cp_v" "$ROOT/knotlog" "$@"
}
cp_history() { # file  -> a scaffolded block, 6 closed entries, free text below
  {
    printf '<!-- quipu:threads:start -->\n'
    printf '### Active threads\n- live one\n\n### Closed threads\n'
    printf -- '- closed 1 first\n- closed 2\n- closed 3\n- closed 4\n- closed 5\n- closed 6 last\n'
    printf '<!-- quipu:threads:end -->\nfree text stays\n'
  } > "$1"
}
cp_find_archive() { # vault -> path of the archive file, empty when absent
  find "$1" -name 'Threads-Archive.md' -o -name 'Konular-Arsivi.md' | head -1
}

# T-634..T-637: the crop note (en).
mkvault vcn
{
  printf '<!-- quipu:threads:start -->\n### Active threads\n'
  cn_i=1
  while [ "$cn_i" -le 80 ]; do
    printf -- '- line %d of a long history\n' "$cn_i"
    cn_i=$((cn_i + 1))
  done
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vcn/Threads.md"
cpq "$TMP/vcn" en context > "$TMP/cn-big.out" 2>&1
(QUIPU_CTX_MAX=1500 cpq "$TMP/vcn" en context > "$TMP/cn-cut.out" 2>&1)
CN_SIZE=$(wc -c < "$TMP/vcn/Threads.md" | tr -d ' ')
CN_KEPT=$(LC_ALL=C awk -v hdr="$(men ctx_threads)" -v m="$(men ctx_truncated)" '
  $0 == hdr { on = 1; next }
  $0 == m { on = 0 }
  on { n += length($0) + 1 }
  END { print n + 0 }' "$TMP/cn-cut.out")
t; assert_eq "T-634: a cropped threads section is followed by the exact dropped-byte note" 'yes' \
  "$(grep -qxF "$(memfmt en ctx_threads_dropped $((CN_SIZE - CN_KEPT)))" "$TMP/cn-cut.out" && printf yes || printf no)"
t; assert_eq "T-635: the crop marker itself is still printed, and the note comes right after it" 'yes' \
  "$(awk -v m="$(men ctx_truncated)" -v h="$(mi18n en ctx_threads_dropped | awk -F'%d' '{print $2}')" '$0 == m { f = 1; next } f && index($0, h) > 0 { ok = 1 } { f = 0 } END { print (ok ? "yes" : "no") }' "$TMP/cn-cut.out")"
t; assert_eq "T-636: with the note, the whole context still fits inside ctx_max" 'yes' \
  "$([ "$(wc -c < "$TMP/cn-cut.out" | tr -d ' ')" -le 1500 ] && printf yes || printf no)"
t; assert_eq "T-637: a section that fits prints neither marker nor note" 'no' \
  "$(grep -qF "$(mi18n en ctx_threads_dropped | awk -F'%d' '{print $2}')" "$TMP/cn-big.out" && printf yes || printf no)"
t; assert_eq "T-637: a section that fits still carries the whole file (byte-identical section)" 'yes' \
  "$(awk -v hdr="$(men ctx_threads)" '$0 == hdr { on = 1; next } /^<!-- quipu:threads:end -->$/ { print; on = 0 } on { print }' "$TMP/cn-big.out" | cmp -s - "$TMP/vcn/Threads.md" && printf yes || printf no)"

# T-638: the same note in a Turkish vault.
mkvault vcnt
printf 'lang=tr\n' > "$TMP/vcnt/.knotlog/config"
cp "$TMP/vcn/Threads.md" "$TMP/vcnt/Konular.md"
(QUIPU_CTX_MAX=1500 cpq "$TMP/vcnt" tr context > "$TMP/cnt-cut.out" 2>&1)
t; assert_eq "T-638: the note is printed in Turkish in a Turkish vault" 'yes' \
  "$(grep -qF "$(mi18n tr ctx_threads_dropped | awk -F'%d' '{print $2}')" "$TMP/cnt-cut.out" && printf yes || printf no)"

# T-639..T-641: dry run by default; nothing on disk changes.
mkvault vcp
cp_history "$TMP/vcp/Threads.md"
cksum "$TMP/vcp/Threads.md" > "$TMP/vcp-before.ck"
CP_MT1=$(mtime "$TMP/vcp/Threads.md")
sleep 1
t; cpq "$TMP/vcp" en compact --keep 2 > "$TMP/cp-dry.out" 2>&1; RC=$?
assert_eq "T-639: compact (dry run) exits 0" '0' "$RC"
t; assert_eq "T-639: the preview names counts, bytes, keep and both files from i18n" 'yes' \
  "$(grep -qxF "$(memfmt en compact_preview 4 6 50 2 Threads.md '📦 900-Archive/Threads-Archive.md')" "$TMP/cp-dry.out" && printf yes || printf no)"
t; assert_eq "T-640: the dry run says it changed nothing" 'yes' \
  "$(grep -qxF "$(men compact_dry_run_note)" "$TMP/cp-dry.out" && printf yes || printf no)"
cksum "$TMP/vcp/Threads.md" > "$TMP/vcp-after.ck"
t; assert_eq "T-641: the dry run leaves Threads.md byte-identical" 'yes' \
  "$(cmp -s "$TMP/vcp-before.ck" "$TMP/vcp-after.ck" && printf yes || printf no)"
t; assert_eq "T-641: ... its mtime untouched, and no archive file created" "$CP_MT1 " \
  "$(mtime "$TMP/vcp/Threads.md") $(cp_find_archive "$TMP/vcp")"

# T-642..T-646: --apply is lossless, keeps the newest, and is idempotent.
t; cpq "$TMP/vcp" en compact --keep 2 --apply > "$TMP/cp-app.out" 2>&1; RC=$?
assert_eq "T-642: compact --apply exits 0" '0' "$RC"
CP_ARCH=$(cp_find_archive "$TMP/vcp")
t; assert_eq "T-642: the done line names the moved count and bytes" 'yes' \
  "$(grep -qF "$(memfmt en compact_done 4 50 Threads.md '' | awk -F' from ' '{print $1}')" "$TMP/cp-app.out" && printf yes || printf no)"
t; assert_eq "T-643: the archive is named from i18n and holds the marker line, then the OLD entries" 'yes' \
  "$([ "${CP_ARCH##*/}" = "$(men threads_archive_file)" ] && [ "$(sed -n 2,5p "$CP_ARCH" | tr '\n' '|')" = '- closed 1 first|- closed 2|- closed 3|- closed 4|' ] && sed -n 1p "$CP_ARCH" | grep -q '^<!-- knotlog:compacted [0-9-]* from=Threads.md -->$' && printf yes || printf no)"
{
  printf '<!-- quipu:threads:start -->\n'
  printf '### Active threads\n- live one\n\n### Closed threads\n'
  printf -- '- closed 5\n- closed 6 last\n'
  printf '<!-- quipu:threads:end -->\nfree text stays\n'
} > "$TMP/cp-expect.md"
t; assert_eq "T-644: the source keeps Active, skeleton, markers, free text and the newest 2" 'yes' \
  "$(cmp -s "$TMP/cp-expect.md" "$TMP/vcp/Threads.md" && printf yes || printf no)"
# Lossless: source head + archive body + source rest == the original file.
cp_history "$TMP/cp-orig.md"
{ sed -n 1,5p "$TMP/vcp/Threads.md"; tail -n +2 "$CP_ARCH"; sed -n '6,$p' "$TMP/vcp/Threads.md"; } > "$TMP/cp-rebuilt.md"
t; assert_eq "T-645: lossless — head + archived entries + rest rebuilds the original exactly" 'yes' \
  "$([ -s "$CP_ARCH" ] && cmp -s "$TMP/cp-orig.md" "$TMP/cp-rebuilt.md" && printf yes || printf no)"
cksum "$TMP/vcp/Threads.md" "$CP_ARCH" > "$TMP/vcp-a1.ck"
t; cpq "$TMP/vcp" en compact --keep 2 --apply > "$TMP/cp-app2.out" 2>&1; RC=$?
cksum "$TMP/vcp/Threads.md" "$CP_ARCH" > "$TMP/vcp-a2.ck"
t; assert_eq "T-646: a second --apply is a no-op (exit 0, both files byte-identical, says nothing to move)" '0 yes yes' \
  "$RC $(cmp -s "$TMP/vcp-a1.ck" "$TMP/vcp-a2.ck" && printf yes || printf no) $(grep -qxF "$(memfmt en compact_nothing 2 2)" "$TMP/cp-app2.out" && printf yes || printf no)"
t; assert_eq "T-646: no temp files are left behind in .knotlog/" '0' "$(find "$TMP/vcp/.knotlog" -name 'compact.*' | wc -l | tr -d ' ')"

# T-647: --keep 0 moves everything under the heading; default keep is 20.
mkvault vcp0
cp_history "$TMP/vcp0/Threads.md"
t; cpq "$TMP/vcp0" en compact --keep 0 --apply > /dev/null 2>&1; RC=$?
assert_eq "T-647: --keep 0 moves all six entries and exits 0" '0 6' \
  "$RC $(grep -c '^- closed' "$(cp_find_archive "$TMP/vcp0")")"
mkvault vcpd
cp_history "$TMP/vcpd/Threads.md"
cpq "$TMP/vcpd" en compact --apply > "$TMP/cp-def.out" 2>&1
t; assert_eq "T-647: the default keep (20) leaves a 6-entry section alone" 'yes' \
  "$(grep -qxF "$(memfmt en compact_nothing 6 20)" "$TMP/cp-def.out" && [ -z "$(cp_find_archive "$TMP/vcpd")" ] && printf yes || printf no)"

# T-648: an existing archive keeps its bytes; new entries go after them.
mkvault vcpa
cp_history "$TMP/vcpa/Threads.md"
mkdir -p "$TMP/vcpa/📦 900-Archive"
printf '# old archive\n- earlier thing\n' > "$TMP/vcpa/📦 900-Archive/Threads-Archive.md"
cp "$TMP/vcpa/📦 900-Archive/Threads-Archive.md" "$TMP/cpa-old.md"
t; cpq "$TMP/vcpa" en compact --keep 4 --apply > /dev/null 2>&1; RC=$?
CPA_SZ=$(wc -c < "$TMP/cpa-old.md" | tr -d ' ')
assert_eq "T-648: an existing archive keeps its exact bytes as a prefix" '0 yes' \
  "$RC $(head -c "$CPA_SZ" "$TMP/vcpa/📦 900-Archive/Threads-Archive.md" | cmp -s - "$TMP/cpa-old.md" && printf yes || printf no)"
t; assert_eq "T-648: ... then a blank line, the marker and the moved entries" 'yes' \
  "$(tail -n +3 "$TMP/vcpa/📦 900-Archive/Threads-Archive.md" | sed -n '1p;2p;3p;4p' | tr '\n' '|' | grep -q '^|<!-- knotlog:compacted [0-9-]* from=Threads.md -->|- closed 1 first|- closed 2|$' && printf yes || printf no)"

# T-649: entry shapes — continuation lines, sub-headings, preface, a heading
# that ends the section, free text. Only whole entries of the section move.
mkvault vcps
{
  printf '<!-- quipu:threads:start -->\n'
  printf '### Active threads\n- live one\n  continued\n\n### Closed threads\n'
  printf 'preface line stays\n'
  printf -- '- e1\n  cont e1\n\n- e2\n#### e3 heading\nbody e3\n\n'
  printf -- '- e4\n'
  printf '### Notes inside the block\n- not closed, stays\n'
  printf '<!-- quipu:threads:end -->\nfree text stays\n'
} > "$TMP/vcps/Threads.md"
t; cpq "$TMP/vcps" en compact --keep 1 --apply > /dev/null 2>&1; RC=$?
{
  printf '<!-- quipu:threads:start -->\n'
  printf '### Active threads\n- live one\n  continued\n\n### Closed threads\n'
  printf 'preface line stays\n'
  printf -- '- e4\n'
  printf '### Notes inside the block\n- not closed, stays\n'
  printf '<!-- quipu:threads:end -->\nfree text stays\n'
} > "$TMP/cps-expect.md"
{
  printf -- '- e1\n  cont e1\n\n- e2\n#### e3 heading\nbody e3\n\n'
} > "$TMP/cps-arch.md"
CPS_ARCH=$(cp_find_archive "$TMP/vcps")
t; assert_eq "T-649: sub-headings and continuation lines move with their entry; the rest is untouched" '0 yes yes' \
  "$RC $(cmp -s "$TMP/cps-expect.md" "$TMP/vcps/Threads.md" && printf yes || printf no) $(tail -n +2 "$CPS_ARCH" | cmp -s - "$TMP/cps-arch.md" && printf yes || printf no)"

# T-650: CRLF Threads.md — no byte is lost or altered.
mkvault vcpc
cp_history "$TMP/cpc-lf.md"
awk -v cr="$CRC" '{ print $0 cr }' "$TMP/cpc-lf.md" > "$TMP/vcpc/Threads.md"
cp "$TMP/vcpc/Threads.md" "$TMP/cpc-orig.md"
t; cpq "$TMP/vcpc" en compact --keep 2 --apply > /dev/null 2>&1; RC=$?
CPC_ARCH=$(cp_find_archive "$TMP/vcpc")
{ head -n 5 "$TMP/vcpc/Threads.md"; tail -n +2 "$CPC_ARCH"; tail -n +6 "$TMP/vcpc/Threads.md"; } > "$TMP/cpc-rebuilt.md"
t; assert_eq "T-650: CRLF file — exit 0, and head + archive + rest rebuilds the original byte for byte" '0 yes' \
  "$RC $(cmp -s "$TMP/cpc-orig.md" "$TMP/cpc-rebuilt.md" && printf yes || printf no)"
t; assert_eq "T-650: the archived entries keep their CRs (4 lines, 4 CRs)" '4' \
  "$(tail -n +2 "$CPC_ARCH" | LC_ALL=C tr -cd "$CRC" | wc -c | tr -d ' ')"

# T-651: a failed archive write leaves the source byte-identical and fails.
mkvault vcpf
cp_history "$TMP/vcpf/Threads.md"
mkdir -p "$TMP/vcpf/📦 900-Archive/Threads-Archive.md"
cp "$TMP/vcpf/Threads.md" "$TMP/cpf-before.md"
t; cpq "$TMP/vcpf" en compact --keep 2 --apply > "$TMP/cpf.out" 2>&1; RC=$?
assert_eq "T-651: archive write fails -> non-zero exit" 'yes' "$([ "$RC" -ne 0 ] && printf yes || printf no)"
t; assert_eq "T-651: ... the source is byte-identical and the i18n error is printed" 'yes yes' \
  "$(cmp -s "$TMP/cpf-before.md" "$TMP/vcpf/Threads.md" && printf yes || printf no) $(grep -qF "$(mi18n en err_compact_write | awk -F'%s' '{print $2}')" "$TMP/cpf.out" && printf yes || printf no)"
t; assert_eq "T-651: ... and no temp files are left in .knotlog/" '0' "$(find "$TMP/vcpf/.knotlog" -name 'compact.*' | wc -l | tr -d ' ')"

# T-652..T-654: files that cannot be compacted are refused and untouched.
mkvault vcpn1
t; cpq "$TMP/vcpn1" en compact --apply > "$TMP/cpn1.out" 2>&1; RC=$?
assert_eq "T-652: no Threads.md -> exit 1, i18n message, nothing created" '1 yes 0' \
  "$RC $(grep -qF "$(mi18n en err_archive_no_threads | awk -F'%s' '{print $1}')" "$TMP/cpn1.out" && printf yes || printf no) $(find "$TMP/vcpn1" -name 'Threads*' | wc -l | tr -d ' ')"
mkvault vcpn2
printf '### Closed threads\n- x\n- y\n' > "$TMP/vcpn2/Threads.md"
cp "$TMP/vcpn2/Threads.md" "$TMP/cpn2-before.md"
t; cpq "$TMP/vcpn2" en compact --keep 0 --apply > "$TMP/cpn2.out" 2>&1; RC=$?
assert_eq "T-653: no scaffold block -> exit 1, i18n message, file untouched, no archive" '1 yes yes yes' \
  "$RC $(grep -qF "$(mi18n en err_compact_no_block | awk -F'%s' '{print $2}')" "$TMP/cpn2.out" && printf yes || printf no) $(cmp -s "$TMP/cpn2-before.md" "$TMP/vcpn2/Threads.md" && printf yes || printf no) $([ -z "$(cp_find_archive "$TMP/vcpn2")" ] && printf yes || printf no)"
mkvault vcpn3
printf '<!-- quipu:threads:start -->\n### Active threads\n- a\n<!-- quipu:threads:end -->\n' > "$TMP/vcpn3/Threads.md"
cp "$TMP/vcpn3/Threads.md" "$TMP/cpn3-before.md"
t; cpq "$TMP/vcpn3" en compact --keep 0 --apply > "$TMP/cpn3.out" 2>&1; RC=$?
assert_eq "T-654: block without a Closed heading -> exit 1, i18n message, file untouched" '1 yes yes' \
  "$RC $(grep -qF "$(mi18n en err_compact_no_closed | awk -F'%s' '{print $2}')" "$TMP/cpn3.out" && printf yes || printf no) $(cmp -s "$TMP/cpn3-before.md" "$TMP/vcpn3/Threads.md" && printf yes || printf no)"

# T-655..T-657: Turkish vault (Konular.md, Kapanmış konular, Konular-Arsivi.md).
mkvault vcpt
printf 'lang=tr\n' > "$TMP/vcpt/.knotlog/config"
{
  printf '<!-- quipu:threads:start -->\n'
  printf '### %s\n- canlı\n\n### %s\n' "$(mi18n tr threads_head_active)" "$(mi18n tr threads_head_closed)"
  printf -- '- eski 1\n- eski 2\n- eski 3\n'
  printf '<!-- quipu:threads:end -->\n'
} > "$TMP/vcpt/Konular.md"
t; cpq "$TMP/vcpt" tr compact --keep 1 > "$TMP/cpt-dry.out" 2>&1; RC=$?
assert_eq "T-655: Turkish dry run exits 0 and prints the Turkish note" '0 yes' \
  "$RC $(grep -qxF "$(mi18n tr compact_dry_run_note)" "$TMP/cpt-dry.out" && printf yes || printf no)"
t; cpq "$TMP/vcpt" tr compact --keep 1 --apply > "$TMP/cpt-app.out" 2>&1; RC=$?
CPT_ARCH=$(cp_find_archive "$TMP/vcpt")
assert_eq "T-656: Turkish --apply moves the old entries into Konular-Arsivi.md" '0 Konular-Arsivi.md 2' \
  "$RC ${CPT_ARCH##*/} $(grep -c '^- eski' "$CPT_ARCH")"
t; assert_eq "T-657: the Turkish source keeps only the newest entry" 'yes' \
  "$(grep -c '^- eski' "$TMP/vcpt/Konular.md" | grep -qx 1 && grep -qx -- '- eski 3' "$TMP/vcpt/Konular.md" && printf yes || printf no)"

# T-658..T-660: argument handling, usage line, and no other file is touched.
t; cpq "$TMP/vcpd" en compact --keep abc > "$TMP/cpk.out" 2>&1; RC=$?
assert_eq "T-658: --keep with a non-integer -> exit 2 and the i18n message" '2 yes' \
  "$RC $(grep -qF "$(mi18n en err_compact_keep | awk -F'%s' '{print $1}')" "$TMP/cpk.out" && printf yes || printf no)"
t; cpq "$TMP/vcpd" en compact --bogus > /dev/null 2>&1; RC=$?
assert_eq "T-659: an unknown flag -> exit 2" '2' "$RC"
t; assert_eq "T-660: the usage list names compact in both languages" 'yes yes' \
  "$(cpq "$TMP/vcpd" en help 2>&1 | grep -qxF "$(men usage_compact)" && printf yes || printf no) $(cpq "$TMP/vcpd" en help --tr 2>&1 | grep -qxF "$(mtr usage_compact)" && printf yes || printf no)"

# T-661: a budget too small to spare the note keeps the plain marker only.
(QUIPU_CTX_MAX=1 cpq "$TMP/vcn" en context > "$TMP/cn-tiny.out" 2>&1)
t; assert_eq "T-661: a budget that cannot spare the note prints the marker and no note" 'yes no' \
  "$(grep -qxF "$(men ctx_truncated)" "$TMP/cn-tiny.out" && printf yes || printf no) $(grep -qF "$(mi18n en ctx_threads_dropped | awk -F'%d' '{print $2}')" "$TMP/cn-tiny.out" && printf yes || printf no)"

# ---- T-662..T-673: update/rollback -- what the release JSON may steer, ------
# ---- intermediate installs, and locally edited files -------------------------
# Reuses UPDPKG's "new release" tarball and _q_seed_checkout from the
# T-517..T-524 block above. Offline like the rest: file:// fixtures only.
UPDHX="$TMP/updhx"
mkdir -p "$UPDHX"
case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*) HXURL="file:///$(cygpath -m "$UPDHX")" ;;
  *) HXURL="file://$UPDHX" ;;
esac

# hx_apply NAME TAG FLAG: fresh 2.7.3 checkout, a release JSON whose tag_name
# is TAG, the download override pointing at the good 2.8.0 tarball -- so the
# only thing under test is whether TAG itself is accepted. Sets HX_RC and
# HX_BEFORE/HX_AFTER (checksum of the checkout AND its staging/backup siblings).
hx_apply() {
  HXH="$TMP/hx-$1/Quipu"
  rm -rf "$TMP/hx-$1"
  _q_seed_checkout "$HXH" 2.7.3
  printf '{"tag_name":"%s"}\n' "$2" > "$UPDHX/$1.json"
  HX_BEFORE=$(find "$TMP/hx-$1" -type f | sort | xargs cat | cksum)
  QUIPU_LANG=en QUIPU_HOME="$HXH" QUIPU_RELEASE_API_URL="$HXURL/$1.json" \
    QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
    sh "$ROOT/knotlog" update "$3" >"$TMP/hx-$1.out" 2>"$TMP/hx-$1.err"; HX_RC=$?
  HX_AFTER=$(find "$TMP/hx-$1" -type f | sort | xargs cat | cksum)
}
hx_expect_refused() { # label name tag flag
  hx_apply "$2" "$3" "$4"
  t; assert_eq "$1: a tag_name that is not a plain version is refused ($4)" 'yes' \
    "$([ "$HX_RC" -ne 0 ] && grep -qF 'could not read a version' "$TMP/hx-$2.err" && printf yes || printf no)"
  t; assert_eq "$1: the refused run leaves checkout, staging and backup untouched" 'yes' \
    "$([ "$HX_BEFORE" = "$HX_AFTER" ] && printf yes || printf no)"
}

# T-662..T-665: the default download URL is https://github.com/MSelmanSonmez/
# Knotlog/archive/refs/tags/v<tag>.tar.gz -- the tag is spliced into a path, so a
# tag_name carrying / .. ? # % or a space could aim the download at another
# repository or query. Refused before anything is fetched.
hx_expect_refused T-662 hxpath 'v2.8.0/../../../../attacker/Quipu/archive/refs/heads/x' --apply
hx_expect_refused T-663 hxquery 'v2.8.0?x=1#frag' --apply
hx_expect_refused T-664 hxpct 'v2.8.0%2f..%2fx' --apply
hx_expect_refused T-665 hxcheck 'v2.8.0/../../x' --check

# T-666: the check must not reject ordinary version tags with a suffix.
hx_apply hxrc 'v2.10.0-rc.1+build.5' --check
t; assert_eq "T-666: a tag with a pre-release/build suffix is still a valid version" 'yes' \
  "$([ "$HX_RC" -eq 0 ] && grep -qF '2.10.0-rc.1+build.5' "$TMP/hx-hxrc.out" && printf yes || printf no)"

# T-667: only tag_name is read from the release JSON. A tarball_url / html_url /
# renamed-repo url in it (here a decoy 6.6.6 archive) is never followed, so a
# renamed repository (new name in the reply) or a foreign address cannot
# change where the archive comes from.
_q_seed_checkout "$TMP/hx-decoy/Quipu-6.6.6" 6.6.6
tar -czf "$TMP/hx-decoy.tar.gz" -C "$TMP/hx-decoy" Quipu-6.6.6
printf '{"tag_name":"v2.8.0","tarball_url":"%s/hx-decoy.tar.gz","zipball_url":"https://evil.example/q.zip","html_url":"https://github.com/attacker/Quipu","url":"https://api.github.com/repos/example/Quipu-Renamed/releases/1"}\n' \
  "$UPDTARURL" > "$UPDHX/hxforeign.json"
HXF="$TMP/hx-foreign/Quipu"
_q_seed_checkout "$HXF" 2.7.3
t; QUIPU_LANG=en QUIPU_HOME="$HXF" QUIPU_RELEASE_API_URL="$HXURL/hxforeign.json" \
  QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
  sh "$ROOT/knotlog" update --apply >/dev/null 2>&1; RC667=$?
t; assert_eq "T-667: extra url fields in the release JSON are ignored (2.8.0 installed, decoy 6.6.6 not)" '0 yes no' \
  "$RC667 $(grep -qF '_q_version=2.8.0' "$HXF/knotlog" && printf yes || printf no) $(grep -qF '_q_version=6.6.6' "$HXF/knotlog" && printf yes || printf no)"

# T-668/T-669: an intermediate install -- same version string as the release
# it is compared with, but different content (installed from a branch, or from
# an earlier commit of the same version): it lacks a file the release ships and
# carries one the release does not. `--apply` to a newer release replaces the
# whole directory, so the result must be exactly the release tree (nothing
# missing, nothing stale) and the backup exactly the pre-update tree.
HXM="$TMP/hx-mid/Quipu"
_q_seed_checkout "$HXM" 2.7.3
rm -f "$HXM/lib/block.awk"
printf 'stale\n' > "$HXM/lib/only-in-the-old-install.awk"
cp -r "$HXM" "$TMP/hx-mid-snapshot"
t; QUIPU_LANG=en QUIPU_HOME="$HXM" QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
  sh "$ROOT/knotlog" update --apply >/dev/null 2>&1; RC668=$?
t; assert_eq "T-668: applying over an intermediate install yields exactly the release tree" '0 yes' \
  "$RC668 $(diff -r "$HXM" "$UPDPKG/Quipu-2.8.0" >/dev/null 2>&1 && printf yes || printf no)"
t; assert_eq "T-668: the file the old install lacked is present and its stale file is gone" 'yes no' \
  "$([ -f "$HXM/lib/block.awk" ] && printf yes || printf no) $([ -e "$HXM/lib/only-in-the-old-install.awk" ] && printf yes || printf no)"
t; assert_eq "T-668: the backup is exactly the pre-update tree, stale file included" 'yes' \
  "$(diff -r "$HXM.knotlog-previous" "$TMP/hx-mid-snapshot" >/dev/null 2>&1 && printf yes || printf no)"

# T-669: versions are compared as strings of numbers, never file content: an
# install with the same version string as the latest release counts as up to
# date even when its files differ. (Documented behaviour, pinned here.)
HXS="$TMP/hx-same/Quipu"
_q_seed_checkout "$HXS" 2.7.3
printf 'stale\n' > "$HXS/lib/only-in-the-old-install.awk"
t; UPD669=$(QUIPU_LANG=en QUIPU_HOME="$HXS" QUIPU_RELEASE_API_URL="$FIXURL/release-current.json" \
  QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
  sh "$ROOT/knotlog" update --apply 2>&1); RC669=$?
t; assert_eq "T-669: same version string means up to date and nothing is touched" '0 yes no yes' \
  "$RC669 $(printf '%s\n' "$UPD669" | grep -qF 'Up to date' && printf yes || printf no) $([ -e "$HXS.knotlog-previous" ] && printf yes || printf no) $([ -f "$HXS/lib/only-in-the-old-install.awk" ] && printf yes || printf no)"

# T-670..T-672: a checkout the user edited by hand (program file, library file,
# extra file of their own). `--apply` swaps the whole directory, so the edits
# are not carried into the new tree -- but they must survive byte-for-byte in
# the one-level backup, and `rollback` must bring them back. (Whether the swap
# should warn first is left open; this pins only that nothing is lost by one
# update followed by a rollback.)
HXE="$TMP/hx-edit/Quipu"
_q_seed_checkout "$HXE" 2.7.3
printf '# local edit\n' >> "$HXE/knotlog"
printf '# local edit\n' >> "$HXE/lib/index.awk"
mkdir -p "$HXE/mine"
printf 'my own file\n' > "$HXE/mine/notes.txt"
cp -r "$HXE" "$TMP/hx-edit-snapshot"
t; QUIPU_LANG=en QUIPU_HOME="$HXE" QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
  sh "$ROOT/knotlog" update --apply >/dev/null 2>&1; RC670=$?
t; assert_eq "T-670: --apply over a hand-edited checkout installs the release tree" '0 yes' \
  "$RC670 $(diff -r "$HXE" "$UPDPKG/Quipu-2.8.0" >/dev/null 2>&1 && printf yes || printf no)"
t; assert_eq "T-671: every local edit and the user's extra file survive byte-for-byte in the backup" 'yes' \
  "$(diff -r "$HXE.knotlog-previous" "$TMP/hx-edit-snapshot" >/dev/null 2>&1 && printf yes || printf no)"
t; QUIPU_LANG=en QUIPU_HOME="$HXE" sh "$ROOT/knotlog" rollback >/dev/null 2>&1; RC672=$?
t; assert_eq "T-672: rollback brings the hand-edited checkout back byte-for-byte" '0 yes' \
  "$RC672 $(diff -r "$HXE" "$TMP/hx-edit-snapshot" >/dev/null 2>&1 && printf yes || printf no)"

# T-673: git-clone checkout with a local edit to a file the release changes:
# git refuses to overwrite it, so --apply fails naming the tag, HEAD does not
# move and the edit is intact (no forced checkout).
HXG0="$TMP/hx-gseed"
_q_seed_checkout "$HXG0" 2.7.3
( cd "$HXG0" && git init -q && git config user.email test@example.test \
    && git config user.name test && git add -A \
    && git commit -q -m base && git tag v2.7.3 ) >/dev/null 2>&1
sed "s/^_q_version=.*\$/_q_version=2.8.0/" "$HXG0/knotlog" > "$HXG0/knotlog.new"
mv "$HXG0/knotlog.new" "$HXG0/knotlog"
chmod +x "$HXG0/knotlog"
printf 'upstream change\n' >> "$HXG0/i18n/en.txt"
( cd "$HXG0" && git add -A && git commit -q -m bump && git tag v2.8.0 ) >/dev/null 2>&1
HXG="$TMP/hx-gclone"
git clone -q "$HXG0" "$HXG" >/dev/null 2>&1
( cd "$HXG" && git checkout -q v2.7.3 ) >/dev/null 2>&1
printf '# local edit\n' >> "$HXG/i18n/en.txt"
t; QUIPU_LANG=en QUIPU_HOME="$HXG" QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
  sh "$ROOT/knotlog" update --apply >"$TMP/hx-g.out" 2>"$TMP/hx-g.err"; RC673=$?
t; assert_eq "T-673: git --apply refuses to overwrite a locally edited file the release changes" 'yes yes yes yes' \
  "$([ "$RC673" -ne 0 ] && printf yes || printf no) $(grep -qF 'v2.8.0' "$TMP/hx-g.err" && printf yes || printf no) $(grep -qF 'local edit' "$HXG/i18n/en.txt" && printf yes || printf no) $([ "$(cd "$HXG" && git rev-parse HEAD)" = "$(cd "$HXG0" && git rev-parse v2.7.3)" ] && printf yes || printf no)"

# ---- note (T-674..T-690): one line into today's reflection block ----------
# Each case builds its own vault; D is refreshed per section to avoid midnight skew.
D=$(date +%Y-%m-%d)
nte() { _n_v=$1; shift; QUIPU_VAULT="$TMP/$_n_v" QUIPU_LANG=en sh "$ROOT/knotlog" note "$@"; }
# last byte of FILE line N (od spells CR as \r; $(...) is not trusted with CR)
line_end() { tail -n "+$2" "$1" | head -n 1 | tr -d '\n' | tail -c 1 | od -An -c | tr -d ' '; }

# T-674: no vault anywhere on the walk-up -> err_no_vault, exit 1.
mkdir -p "$TMP/nonote-nov"
t; OUT=$(cd "$TMP/nonote-nov" && env -u QUIPU_VAULT QUIPU_LANG=en sh "$ROOT/knotlog" note hi 2>&1); RC=$?
assert_eq "T-674: note without a vault exits 1 with err_no_vault" 'yes' \
  "$([ "$RC" -eq 1 ] && [ "$OUT" = "$(i18n err_no_vault)" ] && printf yes || printf no)"

# T-675: no argument -> err_missing_arg, exit 2.
mkrem vn1
t; OUT=$(nte vn1 2>&1); RC=$?
assert_eq "T-675: note without an argument exits 2 with err_missing_arg" 'yes' \
  "$([ "$RC" -eq 2 ] && [ "$OUT" = "$(i18n err_missing_arg)" ] && printf yes || printf no)"

# T-676: empty text is treated as a missing argument, exit 2.
t; OUT=$(nte vn1 '' 2>&1); RC=$?
assert_eq "T-676: empty note text exits 2 with err_missing_arg" 'yes' \
  "$([ "$RC" -eq 2 ] && [ "$OUT" = "$(i18n err_missing_arg)" ] && printf yes || printf no)"

# T-677: two arguments -> err_note_args, exit 2.
t; OUT=$(nte vn1 one two 2>&1); RC=$?
assert_eq "T-677: two arguments exit 2 with err_note_args" 'yes' \
  "$([ "$RC" -eq 2 ] && [ "$OUT" = "$(i18n err_note_args)" ] && printf yes || printf no)"

# T-678: a leading dash is an unknown flag, exit 2.
t; OUT=$(nte vn1 -x 2>&1); RC=$?
assert_eq "T-678: -x exits 2 with err_unknown_flag" 'yes' \
  "$([ "$RC" -eq 2 ] && [ "$OUT" = "$(printf "$(i18n err_unknown_flag)" -x)" ] && printf yes || printf no)"

# T-679: LF or CR in the text -> err_note_newline, exit 2, no session file.
mkrem vn2
t; OUT=$(nte vn2 "$(printf 'a\nb')" 2>&1); RC=$?
OUT2=$(nte vn2 "$(printf 'a\rb')" 2>&1); RC2=$?
assert_eq "T-679: LF or CR in the text exits 2, err_note_newline, nothing written" 'yes' \
  "$([ "$RC" -eq 2 ] && [ "$RC2" -eq 2 ] && [ "$OUT" = "$(i18n err_note_newline)" ] && [ "$OUT2" = "$(i18n err_note_newline)" ] && [ ! -e "$TMP/vn2/700-Sessions/$D.md" ] && printf yes || printf no)"

# T-680: first note on a day with no session file: file + scaffold + one line
# under the first heading, output "wrote: 700-Sessions/<day>.md".
mkrem vn3
F3="$TMP/vn3/700-Sessions/$D.md"
t; OUT=$(nte vn3 'first note'); RC=$?
NL3=$(grep -n 'first note' "$F3" | cut -d: -f1)
H1=$(grep -n '^### ' "$F3" | sed -n 1p | cut -d: -f1)
H2=$(grep -n '^### ' "$F3" | sed -n 2p | cut -d: -f1)
assert_eq "T-680: first note creates file, scaffold, and a line under the first heading" 'yes' \
  "$([ "$RC" -eq 0 ] && [ "$OUT" = "$(printf "$(i18n note_ok)" "700-Sessions/$D.md")" ] \
     && [ "$(grep -c 'knotlog:reflect:start' "$F3")" = 1 ] && [ "$(grep -c '^### ' "$F3")" = 3 ] \
     && grep -qE "^- [0-9]{2}:[0-9]{2} first note\$" "$F3" \
     && [ "$NL3" -gt "$H1" ] && [ "$NL3" -lt "$H2" ] && printf yes || printf no)"

# T-681: a second note the same day lands after the first, order kept.
t; nte vn3 'second note' >/dev/null; RC=$?
N1=$(grep -n 'first note' "$F3" | cut -d: -f1)
N2=$(grep -n 'second note' "$F3" | cut -d: -f1)
assert_eq "T-681: second note is added after the first, order kept, one block" 'yes' \
  "$([ "$RC" -eq 0 ] && [ "$N2" -eq "$((N1 + 1))" ] && [ "$(grep -c 'knotlog:reflect:start' "$F3")" = 1 ] && printf yes || printf no)"

# T-682: note added to a remember-written file; removing the added line gives
# the original bytes (the rest of the file, including user text, is untouched).
mkrem vn4
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vn4/.knotlog/activity.log"
rem vn4 >/dev/null 2>&1
printf '%s\n' 'User text outside the block.' >> "$TMP/vn4/700-Sessions/$D.md"
cp "$TMP/vn4/700-Sessions/$D.md" "$TMP/vn4-orig.md"
t; nte vn4 'added line & \ % $HOME' >/dev/null; RC=$?
grep -v -e '^- [0-9][0-9]:[0-9][0-9] added line' "$TMP/vn4/700-Sessions/$D.md" > "$TMP/vn4-stripped.md"
assert_eq "T-682: note in a remember file: removing the added line gives the original bytes" 'yes' \
  "$([ "$RC" -eq 0 ] && cmp -s "$TMP/vn4-stripped.md" "$TMP/vn4-orig.md" \
     && [ "$(grep -c 'added line' "$TMP/vn4/700-Sessions/$D.md")" = 1 ] && printf yes || printf no)"

# T-683: special characters are written verbatim: \ t \n % s & $HOME.
mkrem vn5
SPEC='a\tb\\n %s & $HOME'
t; nte vn5 "$SPEC" >/dev/null; RC=$?
assert_eq "T-683: backslashes, percent, ampersand and dollar are written verbatim" 'yes' \
  "$([ "$RC" -eq 0 ] && grep -qF -- "$SPEC" "$TMP/vn5/700-Sessions/$D.md" && printf yes || printf no)"

# T-684: CRLF file: the added line ends with CR; removing it gives the original bytes.
mkrem vn6
F6="$TMP/vn6/700-Sessions/$D.md"
printf '%s\r\n' '## 09:00' '<!-- quipu:reflect:start -->' '### What changed in this session?' '' 'kept line' '### Where did the work happen?' '' '<!-- quipu:reflect:end -->' > "$F6"
cp "$F6" "$TMP/vn6-orig.md"
t; nte vn6 'crlf one' >/dev/null; RC=$?
assert_eq "T-684: CRLF file: added line ends with CR, other bytes unchanged" 'yes' \
  "$([ "$RC" -eq 0 ] && [ "$(line_end "$F6" 6)" = '\r' ] && { head -n 5 "$F6"; tail -n +7 "$F6"; } | cmp -s - "$TMP/vn6-orig.md" && printf yes || printf no)"

# T-685: SessionStart does not ask for a reflection once a note fills the block.
# Sanity first: an empty scaffold block does trigger the ask (T-99 pattern).
mkrem vn7
F7="$TMP/vn7/700-Sessions/$D.md"
{
  printf '%s\n' '<!-- quipu:reflect:start -->'
  printf '### %s\n' "$(i18n reflect_head_what)"
  printf '%s\n' ''
  printf '### %s\n' "$(i18n reflect_head_where)"
  printf '%s\n' ''
  printf '### %s\n' "$(i18n reflect_head_threads)"
  printf '%s\n' ''
  printf '%s\n' '<!-- quipu:reflect:end -->'
} > "$F7"
A85=$(QUIPU_VAULT="$TMP/vn7" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart)
A85D=$(printf '%s' "$A85" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
# shellcheck disable=SC2059
A85_EXPECT=$(printf "$(i18n ctx_reflect_ask)" "700-Sessions/$D.md" 'quipu:reflect')
t; nte vn7 'filled' >/dev/null
A85B=$(QUIPU_VAULT="$TMP/vn7" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart)
A85BD=$(printf '%s' "$A85B" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "T-685: empty block asks (sanity), a note fills it and the ask is gone" 'yes' \
  "$(printf '%s\n' "$A85D" | grep -qF "$A85_EXPECT" && ! printf '%s\n' "$A85BD" | grep -qF "$A85_EXPECT" && printf yes || printf no)"

# T-686: a note written before remember survives it; the block stays single.
mkrem vn8
printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | 500-Knowledge/not.md' >> "$TMP/vn8/.knotlog/activity.log"
nte vn8 'kept line' >/dev/null
t; rem vn8 >/dev/null 2>&1; RC=$?
F8="$TMP/vn8/700-Sessions/$D.md"
assert_eq "T-686: remember keeps the note line and leaves one reflection block" 'yes' \
  "$([ "$RC" -eq 0 ] && grep -qF 'kept line' "$F8" && [ "$(grep -c 'knotlog:reflect:start' "$F8")" = 1 ] && [ "$(grep -c '^### ' "$F8")" = 3 ] && printf yes || printf no)"

# T-687: busy lock (live pid) -> note_busy, exit 1, file unchanged.
mkrem vn9
nte vn9 'before' >/dev/null
cp "$TMP/vn9/700-Sessions/$D.md" "$TMP/vn9-orig.md"
mkdir "$TMP/vn9/.knotlog/remember.lock"
printf '%s\n' "$$" > "$TMP/vn9/.knotlog/remember.lock/pid"
t; OUT=$(nte vn9 'busy' 2>&1); RC=$?
rm -f "$TMP/vn9/.knotlog/remember.lock/pid"; rmdir "$TMP/vn9/.knotlog/remember.lock"
assert_eq "T-687: busy lock exits 1 with note_busy and leaves the file unchanged" 'yes' \
  "$([ "$RC" -eq 1 ] && [ "$OUT" = "$(i18n note_busy)" ] && cmp -s "$TMP/vn9/700-Sessions/$D.md" "$TMP/vn9-orig.md" && printf yes || printf no)"

# T-688: start marker without end marker -> err_note_block, exit 1, unchanged.
mkrem vn10
F10="$TMP/vn10/700-Sessions/$D.md"
printf '%s\n' '<!-- quipu:reflect:start -->' '### a' '### b' > "$F10"
cp "$F10" "$TMP/vn10-orig.md"
t; OUT=$(nte vn10 'x' 2>&1); RC=$?
assert_eq "T-688: start without end exits 1 with err_note_block and writes nothing" 'yes' \
  "$([ "$RC" -eq 1 ] && [ "$OUT" = "$(i18n err_note_block)" ] && cmp -s "$F10" "$TMP/vn10-orig.md" && printf yes || printf no)"

# T-689: a block with a single heading gets the line before its end marker.
mkrem vn12
F12="$TMP/vn12/700-Sessions/$D.md"
printf '%s\n' '<!-- quipu:reflect:start -->' 'only text' '<!-- quipu:reflect:end -->' > "$F12"
t; nte vn12 'single' >/dev/null; RC=$?
assert_eq "T-689: block without a second heading: line goes before the end marker" 'yes' \
  "$([ "$RC" -eq 0 ] && [ "$(sed -n 2p "$F12")" = 'only text' ] && grep -qE '^- [0-9]{2}:[0-9]{2} single$' "$F12" \
     && [ "$(sed -n 4p "$F12")" = '<!-- quipu:reflect:end -->' ] && [ "$(sed -n 3p "$F12")" != 'only text' ] && printf yes || printf no)"

# T-690: QUIPU_LANG=tr prints the Turkish note_ok line.
mkrem vn11
TR_OK=$(awk -F= '$1=="note_ok"{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/tr.txt")
t; OUT=$(QUIPU_VAULT="$TMP/vn11" QUIPU_LANG=tr sh "$ROOT/knotlog" note 'tr line' 2>&1); RC=$?
assert_eq "T-690: QUIPU_LANG=tr prints yazıldı: with the relative path" 'yes' \
  "$([ "$RC" -eq 0 ] && [ "$OUT" = "$(printf "$TR_OK" "700-Sessions/$D.md")" ] && printf yes || printf no)"

# T-708: the temp file cannot be created (a directory sits where .knotlog/note.tmp
# must go, so the write fails portably) -> err_note_write with the relative
# path, exit 1, session file unchanged. The shell may add its own redirect
# error line, so the message is matched as a whole line, not as the output.
mkrem vn13
F13="$TMP/vn13/700-Sessions/$D.md"
printf '%s\n' '<!-- quipu:reflect:start -->' '### a' '### b' '<!-- quipu:reflect:end -->' > "$F13"
cp "$F13" "$TMP/vn13-orig.md"
mkdir -p "$TMP/vn13/.knotlog/note.tmp"
t; OUT=$(nte vn13 'wf' 2>&1); RC=$?
EXP13=$(printf "$(i18n err_note_write)" "700-Sessions/$D.md")
assert_eq "T-708: an unwritable temp file exits 1 with err_note_write and leaves the session file unchanged" 'yes' \
  "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qxF "$EXP13" && cmp -s "$F13" "$TMP/vn13-orig.md" && printf yes || printf no)"

# T-691: CRLF Threads.md -- `archive` writes the section's lines WITH their CRs,
# and head + archive + rest rebuilds the original byte for byte (head/tail/cmp).
mkvault vrac
printf '<!-- quipu:threads:start -->\n### Active threads\n- live\n\n### Closed threads\n- old A\n  cont\n\n### Closed old topic\n- old B\n\n- old C\n### Other\n- x\n<!-- quipu:threads:end -->\nfree\n' | tocrlf > "$TMP/vrac/Threads.md"
cp "$TMP/vrac/Threads.md" "$TMP/rac-orig.md"
t; cpq "$TMP/vrac" en archive "Closed old topic" > /dev/null 2>&1; RC691=$?
RAC_ARCH=$(cp_find_archive "$TMP/vrac")
{ head -n 8 "$TMP/rac-orig.md"; tail -n +2 "$RAC_ARCH"; tail -n +13 "$TMP/rac-orig.md"; } > "$TMP/rac-rebuilt.md"
t; assert_eq "T-691: CRLF archive -- exit 0, the archived lines keep their CRs (4 lines, 4 CRs), and head + archive + rest rebuilds the original byte for byte" '0 4 yes' \
  "$RC691 $(tail -n +2 "$RAC_ARCH" | LC_ALL=C tr -cd "$CRC" | wc -c | tr -d ' ') $(cmp -s "$TMP/rac-orig.md" "$TMP/rac-rebuilt.md" && printf yes || printf no)"

# T-692: CRLF Threads.md -- the lines left in the source keep their CRs, and
# head + tail of the original is exactly what remains (12 lines, 12 CRs).
t; assert_eq "T-692: CRLF source after archive -- the 12 kept lines keep their CRs and equal head + tail of the original" '12 yes' \
  "$(LC_ALL=C tr -cd "$CRC" < "$TMP/vrac/Threads.md" | wc -c | tr -d ' ') $({ head -n 8 "$TMP/rac-orig.md"; tail -n +13 "$TMP/rac-orig.md"; } | cmp -s - "$TMP/vrac/Threads.md" && printf yes || printf no)"

# ---- doctor reflection nudge (T-693..T-701): one warn row when today's events
# exceed note_nudge_events= and today's reflection block is empty or missing --
# silent otherwise. Each case builds its own vault; D and YD are refreshed here.
D=$(date +%Y-%m-%d)
YD=$(date -d yesterday +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
nudge_rows() { # vault lang -> number of doctor rows named as the nudge row (the name column is localized; the status word is not compared, so tr and en both count)
  _nr_n=$(awk -F= -v k=doc_reflect_name '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/$2.txt")
  (cd "$TMP/$1" && QUIPU_LANG=$2 sh "$ROOT/knotlog" doctor 2>&1) | awk -F"$TAB" -v n="$_nr_n" '$2==n { c++ } END { print c + 0 }'
}
nudge_detail() { # vault lang -> detail column of the nudge row
  _nd_n=$(awk -F= -v k=doc_reflect_name '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/$2.txt")
  (cd "$TMP/$1" && QUIPU_LANG=$2 sh "$ROOT/knotlog" doctor 2>&1) | awk -F"$TAB" -v n="$_nd_n" '$2==n { print $3; exit }'
}
nudge_events() { # vault count date -> append COUNT events dated DATE to activity.log
  _ne_i=0
  while [ "$_ne_i" -lt "$2" ]; do
    _ne_i=$((_ne_i + 1))
    printf '%sT12:10 | PostToolUse | x\n' "$3" >> "$TMP/$1/.knotlog/activity.log"
  done
}
nudge_sess() { # vault -> path of today's session file under the plain layout
  _ns_s=$(awk -F"$TAB" '$1=="sessions"{print $2;exit}' "$ROOT/layout/plain.txt")
  mkdir -p "$TMP/$1/$_ns_s"
  printf '%s\n' '# s' '<!-- quipu:reflect:start -->' '### Yansima' '<!-- quipu:reflect:end -->' > "$TMP/$1/$_ns_s/$D.md"
}

# T-693: 51 events today (default threshold 50), no session file -> one warn row, detail names 51.
mkrem vnu1
nudge_events vnu1 51 "$D"
t; assert_eq "T-693: 51 events today and no session file -> one warn row whose detail names 51" 'yes' \
  "$([ "$(nudge_rows vnu1 en)" -eq 1 ] && nudge_detail vnu1 en | grep -q '51' && printf yes || printf no)"

# T-694: 51 events today + empty reflection block -> one warn row.
mkrem vnu2
nudge_events vnu2 51 "$D"
nudge_sess vnu2
t; assert_eq "T-694: 51 events and an empty reflection block -> one warn row" '1' "$(nudge_rows vnu2 en)"

# T-695: 51 events today + filled reflection block (knotlog note) -> no nudge row.
mkrem vnu3
nudge_events vnu3 51 "$D"
QUIPU_VAULT="$TMP/vnu3" QUIPU_LANG=en sh "$ROOT/knotlog" note 'filled line' >/dev/null 2>&1
t; assert_eq "T-695: 51 events and a filled reflection block -> no nudge row" '0' "$(nudge_rows vnu3 en)"

# T-696: exactly 50 events (the default threshold is strict: > 50) -> no row.
mkrem vnu4
nudge_events vnu4 50 "$D"
t; assert_eq "T-696: exactly 50 events under the default threshold -> no nudge row" '0' "$(nudge_rows vnu4 en)"

# T-697: note_nudge_events=0 turns the check off, even with 60 events -> no row.
mkrem vnu5
printf '%s\n' 'note_nudge_events=0' >> "$TMP/vnu5/.knotlog/config"
nudge_events vnu5 60 "$D"
t; assert_eq "T-697: note_nudge_events=0 with 60 events -> no nudge row" '0' "$(nudge_rows vnu5 en)"

# T-698: note_nudge_events=3 is a custom threshold: 4 events -> row, 3 events -> none.
mkrem vnu6
printf '%s\n' 'note_nudge_events=3' >> "$TMP/vnu6/.knotlog/config"
nudge_events vnu6 4 "$D"
A6=$(nudge_rows vnu6 en)
mkrem vnu7
printf '%s\n' 'note_nudge_events=3' >> "$TMP/vnu7/.knotlog/config"
nudge_events vnu7 3 "$D"
B6=$(nudge_rows vnu7 en)
t; assert_eq "T-698: note_nudge_events=3 -> 4 events warn, 3 events silent" '1 0' "$A6 $B6"

# T-699: a non-number value falls back to the default 50: 51 events -> row, 50 -> none.
mkrem vnu8
printf '%s\n' 'note_nudge_events=lots' >> "$TMP/vnu8/.knotlog/config"
nudge_events vnu8 51 "$D"
mkrem vnu9
printf '%s\n' 'note_nudge_events=lots' >> "$TMP/vnu9/.knotlog/config"
nudge_events vnu9 50 "$D"
t; assert_eq "T-699: non-number note_nudge_events -> default 50 (51 warn, 50 silent)" '1 0' "$(nudge_rows vnu8 en) $(nudge_rows vnu9 en)"

# T-700: yesterday's events are not counted: 60 events dated yesterday -> no row.
mkrem vnu10
nudge_events vnu10 60 "$YD"
t; assert_eq "T-700: 60 events dated yesterday are not counted -> no nudge row" '0' "$(nudge_rows vnu10 en)"

# T-701: QUIPU_LANG=tr prints the Turkish name and detail (yansıma / olay var).
mkrem vnu11
nudge_events vnu11 51 "$D"
TR_NUD=$(awk -F= '$1=="doc_reflect_unwritten"{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/tr.txt")
t; assert_eq "T-701: QUIPU_LANG=tr -> yansıma row with the Turkish detail" 'yes' \
  "$([ "$(nudge_rows vnu11 tr)" -eq 1 ] && [ "$(nudge_detail vnu11 tr)" = "$(printf "$TR_NUD" 51)" ] && printf yes || printf no)"

# ---- T-702..T-706: update backup rotation (N=3) and the rollback chain -------
# Backups: .knotlog-previous (newest), .knotlog-previous.2, .knotlog-previous.3.
# Fixtures: one tarball + release JSON per version (2.8.0 .. 3.1.0), built
# under $TMP/rot; the running script is the repo's own, so no network.
ROT="$TMP/rot"
mkdir -p "$ROT/pkg" "$ROT/rel" "$ROT/home"
for RV in 2.8.0 2.9.0 3.0.0 3.1.0; do
  _q_seed_checkout "$ROT/pkg/Quipu-$RV" "$RV"
  tar -czf "$ROT/rel/t-$RV.tar.gz" -C "$ROT/pkg" "Quipu-$RV"
  _q_mk_sha "$ROT/rel/t-$RV.tar.gz"
  printf '{\n  "tag_name": "v%s"\n}\n' "$RV" > "$ROT/rel/rel-$RV.json"
done
case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*) ROTURL="file:///$(cygpath -m "$ROT/rel")" ;;
  *) ROTURL="file://$ROT/rel" ;;
esac
rot_apply() { # $1 = checkout, $2 = target version
  QUIPU_LANG=en QUIPU_HOME="$1" QUIPU_RELEASE_API_URL="$ROTURL/rel-$2.json" \
    QUIPU_UPDATE_TARBALL_URL="$ROTURL/t-$2.tar.gz" \
    sh "$ROOT/knotlog" update --apply >/dev/null 2>"$ROT/apply-$2.err"
}

# T-702: two --apply in a row. The newest backup is the tree just before the
# second update; .knotlog-previous.2 is the tree before the first update, with
# the hand edit made before it kept byte for byte.
RH="$ROT/home/Quipu"
_q_seed_checkout "$RH" 2.7.3
printf 'edit-a\n' >> "$RH/i18n/en.txt"
cp -r "$RH" "$ROT/snap-a"
rot_apply "$RH" 2.8.0
printf 'edit-b\n' >> "$RH/i18n/en.txt"
cp -r "$RH" "$ROT/snap-b"
rot_apply "$RH" 2.9.0
t; assert_eq "T-702: second --apply: .knotlog-previous is the tree before it, byte for byte" 'yes' \
  "$(diff -r "$ROT/snap-b" "$RH.knotlog-previous" >/dev/null 2>&1 && printf yes || printf no)"
t; assert_eq "T-702: second --apply: .knotlog-previous.2 is the tree before the first, edit A kept" 'yes' \
  "$(diff -r "$ROT/snap-a" "$RH.knotlog-previous.2" >/dev/null 2>&1 && printf yes || printf no)"

# T-703: four --apply -> exactly three backups; the 2.7.3 tree is dropped.
rot_apply "$RH" 3.0.0
rot_apply "$RH" 3.1.0
t; assert_eq "T-703: four --apply leave exactly three backups" '3' \
  "$(set -- "$RH".knotlog-previous*; printf %s "$#")"
t; assert_eq "T-703: the oldest tree (2.7.3) is gone from every backup slot" 'no' \
  "$(grep -rlF '_q_version=2.7.3' "$ROT/home" >/dev/null 2>&1 && printf yes || printf no)"
t; assert_eq "T-703: slots hold 3.0.0 (.knotlog-previous), 2.9.0 (.2), 2.8.0 (.3)" 'yes' \
  "$(grep -qF '_q_version=3.0.0' "$RH.knotlog-previous/knotlog" && grep -qF '_q_version=2.9.0' "$RH.knotlog-previous.2/knotlog" \
     && grep -qF '_q_version=2.8.0' "$RH.knotlog-previous.3/knotlog" && printf yes || printf no)"

# T-704: rollback restores the newest backup (3.0.0) and shifts the chain back.
QUIPU_LANG=en QUIPU_HOME="$RH" sh "$ROOT/knotlog" rollback >/dev/null 2>"$ROT/rb704.err"; RC704=$?
t; assert_eq "T-704: rollback exits 0 and restores 3.0.0 into the checkout" 'yes' \
  "$([ "$RC704" -eq 0 ] && grep -qF '_q_version=3.0.0' "$RH/knotlog" && printf yes || printf no)"
t; assert_eq "T-704: rollback shifts the chain: .2 -> .knotlog-previous, .3 -> .2" 'yes' \
  "$(grep -qF '_q_version=2.9.0' "$RH.knotlog-previous/knotlog" && grep -qF '_q_version=2.8.0' "$RH.knotlog-previous.2/knotlog" \
     && [ ! -e "$RH.knotlog-previous.3" ] && printf yes || printf no)"

# T-705: a second rollback walks one step further back (2.9.0), not a no-op.
QUIPU_LANG=en QUIPU_HOME="$RH" sh "$ROOT/knotlog" rollback >/dev/null 2>"$ROT/rb705.err"; RC705=$?
t; assert_eq "T-705: second rollback exits 0 and restores 2.9.0" 'yes' \
  "$([ "$RC705" -eq 0 ] && grep -qF '_q_version=2.9.0' "$RH/knotlog" && printf yes || printf no)"
t; assert_eq "T-705: after it, .knotlog-previous holds 2.8.0 and .2 is gone" 'yes' \
  "$(grep -qF '_q_version=2.8.0' "$RH.knotlog-previous/knotlog" && [ ! -e "$RH.knotlog-previous.2" ] && printf yes || printf no)"

# T-706: a half-finished update (checkout moved away, backup left) is undone
# by rollback: the backup goes straight back into place, no rollback-tmp left.
mv "$RH" "$ROT/side-home"
QUIPU_LANG=en QUIPU_HOME="$RH" sh "$ROOT/knotlog" rollback >/dev/null 2>"$ROT/rb706.err"; RC706=$?
t; assert_eq "T-706: rollback with the checkout missing restores 2.8.0 from .knotlog-previous" 'yes' \
  "$([ "$RC706" -eq 0 ] && grep -qF '_q_version=2.8.0' "$RH/knotlog" && printf yes || printf no)"
t; assert_eq "T-706: that rollback leaves no rollback-tmp directory behind" 'no' \
  "$([ -e "$RH.quipu-rollback-tmp" ] && printf yes || printf no)"

# T-707: the FIRST swap mv fails after the rotation ran -- the rotation is
# undone before the error, so .knotlog-previous holds the tree it held before
# the update. The failure is provoked by an open file inside the checkout:
# Windows refuses to rename a directory that holds an open file. Where a
# rename still works with an open handle (POSIX), there is no portable way
# to fail that mv without a test hook, so the case is recorded as skipped.
PROBE707="$ROT/probe707"
mkdir -p "$PROBE707/d" && printf 'x\n' > "$PROBE707/d/f"
exec 9< "$PROBE707/d/f"
if mv -- "$PROBE707/d" "$PROBE707/d2" 2>/dev/null; then LOCK707=0; else LOCK707=1; fi
exec 9<&-
if [ "$LOCK707" -eq 1 ]; then
  RL="$ROT/home707/Quipu"
  mkdir -p "$ROT/home707"
  _q_seed_checkout "$RL" 2.7.3
  rot_apply "$RL" 2.8.0
  exec 9< "$RL/knotlog"
  rot_apply "$RL" 2.9.0; RC707=$?
  exec 9<&-
  t; assert_eq "T-707: the failed first swap exits non-zero and names the swap error" 'yes' \
    "$([ "$RC707" -ne 0 ] && grep -qF 'could not swap' "$ROT/apply-2.9.0.err" && printf yes || printf no)"
  t; assert_eq "T-707: the failed swap leaves the checkout at 2.8.0" 'yes' \
    "$(grep -qF '_q_version=2.8.0' "$RL/knotlog" && printf yes || printf no)"
  t; assert_eq "T-707: the rotation is undone: .knotlog-previous is 2.7.3 again" 'yes' \
    "$(grep -qF '_q_version=2.7.3' "$RL.knotlog-previous/knotlog" && printf yes || printf no)"
  t; assert_eq "T-707: the rotation is undone: no .knotlog-previous.2 is left" 'no' \
    "$([ -e "$RL.knotlog-previous.2" ] && printf yes || printf no)"
  t; assert_eq "T-707: the failed update leaves no staging directory behind" 'no' \
    "$([ -e "$RL.quipu-update-staging" ] && printf yes || printf no)"
else
  t; skip "T-707: failed first swap undoes the rotation" "no open-handle rename lock on this platform"
fi

# T-709/T-710: the checkout's OWN quipu runs `update --apply` (QUIPU_HOME
# unset in T-709, set to the checkout in T-710). Windows refuses to move a
# checkout while its running script is open; the update must run from a copy
# outside the checkout instead. The checkout ends at the new version, the old
# tree is the one-level backup, and no trampoline copy lands in the checkout
# or its backup. TMPDIR is pointed at a private dir so the copy is visible.
_q_t709() { # $1 = checkout, $2 = dir for the copy, $3 = QUIPU_HOME value or "-" (unset)
  if [ "$3" = - ]; then
    ( unset QUIPU_HOME; TMPDIR="$2" QUIPU_LANG=en QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
      QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
      sh "$1/knotlog" update --apply >/dev/null 2>"$2.err" )
  else
    ( QUIPU_HOME="$3" TMPDIR="$2" QUIPU_LANG=en QUIPU_RELEASE_API_URL="$FIXURL/release-newer.json" \
      QUIPU_UPDATE_TARBALL_URL="$UPDTARURL/update-new.tar.gz" \
      sh "$1/knotlog" update --apply >/dev/null 2>"$2.err" )
  fi
}
RK709="$TMP/t709/Quipu"
_q_seed_checkout "$RK709" 2.7.3
mkdir -p "$TMP/t709/tr1"
_q_t709 "$RK709" "$TMP/t709/tr1" -; RC709=$?
t; assert_eq "T-709: the checkout's own quipu runs --apply without QUIPU_HOME and exits 0" '0' "$RC709"
t; assert_eq "T-709: the checkout is now 2.8.0" 'yes' \
  "$(grep -qF '_q_version=2.8.0' "$RK709/knotlog" && printf yes || printf no)"
t; assert_eq "T-709: .knotlog-previous is the old 2.7.3 tree" 'yes' \
  "$(grep -qF '_q_version=2.7.3' "$RK709.knotlog-previous/knotlog" && printf yes || printf no)"
t; assert_eq "T-709: the update ran from a trampoline copy outside the checkout" 'yes' \
  "$([ -n "$(ls "$TMP/t709/tr1" 2>/dev/null)" ] && printf yes || printf no)"
t; assert_eq "T-709: no trampoline copy is left inside the checkout or its backup" '0' \
  "$(find "$RK709" "$RK709.knotlog-previous" -name 'quipu-update-*' 2>/dev/null | wc -l | tr -d ' ')"
t; assert_eq "T-709: no staging directory is left behind" 'no' \
  "$([ -e "$RK709.quipu-update-staging" ] && printf yes || printf no)"

RK710="$TMP/t710/Quipu"
_q_seed_checkout "$RK710" 2.7.3
mkdir -p "$TMP/t710/tr1"
_q_t709 "$RK710" "$TMP/t710/tr1" "$RK710"; RC710=$?
t; assert_eq "T-710: QUIPU_HOME equal to the checkout: --apply exits 0" '0' "$RC710"
t; assert_eq "T-710: the checkout is now 2.8.0 and .knotlog-previous is 2.7.3" 'yes' \
  "$(grep -qF '_q_version=2.8.0' "$RK710/knotlog" && grep -qF '_q_version=2.7.3' "$RK710.knotlog-previous/knotlog" \
     && printf yes || printf no)"

# ---- T-712: doctor path token matching with multibyte/emoji under UTF-8 locales
# GNU grep 3.0 fails on multibyte fixed-string matches under UTF-8 locales.
# knotlog doctor uses LC_ALL=C for the token lookup so emoji directories resolve.
mkenmem t712 tr
mkdir -p "$TMP/t712/sub/🗂️ Projeler"
cat > "$TMP/t712/Konular.md" <<'EOF'
referans: `🗂️ Projeler/`
EOF

t; (cd "$TMP/t712" && LC_ALL=C.UTF-8 LANG=C.UTF-8 "$ROOT/knotlog" doctor) >"$TMP/t712.out" 2>&1; RC=$?
assert_eq "T-712: bare emoji folder reference is recognized under LC_ALL=C.UTF-8 (exit 0)" '0' "$RC"
t; assert_eq "T-712: no broken path warning for existing bare emoji folder under LC_ALL=C.UTF-8" '0' \
  "$(awk -F"$TAB" -v n="$(mtr doc_paths)" '$2 == n { c++ } END { print c + 0 }' "$TMP/t712.out")"

t; (cd "$TMP/t712" && LC_ALL=C LANG=C "$ROOT/knotlog" doctor) >"$TMP/t712-c.out" 2>&1; RC_C=$?
assert_eq "T-712: bare emoji folder reference is recognized under LC_ALL=C (exit 0)" '0' "$RC_C"
t; assert_eq "T-712: no broken path warning for existing bare emoji folder under LC_ALL=C" '0' \
  "$(awk -F"$TAB" -v n="$(mtr doc_paths)" '$2 == n { c++ } END { print c + 0 }' "$TMP/t712-c.out")"

# ---- T-713..T-722: checkpoint signal (kayıt bekçisi) ----

D_TODAY=$(date +%Y-%m-%d)
NOW=$(date +%s)
OLD_NOTE=$((NOW - 7200))
OLD_INIT=$((NOW - 10800))

# Create base git vault once
mkdir -p "$TMP/tbase/.knotlog"
printf 'layout=plain\nlang=en\n' > "$TMP/tbase/.knotlog/config"
(cd "$TMP/tbase" && git init --quiet && git config user.name 'Test' && git config user.email 'test@test.com' && git config core.quotepath false)
mkdir -p "$TMP/tbase/700-Sessions"
echo 'session content' > "$TMP/tbase/700-Sessions/$D_TODAY.md"
echo 'tracked' > "$TMP/tbase/tracked.md"
(cd "$TMP/tbase" && git add -A && GIT_COMMITTER_DATE="@$OLD_INIT" GIT_AUTHOR_DATE="@$OLD_INIT" git commit -m "init" --quiet)

# (a) not taze -> sessiz
cp -r "$TMP/tbase" "$TMP/t713"
touch "$TMP/t713/700-Sessions/$D_TODAY.md"
t; OUT_713=$(QUIPU_VAULT="$TMP/t713" sh "$ROOT/knotlog" context --json UserPromptSubmit)
assert_eq "T-713 (a): fresh note -> UserPromptSubmit has no checkpoint due" 'no' \
  "$(printf '%s\n' "$OUT_713" | grep -q "ctx_checkpoint_due" && printf yes || printf no)"
t; OUT_713_STOP=$(printf '{}' | QUIPU_VAULT="$TMP/t713" sh "$ROOT/knotlog" context --json Stop)
assert_eq "T-713 (a): fresh note -> Stop outputs nothing" '' "$OUT_713_STOP"

# (b) not eski, iş yok -> sessiz
cp -r "$TMP/tbase" "$TMP/t714"
touch_at "$OLD_NOTE" "$TMP/t714/700-Sessions/$D_TODAY.md"
t; OUT_714=$(QUIPU_VAULT="$TMP/t714" sh "$ROOT/knotlog" context --json UserPromptSubmit)
assert_eq "T-714 (b): old note, no new work -> UserPromptSubmit silent" 'no' \
  "$(printf '%s\n' "$OUT_714" | grep -q "ctx_checkpoint_due" && printf yes || printf no)"
t; OUT_714_STOP=$(printf '{}' | QUIPU_VAULT="$TMP/t714" sh "$ROOT/knotlog" context --json Stop)
assert_eq "T-714 (b): old note, no new work -> Stop silent" '' "$OUT_714_STOP"

# (c) not eski + nottan yeni commit -> UserPromptSubmit metni var, Stop decision:block
cp -r "$TMP/tbase" "$TMP/t715"
touch_at "$OLD_NOTE" "$TMP/t715/700-Sessions/$D_TODAY.md"
echo 'new work' > "$TMP/t715/work.md"
(cd "$TMP/t715" && git add work.md && git commit -m "new work" --quiet)
t; OUT_715_NUDGE=$(QUIPU_VAULT="$TMP/t715" QUIPU_LANG=en sh "$ROOT/knotlog" context --json UserPromptSubmit)
CTX_715=$(printf '%s' "$OUT_715_NUDGE" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "T-715 (c): old note + newer commit -> UserPromptSubmit has checkpoint due" 'yes' \
  "$(printf '%s\n' "$CTX_715" | grep -qF "Checkpoint: session note was written" && printf yes || printf no)"
rm -f "$TMP/t715/.knotlog/checkpoint_nudged"
t; OUT_715_STOP=$(printf '{}' | QUIPU_VAULT="$TMP/t715" QUIPU_LANG=en sh "$ROOT/knotlog" context --json Stop)
assert_eq "T-715 (c): old note + newer commit -> Stop blocks" 'yes' \
  "$(printf '%s\n' "$OUT_715_STOP" | grep -qF '"decision":"block"' && printf yes || printf no)"

# (d) not eski + nottan yeni değişmiş izlenen dosya -> aynı
cp -r "$TMP/tbase" "$TMP/t716"
touch_at "$OLD_NOTE" "$TMP/t716/700-Sessions/$D_TODAY.md"
echo 'more tracked work' >> "$TMP/t716/tracked.md"
t; OUT_716_NUDGE=$(QUIPU_VAULT="$TMP/t716" QUIPU_LANG=en sh "$ROOT/knotlog" context --json UserPromptSubmit)
CTX_716=$(printf '%s' "$OUT_716_NUDGE" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "T-716 (d): old note + modified tracked file -> UserPromptSubmit has checkpoint due" 'yes' \
  "$(printf '%s\n' "$CTX_716" | grep -qF "Checkpoint: session note was written" && printf yes || printf no)"
rm -f "$TMP/t716/.knotlog/checkpoint_nudged"
t; OUT_716_STOP=$(printf '{}' | QUIPU_VAULT="$TMP/t716" QUIPU_LANG=en sh "$ROOT/knotlog" context --json Stop)
assert_eq "T-716 (d): old note + modified tracked file -> Stop blocks" 'yes' \
  "$(printf '%s\n' "$OUT_716_STOP" | grep -qF '"decision":"block"' && printf yes || printf no)"

# (e) hemen ikinci çağrı -> sessiz (checkpoint_nudged throttle)
t; OUT_716_REPEAT=$(QUIPU_VAULT="$TMP/t716" QUIPU_LANG=en sh "$ROOT/knotlog" context --json UserPromptSubmit)
CTX_716_REPEAT=$(printf '%s' "$OUT_716_REPEAT" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "T-717 (e): immediate second UserPromptSubmit -> suppressed by throttle" 'no' \
  "$(printf '%s\n' "$CTX_716_REPEAT" | grep -qF "Checkpoint: session note was written" && printf yes || printf no)"
t; OUT_716_STOP_REPEAT=$(printf '{}' | QUIPU_VAULT="$TMP/t716" QUIPU_LANG=en sh "$ROOT/knotlog" context --json Stop)
assert_eq "T-717 (e): immediate second Stop -> suppressed by throttle (silent)" '' "$OUT_716_STOP_REPEAT"

# (f) stop_hook_active:true -> sessiz
cp -r "$TMP/tbase" "$TMP/t718"
touch_at "$OLD_NOTE" "$TMP/t718/700-Sessions/$D_TODAY.md"
echo 'new work' > "$TMP/t718/work.md"
(cd "$TMP/t718" && git add work.md && git commit -m "new work" --quiet)
t; OUT_718_ACTIVE1=$(printf '{"stop_hook_active": true}' | QUIPU_VAULT="$TMP/t718" sh "$ROOT/knotlog" context --json Stop)
assert_eq "T-718 (f): stop_hook_active: true -> Stop outputs nothing" '' "$OUT_718_ACTIVE1"
t; OUT_718_ACTIVE2=$(printf '{"stop_hook_active":true}' | QUIPU_VAULT="$TMP/t718" sh "$ROOT/knotlog" context --json Stop)
assert_eq "T-718 (f): stop_hook_active:true (no space) -> Stop outputs nothing" '' "$OUT_718_ACTIVE2"

# (g) git deposu olmayan kasa -> sessiz, hata yok
mkdir -p "$TMP/t719/.knotlog"
printf 'layout=plain\nlang=en\n' > "$TMP/t719/.knotlog/config"
mkdir -p "$TMP/t719/700-Sessions"
echo 'session content' > "$TMP/t719/700-Sessions/$D_TODAY.md"
touch_at "$OLD_NOTE" "$TMP/t719/700-Sessions/$D_TODAY.md"
t; OUT_719=$(QUIPU_VAULT="$TMP/t719" sh "$ROOT/knotlog" context --json UserPromptSubmit); RC_719=$?
assert_eq "T-719 (g): non-git vault UserPromptSubmit exits 0" '0' "$RC_719"
t; assert_eq "T-719 (g): non-git vault UserPromptSubmit has no checkpoint due" 'no' \
  "$(printf '%s\n' "$OUT_719" | grep -q "ctx_checkpoint_due" && printf yes || printf no)"
t; OUT_719_STOP=$(printf '{}' | QUIPU_VAULT="$TMP/t719" sh "$ROOT/knotlog" context --json Stop); RC_719_STOP=$?
assert_eq "T-719 (g): non-git vault Stop exits 0" '0' "$RC_719_STOP"
t; assert_eq "T-719 (g): non-git vault Stop outputs nothing" '' "$OUT_719_STOP"

# (h) Stop çıktısı tek satır geçerli JSON
t; STOP_LINES=$(printf '%s\n' "$OUT_715_STOP" | wc -l | tr -d ' ')
assert_eq "T-720 (h): Stop output is exactly 1 line" '1' "$STOP_LINES"
t; STOP_DEC=$(printf '%s' "$OUT_715_STOP" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookdecision.awk" -)
assert_eq "T-720 (h): Stop json decision field is block" 'block' "$STOP_DEC"
t; STOP_REASON=$(printf '%s' "$OUT_715_STOP" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookreason.awk" -)
assert_eq "T-720 (h): Stop json reason field is non-empty" 'yes' \
  "$([ -n "$STOP_REASON" ] && printf yes || printf no)"

# (i) emoji'li oturum klasörü adıyla çalışır
mkdir -p "$TMP/t721/.knotlog"
printf 'layout=emoji\nlang=tr\n' > "$TMP/t721/.knotlog/config"
(cd "$TMP/t721" && git init --quiet && git config user.name 'Test' && git config user.email 'test@test.com' && git config core.quotepath false)
SESS_EMOJI=$(awk -F"$TAB" '$1=="sessions"{print $2;exit}' "$ROOT/layout/emoji.txt")
mkdir -p "$TMP/t721/$SESS_EMOJI"
echo 'session content' > "$TMP/t721/$SESS_EMOJI/$D_TODAY.md"
(cd "$TMP/t721" && git add -A && GIT_COMMITTER_DATE="@$OLD_INIT" GIT_AUTHOR_DATE="@$OLD_INIT" git commit -m "init" --quiet)
touch_at "$OLD_NOTE" "$TMP/t721/$SESS_EMOJI/$D_TODAY.md"
echo 'new work' > "$TMP/t721/$SESS_EMOJI/work.md"
(cd "$TMP/t721" && git add -A && git commit -m "work" --quiet)
t; OUT_721_STOP=$(printf '{}' | QUIPU_VAULT="$TMP/t721" QUIPU_LANG=tr sh "$ROOT/knotlog" context --json Stop)
assert_eq "T-721 (i): emoji sessions dir -> Stop blocks" 'yes' \
  "$(printf '%s\n' "$OUT_721_STOP" | grep -qF '"decision":"block"' && printf yes || printf no)"
t; STOP_721_REASON=$(printf '%s' "$OUT_721_STOP" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookreason.awk" -)
assert_eq "T-721 (i): emoji sessions dir -> reason is in Turkish" 'yes' \
  "$(printf '%s\n' "$STOP_721_REASON" | grep -qF "Ara kayıt:" && printf yes || printf no)"

# (j) mevcut C-19/C-20 nudge testleri dokunmadan çalışır
mkdir -p "$TMP/vnudge/.knotlog"
printf 'layout=plain\nlang=en\n' > "$TMP/vnudge/.knotlog/config"
for _n in 1 2 3; do
  printf '2026-08-20T10:0%s | PostToolUse | Read | nudge%s.md\n' "$_n" "$_n" >> "$TMP/vnudge/.knotlog/activity.log"
done
CPREC=$(awk -F= -v k=ctx_precompact '$1==k{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
CPREC_EXPECT=$(printf "$CPREC" '700-Sessions')
t; NJ=$(QUIPU_NUDGE_AFTER=2 QUIPU_VAULT="$TMP/vnudge" sh "$ROOT/knotlog" context --json UserPromptSubmit)
ND=$(printf '%s' "$NJ" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "T-722 (j): existing C-19/C-20 nudge still triggers ctx_precompact" 'yes' \
  "$(printf '%s\n' "$ND" | grep -F -q "$CPREC_EXPECT" && printf yes || printf no)"

# ---- Knotlog rename: state directory .knotlog/, pre-rename .quipu/ kept (T-724..T-730) ----
# A new vault gets .knotlog/. A vault made before the rename keeps working on
# its .quipu/ without being migrated: found by the walk-up, written to in
# place, never given a second state directory by init.

# T-724: a fresh init creates .knotlog/config and no .quipu/.
mkdir -p "$TMP/kn724"
t; QUIPU_VAULT="$TMP/kn724" QUIPU_LANG=en sh "$ROOT/knotlog" init >/dev/null 2>&1
assert_eq "T-724: fresh init creates .knotlog/config" 'yes' \
  "$([ -f "$TMP/kn724/.knotlog/config" ] && printf yes || printf no)"
t; assert_eq "T-724: fresh init creates no .quipu/" 'no' \
  "$([ -e "$TMP/kn724/.quipu" ] && printf yes || printf no)"

# T-725: a pre-rename vault (only .quipu/) is indexed in place.
mkdir -p "$TMP/kn725/.quipu" "$TMP/kn725/sub"
printf 'layout=plain\nlang=en\n' > "$TMP/kn725/.quipu/config"
printf '# Legacy note\n\nknotlegacy word\n' > "$TMP/kn725/legacy.md"
t; QUIPU_VAULT="$TMP/kn725" sh "$ROOT/knotlog" index >/dev/null 2>&1
assert_eq "T-725: legacy vault: index writes .quipu/index.tsv" 'yes' \
  "$(grep -qF 'legacy.md' "$TMP/kn725/.quipu/index.tsv" 2>/dev/null && printf yes || printf no)"
t; assert_eq "T-725: legacy vault: index creates no .knotlog/" 'no' \
  "$([ -e "$TMP/kn725/.knotlog" ] && printf yes || printf no)"

# T-726: the walk-up finds a pre-rename vault from a subdirectory.
t; OUT726=$(cd "$TMP/kn725/sub" && QUIPU_VAULT='' sh "$ROOT/knotlog" search knotlegacy --paths 2>&1)
assert_eq "T-726: walk-up from a subdirectory finds the .quipu/ vault" 'legacy.md' "$OUT726"

# T-727: init over a pre-rename vault reuses .quipu/.
t; QUIPU_VAULT="$TMP/kn725" QUIPU_LANG=en sh "$ROOT/knotlog" init >/dev/null 2>&1
assert_eq "T-727: init over a legacy vault creates no .knotlog/" 'no' \
  "$([ -e "$TMP/kn725/.knotlog" ] && printf yes || printf no)"
t; assert_eq "T-727: init over a legacy vault keeps its .quipu/config" 'yes' \
  "$(grep -qF 'layout=plain' "$TMP/kn725/.quipu/config" && printf yes || printf no)"

# T-728: context reads a pre-rename vault's activity log.
printf '2026-08-20T10:00 | PostToolUse | Read | legacy.md\n' >> "$TMP/kn725/.quipu/activity.log"
t; OUT728=$(QUIPU_VAULT="$TMP/kn725" QUIPU_LANG=en sh "$ROOT/knotlog" context 2>&1)
assert_eq "T-728: context reads the legacy activity log" 'yes' \
  "$(printf '%s\n' "$OUT728" | grep -qF 'legacy.md' && printf yes || printf no)"

# T-729: when both exist, .knotlog/ wins (a half-migrated vault).
mkdir -p "$TMP/kn729/.quipu" "$TMP/kn729/.knotlog"
printf 'layout=plain\nlang=en\n' > "$TMP/kn729/.quipu/config"
printf 'layout=plain\nlang=en\n' > "$TMP/kn729/.knotlog/config"
printf '# Both\n' > "$TMP/kn729/both.md"
t; QUIPU_VAULT="$TMP/kn729" sh "$ROOT/knotlog" index >/dev/null 2>&1
assert_eq "T-729: with both present, index writes .knotlog/" 'yes|no' \
  "$([ -f "$TMP/kn729/.knotlog/index.tsv" ] && printf yes || printf no)|$([ -f "$TMP/kn729/.quipu/index.tsv" ] && printf yes || printf no)"

# T-730: the secret gate reads lang= from a pre-rename .quipu/config.
mkdir -p "$TMP/kn730/.quipu"
printf 'lang=tr\n' > "$TMP/kn730/.quipu/config"
(cd "$TMP/kn730" && git init -q . && git config user.email t@t && git config user.name t)
printf 'k=AKIAIOSFODNN7EXAMPLE\n' > "$TMP/kn730/s.txt"
(cd "$TMP/kn730" && git add s.txt)
t; OUT730=$(cd "$TMP/kn730" && sh "$ROOT/hooks/pre-commit" 2>&1 || true)
assert_eq "T-730: secret gate speaks the legacy vault's language" 'yes' \
  "$(printf '%s\n' "$OUT730" | grep -qF 'sır kapanı' && printf yes || printf no)"

# ---- Knotlog rename: KNOTLOG_* settings, QUIPU_* still accepted (T-731..T-735) ----
# T-367 above keeps covering the pre-rename QUIPU_SKIP_SECRET_SCAN.

# T-731: KNOTLOG_VAULT selects the vault.
t; OUT731=$(cd "$TMP" && QUIPU_VAULT='' KNOTLOG_VAULT="$TMP/kn725" sh "$ROOT/knotlog" search knotlegacy --paths 2>&1)
assert_eq "T-731: KNOTLOG_VAULT selects the vault" 'legacy.md' "$OUT731"

# T-732: KNOTLOG_VAULT wins over QUIPU_VAULT.
t; OUT732=$(cd "$TMP" && QUIPU_VAULT="$TMP/kn724" KNOTLOG_VAULT="$TMP/kn725" sh "$ROOT/knotlog" search knotlegacy --paths 2>&1)
assert_eq "T-732: KNOTLOG_VAULT wins over QUIPU_VAULT" 'legacy.md' "$OUT732"

# T-733: KNOTLOG_LANG picks the message language.
mkdir -p "$TMP/kn733"
t; OUT733=$(cd "$TMP/kn733" && QUIPU_VAULT='' QUIPU_LANG='' KNOTLOG_LANG=tr sh "$ROOT/knotlog" search x 2>&1 || true)
assert_eq "T-733: KNOTLOG_LANG=tr gives the Turkish message" 'yes' \
  "$(printf '%s\n' "$OUT733" | grep -qF 'kasa bulunamadı' && printf yes || printf no)"

# T-734: KNOTLOG_CTX_MAX bounds context exactly as QUIPU_CTX_MAX does.
t; C734K=$(KNOTLOG_CTX_MAX=600 QUIPU_VAULT="$TMP/kn725" QUIPU_LANG=en sh "$ROOT/knotlog" context | sed '/^now: /d')
C734Q=$(QUIPU_CTX_MAX=600 QUIPU_VAULT="$TMP/kn725" QUIPU_LANG=en sh "$ROOT/knotlog" context | sed '/^now: /d')
C734D=$(QUIPU_VAULT="$TMP/kn725" QUIPU_LANG=en sh "$ROOT/knotlog" context | sed '/^now: /d')
if ! { [ "$C734K" = "$C734Q" ] && [ "${#C734K}" -lt "${#C734D}" ]; }; then
  printf '# T-734 diag: len K=%s Q=%s D=%s\n' "${#C734K}" "${#C734Q}" "${#C734D}"
  printf '%s\n' "$C734K" > "$TMP/c734k"; printf '%s\n' "$C734Q" > "$TMP/c734q"
  diff "$TMP/c734k" "$TMP/c734q" 2>&1 | sed -n '1,40p' | sed 's/^/# T-734 diff: /'
fi
assert_eq "T-734: KNOTLOG_CTX_MAX bounds context like QUIPU_CTX_MAX" 'yes' \
  "$([ "$C734K" = "$C734Q" ] && [ "${#C734K}" -lt "${#C734D}" ] && printf yes || printf no)"

# T-735: KNOTLOG_SKIP_SECRET_SCAN=1 lets a flagged commit through the gate.
t; (cd "$TMP/kn730" && KNOTLOG_SKIP_SECRET_SCAN=1 sh "$ROOT/hooks/pre-commit" >/dev/null 2>&1); RC735=$?
assert_eq "T-735: KNOTLOG_SKIP_SECRET_SCAN=1 skips the secret gate" '0' "$RC735"

# ---- Knotlog rename: the command is knotlog (T-742) ----

# T-742: uninstall removes a knotlog link that resolves into this checkout.
mkdir -p "$TMP/kn742/bin"
if make_true_symlink "$ROOT/knotlog" "$TMP/kn742/bin/knotlog" 2>/dev/null; then
  t; ( cd "$TMP/kn742" && PATH="$TMP/kn742/bin:/usr/bin:/bin" QUIPU_LANG=en \
    sh "$ROOT/knotlog" uninstall >/dev/null 2>&1 )
  assert_eq "T-742: uninstall removes the knotlog link" 'no' \
    "$([ -e "$TMP/kn742/bin/knotlog" ] || [ -L "$TMP/kn742/bin/knotlog" ] && printf yes || printf no)"
else
  t; skip "T-742: uninstall removes the knotlog link" "true symlinks unavailable (Windows without Developer Mode)"
fi

# ---- knotlog setup: one agent's hook file, never overwritten (T-743..T-751) ----

# T-743: setup claude into an empty vault writes the shipped file.
mkdir -p "$TMP/kn743/.knotlog"; : > "$TMP/kn743/.knotlog/config"
t; OUT743=$(cd "$TMP/kn743" && QUIPU_LANG=en sh "$ROOT/knotlog" setup claude 2>&1)
assert_eq "T-743: setup claude reports written" 'yes' \
  "$(printf '%s\n' "$OUT743" | grep -qF 'written to' && printf yes || printf no)"
assert_eq "T-743: the written settings.json is byte-identical to the shipped adapter" 'yes' \
  "$(cmp -s "$ROOT/adapters/claude-code.json" "$TMP/kn743/.claude/settings.json" && printf yes || printf no)"

# T-744: codex and omp land at their own paths in the same vault.
t; OUT744=$(cd "$TMP/kn743" && QUIPU_LANG=en sh "$ROOT/knotlog" setup codex 2>&1 && QUIPU_LANG=en sh "$ROOT/knotlog" setup omp 2>&1)
assert_eq "T-744: setup codex and omp both report written" '2' \
  "$(printf '%s\n' "$OUT744" | grep -c 'written to')"
assert_eq "T-744: codex hooks.json and omp knotlog.ts are byte-identical to their adapters" 'yes' \
  "$(cmp -s "$ROOT/adapters/codex/hooks.json" "$TMP/kn743/.codex/hooks.json" && cmp -s "$ROOT/adapters/omp/hooks/pre/knotlog.ts" "$TMP/kn743/.omp/hooks/pre/knotlog.ts" && printf yes || printf no)"

# T-745: a second run on an identical file touches nothing and says so.
t; OUT745=$(cd "$TMP/kn743" && QUIPU_LANG=en sh "$ROOT/knotlog" setup claude 2>&1)
assert_eq "T-745: second run reports already up to date" 'yes' \
  "$(printf '%s\n' "$OUT745" | grep -qF 'already up to date' && printf yes || printf no)"

# T-746: a differing file is preserved byte for byte; the source path is printed.
mkdir -p "$TMP/kn746/.knotlog" "$TMP/kn746/.codex"; : > "$TMP/kn746/.knotlog/config"
printf '%s\n' 'user hooks, not ours' > "$TMP/kn746/.codex/hooks.json"
cp "$TMP/kn746/.codex/hooks.json" "$TMP/kn746-before.json"
t; OUT746=$(cd "$TMP/kn746" && QUIPU_LANG=en sh "$ROOT/knotlog" setup codex 2>&1)
assert_eq "T-746: differing codex hooks.json reports preserved" 'yes' \
  "$(printf '%s\n' "$OUT746" | grep -qF 'preserved' && printf yes || printf no)"
assert_eq "T-746: the preserved file is unchanged" 'yes' \
  "$(cmp -s "$TMP/kn746-before.json" "$TMP/kn746/.codex/hooks.json" && printf yes || printf no)"
assert_eq "T-746: the output names the shipped source to merge from" 'yes' \
  "$(printf '%s\n' "$OUT746" | grep -qF 'adapters/codex/hooks.json' && printf yes || printf no)"

# T-747: --dry-run prints the decision and writes nothing.
mkdir -p "$TMP/kn747/.knotlog"; : > "$TMP/kn747/.knotlog/config"
t; OUT747=$(cd "$TMP/kn747" && QUIPU_LANG=en sh "$ROOT/knotlog" setup claude --dry-run 2>&1)
assert_eq "T-747: dry run prints the written decision" 'yes' \
  "$(printf '%s\n' "$OUT747" | grep -qF 'written to' && printf yes || printf no)"
assert_eq "T-747: dry run creates no .claude directory or file" 'no' \
  "$([ -e "$TMP/kn747/.claude" ] || [ -L "$TMP/kn747/.claude" ] && printf yes || printf no)"

# T-748: an unknown agent lists the supported set and exits 2.
t; OUT748=$(cd "$TMP/kn743" && QUIPU_LANG=en sh "$ROOT/knotlog" setup foo 2>&1); RC748=$?
assert_eq "T-748: unknown agent exits 2" '2' "$RC748"
assert_eq "T-748: unknown agent message lists the supported agents" 'yes' \
  "$(printf '%s\n' "$OUT748" | grep -qF 'claude, codex, omp, gemini, cursor' && printf yes || printf no)"

# T-749: setup gemini writes .gemini/settings.json byte-identical to the shipped adapter.
mkdir -p "$TMP/kn749/.knotlog"; : > "$TMP/kn749/.knotlog/config"
t; OUT749=$(cd "$TMP/kn749" && QUIPU_LANG=en sh "$ROOT/knotlog" setup gemini 2>&1)
assert_eq "T-749: setup gemini reports written" 'yes' \
  "$(printf '%s\n' "$OUT749" | grep -qF 'written to' && printf yes || printf no)"
assert_eq "T-749: the written .gemini/settings.json is byte-identical to the adapter" 'yes' \
  "$(cmp -s "$ROOT/adapters/gemini/settings.json" "$TMP/kn749/.gemini/settings.json" && printf yes || printf no)"

# T-750: second run on the identical file reports up to date; the adapter has balanced braces
# and the Gemini event keys (kaba JSON kontrolü, jq yok).
t; OUT750=$(cd "$TMP/kn749" && QUIPU_LANG=en sh "$ROOT/knotlog" setup gemini 2>&1)
assert_eq "T-750: second gemini run reports already up to date" 'yes' \
  "$(printf '%s\n' "$OUT750" | grep -qF 'already up to date' && printf yes || printf no)"
assert_eq "T-750: gemini adapter has balanced braces and BeforeAgent/AfterTool keys" 'yes' \
  "$(o=$(tr -cd '{' < "$ROOT/adapters/gemini/settings.json" | wc -c); c=$(tr -cd '}' < "$ROOT/adapters/gemini/settings.json" | wc -c); [ "$o" -eq "$c" ] && grep -qF '"BeforeAgent"' "$ROOT/adapters/gemini/settings.json" && grep -qF '"AfterTool"' "$ROOT/adapters/gemini/settings.json" && printf yes || printf no)"

# T-751: BeforeAgent (Gemini) runs the checkpoint reminder like UserPromptSubmit does.
cp -r "$TMP/tbase" "$TMP/t751"
touch_at "$OLD_NOTE" "$TMP/t751/700-Sessions/$D_TODAY.md"
echo 'gemini work' > "$TMP/t751/work.md"
(cd "$TMP/t751" && git add work.md && git commit -m "gemini work" --quiet)
t; OUT_751=$(QUIPU_VAULT="$TMP/t751" QUIPU_LANG=en sh "$ROOT/knotlog" context --json BeforeAgent)
CTX_751=$(printf '%s' "$OUT_751" | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
assert_eq "T-751 (a): BeforeAgent with checkpoint due -> reminder in additionalContext" 'yes' \
  "$(printf '%s\n' "$CTX_751" | grep -qF "Checkpoint: session note was written" && printf yes || printf no)"
assert_eq "T-751 (b): BeforeAgent output keeps hookEventName BeforeAgent" 'yes' \
  "$(printf '%s\n' "$OUT_751" | grep -qF '"hookEventName":"BeforeAgent"' && printf yes || printf no)"

# ---- knotlog context --cursor (T-752) ----
# T-752 (a): --cursor emits the Cursor shape (additional_context), never hookSpecificOutput.
# T-752 (b): without --cursor the Claude envelope is unchanged.
# T-752 (c): a Cursor afterFileEdit payload (top-level file_path, no tool_name) logs one row.
mkdir -p "$TMP/kn752/.knotlog"; : > "$TMP/kn752/.knotlog/config"
printf '%s\n' '{"hook_event_name":"afterFileEdit","file_path":"/proj/a.md","edits":[]}' | QUIPU_VAULT="$TMP/kn752" sh "$ROOT/knotlog" capture
assert_eq "T-752 (c): cursor afterFileEdit logs top-level file_path as Write" 'afterFileEdit | Write | /proj/a.md' "$(log_line "$TMP/kn752")"

# T-752 (d): setup cursor writes .cursor/hooks.json byte-identical to the adapter.
# T-752 (e): the adapter has balanced braces and the sessionStart/afterFileEdit keys.
mkdir -p "$TMP/kn752s/.knotlog"; : > "$TMP/kn752s/.knotlog/config"
t; OUT752D=$(cd "$TMP/kn752s" && QUIPU_LANG=en sh "$ROOT/knotlog" setup cursor 2>&1)
assert_eq "T-752 (d): setup cursor reports written" 'yes' \
  "$(printf '%s\n' "$OUT752D" | grep -qF 'written to' && printf yes || printf no)"
assert_eq "T-752 (d): the written .cursor/hooks.json is byte-identical to the adapter" 'yes' \
  "$(cmp -s "$ROOT/adapters/cursor/hooks.json" "$TMP/kn752s/.cursor/hooks.json" && printf yes || printf no)"
assert_eq "T-752 (e): cursor adapter has balanced braces and sessionStart/afterFileEdit keys" 'yes' \
  "$(o=$(tr -cd '{' < "$ROOT/adapters/cursor/hooks.json" | wc -c); c=$(tr -cd '}' < "$ROOT/adapters/cursor/hooks.json" | wc -c); [ "$o" -eq "$c" ] && grep -qF '"sessionStart"' "$ROOT/adapters/cursor/hooks.json" && grep -qF '"afterFileEdit"' "$ROOT/adapters/cursor/hooks.json" && printf yes || printf no)"
t; OUT752A=$(QUIPU_VAULT="$TMP/kn752" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart --cursor)
assert_eq "T-752 (a): cursor context carries additional_context" 'yes' \
  "$(printf '%s\n' "$OUT752A" | grep -qF '"additional_context":' && printf yes || printf no)"
assert_eq "T-752 (a): cursor context has no hookSpecificOutput" 'no' \
  "$(printf '%s\n' "$OUT752A" | grep -qF 'hookSpecificOutput' && printf yes || printf no)"
t; OUT752B=$(QUIPU_VAULT="$TMP/kn752" QUIPU_LANG=en sh "$ROOT/knotlog" context --json SessionStart)
assert_eq "T-752 (b): without --cursor the Claude hookSpecificOutput is unchanged" 'yes' \
  "$(printf '%s\n' "$OUT752B" | grep -qF '"hookSpecificOutput"' && printf yes || printf no)"

# ---- T-790..T-793: doctor warns when PATH's bash is WSL (Windows only) ------
# A stub bash under a System32 dir, first on PATH, must draw the warning; Git's
# bash first must stay silent. Windows-only rows skip elsewhere (uname gate);
# the exit-code check runs everywhere. Stubs live in their own fake tree.
WSLD="$TMP/wsl"
rm -rf "$WSLD"
mkdir -p "$WSLD/Windows/System32" "$WSLD/WINDOWS/SYSTEM32" "$WSLD/git/bin"
for _w in "$WSLD/Windows/System32/bash.exe" "$WSLD/WINDOWS/SYSTEM32/bash.exe" "$WSLD/git/bin/bash.exe"; do
  printf '#!/bin/sh\nexit 0\n' > "$_w"
  :
done
case $(uname -s) in
  MINGW* | MSYS* | CYGWIN*)
    t; (cd "$TMP" && QUIPU_LANG=en PATH="$WSLD/Windows/System32:$PATH" "$ROOT/knotlog" doctor) >"$WSLD/sys.out" 2>&1
    assert_eq "T-790: System32 bash first on PATH -> doctor warns (Git Bash hint)" 'yes' \
      "$(grep -qF 'Git Bash' "$WSLD/sys.out" && printf yes || printf no)"
    t; (cd "$TMP" && QUIPU_LANG=en PATH="$WSLD/git/bin:$PATH" "$ROOT/knotlog" doctor) >"$WSLD/git.out" 2>&1
    assert_eq "T-791: Git bash first on PATH -> doctor silent" 'no' \
      "$(grep -qF 'Git Bash' "$WSLD/git.out" && printf yes || printf no)"
    t; (cd "$TMP" && QUIPU_LANG=en PATH="$WSLD/WINDOWS/SYSTEM32:$PATH" "$ROOT/knotlog" doctor) >"$WSLD/up.out" 2>&1
    assert_eq "T-792: SYSTEM32 in upper case still warns" 'yes' \
      "$(grep -qF 'Git Bash' "$WSLD/up.out" && printf yes || printf no)"
    ;;
  *)
    t; skip "T-790: System32 bash first on PATH -> doctor warns" "Windows only"
    t; skip "T-791: Git bash first on PATH -> doctor silent" "Windows only"
    t; skip "T-792: SYSTEM32 in upper case still warns" "Windows only"
    ;;
esac
t; (cd "$TMP" && PATH="$WSLD/Windows/System32:$PATH" "$ROOT/knotlog" doctor) >/dev/null 2>&1; RC=$?
assert_eq "T-793: doctor exits 0 with System32 bash first on PATH" '0' "$RC"
# ---- index_exclude= in .knotlog/config (T-780, T-781) ----
# T-780 (a): without the key every .md is indexed, nested folders included (default unchanged).
# T-780 (b): index_exclude=Gomulu drops that folder name at any depth; other folders stay.
# T-781: glob (Gom*) and slash (deep/x) tokens are ignored, so Gomx/e.md stays indexed.
mkdir -p "$TMP/ix780/.knotlog" "$TMP/ix780/Gomulu" "$TMP/ix780/deep/Gomulu" "$TMP/ix780/Diger" "$TMP/ix780/Gomx"
: > "$TMP/ix780/.knotlog/config"
for f in a.md Gomulu/b.md deep/Gomulu/c.md Diger/d.md Gomx/e.md; do printf 'x\n' > "$TMP/ix780/$f"; touch_at 1000000000 "$TMP/ix780/$f"; done
t; QUIPU_VAULT="$TMP/ix780" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1
IX780A=$(awk -F'\t' '{print $1}' "$TMP/ix780/.knotlog/index.tsv" | sort | tr '\n' ' ')
assert_eq "T-780 (a): without index_exclude all five notes are indexed" 'yes' \
  "$(for p in a.md Gomulu/b.md deep/Gomulu/c.md Diger/d.md Gomx/e.md; do printf '%s' "$IX780A" | grep -qF "$p " || { printf no; exit 0; }; done; printf yes)"
printf 'index_exclude=Gomulu  Gom* deep/x\n' > "$TMP/ix780/.knotlog/config"
rm -f "$TMP/ix780/.knotlog/index.tsv" "$TMP/ix780/.knotlog/index.schema"
t; QUIPU_VAULT="$TMP/ix780" QUIPU_LANG=en sh "$ROOT/knotlog" index >/dev/null 2>&1
IX780=$(awk -F'\t' '{print $1}' "$TMP/ix780/.knotlog/index.tsv" | sort | tr '\n' ' ')
assert_eq "T-780 (b): Gomulu is dropped at any depth; Diger and a.md stay" 'yes' \
  "$(printf '%s' "$IX780" | grep -qF 'Diger/d.md' && printf '%s' "$IX780" | grep -qF 'a.md ' && ! printf '%s' "$IX780" | grep -qF 'Gomulu/' && printf yes || printf no)"
assert_eq "T-781: glob and slash tokens are ignored, Gomx/e.md stays indexed" 'yes' \
  "$(printf '%s' "$IX780" | grep -qF 'Gomx/e.md' && printf yes || printf no)"

# ---- index.version stamp (T-785..T-789) ----
# T-785: a successful index writes .knotlog/index.version = the Knotlog version; index.schema is "3".
# T-786: same version -> incremental; a sentinel title in an unchanged row survives.
# T-787: a different stamp -> one full rebuild without --full; the sentinel is gone and the stamp is rewritten.
# T-788: no stamp file (an index from before the stamp) -> the same one-time rebuild.
mkdir -p "$TMP/ix785/.knotlog"
: > "$TMP/ix785/.knotlog/config"
printf '# Alfa\n\nx\n' > "$TMP/ix785/a.md"; printf '# Beta\n\ny\n' > "$TMP/ix785/b.md"
touch_at 1000000000 "$TMP/ix785/a.md" "$TMP/ix785/b.md"
IX785_VER=$(sh "$ROOT/knotlog" --version | awk '{print $2}')
ix785_run() { QUIPU_VAULT="$TMP/ix785" QUIPU_LANG=en sh "$ROOT/knotlog" index </dev/null >/dev/null 2>&1; }
ix785_tamper() { awk -F'\t' -v OFS='\t' '$1=="a.md"{$2="SENTINEL"}1' "$TMP/ix785/.knotlog/index.tsv" > "$TMP/ix785/t.tmp" && mv "$TMP/ix785/t.tmp" "$TMP/ix785/.knotlog/index.tsv"; }
ix785_title() { awk -F'\t' '$1=="a.md"{print $2}' "$TMP/ix785/.knotlog/index.tsv"; }
t; ix785_run
assert_eq "T-785: index.version holds the Knotlog version and index.schema is 3" "$IX785_VER 3" \
  "$(printf '%s %s' "$(cat "$TMP/ix785/.knotlog/index.version")" "$(cat "$TMP/ix785/.knotlog/index.schema")")"
t; ix785_tamper; ix785_run
assert_eq "T-786: same version runs incrementally (sentinel survives)" 'SENTINEL' "$(ix785_title)"
printf '0.0.0\n' > "$TMP/ix785/.knotlog/index.version"
t; ix785_tamper; ix785_run
assert_eq "T-787: a different stamp rebuilds in full without --full (title restored)" 'Alfa' "$(ix785_title)"
assert_eq "T-787: the stamp is rewritten to the current version" "$IX785_VER" "$(cat "$TMP/ix785/.knotlog/index.version")"
rm -f "$TMP/ix785/.knotlog/index.version"
t; ix785_tamper; ix785_run
assert_eq "T-788: a missing stamp rebuilds once (title restored, stamp written)" "Alfa $IX785_VER" \
  "$(printf '%s %s' "$(ix785_title)" "$(cat "$TMP/ix785/.knotlog/index.version")")"
# ---- knotlog digest --since/--until (T-760..T-769) ----
# Own vault, own fixtures: activity on 08-26 and 08-27 only; session notes on 08-25..08-28.
DR_VAULT="$TMP/dr-vault"
mkdir -p "$DR_VAULT/.knotlog" "$DR_VAULT/700-Sessions"
printf '%s\n' 'layout=plain' > "$DR_VAULT/.knotlog/config"
printf '%s\n' \
  '2026-08-27T10:00 | PostToolUse | Edit | today-a.md' \
  '2026-08-27T10:01 | PostToolUse | Read | today-b.md' \
  '2026-08-26T10:00 | PostToolUse | Edit | yesterday.md' \
  > "$DR_VAULT/.knotlog/activity.log"
for _drd in 2026-08-25 2026-08-26 2026-08-27 2026-08-28; do : > "$DR_VAULT/700-Sessions/$_drd.md"; done

# T-760 (a): a range prints each day with a session note, in date order.
# T-761 (b): days outside the range (08-25, 08-28) are not printed.
t; OUT760=$(QUIPU_VAULT="$DR_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest --since 2026-08-26 --until 2026-08-27 --dry-run 2>&1)
assert_eq "T-760 (a): range prints both days in date order" 'Activity digest: 2026-08-26
Activity digest: 2026-08-27' \
  "$(printf '%s\n' "$OUT760" | grep -F 'Activity digest: ')"
t; assert_eq "T-761 (b): range excludes days outside the window" 'yes' \
  "$(printf '%s\n' "$OUT760" | grep -qE '2026-08-25|2026-08-28' && printf no || printf yes)"

# T-762 (c): --date with --since is a usage error (exit 2).
# T-763 (d): a malformed --since date is a usage error (exit 2).
# T-764 (e): a malformed --until date is a usage error (exit 2).
t; QUIPU_VAULT="$DR_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest --date 2026-08-27 --since 2026-08-26 >/dev/null 2>&1; RC762=$?
assert_eq "T-762 (c): --date combined with --since exits 2" '2' "$RC762"
t; QUIPU_VAULT="$DR_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest --since 2026-8-1 >/dev/null 2>&1; RC763=$?
assert_eq "T-763 (d): malformed --since exits 2" '2' "$RC763"
t; QUIPU_VAULT="$DR_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest --since 2026-08-01 --until 2026-8-31 >/dev/null 2>&1; RC764=$?
assert_eq "T-764 (e): malformed --until exits 2" '2' "$RC764"

# T-765 (f): without --until the range runs to today; 08-26 is excluded by --since.
t; OUT765=$(QUIPU_VAULT="$DR_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest --since 2026-08-27 --dry-run 2>&1)
assert_eq "T-765 (f): --since alone runs to today" 'yes' \
  "$(printf '%s\n' "$OUT765" | grep -qF 'Activity digest: 2026-08-27' && ! printf '%s\n' "$OUT765" | grep -qF 'Activity digest: 2026-08-26' && printf yes || printf no)"

# T-766 (g): --date output is unchanged by the range work (exact day body).
t; OUT766=$(QUIPU_VAULT="$DR_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest --date 2026-08-27 --dry-run 2>&1)
assert_eq "T-766 (g): --date body is byte-identical to the single-day format" '---
Activity digest: 2026-08-27
type: digest
status: generated
---

Range: 2026-08-27T10:00 → 2026-08-27T10:01 (2 events)
Tools: Edit 1, Read 1
Touched files (top 10):
- today-a.md (1)
- today-b.md (1)' "$OUT766"

# T-767 (h): a window with no session notes prints the none-found line and exits 0.
t; OUT767=$(QUIPU_VAULT="$DR_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest --since 2026-09-01 --until 2026-09-05 2>&1); RC767=$?
assert_eq "T-767 (h): empty window names the range and exits 0" 'no session notes between 2026-09-01 and 2026-09-05' "$OUT767"
assert_eq "T-767 (h): empty window exit code" '0' "$RC767"

# T-768 (i): --until without --since is a usage error (exit 2).
t; QUIPU_VAULT="$DR_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest --until 2026-08-27 >/dev/null 2>&1; RC768=$?
assert_eq "T-768 (i): --until alone exits 2" '2' "$RC768"

# T-769 (j): range mode never writes a digest file into the dump folder.
t; QUIPU_VAULT="$DR_VAULT" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" digest --since 2026-08-26 --until 2026-08-27 >/dev/null 2>&1
assert_eq "T-769 (j): range writes no digest files" 'yes' \
  "$(ls "$DR_VAULT"/000-Inbox/Dump/*-digest.md >/dev/null 2>&1 && printf no || printf yes)"

# T-770..T-779 (note --thread): one list line lands at the END of the active
# section of the threads block; the pin block, the closed section and a plain
# `note` never change. Each case builds its own fixture under $TMP/kn77*.
# Every call's exit status is asserted; the bytes it leaves behind are checked
# as well. No external timeout wrapper is used (it is not portable).
TH="$TMP/kn770"
mkdir -p "$TH/.knotlog" && : > "$TH/.knotlog/config"
printf '%s\n' '# Threads' '<!-- quipu:pin:start -->' '### Pinned' '- pin A' \
  '<!-- quipu:pin:end -->' '<!-- quipu:threads:start -->' '### Active threads' \
  '- eski konu 1' '' '- eski konu 2' '### Closed threads' '- kapanan' \
  '<!-- quipu:threads:end -->' > "$TH/Threads.md"
cp "$TH/Threads.md" "$TH/before.md"
QUIPU_LANG=en QUIPU_VAULT="$TH" sh "$ROOT/knotlog" note --thread "B-K3 bitti \ % & \$HOME" </dev/null >"$TH/o770" 2>&1; RC770=$?
t; assert_eq "T-770: note --thread exits 0" '0' "$RC770"
N770=$(awk '/Active threads/{a=1} /Closed threads/{exit} a' "$TH/Threads.md" | tail -n 1)
t; assert_eq "T-770: note --thread puts the text on the last line of the active section" 'yes' \
  "$(printf '%s\n' "$N770" | grep -qF 'B-K3 bitti \ % & $HOME' && printf yes || printf no)"
t; assert_eq "T-770: the diff is exactly one added line, nothing removed" 'yes' \
  "$([ "$(diff "$TH/before.md" "$TH/Threads.md" | grep -c '^<')" -eq 0 ] && [ "$(diff "$TH/before.md" "$TH/Threads.md" | grep -c '^>')" -eq 1 ] && printf yes || printf no)"
PINA=$(awk '/quipu:pin:start/{p=1} p{print} /quipu:pin:end/{if(p) exit}' "$TH/before.md")
PINB=$(awk '/quipu:pin:start/{p=1} p{print} /quipu:pin:end/{if(p) exit}' "$TH/Threads.md")
t; assert_eq "T-771: pin block is byte-identical after note --thread" 'yes' \
  "$([ "$PINA" = "$PINB" ] && [ -n "$PINA" ] && printf yes || printf no)"
cp "$TH/Threads.md" "$TH/mid.md"
QUIPU_LANG=en QUIPU_VAULT="$TH" sh "$ROOT/knotlog" note "plain bare note" </dev/null >/dev/null 2>&1; RC772=$?
t; assert_eq "T-772: bare note exits 0" '0' "$RC772"
t; assert_eq "T-772: bare note leaves Threads.md byte-identical and writes the session file" 'yes' \
  "$(cmp -s "$TH/mid.md" "$TH/Threads.md" && grep -rqF 'plain bare note' "$TH" && printf yes || printf no)"
TN="$TMP/kn773"; mkdir -p "$TN/.knotlog" && : > "$TN/.knotlog/config"
QUIPU_LANG=en QUIPU_VAULT="$TN" sh "$ROOT/knotlog" note --thread "x" </dev/null >/dev/null 2>&1; RC773=$?
t; assert_eq "T-773: missing threads file exits 1 and creates nothing" 'yes' \
  "$([ "$RC773" -eq 1 ] && [ ! -e "$TN/Threads.md" ] && printf yes || printf no)"
TS="$TMP/kn774"; mkdir -p "$TS/.knotlog" && : > "$TS/.knotlog/config"
printf '%s\n' '# Threads' '<!-- quipu:threads:start -->' '### Closed threads' '- x' '<!-- quipu:threads:end -->' > "$TS/Threads.md"
cp "$TS/Threads.md" "$TS/before.md"
QUIPU_LANG=en QUIPU_VAULT="$TS" sh "$ROOT/knotlog" note --thread "x" </dev/null >/dev/null 2>&1; RC774=$?
t; assert_eq "T-774: no active section exits 1 and leaves the file byte-identical" 'yes' \
  "$([ "$RC774" -eq 1 ] && cmp -s "$TS/before.md" "$TS/Threads.md" && printf yes || printf no)"
TC="$TMP/kn775"; mkdir -p "$TC/.knotlog" && : > "$TC/.knotlog/config"
printf '%s\r\n' '# Threads' '<!-- quipu:threads:start -->' '### Active threads' '- a' '### Closed threads' '<!-- quipu:threads:end -->' > "$TC/Threads.md"
QUIPU_LANG=en QUIPU_VAULT="$TC" sh "$ROOT/knotlog" note --thread "crlf" </dev/null >/dev/null 2>&1; RC775=$?
t; assert_eq "T-775: note --thread exits 0 on a CRLF file" '0' "$RC775"
t; assert_eq "T-775: the inserted line keeps the file's CRLF ending" 'yes' \
  "$(N775=$(grep -n 'crlf' "$TC/Threads.md" | cut -d: -f1); [ "$(head -n "$N775" "$TC/Threads.md" | tail -n 1 | tr -d '\n' | tail -c 1 | od -An -c | tr -d ' ')" = '\r' ] && printf yes || printf no)"
TA="$TMP/kn776"; mkdir -p "$TA/.knotlog" && : > "$TA/.knotlog/config" && cp "$TH/before.md" "$TA/Threads.md"
QUIPU_LANG=en QUIPU_VAULT="$TA" sh "$ROOT/knotlog" note --thread "first" </dev/null >/dev/null 2>&1; RC776A=$?
QUIPU_LANG=en QUIPU_VAULT="$TA" sh "$ROOT/knotlog" note --thread "second" </dev/null >/dev/null 2>&1; RC776B=$?
t; assert_eq "T-776: both calls exit 0" '00' "$RC776A$RC776B"
t; assert_eq "T-776: two calls append two lines in order and never overwrite" 'yes' \
  "$(awk '/first/{f=NR} /second/{s=NR} END{exit !(f && s && f < s)}' "$TA/Threads.md" && grep -qF 'eski konu 1' "$TA/Threads.md" && printf yes || printf no)"
TT="$TMP/kn777"; mkdir -p "$TT/.knotlog" && : > "$TT/.knotlog/config"
printf '%s\n' '# Konular' '<!-- quipu:threads:start -->' '### Aktif konular' '- a' '### Kapanmış konular' '<!-- quipu:threads:end -->' > "$TT/Konular.md"
QUIPU_LANG=tr QUIPU_VAULT="$TT" sh "$ROOT/knotlog" note --thread "Türkçe satır" </dev/null >/dev/null 2>&1; RC777=$?
t; assert_eq "T-777: Turkish vault note --thread exits 0" '0' "$RC777"
t; assert_eq "T-777: Turkish vault writes into Konular.md under Aktif konular" 'yes' \
  "$(awk '/Aktif konular/{a=1} /Kapanm/{exit} a' "$TT/Konular.md" | tail -n 1 | grep -qF 'Türkçe satır' && printf yes || printf no)"
QUIPU_LANG=en QUIPU_VAULT="$TH" sh "$ROOT/knotlog" note --thread </dev/null >/dev/null 2>&1; RC778A=$?
QUIPU_LANG=en QUIPU_VAULT="$TH" sh "$ROOT/knotlog" note --thread "a" "b" </dev/null >/dev/null 2>&1; RC778B=$?
t; assert_eq "T-778: note --thread without text, or with two texts, exits 2" 'yes' \
  "$([ "$RC778A" -eq 2 ] && [ "$RC778B" -eq 2 ] && printf yes || printf no)"
t; assert_eq "T-779: the threads fixture still has its pin block after all note --thread calls" 'yes' \
  "$(grep -qF '<!-- quipu:pin:end -->' "$TH/Threads.md" && grep -qF -- '- pin A' "$TH/Threads.md" && printf yes || printf no)"

# ---- T-800..T-805: step 2.1, visible names (vault folder, omp hook, uninstall, notice) ----
# Everything the product WRITES for the user says Knotlog: the vault folder
# <user>'s Knotlog, .omp/hooks/pre/knotlog.ts, .icon/knotlog.png + Knotlog.ico.
# uninstall still recognises what a pre-rename install left behind: the old
# %LOCALAPPDATA%\Quipu\bin shims (uninstall.ps1) and the old omp hook and icons
# inside a vault. $TMP/kn80* are this block's own fixtures.
KN800_HOME="$TMP/kn800-home"
KN800_PARENT="$TMP/kn800-parent"
mkdir -p "$KN800_HOME" "$KN800_PARENT"
PATH="$INSTALL_TOOLS" QUIPU_HOME="$ROOT" HOME="$KN800_HOME" \
  sh "$ROOT/knotlog" install --no-link "$KN800_PARENT" --no-prompt --no-git \
  --user "Vis" --lang en >"$TMP/kn800.out" 2>"$TMP/kn800.err"; RC800=$?
t; assert_eq "T-800: install exits 0 and creates exactly <user>'s Knotlog, no <user>'s Quipu" 'yes' \
  "$([ "$RC800" -eq 0 ] && [ -f "$KN800_PARENT/Vis's Knotlog/.knotlog/config" ] \
     && [ ! -e "$KN800_PARENT/Vis's Quipu" ] && printf yes || printf no)"
t; assert_eq "T-801: install writes .omp/hooks/pre/knotlog.ts (byte-identical) and no quipu.ts" 'yes' \
  "$(cmp -s "$ROOT/adapters/omp/hooks/pre/knotlog.ts" "$KN800_PARENT/Vis's Knotlog/.omp/hooks/pre/knotlog.ts" \
     && [ ! -e "$KN800_PARENT/Vis's Knotlog/.omp/hooks/pre/quipu.ts" ] \
     && [ ! -e "$ROOT/adapters/omp/hooks/pre/quipu.ts" ] && printf yes || printf no)"
t; assert_eq "T-802: install writes .icon/knotlog.png + .icon/Knotlog.ico and .directory points at knotlog.png" 'yes' \
  "$(cmp -s "$ROOT/icon/Knotlog.png" "$KN800_PARENT/Vis's Knotlog/.icon/knotlog.png" \
     && cmp -s "$ROOT/icon/Knotlog.ico" "$KN800_PARENT/Vis's Knotlog/.icon/Knotlog.ico" \
     && [ ! -e "$ROOT/icon/Quipu.png" ] && [ ! -e "$ROOT/icon/Quipu.ico" ] \
     && grep -q '^Icon=.*/\.icon/knotlog\.png$' "$KN800_PARENT/Vis's Knotlog/.directory" && printf yes || printf no)"

# T-803: uninstall (POSIX) still lists the pre-rename omp hook and icons a
# vault holds, by directory (.omp, .icon), and points at the Windows remover
# for both the new and the old %LOCALAPPDATA% folder.
KN803_V="$TMP/kn803/old's Quipu"
mkdir -p "$KN803_V/.knotlog" "$KN803_V/.omp/hooks/pre" "$KN803_V/.icon"
: > "$KN803_V/.knotlog/config"
: > "$KN803_V/.omp/hooks/pre/quipu.ts"; : > "$KN803_V/.icon/Quipu.ico"
KN803_OUT=$(cd "$KN803_V" && HOME="$TMP/kn803" LOCALAPPDATA="$TMP/kn803/la" QUIPU_VAULT="$KN803_V" QUIPU_HOME="$ROOT" QUIPU_LANG=en \
  sh "$ROOT/knotlog" uninstall --dry-run 2>&1)
t; assert_eq "T-803: uninstall reports an old vault's .omp and .icon and names both Windows folders" 'yes' \
  "$(printf '%s\n' "$KN803_OUT" | grep -q '\.omp' && printf '%s\n' "$KN803_OUT" | grep -q '\.icon' \
     && printf '%s\n' "$KN803_OUT" | grep -qF 'Knotlog\bin' && printf '%s\n' "$KN803_OUT" | grep -qF 'Quipu\bin' \
     && printf yes || printf no)"

# T-804: uninstall.ps1 lists both bin folders in its source, and (where
# powershell.exe exists) a -DryRun against a fake LOCALAPPDATA holding only
# pre-rename shims finds them.
t; assert_eq "T-804: uninstall.ps1 source covers Knotlog\bin and the pre-rename Quipu\bin" 'yes' \
  "$(grep -qF "'Knotlog\bin'" "$ROOT/uninstall.ps1" && grep -qF "'Quipu\bin'" "$ROOT/uninstall.ps1" \
     && printf yes || printf no)"
if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
  KN804_LA="$TMP/kn804-la"
  mkdir -p "$KN804_LA/Quipu/bin"
  printf '@echo off\r\n"bash" "x\quipu" %%*\r\n' > "$KN804_LA/Quipu/bin/quipu.cmd"
  KN804_OUT=$(powershell.exe -NoProfile -NonInteractive -Command \
    "\$env:LOCALAPPDATA='$(cygpath -w "$KN804_LA")'; & '$(cygpath -w "$ROOT/uninstall.ps1")' -DryRun" </dev/null 2>&1)
  t; assert_eq "T-804b: uninstall.ps1 -DryRun finds a pre-rename Quipu\bin shim" 'yes' \
    "$(printf '%s\n' "$KN804_OUT" | grep -qF 'Quipu\bin\quipu.cmd' && printf yes || printf no)"
else
  t; skip "T-804b: uninstall.ps1 -DryRun on a pre-rename shim" "powershell.exe or cygpath unavailable"
fi

# ---- T-810..T-815: step 2.2, block markers (knotlog: written, quipu: still read) ----
# Everything the product WRITES uses the knotlog: marker family. Every reader also
# accepts the legacy quipu: family, and an existing block is updated in place
# with its own family kept (renaming old markers is `migrate`'s job, step 2.3).
# $TMP/mk81* are this block's own fixtures; the helpers here are self-contained.
mk81_run() { # vault args... -> knotlog with English output, no stdin
  _mk_v=$1; shift
  QUIPU_LANG=en QUIPU_VAULT="$_mk_v" sh "$ROOT/knotlog" "$@" </dev/null
}
mk81_vault() { # name -> a fresh plain vault with one captured event, a remember and a bridge context
  _mk_d="$TMP/$1"; mkdir -p "$_mk_d"
  mk81_run "$_mk_d" init --plain >/dev/null 2>&1
  printf '%s\n' '2026-09-01T10:00 | PostToolUse | Edit | a.md' >> "$_mk_d/.knotlog/activity.log"
  mk81_run "$_mk_d" remember >/dev/null 2>&1
  mk81_run "$_mk_d" context --bridge >/dev/null 2>&1
}

# T-810: a new vault carries only knotlog: markers -- bridge, context, core,
# reflect and threads blocks -- and not a single quipu: marker line.
mk81_vault mk810
MK810=$(find "$TMP/mk810" -name '*.md' -not -path '*/.knotlog/*' | tr '\n' '\0' | xargs -0 cat)
t; assert_eq "T-810: new vault writes the knotlog: start/end, context, core, reflect and threads markers" 'yes' \
  "$(for _m in start end context:start context:end core:start core:end reflect:start reflect:end threads:start threads:end; do
       printf '%s\n' "$MK810" | grep -qF "<!-- knotlog:$_m -->" || { printf no; exit; }
     done; printf yes)"
t; assert_eq "T-810: new vault writes no quipu: marker anywhere" 'no' \
  "$(printf '%s\n' "$MK810" | grep -qF '<!-- quipu:' && printf yes || printf no)"
t; assert_eq "T-810: the bridge heading reads ## knotlog" 'yes' \
  "$(grep -q '^## knotlog$' "$TMP/mk810/AGENTS.md" && ! grep -q '^## quipu$' "$TMP/mk810/AGENTS.md" && printf yes || printf no)"

# T-811: a vault whose blocks carry quipu: markers is updated in place: init,
# remember and note rewrite/extend the existing blocks, keep the quipu: family
# and never add a second (knotlog:) block of the same kind.
mk81_vault mk811
for _f in "$TMP/mk811/AGENTS.md" "$TMP/mk811/CLAUDE.md" "$TMP/mk811"/700-Sessions/*.md "$TMP/mk811/Threads.md"; do
  sed 's/<!-- knotlog:/<!-- quipu:/' "$_f" > "$_f.mk" && mv "$_f.mk" "$_f"
done
printf '%s\n' '2026-09-01T10:05 | PostToolUse | Edit | b.md' >> "$TMP/mk811/.knotlog/activity.log"
mk81_run "$TMP/mk811" init --plain >/dev/null 2>&1
mk81_run "$TMP/mk811" context --bridge >/dev/null 2>&1
mk81_run "$TMP/mk811" remember >/dev/null 2>&1
mk81_run "$TMP/mk811" note "legacy reflect line" >/dev/null 2>&1
mk81_run "$TMP/mk811" note --thread "legacy thread line" >/dev/null 2>&1
t; assert_eq "T-811: bridge block updated in place -- one quipu:start/end pair, no knotlog:start, heading refreshed" 'yes' \
  "$([ "$(grep -c '^<!-- quipu:start -->$' "$TMP/mk811/AGENTS.md")" = 1 ] \
     && [ "$(grep -c '^<!-- quipu:end -->$' "$TMP/mk811/AGENTS.md")" = 1 ] \
     && [ "$(grep -c '^<!-- quipu:start -->$' "$TMP/mk811/CLAUDE.md")" = 1 ] \
     && [ "$(grep -c 'knotlog:start' "$TMP/mk811/AGENTS.md")" = 0 ] \
     && [ "$(grep -c '^## knotlog$' "$TMP/mk811/AGENTS.md")" = 1 ] && printf yes || printf no)"
t; assert_eq "T-811: the existing context block is rewritten in place, one quipu:context pair per file, none added as knotlog:" 'yes'   "$([ "$(grep -c '^<!-- quipu:context:start -->$' "$TMP/mk811/AGENTS.md")" = 1 ]      && [ "$(grep -c '^<!-- quipu:context:start -->$' "$TMP/mk811/CLAUDE.md")" = 1 ]      && [ "$(grep -c 'knotlog:context' "$TMP/mk811/AGENTS.md")" = 0 ]      && [ "$(grep -c 'knotlog:context' "$TMP/mk811/CLAUDE.md")" = 0 ] && printf yes || printf no)"
MK811S=$(cat "$TMP/mk811"/700-Sessions/*.md)
t; assert_eq "T-811: session note keeps its single quipu:reflect block and gets the note inside it" 'yes' \
  "$([ "$(printf '%s\n' "$MK811S" | grep -c 'reflect:start')" = 1 ] \
     && printf '%s\n' "$MK811S" | grep -q '^<!-- quipu:reflect:start -->$' \
     && printf '%s\n' "$MK811S" | grep -qF 'legacy reflect line' && printf yes || printf no)"
t; assert_eq "T-811: Threads.md keeps its single quipu:threads block and gets the thread line inside it" 'yes' \
  "$([ "$(grep -c 'threads:start' "$TMP/mk811/Threads.md")" = 1 ] \
     && grep -q '^<!-- quipu:threads:start -->$' "$TMP/mk811/Threads.md" \
     && awk '/quipu:threads:start/{a=1} /quipu:threads:end/{exit} a' "$TMP/mk811/Threads.md" | grep -qF 'legacy thread line' \
     && printf yes || printf no)"

# T-812: both families in one file -- the first block found is the one that
# is updated (its markers kept); the other family's block stays byte for byte.
printf '%s\n' 'top' '<!-- quipu:start -->' 'old q' '<!-- quipu:end -->' 'mid' '<!-- knotlog:start -->' 'old k' '<!-- knotlog:end -->' 'tail' > "$TMP/mk812.md"
printf 'NEW\n' | awk -f "$LIB/block.awk" "$TMP/mk812.md" > "$TMP/mk812.out"
t; assert_eq "T-812: two families in one file -- first (quipu:) block updated, knotlog: block untouched" \
  'top|<!-- quipu:start -->|NEW|<!-- quipu:end -->|mid|<!-- knotlog:start -->|old k|<!-- knotlog:end -->|tail|' \
  "$(tr '\n' '|' < "$TMP/mk812.out")"
printf '%s\n' 'top' '<!-- knotlog:start -->' 'old k' '<!-- knotlog:end -->' '<!-- quipu:start -->' 'old q' '<!-- quipu:end -->' > "$TMP/mk812b.md"
printf 'NEW\n' | awk -f "$LIB/block.awk" "$TMP/mk812b.md" > "$TMP/mk812b.out"
t; assert_eq "T-812: knotlog: block first -- it is the one updated, the quipu: block untouched" \
  'top|<!-- knotlog:start -->|NEW|<!-- knotlog:end -->|<!-- quipu:start -->|old q|<!-- quipu:end -->|' \
  "$(tr '\n' '|' < "$TMP/mk812b.out")"

# T-813: readers -- reflect fullness and ask, pin and threads in context, and
# the core block detection -- behave the same for the knotlog: and quipu: families.
for _fam in knotlog quipu; do
  _v="$TMP/mk813$_fam"; mkdir -p "$_v/700-Sessions"
  mk81_run "$_v" init --plain >/dev/null 2>&1
  _d=$(date +%Y-%m-%d)
  printf '<!-- %s:reflect:start -->\n### %s\n\n<!-- %s:reflect:end -->\n' "$_fam" "$(i18n reflect_head_what)" "$_fam" > "$_v/700-Sessions/$_d.md"
  {
    printf '<!-- %s:pin:start -->\n### Pinned\n- pin %s\n<!-- %s:pin:end -->\n' "$_fam" "$_fam" "$_fam"
    printf '<!-- %s:threads:start -->\n### Active threads\n- thread %s\n### Closed threads\n<!-- %s:threads:end -->\n' "$_fam" "$_fam" "$_fam"
  } > "$_v/Threads.md"
  MK813=$(mk81_run "$_v" context --json SessionStart | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
  # shellcheck disable=SC2059
  MK813ASK=$(printf "$(i18n ctx_reflect_ask)" "700-Sessions/$_d.md" "$_fam:reflect")
  t; assert_eq "T-813: $_fam: empty reflect block -> the ask names the $_fam: marker" 'yes' \
    "$(printf '%s\n' "$MK813" | grep -qF "$MK813ASK" && printf yes || printf no)"
  if ! { printf '%s\n' "$MK813" | grep -qF -- "- pin $_fam" && printf '%s\n' "$MK813" | grep -qF -- "- thread $_fam"; }; then
    printf '# T-813 diag (%s): wanted "- pin %s" and "- thread %s"; context follows\n' "$_fam" "$_fam" "$_fam"
    printf '%s\n' "$MK813" | sed -n '1,60p' | sed 's/^/# T-813 ctx: /'
  fi
  t; assert_eq "T-813: $_fam: pin block and threads reach the context" 'yes' \
    "$(printf '%s\n' "$MK813" | grep -qF -- "- pin $_fam" && printf '%s\n' "$MK813" | grep -qF -- "- thread $_fam" && printf yes || printf no)"
  awk -v e="<!-- $_fam:reflect:end -->" '$0 == e { print "a real reflection line" } { print }' \
    "$_v/700-Sessions/$_d.md" > "$_v/700-Sessions/$_d.md.mk" && mv "$_v/700-Sessions/$_d.md.mk" "$_v/700-Sessions/$_d.md"
  MK813B=$(mk81_run "$_v" context --json SessionStart | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" -)
  t; assert_eq "T-813: $_fam: filled reflect block -> no ask" 'no' \
    "$(printf '%s\n' "$MK813B" | grep -qF "$MK813ASK" && printf yes || printf no)"
  # core block detection through the generalized helper (it has no CLI surface)
  {
    awk '/^_q_reflect_filled\(\) \{/,/^\}/' "$ROOT/knotlog"
    # literal $1/$2 and $_q_rf belong to the generated harness script.
    # shellcheck disable=SC2016
    printf '%s\n' '_q_reflect_filled "$1" "$2"; printf "%s" "$_q_rf"'
  } > "$TMP/mk813rf.sh"
  printf '<!-- %s:core:start -->\n### Core\n\n<!-- %s:core:end -->\n' "$_fam" "$_fam" > "$TMP/mk813core.md"
  MK813E=$(sh "$TMP/mk813rf.sh" "$TMP/mk813core.md" "knotlog:core")
  printf '<!-- %s:core:start -->\n### Core\nremember this\n<!-- %s:core:end -->\n' "$_fam" "$_fam" > "$TMP/mk813core.md"
  MK813F=$(sh "$TMP/mk813rf.sh" "$TMP/mk813core.md" "knotlog:core")
  t; assert_eq "T-813: $_fam: core block empty -> 0, filled -> 1" '0 1' "$MK813E $MK813F"
done

# T-814: compact reads both families (pin protection, section anchors) and the
# marker line it writes into the archive is a knotlog: one.
_v="$TMP/mk814"; mkdir -p "$_v/.knotlog"; : > "$_v/.knotlog/config"
printf '%s\n' '# Threads' '<!-- quipu:pin:start -->' '### Pinned' '- keep me' '<!-- quipu:pin:end -->' \
  '<!-- quipu:threads:start -->' '### Active threads' '- a' '### Closed threads' '- c1' '- c2' '- c3' '<!-- quipu:threads:end -->' > "$_v/Threads.md"
mk81_run "$_v" compact --keep 1 --apply >/dev/null 2>&1; RC814=$?
t; assert_eq "T-814: compact on a quipu:-marked Threads.md exits 0, keeps pin and family, archives with a knotlog: line" 'yes' \
  "$([ "$RC814" -eq 0 ] && grep -qF -- '- keep me' "$_v/Threads.md" && [ "$(grep -c 'knotlog:threads' "$_v/Threads.md")" = 0 ] \
     && [ "$(grep -c '^<!-- quipu:threads:start -->$' "$_v/Threads.md")" = 1 ] \
     && grep -rqF '<!-- knotlog:compacted ' "$_v" && printf yes || printf no)"

# T-815: secret-scan -- the hook signature is recognised in both families: a
# hook carrying either one is refreshed by init, a hand-written one is preserved.
_v="$TMP/mk815"; mkdir -p "$_v/.githooks"; git init -q "$_v" </dev/null >/dev/null 2>&1
printf '#!/bin/sh\n# quipu:secret-scan old signature\nexit 0\n' > "$_v/.githooks/pre-commit"
mk81_run "$_v" init --plain >/dev/null 2>&1
t; assert_eq "T-815: a hook with the legacy quipu:secret-scan signature is refreshed to the shipped knotlog: one" 'yes' \
  "$(cmp -s "$_v/.githooks/pre-commit" "$ROOT/hooks/pre-commit" && grep -qF 'knotlog:secret-scan' "$_v/.githooks/pre-commit" && printf yes || printf no)"
printf '#!/bin/sh\n# knotlog:secret-scan hand tweak\nexit 0\n' > "$_v/.githooks/pre-commit"
mk81_run "$_v" init --plain >/dev/null 2>&1
t; assert_eq "T-815: a hook with the knotlog:secret-scan signature is recognised (refreshed, not preserved)" 'yes' \
  "$(cmp -s "$_v/.githooks/pre-commit" "$ROOT/hooks/pre-commit" && printf yes || printf no)"
printf '#!/bin/sh\n# hand written\nexit 0\n' > "$_v/.githooks/pre-commit"
mk81_run "$_v" init --plain >/dev/null 2>&1
t; assert_eq "T-815: a hand-written hook without either signature is preserved" 'yes' \
  "$(grep -qF 'hand written' "$_v/.githooks/pre-commit" && printf yes || printf no)"

# ---- T-820..T-829: step 2.3, `knotlog migrate` (pre-rename vault -> Knotlog) ----
# A vault made before the rename migrates in place: dry run by default (writes
# nothing), --apply rewrites only what Knotlog wrote itself, a second --apply
# finds nothing. $TMP/mg82* are this block's own fixtures; helpers are local.
mg82_run() { # vault args... -> knotlog with English output, no stdin
  _mg_v=$1; shift
  QUIPU_LANG=en QUIPU_VAULT="$_mg_v" sh "$ROOT/knotlog" "$@" </dev/null
}
mg82_sum() { # vault -> checksum of every file, path-sorted
  (cd "$1" && find . -type f | sort | while IFS= read -r _mg_f; do cksum < "$_mg_f" | tr '\n' ' '; printf '%s\n' "$_mg_f"; done)
}
mg82_vault() { # name -> a pre-rename vault: .quipu state, quipu: markers, old hook commands
  _mg_d="$TMP/$1"; rm -rf "$_mg_d"; mkdir -p "$_mg_d/.quipu" "$_mg_d/.claude" "$_mg_d/.codex" "$_mg_d/.omp/hooks/pre" "$_mg_d/.githooks" "$_mg_d/Notes"
  printf 'layout=en\nlang=en\nQUIPU_CTX_MAX=999\n' > "$_mg_d/.quipu/config"
  printf '# Mine\nmy words about quipu\n<!-- quipu:start -->\n## quipu\nuser edit inside\n<!-- quipu:end -->\nafter\n' > "$_mg_d/AGENTS.md"
  {
    printf '<!-- quipu:reflect:start -->\nmy reflection\n<!-- quipu:reflect:end -->\n'
    printf 'prose mentions <!-- quipu:start --> inline\n```\n<!-- quipu:start -->\nexample\n<!-- quipu:end -->\n```\n'
  } > "$_mg_d/Notes/n.md"
  printf 'plain user note\nquipu: is just a word here\n' > "$_mg_d/Notes/p.md"
  sed 's/KNOTLOG_HOOK=1 knotlog/QUIPU_HOOK=1 quipu/g' "$ROOT/adapters/claude-code.json" > "$_mg_d/.claude/settings.json"
  sed 's/KNOTLOG_HOOK=1/QUIPU_HOOK=1/g; s/knotlog/quipu/g' "$ROOT/adapters/codex/hooks.json" > "$_mg_d/.codex/hooks.json"
  printf '%s\n' '"command": "QUIPU_HOOK=1 mytool run",' >> "$_mg_d/.codex/hooks.json"
  cp "$ROOT/adapters/omp/hooks/pre/knotlog.ts" "$_mg_d/.omp/hooks/pre/quipu.ts"
  printf '# quipu: machine state, regenerated -- not memory.\n.quipu/activity.log*\n.quipu/index.tsv\ndesktop.ini\n' > "$_mg_d/.gitignore"
  printf '#!/bin/sh\n# quipu:secret-scan old signature\nexit 0\n' > "$_mg_d/.githooks/pre-commit"
}

mg82_vault mg820
MG820_BEFORE=$(mg82_sum "$TMP/mg820")
mg82_run "$TMP/mg820" migrate >"$TMP/mg820.out" 2>"$TMP/mg820.err"; RC820=$?
t; assert_eq "T-820: dry run exits 0 and writes nothing (every file checksum identical)" 'yes' \
  "$([ "$RC820" -eq 0 ] && [ "$MG820_BEFORE" = "$(mg82_sum "$TMP/mg820")" ] && printf yes || printf no)"
t; assert_eq "T-820: dry run lists the folder, config, markers, hooks, omp hook, .gitignore and secret hook, and points at --apply" 'yes' \
  "$(grep -qF 'rename .quipu to .knotlog' "$TMP/mg820.out" && grep -qF 'QUIPU_* keys in .quipu/config' "$TMP/mg820.out" \
     && grep -qF 'block markers in AGENTS.md' "$TMP/mg820.out" && grep -qF 'block markers in Notes/n.md' "$TMP/mg820.out" \
     && grep -qF 'hook commands in .claude/settings.json' "$TMP/mg820.out" && grep -qF 'hook commands in .codex/hooks.json' "$TMP/mg820.out" \
     && grep -qF 'old omp hook .omp/hooks/pre/quipu.ts' "$TMP/mg820.out" && grep -qF '.quipu entries in .gitignore' "$TMP/mg820.out" \
     && grep -qF 'secret-scan hook .githooks/pre-commit' "$TMP/mg820.out" && grep -qF 'knotlog migrate --apply' "$TMP/mg820.out" \
     && ! grep -qF 'Notes/p.md' "$TMP/mg820.out" && printf yes || printf no)"

mg82_run "$TMP/mg820" migrate --apply >"$TMP/mg821.out" 2>"$TMP/mg821.err"; RC821=$?
MG821=$TMP/mg820
t; assert_eq "T-821: --apply exits 0; .quipu is gone, .knotlog/config holds the old keys with QUIPU_ renamed" 'yes' \
  "$([ "$RC821" -eq 0 ] && [ ! -e "$MG821/.quipu" ] && grep -qx 'layout=en' "$MG821/.knotlog/config" \
     && grep -qx 'KNOTLOG_CTX_MAX=999' "$MG821/.knotlog/config" && ! grep -q '^QUIPU_' "$MG821/.knotlog/config" && printf yes || printf no)"
t; assert_eq "T-821: tool-owned markers become knotlog:, the user's text inside the block and around it is unchanged" 'yes' \
  "$([ "$(cat "$MG821/AGENTS.md")" = "$(printf '# Mine\nmy words about quipu\n<!-- knotlog:start -->\n## quipu\nuser edit inside\n<!-- knotlog:end -->\nafter')" ] \
     && grep -qx '<!-- knotlog:reflect:start -->' "$MG821/Notes/n.md" && grep -qx 'my reflection' "$MG821/Notes/n.md" && printf yes || printf no)"
t; assert_eq "T-821: a quipu: mention in prose, a fenced marker example and an unmarked note are not touched" 'yes' \
  "$(grep -qF 'prose mentions <!-- quipu:start --> inline' "$MG821/Notes/n.md" && [ "$(grep -c '^<!-- quipu:start -->$' "$MG821/Notes/n.md")" = 1 ] \
     && [ "$(grep -c '^<!-- quipu:end -->$' "$MG821/Notes/n.md")" = 1 ] \
     && [ "$(cat "$MG821/Notes/p.md")" = "$(printf 'plain user note\nquipu: is just a word here')" ] && printf yes || printf no)"
t; assert_eq "T-821: hook commands say KNOTLOG_HOOK=1 knotlog (claude + codex incl. Windows form); a user's own QUIPU_HOOK command stays" 'yes' \
  "$(cmp -s "$MG821/.claude/settings.json" "$ROOT/adapters/claude-code.json" && grep -qF 'set KNOTLOG_HOOK=1&& knotlog remember' "$MG821/.codex/hooks.json" \
     && grep -qF 'knotlog memory hooks' "$MG821/.codex/hooks.json" && grep -qF 'QUIPU_HOOK=1 mytool run' "$MG821/.codex/hooks.json" \
     && [ "$(grep -c 'QUIPU_HOOK' "$MG821/.codex/hooks.json")" = 1 ] && printf yes || printf no)"
t; assert_eq "T-821: the old omp hook is replaced by the shipped knotlog.ts" 'yes' \
  "$([ ! -e "$MG821/.omp/hooks/pre/quipu.ts" ] && cmp -s "$MG821/.omp/hooks/pre/knotlog.ts" "$ROOT/adapters/omp/hooks/pre/knotlog.ts" && printf yes || printf no)"
t; assert_eq "T-821: .gitignore entries and comment follow, other lines kept; the secret hook is the shipped one" 'yes' \
  "$([ "$(cat "$MG821/.gitignore")" = "$(printf '# knotlog: machine state, regenerated -- not memory.\n.knotlog/activity.log*\n.knotlog/index.tsv\ndesktop.ini')" ] \
     && cmp -s "$MG821/.githooks/pre-commit" "$ROOT/hooks/pre-commit" && printf yes || printf no)"

MG822_BEFORE=$(mg82_sum "$MG821")
mg82_run "$MG821" migrate --apply >"$TMP/mg822.out" 2>"$TMP/mg822.err"; RC822=$?
t; assert_eq "T-822: a second --apply says nothing to migrate, exits 0 and changes no byte; so does a dry run" 'yes' \
  "$([ "$RC822" -eq 0 ] && [ "$(cat "$TMP/mg822.out")" = 'nothing to migrate' ] && [ "$MG822_BEFORE" = "$(mg82_sum "$MG821")" ] \
     && [ "$(mg82_run "$MG821" migrate 2>/dev/null)" = 'nothing to migrate' ] && printf yes || printf no)"

mg82_vault mg823; mkdir -p "$TMP/mg823/.knotlog"; : > "$TMP/mg823/.knotlog/config"
MG823_BEFORE=$(mg82_sum "$TMP/mg823")
mg82_run "$TMP/mg823" migrate --apply >"$TMP/mg823.out" 2>"$TMP/mg823.err"; RC823=$?
t; assert_eq "T-823: .quipu and .knotlog together -> exit 1, an explanation on stderr, nothing changed (also in a dry run)" 'yes' \
  "$([ "$RC823" -eq 1 ] && grep -qF 'both ' "$TMP/mg823.err" && grep -qF '.knotlog exist' "$TMP/mg823.err" && [ "$MG823_BEFORE" = "$(mg82_sum "$TMP/mg823")" ] \
     && { mg82_run "$TMP/mg823" migrate >/dev/null 2>&1; [ "$?" -eq 1 ]; } && printf yes || printf no)"

mg82_vault mg824
printf '%s\n' '// my own tweak' >> "$TMP/mg824/.omp/hooks/pre/quipu.ts"
mg82_run "$TMP/mg824" migrate --apply >"$TMP/mg824.out" 2>"$TMP/mg824.err"; RC824=$?
t; assert_eq "T-824: a hand-edited quipu.ts is left in place with a warning and no knotlog.ts is added" 'yes' \
  "$([ "$RC824" -eq 0 ] && grep -qF 'my own tweak' "$TMP/mg824/.omp/hooks/pre/quipu.ts" && [ ! -e "$TMP/mg824/.omp/hooks/pre/knotlog.ts" ] \
     && grep -qF 'quipu.ts differs from every file Knotlog installed' "$TMP/mg824.err" && ! grep -qF 'old omp hook' "$TMP/mg824.out" && printf yes || printf no)"
# a quipu.ts that a real older release shipped (checksum table); skipped without the git history
if git -C "$ROOT" cat-file -e 9ca5288:adapters/omp/hooks/pre/quipu.ts 2>/dev/null; then
  mg82_vault mg824b
  git -C "$ROOT" show 9ca5288:adapters/omp/hooks/pre/quipu.ts > "$TMP/mg824b/.omp/hooks/pre/quipu.ts"
  mg82_run "$TMP/mg824b" migrate --apply >/dev/null 2>&1
  t; assert_eq "T-824: a quipu.ts from an older release is recognised by checksum and retired" 'yes' \
    "$([ ! -e "$TMP/mg824b/.omp/hooks/pre/quipu.ts" ] && cmp -s "$TMP/mg824b/.omp/hooks/pre/knotlog.ts" "$ROOT/adapters/omp/hooks/pre/knotlog.ts" && printf yes || printf no)"
else
  t; skip "T-824: older-release quipu.ts checksum" "git history unavailable"
fi

mg82_vault mg825
printf 'KNOTLOG_CTX_MAX=500\n' >> "$TMP/mg825/.quipu/config"
mg82_run "$TMP/mg825" migrate --apply >/dev/null 2>"$TMP/mg825.err"
t; assert_eq "T-825: QUIPU_X and KNOTLOG_X both set -> KNOTLOG wins, the old line survives as a comment, the clash is reported" 'yes' \
  "$([ "$(grep -c '^KNOTLOG_CTX_MAX=' "$TMP/mg825/.knotlog/config")" = 1 ] && grep -qx 'KNOTLOG_CTX_MAX=500' "$TMP/mg825/.knotlog/config" \
     && grep -qx '# migrated, KNOTLOG_CTX_MAX wins: QUIPU_CTX_MAX=999' "$TMP/mg825/.knotlog/config" && grep -qF 'KNOTLOG_CTX_MAX is set twice' "$TMP/mg825.err" && printf yes || printf no)"

mg82_vault mg826
printf '#!/bin/sh\n# written by hand\nexit 0\n' > "$TMP/mg826/.githooks/pre-commit"
printf '%s\n' '{ "command": "QUIPU_HOOK=1 \"/old/place/quipu\" remember" }' > "$TMP/mg826/.cursor-probe.json"
mkdir -p "$TMP/mg826/.cursor"; cp "$TMP/mg826/.cursor-probe.json" "$TMP/mg826/.cursor/hooks.json"
mg82_run "$TMP/mg826" migrate --apply >/dev/null 2>&1
t; assert_eq "T-826: a hand-written pre-commit stays; a repair-hooks style quoted checkout path is pointed at this checkout's knotlog" 'yes' \
  "$(grep -qF 'written by hand' "$TMP/mg826/.githooks/pre-commit" \
     && [ "$(cat "$TMP/mg826/.cursor/hooks.json")" = "$(printf '{ "command": "KNOTLOG_HOOK=1 \\"%s/knotlog\\" remember" }' "$ROOT")" ] && printf yes || printf no)"

mg82_vault mg827
mg82_run "$TMP/mg827" doctor >"$TMP/mg827.out" 2>&1
mg82_run "$TMP/mg827" migrate --apply >/dev/null 2>&1
mg82_run "$TMP/mg827" doctor >"$TMP/mg827b.out" 2>&1
t; assert_eq "T-827: doctor on an old vault warns (not fails) and names knotlog migrate; after migrating the warning is gone" 'yes' \
  "$(grep -qF 'run: knotlog migrate' "$TMP/mg827.out" && grep -F 'knotlog migrate' "$TMP/mg827.out" | grep -qF 'warn' \
     && ! grep -qF 'knotlog migrate' "$TMP/mg827b.out" && printf yes || printf no)"
mkdir -p "$TMP/mg827c/.knotlog"; printf 'QUIPU_LANG=en\n' > "$TMP/mg827c/.knotlog/config"
t; assert_eq "T-827: a QUIPU_* key in a .knotlog config also triggers the warning" 'yes' \
  "$(mg82_run "$TMP/mg827c" doctor 2>&1 | grep -qF 'run: knotlog migrate' && printf yes || printf no)"

t; assert_eq "T-828: help lists migrate in English and Turkish" 'yes' \
  "$(mg82_run "$TMP/mg827" help | grep -q '^  migrate ' && mg82_run "$TMP/mg827" help --tr | grep -q '^  migrate ' && printf yes || printf no)"
mg82_run "$TMP/mg827" migrate --bogus >/dev/null 2>&1; RC828=$?
mg82_run "$TMP/mg827" migrate extra >/dev/null 2>&1; RC828B=$?
t; assert_eq "T-828: an unknown flag or stray argument is a usage error (exit 2)" '2 2' "$RC828 $RC828B"
# T-829: the bridge block's CONTENT is refreshed only when nobody edited it:
# its text must equal what init writes today with knotlog/Knotlog turned back
# into quipu/Quipu. A block with hand-added lines (like a real vault's) keeps
# every byte, only its markers are renamed, and a warning goes to stderr.
mg829_old() { # name -> vault whose AGENTS.md/CLAUDE.md carry an unedited old-name bridge block
  _mg_d="$TMP/$1"; rm -rf "$_mg_d"; mkdir -p "$_mg_d/.quipu"
  printf 'layout=en\nlang=en\n' > "$_mg_d/.quipu/config"
  rm -rf "$TMP/mg829gen"; mkdir -p "$TMP/mg829gen/.knotlog"; printf 'layout=en\nlang=en\n' > "$TMP/mg829gen/.knotlog/config"
  mg82_run "$TMP/mg829gen" init --no-prompt >/dev/null 2>&1
  sed 's/knotlog/quipu/g; s/Knotlog/Quipu/g; s/KNOTLOG/QUIPU/g' "$TMP/mg829gen/AGENTS.md" > "$TMP/mg829gen.old"
  { printf 'top line\n'; cat "$TMP/mg829gen.old"; printf 'bottom line\n'; } > "$_mg_d/CLAUDE.md"
  cp "$TMP/mg829gen.old" "$_mg_d/AGENTS.md"
}
mg829_block() { awk '/^<!-- knotlog:start -->$/{b=1} b{print} /^<!-- knotlog:end -->$/{b=0}' "$1"; }

mg829_old mg829
mg82_run "$TMP/mg829" migrate >"$TMP/mg829.dry" 2>"$TMP/mg829.dry.err"
mg82_run "$TMP/mg829" migrate --apply >/dev/null 2>"$TMP/mg829.err"
t; assert_eq "T-829: unedited old blocks: the dry run lists both files for a refresh; --apply writes today's text (no quipu left), no warning" 'yes' \
  "$([ "$(grep -c 'refresh the Knotlog block' "$TMP/mg829.dry")" = 2 ] && [ ! -s "$TMP/mg829.err" ] \
     && [ "$(mg829_block "$TMP/mg829/AGENTS.md")" = "$(mg829_block "$TMP/mg829gen/AGENTS.md")" ] \
     && [ "$(mg829_block "$TMP/mg829/CLAUDE.md")" = "$(mg829_block "$TMP/mg829gen/AGENTS.md")" ] \
     && [ "$(sed -n '1p' "$TMP/mg829/CLAUDE.md")" = 'top line' ] && [ "$(tail -n 1 "$TMP/mg829/CLAUDE.md")" = 'bottom line' ] \
     && ! grep -q 'quipu' "$TMP/mg829/CLAUDE.md" && printf yes || printf no)"
MG829_B=$(mg82_sum "$TMP/mg829")
t; assert_eq "T-829: a second --apply on the refreshed vault finds nothing" 'yes' \
  "$([ "$(mg82_run "$TMP/mg829" migrate --apply 2>&1)" = 'nothing to migrate' ] && [ "$MG829_B" = "$(mg82_sum "$TMP/mg829")" ] && printf yes || printf no)"

mg829_old mg829e
# a vault like a real one: hand-added lines inside the block, plus a path in the old wording
{ sed -n '1,/^Run: quipu context$/p' "$TMP/mg829gen.old"; printf '%s\n' 'Video rule: when a link arrives, write the transcript note first.' \
    'Extra: the assistant lives in the Assistant folder (example text).'; sed -n '/^Run: quipu context$/,$p' "$TMP/mg829gen.old" | sed '1d'; } > "$TMP/mg829e.blk"
{ printf 'top line\n'; cat "$TMP/mg829e.blk"; printf 'bottom line\n'; } > "$TMP/mg829e/CLAUDE.md"
cp "$TMP/mg829e/CLAUDE.md" "$TMP/mg829e.before"
mg82_run "$TMP/mg829e" migrate >"$TMP/mg829e.dry" 2>"$TMP/mg829e.dry.err"
mg82_run "$TMP/mg829e" migrate --apply >"$TMP/mg829e.out" 2>"$TMP/mg829e.err"
sed 's/^<!-- quipu:start -->$/<!-- knotlog:start -->/; s/^<!-- quipu:end -->$/<!-- knotlog:end -->/' "$TMP/mg829e.before" > "$TMP/mg829e.expect"
t; assert_eq "T-829: an edited block keeps every byte (only its two marker lines change), the extra lines survive, a warning names CLAUDE.md" 'yes' \
  "$(cmp -s "$TMP/mg829e/CLAUDE.md" "$TMP/mg829e.expect" && grep -qF 'Video rule: when a link arrives' "$TMP/mg829e/CLAUDE.md" \
     && grep -qF 'CLAUDE.md was edited by hand' "$TMP/mg829e.err" && grep -qF 'CLAUDE.md was edited by hand' "$TMP/mg829e.dry.err" \
     && ! grep -qF 'refresh the Knotlog block in CLAUDE.md' "$TMP/mg829e.dry" && printf yes || printf no)"
t; assert_eq "T-829: the unedited AGENTS.md next to it is still refreshed, and a second --apply on the mixed vault changes nothing" 'yes' \
  "$(grep -qF 'refresh the Knotlog block in AGENTS.md' "$TMP/mg829e.dry" && [ "$(mg829_block "$TMP/mg829e/AGENTS.md")" = "$(mg829_block "$TMP/mg829gen/AGENTS.md")" ] \
     && MG829E_B=$(mg82_sum "$TMP/mg829e") && [ "$(mg82_run "$TMP/mg829e" migrate --apply 2>/dev/null)" = 'nothing to migrate' ] \
     && [ "$MG829E_B" = "$(mg82_sum "$TMP/mg829e")" ] && printf yes || printf no)"
# ---- T-830..T-832: backups written under the old .quipu-previous names ------
# A checkout updated before the rename carries .quipu-previous[.2|.3]. The
# chain must stay usable: rollback finds it, and the next --apply carries it
# over under the new names without losing a slot. Reuses the ROT fixtures.
legacy_chain() { # $1 = checkout (current 3.0.0); old chain: 2.9.0, 2.8.0
  _q_seed_checkout "$1" 3.0.0
  _q_seed_checkout "$1.quipu-previous" 2.9.0
  _q_seed_checkout "$1.quipu-previous.2" 2.8.0
}
LG1="$ROT/home/lg1"
legacy_chain "$LG1"
QUIPU_LANG=en QUIPU_HOME="$LG1" sh "$ROOT/knotlog" rollback >/dev/null 2>"$ROT/rb830.err"; RC830=$?
t; assert_eq "T-830: rollback finds an old-named chain and restores 2.9.0" 'yes' \
  "$([ "$RC830" -eq 0 ] && grep -qF '_q_version=2.9.0' "$LG1/knotlog" && printf yes || printf no)"
t; assert_eq "T-830: the chain shifts under the new name and no old-named slot is left" 'yes' \
  "$(grep -qF '_q_version=2.8.0' "$LG1.knotlog-previous/knotlog" && [ ! -e "$LG1.knotlog-previous.2" ] \
     && [ -z "$(ls -d "$LG1".quipu-previous* 2>/dev/null)" ] && printf yes || printf no)"

LG2="$ROT/home/lg2"
legacy_chain "$LG2"
rot_apply "$LG2" 3.1.0
t; assert_eq "T-831: --apply over an old-named chain keeps all of it, now as .knotlog-previous, .2, .3" 'yes' \
  "$(grep -qF '_q_version=3.0.0' "$LG2.knotlog-previous/knotlog" && grep -qF '_q_version=2.9.0' "$LG2.knotlog-previous.2/knotlog" \
     && grep -qF '_q_version=2.8.0' "$LG2.knotlog-previous.3/knotlog" && [ -z "$(ls -d "$LG2".quipu-previous* 2>/dev/null)" ] \
     && printf yes || printf no)"

LG3="$ROT/home/lg3"
legacy_chain "$LG3"
_q_seed_checkout "$LG3.knotlog-previous" 2.7.3
QUIPU_LANG=en QUIPU_HOME="$LG3" sh "$ROOT/knotlog" rollback >/dev/null 2>"$ROT/rb832.err"; RC832=$?
t; assert_eq "T-832: with both chains present the new one is used and the old one is left alone" 'yes' \
  "$([ "$RC832" -eq 0 ] && grep -qF '_q_version=2.7.3' "$LG3/knotlog" && grep -qF '_q_version=2.9.0' "$LG3.quipu-previous/knotlog" \
     && grep -qF '_q_version=2.8.0' "$LG3.quipu-previous.2/knotlog" && printf yes || printf no)"

# ---- T-840..T-848: `knotlog setup antigravity` and `context --antigravity` ---
# Antigravity hooks (.agents/hooks.json): SessionStart injects the context as a
# systemMessage step; Stop answers {"decision":...} every time ("continue"
# re-enters the loop). Own fixtures under $TMP/ag84*; helpers are local.
ag84_run() { # vault args... -> knotlog, English, stdin from the caller
  _ag_v=$1; shift
  QUIPU_LANG=en QUIPU_VAULT="$_ag_v" sh "$ROOT/knotlog" "$@"
}
ag84_vault() { # dir [old] -> a git vault; "old" = stale note plus a newer commit (checkpoint due)
  _ag_d=$1; rm -rf "$_ag_d"; mkdir -p "$_ag_d/.knotlog" "$_ag_d/700-Sessions"
  printf 'layout=plain\nlang=en\n' > "$_ag_d/.knotlog/config"
  _ag_day=$(date +%Y-%m-%d); _ag_now=$(date +%s)
  echo 'note' > "$_ag_d/700-Sessions/$_ag_day.md"
  (cd "$_ag_d" && git init --quiet && git config user.name Test && git config user.email t@t.com && git add -A \
    && GIT_COMMITTER_DATE="@$((_ag_now - 10800))" GIT_AUTHOR_DATE="@$((_ag_now - 10800))" git commit -m init --quiet)
  if [ "$2" = old ]; then
    touch_at "$((_ag_now - 7200))" "$_ag_d/700-Sessions/$_ag_day.md"
    echo work > "$_ag_d/work.md"
    (cd "$_ag_d" && git add work.md && git commit -m work --quiet)
  fi
}
ag84_balanced() { # text -> yes when the string closes and braces/brackets outside strings balance
  printf '%s' "$1" | awk 'BEGIN { RS = "\001"; bs = sprintf("%c", 92); dq = sprintf("%c", 34) }
    { n = length($0); for (i = 1; i <= n; i++) { c = substr($0, i, 1)
        if (ins) { if (esc) esc = 0; else if (c == bs) esc = 1; else if (c == dq) ins = 0 }
        else if (c == dq) ins = 1
        else if (c == "{") b++; else if (c == "}") b--; else if (c == "[") a++; else if (c == "]") a-- } }
    END { print ((!ins && b == 0 && a == 0) ? "yes" : "no") }'
}

AG1="$TMP/ag841"; rm -rf "$AG1"; mkdir -p "$AG1/.knotlog"; : > "$AG1/.knotlog/config"
t; ag84_run "$AG1" setup antigravity --dry-run >"$TMP/ag841.dry" 2>&1 </dev/null
assert_eq "T-840: setup antigravity --dry-run reports it would write and writes nothing" 'yes' \
  "$(grep -qF 'written to' "$TMP/ag841.dry" && [ ! -e "$AG1/.agents" ] && printf yes || printf no)"
t; ag84_run "$AG1" setup antigravity >"$TMP/ag841.out" 2>&1 </dev/null
assert_eq "T-841: setup antigravity writes .agents/hooks.json byte-identical to the adapter" 'yes' \
  "$(cmp -s "$ROOT/adapters/antigravity/hooks.json" "$AG1/.agents/hooks.json" && printf yes || printf no)"
t; ag84_run "$AG1" setup antigravity >"$TMP/ag841.again" 2>&1 </dev/null
assert_eq "T-841: a second run reports already up to date" 'yes' \
  "$(grep -qF 'already up to date' "$TMP/ag841.again" && printf yes || printf no)"
printf '{"mine":true}\n' > "$AG1/.agents/hooks.json"
t; ag84_run "$AG1" setup antigravity >"$TMP/ag841.keep" 2>&1 </dev/null
assert_eq "T-842: a differing .agents/hooks.json is preserved untouched and reported" 'yes' \
  "$(grep -qF 'preserved' "$TMP/ag841.keep" && [ "$(cat "$AG1/.agents/hooks.json")" = '{"mine":true}' ] && printf yes || printf no)"
AGA="$ROOT/adapters/antigravity/hooks.json"
t; assert_eq "T-843: the adapter is balanced and binds SessionStart and Stop with --antigravity commands, timeout in seconds" 'yes' \
  "$([ "$(ag84_balanced "$(cat "$AGA")")" = yes ] && [ "$(grep -c -- '--antigravity", "timeout": [0-9]* }' "$AGA")" = 2 ] \
     && grep -qF '"SessionStart"' "$AGA" && grep -qF '"Stop"' "$AGA" && printf yes || printf no)"

# SessionStart: the context rides in an injectSteps systemMessage, never hookSpecificOutput.
ag84_vault "$TMP/ag844"
t; AG_SS=$(ag84_run "$TMP/ag844" context --json SessionStart --antigravity </dev/null)
assert_eq "T-844: SessionStart --antigravity is {injectSteps:[{systemMessage:{systemMessage:...}}]}" 'yes' \
  "$(case "$AG_SS" in ('{"injectSteps":[{"systemMessage":{"systemMessage":"'*'"}}]}') printf yes ;; (*) printf no ;; esac)"
assert_eq "T-844: the output is balanced JSON on one line without hookSpecificOutput" 'yes' \
  "$([ "$(ag84_balanced "$AG_SS")" = yes ] && [ "$(printf '%s\n' "$AG_SS" | wc -l | tr -d ' ')" = 1 ] \
     && ! printf '%s' "$AG_SS" | grep -qF hookSpecificOutput && printf yes || printf no)"

# Stop: checkpoint due -> continue with the reminder; throttled -> allow; fullyIdle:false -> allow.
ag84_vault "$TMP/ag845" old
t; AG_ST1=$(printf '{"fullyIdle":true}' | ag84_run "$TMP/ag845" context --json Stop --antigravity)
assert_eq "T-845: Stop with a checkpoint due answers decision continue with the reminder" 'yes' \
  "$(case "$AG_ST1" in ('{"decision":"continue","reason":"Checkpoint: session note was written'*'"}') printf yes ;; (*) printf no ;; esac)"
assert_eq "T-845: the continue output is balanced JSON" 'yes' "$(ag84_balanced "$AG_ST1")"
t; AG_ST2=$(printf '{"fullyIdle":true}' | ag84_run "$TMP/ag845" context --json Stop --antigravity)
assert_eq "T-846: an immediate second Stop is throttled to decision allow (1800 s guard)" '{"decision":"allow"}' "$AG_ST2"
ag84_vault "$TMP/ag847" old
t; AG_ST3=$(printf '{"fullyIdle": false}' | ag84_run "$TMP/ag847" context --json Stop --antigravity)
assert_eq "T-847: fullyIdle false never stops: decision allow" '{"decision":"allow"}' "$AG_ST3"
assert_eq "T-847: ...and it does not spend the nudge (no checkpoint_nudged written)" 'no' \
  "$([ -e "$TMP/ag847/.knotlog/checkpoint_nudged" ] && printf yes || printf no)"
ag84_vault "$TMP/ag848"
t; AG_ST4=$(printf '{"fullyIdle":true}' | ag84_run "$TMP/ag848" context --json Stop --antigravity)
assert_eq "T-848: a fresh note (no checkpoint due) answers decision allow, never empty" '{"decision":"allow"}' "$AG_ST4"
t; AG_PI=$(printf '{}' | ag84_run "$TMP/ag848" context --json PreInvocation --antigravity)
assert_eq "T-848: any other event with --antigravity answers {}" '{}' "$AG_PI"
t; AG_CL=$(printf '{}' | ag84_run "$TMP/ag845" context --json Stop)
assert_eq "T-848: Stop without --antigravity is unchanged (silent while throttled)" '' "$AG_CL"

# migrate: a pre-rename .agents/hooks.json gets the new hook command.
mkdir -p "$TMP/ag849/.quipu" "$TMP/ag849/.agents"; : > "$TMP/ag849/.quipu/config"
printf '{"quipu":{"Stop":[{"command":"QUIPU_HOOK=1 quipu context --json Stop --antigravity","timeout":10}]}}\n' > "$TMP/ag849/.agents/hooks.json"
t; QUIPU_LANG=en QUIPU_VAULT="$TMP/ag849" sh "$ROOT/knotlog" migrate --apply >/dev/null 2>&1 </dev/null
assert_eq "T-849: migrate --apply rewrites the hook command in .agents/hooks.json" 'yes' \
  "$(grep -qF 'KNOTLOG_HOOK=1 knotlog context --json Stop --antigravity' "$TMP/ag849/.agents/hooks.json" && ! grep -qF QUIPU_HOOK "$TMP/ag849/.agents/hooks.json" && printf yes || printf no)"

# ---- T-850..T-853: remember is silent on stdout in hook mode -----------------
# Every adapter chains `KNOTLOG_HOOK=1 knotlog remember && ... context --json
# SessionStart`; the agent reads that stdout as one JSON object, so remember
# may not print anything there. Own fixtures under $TMP/rm85*; helpers local.
rm85_vault() { # dir [log] -> a git-less vault; "log" = one pending activity line (remember has work)
  rm -rf "$1"; mkdir -p "$1/.knotlog" "$1/700-Sessions"
  printf 'layout=plain\nlang=en\n' > "$1/.knotlog/config"
  [ "$2" != log ] || printf '%s\n' '2026-08-20T10:00 | PostToolUse | Edit | notes/a.md' > "$1/.knotlog/activity.log"
}
rm85_rem() { # vault hookflag(0|1) -> remember stdout only
  if [ "$2" = 1 ]; then QUIPU_LANG=en QUIPU_VAULT="$1" KNOTLOG_HOOK=1 sh "$ROOT/knotlog" remember 2>/dev/null </dev/null
  else QUIPU_LANG=en QUIPU_VAULT="$1" sh "$ROOT/knotlog" remember 2>/dev/null </dev/null; fi
}
t; rm85_vault "$TMP/rm850"
assert_eq "T-850 (a): hook-mode remember with nothing to do prints nothing on stdout" '' "$(rm85_rem "$TMP/rm850" 1)"
t; rm85_vault "$TMP/rm851" log
assert_eq "T-850 (a): hook-mode remember that writes a session note prints nothing on stdout" '' "$(rm85_rem "$TMP/rm851" 1)"
assert_eq "T-850 (a): ...and it still wrote the note" 'yes' \
  "$(grep -qF 'notes/a.md' "$TMP/rm851/700-Sessions/$(date +%Y-%m-%d).md" && printf yes || printf no)"
t; rm85_vault "$TMP/rm852"
assert_eq "T-852 (c): remember outside hook mode still says there is nothing to remember" 'no new lines to remember' "$(rm85_rem "$TMP/rm852" 0)"
t; rm85_vault "$TMP/rm853" log
assert_eq "T-852 (c): remember outside hook mode still reports the note it wrote" 'yes' \
  "$(rm85_rem "$TMP/rm853" 0 | grep -q '^wrote: ' && printf yes || printf no)"

# (b) each adapter's SessionStart command, run as shipped through sh -c, is one JSON object.
mkdir -p "$TMP/rm85bin"
printf '#!/bin/sh\nexec sh "%s/knotlog" "$@"\n' "$ROOT" > "$TMP/rm85bin/knotlog"; chmod +x "$TMP/rm85bin/knotlog"
for _rm_a in claude-code.json codex/hooks.json gemini/settings.json cursor/hooks.json antigravity/hooks.json; do
  _rm_cmd=$(grep -m1 '"command": "[^"]*context --json SessionStart' "$ROOT/adapters/$_rm_a" | sed 's/.*"command": "\([^"]*\)".*/\1/')
  for _rm_k in idle log; do
    rm85_vault "$TMP/rm85b" "$_rm_k"
    t; _rm_out=$(QUIPU_LANG=en QUIPU_VAULT="$TMP/rm85b" PATH="$TMP/rm85bin:$PATH" sh -c "$_rm_cmd" 2>/dev/null </dev/null)
    assert_eq "T-851 (b): $_rm_a SessionStart ($_rm_k) prints one JSON object" 'yes' \
      "$(case "$_rm_out" in ('{'*'}') [ "$(ag84_balanced "$_rm_out")" = yes ] && [ "$(printf '%s\n' "$_rm_out" | wc -l | tr -d ' ')" = 1 ] && printf yes || printf no ;; (*) printf no ;; esac)"
  done
done
t; assert_eq "T-853: the antigravity SessionStart command starts with remember and allows 30 s" 'yes' \
  "$(grep -qF '"command": "KNOTLOG_HOOK=1 knotlog remember && KNOTLOG_HOOK=1 knotlog context --json SessionStart --antigravity", "timeout": 30' "$ROOT/adapters/antigravity/hooks.json" && printf yes || printf no)"

# ---- knotlog mcp: stdio server core (T-860..T-869) -------------------------
mc86_run() { # requests-file -> stdout of `knotlog mcp < file` (stderr to $TMP/mc86.err)
  QUIPU_LANG=en sh "$ROOT/knotlog" mcp < "$1" 2>"$TMP/mc86.err"
}
mc86_lines_ok() { # file -> yes when every line is one balanced JSON-RPC 2.0 object
  _mc_bad=0
  while IFS= read -r _mc_l; do
    case "$_mc_l" in '{"jsonrpc":"2.0",'*'}') [ "$(ag84_balanced "$_mc_l")" = yes ] || _mc_bad=1 ;; *) _mc_bad=1 ;; esac
  done < "$1"
  [ "$_mc_bad" = 0 ] && printf yes || printf no
}
MC="$TMP/mc86"; mkdir -p "$MC"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' > "$MC/legacy.jsonl"
mc86_run "$MC/legacy.jsonl" > "$MC/legacy.out"; mc_rc=$?
t; assert_eq "T-860: legacy initialize -> initialized -> tools/list gives exactly two replies, none for the notification" '2' "$(wc -l < "$MC/legacy.out" | tr -d ' ')"
t; assert_eq "T-860: initialize echoes the client's known protocolVersion with tools capability and serverInfo" 'yes' \
  "$(sed -n 1p "$MC/legacy.out" | grep -qF '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"knotlog","version":"' && printf yes || printf no)"
t; assert_eq "T-860: tools/list names knotlog_search and knotlog_context, query is the only required argument" 'yes' \
  "$(sed -n 2p "$MC/legacy.out" | grep -qF '"name":"knotlog_search"' && sed -n 2p "$MC/legacy.out" | grep -qF '"name":"knotlog_context"' \
     && sed -n 2p "$MC/legacy.out" | grep -qF '"required":["query"]' && sed -n 2p "$MC/legacy.out" | grep -qF '"limit":{"type":"integer"' && printf yes || printf no)"
t; assert_eq "T-860: legacy tools/list carries no resultType" 'no' "$(sed -n 2p "$MC/legacy.out" | grep -qF resultType && printf yes || printf no)"
t; assert_eq "T-860: EOF on stdin exits 0" '0' "$mc_rc"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}' > "$MC/oldver.jsonl"
t; assert_eq "T-860: an unknown client protocolVersion is answered with the newest legacy one" 'yes' \
  "$(mc86_run "$MC/oldver.jsonl" | grep -qF '"protocolVersion":"2025-11-25"' && printf yes || printf no)"
M_META='"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}'
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"disc-1","method":"server/discover","params":{'"$M_META"'}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{'"$M_META"'}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"1900-01-01"}}}' > "$MC/modern.jsonl"
mc86_run "$MC/modern.jsonl" > "$MC/modern.out"
t; assert_eq "T-861: server/discover returns supportedVersions, tools capability, serverInfo and cache hints" 'yes' \
  "$(sed -n 1p "$MC/modern.out" | grep -qF '"id":"disc-1","result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{"tools":{}},"_meta":{"io.modelcontextprotocol/serverInfo":{"name":"knotlog"' \
     && sed -n 1p "$MC/modern.out" | grep -qF '"ttlMs":3600000,"cacheScope":"public"' && printf yes || printf no)"
t; assert_eq "T-861: a modern tools/list is complete, lists both tools and has cache hints" 'yes' \
  "$(sed -n 2p "$MC/modern.out" | grep -qF '"result":{"resultType":"complete","tools":[{"name":"knotlog_search"' && sed -n 2p "$MC/modern.out" | grep -qF '"name":"knotlog_context"' \
     && sed -n 2p "$MC/modern.out" | grep -qF '"cacheScope":"public"' && printf yes || printf no)"
t; assert_eq "T-861: an unsupported _meta protocolVersion gets -32022 listing what is supported" 'yes' \
  "$(sed -n 3p "$MC/modern.out" | grep -qF '"error":{"code":-32022,"message":"Unsupported protocol version","data":{"supported":["2026-07-28"],"requested":"1900-01-01"}}' && printf yes || printf no)"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":3,"method":"no/such"}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"no_such_tool"}}' \
  '{"jsonrpc":"2.0","method":"no/such"}' \
  '{"jsonrpc":"2.0","method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":5,"result":{}}' \
  '{"jsonrpc":"2.0","id":6,"method":"ping"}' > "$MC/err.jsonl"
mc86_run "$MC/err.jsonl" > "$MC/err.out"
t; assert_eq "T-862: replies exist only for the four requests (notifications and a client response stay silent)" '3' "$(wc -l < "$MC/err.out" | tr -d ' ')"
t; assert_eq "T-862: an unknown method is -32601 with the request id" 'yes' \
  "$(sed -n 1p "$MC/err.out" | grep -qF '{"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"Method not found"}}' && printf yes || printf no)"
t; assert_eq "T-862: tools/call with an unknown tool is -32602 (invalid params), not method not found" 'yes' \
  "$(sed -n 2p "$MC/err.out" | grep -qF '"id":4,"error":{"code":-32602,"message":"Unknown tool: no_such_tool"}' && printf yes || printf no)"
t; assert_eq "T-862: ping returns an empty result" 'yes' \
  "$(sed -n 3p "$MC/err.out" | grep -qF '{"jsonrpc":"2.0","id":6,"result":{}}' && printf yes || printf no)"
printf '%s\n' '{bad json' 'not json' '[1,2]' '{"jsonrpc":"2.0","id":8}' '{"jsonrpc":"2.0"}' '' > "$MC/bad.jsonl"
mc86_run "$MC/bad.jsonl" > "$MC/bad.out"
t; assert_eq "T-863: broken JSON is -32700 with id null" 'yes' \
  "$(sed -n 1p "$MC/bad.out" | grep -qF '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}' && sed -n 2p "$MC/bad.out" | grep -qF '"code":-32700' && printf yes || printf no)"
t; assert_eq "T-863: a batch array and an object with neither id nor method are -32600 with id null; a bare response and blank lines are skipped" 'yes' \
  "$(sed -n 3p "$MC/bad.out" | grep -qF '"id":null,"error":{"code":-32600' && sed -n 4p "$MC/bad.out" | grep -qF '"id":null,"error":{"code":-32600' \
     && [ "$(wc -l < "$MC/bad.out" | tr -d ' ')" = 4 ] && printf yes || printf no)"
printf '%s\r\n' '{"jsonrpc":"2.0","id":7,"method":"ping"}' '{"jsonrpc":"2.0","id":"x\"y 1","method":"ping"}' '{"method":"id","id":9}' > "$MC/crlf.jsonl"
mc86_run "$MC/crlf.jsonl" > "$MC/crlf.out"
t; assert_eq "T-864: numeric and string ids come back unchanged, CR at the end of a line is trimmed" 'yes' \
  "$(sed -n 1p "$MC/crlf.out" | grep -qF '{"jsonrpc":"2.0","id":7,"result":{}}' && sed -n 2p "$MC/crlf.out" | grep -qF '"id":"x\"y 1","result":{}' && printf yes || printf no)"
t; assert_eq "T-864: a method value that equals a key name does not confuse the id lookup" 'yes' \
  "$(sed -n 3p "$MC/crlf.out" | grep -qF '"id":9,"error":{"code":-32601' && printf yes || printf no)"
cat "$MC/legacy.jsonl" "$MC/modern.jsonl" "$MC/err.jsonl" "$MC/bad.jsonl" "$MC/crlf.jsonl" > "$MC/all.jsonl"
mc86_run "$MC/all.jsonl" > "$MC/all.out"
t; assert_eq "T-865: every stdout line over a mixed run is one balanced JSON-RPC object" 'yes' "$(mc86_lines_ok "$MC/all.out")"
t; assert_eq "T-865: nothing is written to stderr on a normal run" '0' "$(wc -c < "$TMP/mc86.err" | tr -d ' ')"
t; _mc_long=$(awk 'BEGIN { s = "x"; for (i = 0; i < 12; i++) s = s s; print "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"" s "\"}" }')
printf '%s\n' "$_mc_long" '{"jsonrpc":"2.0","id":2,"method":"ping"}' > "$MC/long.jsonl"
assert_eq "T-866: with QUIPU_MAX_STDIN a line over the cap is rejected (-32600), the next line is still served" 'yes' \
  "$(QUIPU_MAX_STDIN=1000 sh "$ROOT/knotlog" mcp < "$MC/long.jsonl" 2>/dev/null > "$MC/long.out"; sed -n 1p "$MC/long.out" | grep -qF '"id":null,"error":{"code":-32600' && sed -n 2p "$MC/long.out" | grep -qF '"id":2,"result":{}' && printf yes || printf no)"
t; sh "$ROOT/knotlog" mcp extra </dev/null >"$MC/arg.out" 2>"$MC/arg.err"; mc_rc=$?
assert_eq "T-867: knotlog mcp with an argument exits 2, stdout stays empty, the reason goes to stderr" 'yes' \
  "$([ "$mc_rc" = 2 ] && [ ! -s "$MC/arg.out" ] && [ -s "$MC/arg.err" ] && printf yes || printf no)"
t; assert_eq "T-868: help lists mcp in English and Turkish" 'yes' \
  "$(QUIPU_LANG=en sh "$ROOT/knotlog" help </dev/null | grep -q '^  mcp ' && sh "$ROOT/knotlog" help --tr </dev/null | grep -q '^  mcp ' && printf yes || printf no)"

# T-869: jf_read decodes uXXXX escapes to UTF-8 (BMP, surrogate pairs, lone surrogates).
BSL=$(printf '\134')   # a backslash that no editor or transport can decode on the way in
uni86() { # json-string-body -> decoded value as hex bytes
  printf '{"x":"%s"}\n' "$1" > "$TMP/uni86.json"
  awk -f "$LIB/jsonfield.awk" -f "$DRV/value.awk" "$TMP/uni86.json" | od -An -v -tx1 | tr -d ' \n'
}
t; assert_eq "T-869: a BMP escape (s-cedilla) becomes two UTF-8 bytes" 'c59f0a' "$(uni86 "${BSL}u015f")"
t; assert_eq "T-869: a three-byte BMP escape (euro sign) and upper-case hex digits" 'e282ac0a' "$(uni86 "${BSL}u20AC")"
t; assert_eq "T-869: ASCII through an escape stays one byte" '410a' "$(uni86 "${BSL}u0041")"
t; assert_eq "T-869: a surrogate pair becomes one four-byte character" 'f09f98800a' "$(uni86 "${BSL}ud83d${BSL}ude00")"
t; assert_eq "T-869: a lone high surrogate becomes U+FFFD and the text after it survives" 'efbfbd780a' "$(uni86 "${BSL}ud83dx")"
t; assert_eq "T-869: a lone low surrogate becomes U+FFFD" 'efbfbd0a' "$(uni86 "${BSL}ude00")"
t; assert_eq "T-869: malformed hex and U+0000 keep the old placeholder" '3f3f0a' "$(uni86 "${BSL}u00zz${BSL}u0000")"
t; assert_eq "T-869: the same bytes come out under the C locale (byte-wise %c)" 'c59ff09f98800a' \
  "$(LC_ALL=C; export LC_ALL; uni86 "${BSL}u015f${BSL}ud83d${BSL}ude00")"

# ---- knotlog mcp: tools/call (T-870..T-879) --------------------------------
M7="$TMP/mc87"; rm -rf "$M7"; mkdir -p "$M7/vault/notes"
(cd "$M7/vault" && QUIPU_LANG=en sh "$ROOT/knotlog" init </dev/null >/dev/null 2>&1)
printf '# Alpha\nzebra apples are great\n' > "$M7/vault/notes/a.md"
printf '# Beta\nzebra bananas rock\n' > "$M7/vault/notes/b.md"
printf '# Gamma\nzebra cherry\n' > "$M7/vault/notes/c.md"
printf '# Seker\nşeker sweet\n' > "$M7/vault/notes/s.md"
QUIPU_LANG=en QUIPU_VAULT="$M7/vault" sh "$ROOT/knotlog" index </dev/null >/dev/null 2>&1
mc87_cli() { QUIPU_LANG=en QUIPU_VAULT="$M7/vault" sh "$ROOT/knotlog" "$@" </dev/null 2>/dev/null; }
mc87_call() { # file-of-requests -> stdout of knotlog mcp on the test vault
  QUIPU_LANG=en QUIPU_VAULT="$M7/vault" sh "$ROOT/knotlog" mcp < "$1" 2>/dev/null
}
mc87_text() { # reply-line-number outfile < replies -> exact text of the tool result
  sed -n "$1p" "$2" | awk -f "$LIB/jsonfield.awk" -f "$DRV/mcptext.awk"
}
mc87_req() { # id name arguments-json
  printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' "$1" "$2" "$3"
}
{
  mc87_req 1 knotlog_search '{"query":"zebra"}'
  mc87_req 2 knotlog_search '{"query":"zebra","limit":1}'
  mc87_req 3 knotlog_search "{\"query\":\"${BSL}u015feker\"}"
  mc87_req 4 knotlog_context '{}'
  printf '%s\n' '{"jsonrpc":"2.0","id":5,"method":"ping"}'
} > "$M7/ok.jsonl"
mc87_call "$M7/ok.jsonl" > "$M7/ok.out"
mc87_cli search --brief zebra > "$M7/cli1.txt"
mc87_cli search --brief --limit 1 zebra > "$M7/cli2.txt"
mc87_cli search --brief "şeker" > "$M7/cli3.txt"
mc87_cli context | sed 1d > "$M7/cli4.txt"
mc87_text 1 "$M7/ok.out" > "$M7/mcp1.txt"; mc87_text 2 "$M7/ok.out" > "$M7/mcp2.txt"; mc87_text 3 "$M7/ok.out" > "$M7/mcp3.txt"
mc87_text 4 "$M7/ok.out" | sed 1d > "$M7/mcp4.txt"
t; assert_eq "T-870: the CLI itself finds the three zebra notes (the fixture is real)" '3' "$(wc -l < "$M7/cli1.txt" | tr -d ' ')"
t; assert_eq "T-870: knotlog_search text is byte-identical to knotlog search --brief" 'yes' "$(cmp -s "$M7/cli1.txt" "$M7/mcp1.txt" && printf yes || printf no)"
t; assert_eq "T-870: the reply is a text content item with isError false" 'yes' \
  "$(sed -n 1p "$M7/ok.out" | grep -qF '{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"' && sed -n 1p "$M7/ok.out" | grep -qF '"isError":false}}' && printf yes || printf no)"
t; assert_eq "T-871: limit 1 returns one row, identical to the CLI with --limit 1" 'yes' \
  "$([ "$(wc -l < "$M7/mcp2.txt" | tr -d ' ')" = 1 ] && cmp -s "$M7/cli2.txt" "$M7/mcp2.txt" && printf yes || printf no)"
t; assert_eq "T-872: a uXXXX escape in the query reaches the CLI as UTF-8 (s-cedilla finds the note)" 'yes' \
  "$([ -s "$M7/cli3.txt" ] && cmp -s "$M7/cli3.txt" "$M7/mcp3.txt" && printf yes || printf no)"
t; assert_eq "T-873: knotlog_context returns the plain context text (same as the CLI past the clock line)" 'yes' \
  "$([ -s "$M7/cli4.txt" ] && cmp -s "$M7/cli4.txt" "$M7/mcp4.txt" && printf yes || printf no)"
t; assert_eq "T-874: the request after a tool call is still answered (children never read the MCP stdin)" 'yes' \
  "$(sed -n 5p "$M7/ok.out" | grep -qF '{"jsonrpc":"2.0","id":5,"result":{}}' && printf yes || printf no)"
t; assert_eq "T-874: every stdout line of the tool run is one balanced JSON-RPC object" 'yes' "$(mc86_lines_ok "$M7/ok.out")"
{
  mc87_req 1 knotlog_search '{}'
  mc87_req 2 knotlog_search '{"query":7}'
  mc87_req 3 knotlog_search '{"query":"zebra","limit":"2"}'
  mc87_req 4 knotlog_search '{"query":"zebra","limit":1.5}'
  mc87_req 5 no_such_tool '{}'
  printf '%s\n' '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"arguments":{}}}' '{"jsonrpc":"2.0","id":7,"method":"tools/call"}'
  mc87_req 8 knotlog_search '{"query":"zebra","limit":0}'
  mc87_req 9 knotlog_search '{"query":"-x"}'
  mc87_req 10 knotlog_search '{"query":""}'
} > "$M7/bad.jsonl"
mc87_call "$M7/bad.jsonl" > "$M7/bad.out"
t; assert_eq "T-875: wrong-shaped arguments, an unknown tool and a missing name are protocol errors (-32602)" '7' "$(grep -c '"error":{"code":-32602' "$M7/bad.out" | tr -d ' ')"
t; assert_eq "T-875: the unknown-tool error names the tool" 'yes' "$(sed -n 5p "$M7/bad.out" | grep -qF '"message":"Unknown tool: no_such_tool"' && printf yes || printf no)"
t; assert_eq "T-875: a value problem (limit 0, dash-leading query, empty query) is a tool result with isError true" 'yes' \
  "$(sed -n 8p "$M7/bad.out" | grep -qF '"isError":true' && sed -n 9p "$M7/bad.out" | grep -qF '"isError":true' && sed -n 10p "$M7/bad.out" | grep -qF '"isError":true' && printf yes || printf no)"
t; assert_eq "T-875: the CLI's own stderr message comes back inside the isError text" 'yes' "$(sed -n 10p "$M7/bad.out" | grep -qi 'query' && printf yes || printf no)"
t; assert_eq "T-875: every stdout line of the error run is one balanced JSON-RPC object" 'yes' "$(mc86_lines_ok "$M7/bad.out")"
# A vault that has no index: search fails inside the CLI; its stderr must not reach stdout.
mkdir -p "$M7/empty/.knotlog"; : > "$M7/empty/.knotlog/config"
mc87_req 1 knotlog_search '{"query":"zebra"}' > "$M7/noidx.jsonl"
QUIPU_LANG=en QUIPU_VAULT="$M7/empty" sh "$ROOT/knotlog" mcp < "$M7/noidx.jsonl" > "$M7/noidx.out" 2> "$M7/noidx.err"
t; assert_eq "T-876: a failing tool is isError true with the CLI message in the text, stdout stays clean JSON" 'yes' \
  "$(grep -qF '"isError":true' "$M7/noidx.out" && [ "$(mc86_lines_ok "$M7/noidx.out")" = yes ] && [ "$(wc -l < "$M7/noidx.out" | tr -d ' ')" = 1 ] && printf yes || printf no)"
t; assert_eq "T-876: the scratch file of the failing call is the only place its stderr went (nothing on mcp's own stderr)" '0' "$(wc -c < "$M7/noidx.err" | tr -d ' ')"
# Shell metacharacters in a query are data: no file may appear.
PWN="$M7/pwned"
{
  mc87_req 1 knotlog_search "{\"query\":\"x'; touch $PWN.1; \$(touch $PWN.2) \`touch $PWN.3\` | touch $PWN.4 & touch $PWN.5\"}"
  mc87_req 2 knotlog_search "{\"query\":\"it's zebra\"}"
  mc87_req 3 knotlog_search "{\"query\":\"a ${BSL}\"; touch $PWN.6; ${BSL}\" b\"}"
  mc87_req 4 knotlog_search "{\"query\":\"zebra\",\"limit\":2}, \"x\":\"'; touch $PWN.7; '\"}"
  mc87_req 5 knotlog_search "{\"query\":\"zebra\",\"limit\":2; touch $PWN.8}"
} > "$M7/inj.jsonl"
mc87_call "$M7/inj.jsonl" > "$M7/inj.out"
t; assert_eq "T-877: shell metacharacters in the query create no file (eight attempts)" '0' "$(find "$M7" -name 'pwned*' | wc -l | tr -d ' ')"
t; assert_eq "T-877: every injection reply is still one balanced JSON-RPC object" 'yes' "$(mc86_lines_ok "$M7/inj.out")"
mc87_cli search --brief "it's zebra" > "$M7/cli5.txt"; mc87_text 2 "$M7/inj.out" > "$M7/mcp5.txt"
t; assert_eq "T-877: a query with an apostrophe is passed through intact (same text as the CLI)" 'yes' "$(cmp -s "$M7/cli5.txt" "$M7/mcp5.txt" && printf yes || printf no)"
# Modern era: the result carries resultType complete.
mc87_req 1 knotlog_search '{"query":"zebra"}' | sed 's|"params":{|"params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"},|' > "$M7/modern.jsonl"
mc87_call "$M7/modern.jsonl" > "$M7/modern.out"
t; assert_eq "T-878: a modern-era tools/call result carries resultType complete" 'yes' "$(grep -qF '"result":{"resultType":"complete","content":[' "$M7/modern.out" && printf yes || printf no)"

# Rename completeness (roadmap 2.6): a freshly seeded vault must not show the old product name anywhere.
# Exempt: `.knotlog/` (machine state). Nothing else is exempt -- backward compatibility lives in the code, not in seeded files.
# RENAME-BLOCK-START
for L in en tr; do
  RV="$TMP/rename-$L"; mkdir -p "$RV-home"
  HOME="$RV-home" KNOTLOG_VAULT="$RV" sh "$ROOT/knotlog" init --no-prompt --lang "$L" > "$RV.out" 2>&1
  t; assert_eq "T-880: init --lang $L seeds a vault (rules seeded, more than 10 files)" 'yes' "$([ "$(find "$RV" -path "$RV/.knotlog" -prune -o -type f -print | wc -l)" -gt 10 ] && printf yes || printf no)"
  t; assert_eq "T-880: init --lang $L leaves no 'quipu' in any seeded file (outside .knotlog/)" '' \
    "$(cd "$RV" && find . -path ./.knotlog -prune -o -type f -print | while IFS= read -r f; do grep -il quipu "$f"; done)"
done
# RENAME-BLOCK-END

# ---- knotlog mcp: a client's signal ends the server at once (T-890..T-893) ----
# Claude Code stops a stdio server with SIGINT, then SIGTERM, then SIGKILL. The server
# must leave on the first one while stdin is still open, and must not leak its scratch file.
# `set -m` makes the background jobs keep default signal handlers; without it a non-interactive
# sh starts them with SIGINT ignored and the INT trap could never fire. It cannot undo a SIGINT
# that was already ignored when run.sh started (CI steps do this), and no POSIX sh can trap such
# a signal, so perl, when present, restores the default in the server's process before the exec.
SG="$TMP/mc89"; mkdir -p "$SG"
MC89_RS=''
if command -v perl >/dev/null 2>&1; then
  printf '%s\n' '$SIG{INT} = "DEFAULT"; exec @ARGV;' > "$SG/reset-int.pl"
  MC89_RS="perl $SG/reset-int.pl"
fi
mc89_start() { # name -> starts a server whose stdin stays open for 2 s; its pid is left in MC89_PID
  mkdir -p "$SG/$1"
  { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"ping"}'; sleep 2; } \
    | TMPDIR="$SG/$1" QUIPU_LANG=en $MC89_RS sh "$ROOT/knotlog" mcp > "$SG/$1/out" 2>/dev/null &
  MC89_PID=$!
}
mc89_up() { # name -> yes once the first reply is on stdout (3 s at most)
  _i=0; while [ ! -s "$SG/$1/out" ] && [ "$_i" -lt 30 ]; do sleep 0.1 2>/dev/null || sleep 1; _i=$((_i + 1)); done
  [ -s "$SG/$1/out" ] && printf yes || printf no
}
mc89_alive() { # pid -> success while the process runs; an unreaped zombie (dash reaps late) is gone
  kill -0 "$1" 2>/dev/null || return 1
  case $(ps -o stat= -p "$1" 2>/dev/null) in Z*) return 1 ;; esac
}
mc89_gone() { # pid -> yes when the process is gone within 1 s
  _i=0; while mc89_alive "$1" && [ "$_i" -lt 10 ]; do sleep 0.1 2>/dev/null || sleep 1; _i=$((_i + 1)); done
  mc89_alive "$1" && printf no || printf yes
}
set -m
mc89_start term; P_TERM=$MC89_PID
mc89_start int;  P_INT=$MC89_PID
mc89_start hup;  P_HUP=$MC89_PID
set +m
UP_TERM=$(mc89_up term); UP_INT=$(mc89_up int); UP_HUP=$(mc89_up hup)
kill -TERM "$P_TERM" 2>/dev/null; kill -INT "$P_INT" 2>/dev/null; kill -HUP "$P_HUP" 2>/dev/null
GONE_TERM=$(mc89_gone "$P_TERM"); GONE_INT=$(mc89_gone "$P_INT"); GONE_HUP=$(mc89_gone "$P_HUP")
# Anything still alive is cleaned up by pid only (never by name) so a failure cannot leave a process behind.
for _p in "$P_TERM" "$P_INT" "$P_HUP"; do kill -0 "$_p" 2>/dev/null && kill -KILL "$_p" 2>/dev/null; done
wait "$P_TERM"; RC_TERM=$?; wait "$P_INT"; RC_INT=$?; wait "$P_HUP"; RC_HUP=$?
wait
t; assert_eq "T-890: the server answers before the signal (stdin is open and held by the feeder)" 'yes yes yes' "$UP_TERM $UP_INT $UP_HUP"
t; assert_eq "T-891: SIGTERM ends the server within a second, exit status 143" 'yes 143' "$GONE_TERM $RC_TERM"
t; assert_eq "T-892: SIGINT ends the server within a second, exit status 130" 'yes 130' "$GONE_INT $RC_INT"
t; assert_eq "T-892: SIGHUP ends the server within a second, exit status 129" 'yes 129' "$GONE_HUP $RC_HUP"
t; assert_eq "T-893: no scratch file is left behind after any of the three signals" '0' \
  "$(find "$SG/term" "$SG/int" "$SG/hup" -name 'knotlog-mcp-*' | wc -l | tr -d ' ')"
t; assert_eq "T-893: the test left no server running" 'no no no' \
  "$(for _p in "$P_TERM" "$P_INT" "$P_HUP"; do kill -0 "$_p" 2>/dev/null && printf 'yes ' || printf 'no '; done | sed 's/ $//')"

# ---- validity: rejected — hidden from search and compile unless --all (T-900..T-909) ----
mkvault vrej
printf 'lang=en\nlayout=en\n' > "$TMP/vrej/.knotlog/config"
mkdir -p "$TMP/vrej/notes"
rej_note() { # name validity-line body-heading
  { printf -- '---\ntitle: %s\n' "$1"; [ -z "$2" ] || printf '%s\n' "$2"; printf -- '---\n# %s\n\nzebrafish note\n' "$3"; } > "$TMP/vrej/notes/$1.md"
}
rej_note plain ''                        Okapiheading
rej_note rejected 'validity: rejected'   Quokkaheading
rej_note upper 'validity: REJECTED'      Upperheading
rej_note quoted 'validity:   " Rejected " ' Quotedheading
rej_note single "validity: 'rejected'"   Singleheading
rej_note accepted 'validity: accepted'   Acceptedheading
rej_note lookalike 'validity: rejectedish' Lookalikeheading
{
  printf -- '---\ntitle: longrej\nvalidity: rejected\n---\n# longrej\n\n'
  awk 'BEGIN { for (i = 0; i < 400; i++) printf "filler%d words ", i; print "" }'
  printf 'tailquokka\n'
} > "$TMP/vrej/notes/longrej.md"
vrej() { QUIPU_VAULT="$TMP/vrej" sh "$ROOT/knotlog" "$@"; }
t; vrej index >/dev/null 2>&1
t; assert_eq "T-900: default search hides rejected notes in any spelling of the value" 'notes/accepted.md notes/lookalike.md notes/plain.md' \
  "$(vrej search zebrafish --paths | sort | tr '\n' ' ' | sed 's/ $//')"
t; assert_eq "T-901: search --all shows them too" '7' "$(vrej search zebrafish --all --limit 20 --paths | awk 'END{print NR}')"
t; assert_eq "T-902: a rejected note stays on disk and in index.tsv" 'yes' \
  "$([ -f "$TMP/vrej/notes/rejected.md" ] && awk -F"$TAB" '$1=="notes/rejected.md"{f=1} END{print f ? "yes" : "no"}' "$TMP/vrej/.knotlog/index.tsv")"
t; assert_eq "T-903: rejected block rows are skipped by default" '' "$(vrej search tailquokka --paths)"
t; assert_eq "T-904: ... and found with --all" 'notes/longrej.md' "$(vrej search tailquokka --all --paths)"
t; vrej compile >/dev/null 2>&1
t; assert_eq "T-905: compile derives concepts from non-rejected notes" '3' \
  "$(find "$TMP/vrej" -type f \( -iname 'Okapiheading*' -o -iname 'Acceptedheading*' -o -iname 'Lookalikeheading*' \) | awk 'END{print NR}')"
t; assert_eq "T-906: compile skips rejected notes" '0' \
  "$(find "$TMP/vrej" -type f \( -iname 'Quokkaheading*' -o -iname 'Upperheading*' -o -iname 'Quotedheading*' -o -iname 'Singleheading*' \) | awk 'END{print NR}')"
printf '2\n' > "$TMP/vrej/.knotlog/index.schema"
vrej index > "$TMP/vrej-reindex.out" 2>&1
t; assert_eq "T-907: an index built with the old row shape (schema 2) is rebuilt in full" '8 0 8 0' "$(idx_nums "$TMP/vrej-reindex.out")"
t; assert_eq "T-908: help documents --all in English and Turkish" 'yes yes' \
  "$(vrej help | grep -q -e 'search .*--all' && printf yes || printf no) $(grep -q '^usage_search=.*--all' "$ROOT/i18n/tr.txt" && printf yes || printf no)"

# T-910..T-913: the kaomoji tone preset (ninth slug)
mkvault vkao
printf 'lang=tr\n' > "$TMP/vkao/.knotlog/config"
QUIPU_VAULT="$TMP/vkao" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
t; assert_eq "T-910: tone --list shows kaomoji in Turkish and English" 'yes yes' \
  "$( (cd "$TMP/vkao" && "$ROOT/knotlog" tone --list) | grep -qF "kaomoji" && printf yes || printf no) $( (cd "$TMP/vkao" && QUIPU_LANG=en "$ROOT/knotlog" tone --list) | grep -qF "$(men tone_desc_kaomoji)" && printf yes || printf no)"
t; (cd "$TMP/vkao" && "$ROOT/knotlog" tone kaomoji) >/dev/null 2>&1; RC=$?
t; assert_eq "T-911: tone kaomoji exits 0 and writes tone=kaomoji" '0 yes' \
  "$RC $(grep -qxF 'tone=kaomoji' "$TMP/vkao/.knotlog/config" && printf yes || printf no)"
t; assert_eq "T-912: context carries the kaomoji preset text in both languages" 'yes yes' \
  "$(QUIPU_VAULT="$TMP/vkao" sh "$ROOT/knotlog" context | grep -qF 'resimli emoji asla' && printf yes || printf no) $(QUIPU_LANG=en QUIPU_VAULT="$TMP/vkao" sh "$ROOT/knotlog" context | grep -qF 'never pictorial emoji' && printf yes || printf no)"
t; (cd "$TMP/vkao" && "$ROOT/knotlog" tone bilmiyorum) >"$TMP/vkao.out" 2>&1
t; assert_eq "T-913: the unknown-slug error lists kaomoji" 'yes' \
  "$(grep -qF 'ogretici kaomoji)' "$TMP/vkao.out" && printf yes || printf no)"

# T-920..T-929: size limit for the last-session file and the journal
# (doctor warns above companion_max=, default 40000 bytes) and `compact`
# moving old "## " session blocks (oldest first, newest N stay) to an archive.
cs_session() { # file blocks -> preamble + N "## " blocks, newest at the bottom
  {
    printf '# Sessions\n\n'
    _cs_i=1
    while [ "$_cs_i" -le "$2" ]; do
      printf '## block %d\nbody %d\n\n' "$_cs_i" "$_cs_i"
      _cs_i=$((_cs_i + 1))
    done
  } > "$1"
}
cs_doc() { # vault -> doctor output, ambient HOME isolated
  mkdir -p "$TMP/cs-home"
  QUIPU_VAULT="$1" QUIPU_HOME="$ROOT" HOME="$TMP/cs-home" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1
}
cs_archive() { find "$1" -name 'Last-Session-Archive.md' | head -1; }
mkvault vcs
cs_session "$TMP/vcs/Last-Session.md" 3
printf '# Journal\n' > "$TMP/vcs/Journal.md"
cs_doc "$TMP/vcs" > "$TMP/cs-doc-small.out"
t; assert_eq "T-920: files under the limit print no size warning" 'no' \
  "$(grep -qF "$(men doc_companion_big)" "$TMP/cs-doc-small.out" && printf yes || printf no)"
awk 'BEGIN { for (i = 0; i < 1000; i++) print "filler line to grow the file past forty thousand bytes" }' >> "$TMP/vcs/Last-Session.md"
CS_SZ=$(wc -c < "$TMP/vcs/Last-Session.md" | tr -d ' ')
cs_doc "$TMP/vcs" > "$TMP/cs-doc-big.out"
t; assert_eq "T-921: a last-session file above 40000 bytes warns with name, size, limit and the fix" 'yes' \
  "$(grep -qF "$(memfmt en doc_companion_big_session Last-Session.md "$CS_SZ" 40000)" "$TMP/cs-doc-big.out" && printf yes || printf no)"
printf 'companion_max=200\n' > "$TMP/vcs/.knotlog/config"
awk 'BEGIN { for (i = 0; i < 10; i++) print "journal filler line" }' >> "$TMP/vcs/Journal.md"
JR_SZ=$(wc -c < "$TMP/vcs/Journal.md" | tr -d ' ')
cs_doc "$TMP/vcs" > "$TMP/cs-doc-cfg.out"
t; assert_eq "T-922: companion_max= in config lowers the limit, and the journal is checked too" 'yes yes' \
  "$(grep -qF "$(memfmt en doc_companion_big_session Last-Session.md "$CS_SZ" 200)" "$TMP/cs-doc-cfg.out" && printf yes || printf no) $(grep -qF "$(memfmt en doc_companion_big_journal Journal.md "$JR_SZ" 200)" "$TMP/cs-doc-cfg.out" && printf yes || printf no)"
printf 'companion_max=abc\n' > "$TMP/vcs/.knotlog/config"
cs_doc "$TMP/vcs" > "$TMP/cs-doc-bad.out"
t; assert_eq "T-923: a non-numeric companion_max= falls back to 40000" 'yes' \
  "$(grep -qF "$(memfmt en doc_companion_big_session Last-Session.md "$CS_SZ" 40000)" "$TMP/cs-doc-bad.out" && printf yes || printf no)"

mkvault vcs2
cs_session "$TMP/vcs2/Last-Session.md" 7
{ printf '<!-- quipu:threads:start -->\n### Active threads\n\n### Closed threads\n- one\n<!-- quipu:threads:end -->\n'; } > "$TMP/vcs2/Threads.md"
cp "$TMP/vcs2/Last-Session.md" "$TMP/cs2-orig.md"
cksum "$TMP/vcs2/Last-Session.md" > "$TMP/cs2-before.ck"
cpq "$TMP/vcs2" en compact > "$TMP/cs2-dry.out" 2>&1; RC=$?
cksum "$TMP/vcs2/Last-Session.md" > "$TMP/cs2-after.ck"
t; assert_eq "T-924: dry run reports the oldest 2 of 7 blocks, writes no file and creates no archive" 'yes yes' \
  "$(cmp -s "$TMP/cs2-before.ck" "$TMP/cs2-after.ck" && [ -z "$(cs_archive "$TMP/vcs2")" ] && [ "$RC" = 0 ] && printf yes || printf no) $(grep -qxF "$(memfmt en compact_session_preview 2 7 38 5 Last-Session.md '📦 900-Archive/Last-Session-Archive.md')" "$TMP/cs2-dry.out" && printf yes || printf no)"
cpq "$TMP/vcs2" en compact --apply > "$TMP/cs2-app.out" 2>&1; RC=$?
CS_ARCH=$(cs_archive "$TMP/vcs2")
t; assert_eq "T-925: --apply keeps the newest 5 blocks (preamble intact) and archives the oldest 2 in order" 'yes yes' \
  "$([ "$RC" = 0 ] && [ "$(grep -c '^## ' "$TMP/vcs2/Last-Session.md")" = 5 ] && sed -n 3p "$TMP/vcs2/Last-Session.md" | grep -qx '## block 3' && printf yes || printf no) $(sed -n 2,7p "$CS_ARCH" | tr '\n' '|' | grep -qx '## block 1|body 1||## block 2|body 2||' && sed -n 1p "$CS_ARCH" | grep -q '^<!-- knotlog:compacted [0-9-]* from=Last-Session.md -->$' && printf yes || printf no)"
t; assert_eq "T-926: kept bytes plus archived bytes equal the original" 'yes' \
  "$([ $(( $(wc -c < "$TMP/vcs2/Last-Session.md") + 38 )) -eq "$(wc -c < "$TMP/cs2-orig.md")" ] && [ "$(sed -n '2,7p' "$CS_ARCH" | wc -c | tr -d ' ')" = 38 ] && printf yes || printf no)"
cksum "$TMP/vcs2/Last-Session.md" "$CS_ARCH" > "$TMP/cs2-a1.ck"
cpq "$TMP/vcs2" en compact --apply > "$TMP/cs2-app2.out" 2>&1
cksum "$TMP/vcs2/Last-Session.md" "$CS_ARCH" > "$TMP/cs2-a2.ck"
t; assert_eq "T-927: a second run is a no-op (nothing printed for the session file, nothing changed)" 'yes yes' \
  "$(cmp -s "$TMP/cs2-a1.ck" "$TMP/cs2-a2.ck" && printf yes || printf no) $(grep -qF ' session blocks' "$TMP/cs2-app2.out" && printf no || printf yes)"

mkvault vcs3
cs_session "$TMP/vcs3/Last-Session.md" 5
cp "$TMP/vcs3/Last-Session.md" "$TMP/cs3-orig.md"
cpq "$TMP/vcs3" en compact --apply > /dev/null 2>&1
t; assert_eq "T-928: a file with 5 or fewer blocks is untouched and no archive appears" 'yes' \
  "$(cmp -s "$TMP/cs3-orig.md" "$TMP/vcs3/Last-Session.md" && [ -z "$(cs_archive "$TMP/vcs3")" ] && printf yes || printf no)"
cpq "$TMP/vcs3" en compact --keep 2 --apply > /dev/null 2>&1
t; assert_eq "T-929: --keep N applies to the session blocks too and the tr archive name exists" 'yes yes' \
  "$([ "$(grep -c '^## ' "$TMP/vcs3/Last-Session.md")" = 2 ] && [ "$(grep -c '^## ' "$(cs_archive "$TMP/vcs3")")" = 3 ] && printf yes || printf no) $(grep -q '^session_archive_file=Son-Oturum-Arsivi.md$' "$ROOT/i18n/tr.txt" && printf yes || printf no)"

# ---- handoff cards + merge=union (T-930..) ----
# A hook payload names the session; remember keeps one "## " card per session in
# the last-session file and .gitattributes carries merge=union for it.

hc_mk() { QUIPU_VAULT="$TMP/$1" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain >/dev/null 2>&1; }
hc_ev() { printf '2026-08-20T10:0%s | PostToolUse | Edit | %s.md\n' "$2" "$3" >> "$TMP/$1/.knotlog/activity.log"; }
hc_rem() { printf '%s' "$2" | QUIPU_HOOK=1 QUIPU_VAULT="$TMP/$1" QUIPU_LANG=en sh "$ROOT/knotlog" remember >/dev/null 2>&1; }
hc_cards() { grep -c '^## ' "$TMP/$1/Last-Session.md"; }

hc_mk vhc1
hc_ev vhc1 1 a; hc_rem vhc1 '{"hook_event_name":"SessionEnd","session_id":"aaaa1111-2222","transcript_path":"/h/.claude/p/x.jsonl"}'
hc_ev vhc1 2 b; hc_rem vhc1 '{"hook_event_name":"SessionEnd","session_id":"bbbb3333-4444","transcript_path":"/h/.codex/s/y.jsonl"}'
t; assert_eq "T-930: two session ids give two cards named with client and id8" '2 yes yes' \
  "$(hc_cards vhc1) $(grep -q '^## [0-9-]* [0-9:]* · claude-code · aaaa1111$' "$TMP/vhc1/Last-Session.md" && printf yes || printf no) $(grep -q '^## [0-9-]* [0-9:]* · codex · bbbb3333$' "$TMP/vhc1/Last-Session.md" && printf yes || printf no)"

cp "$TMP/vhc1/Last-Session.md" "$TMP/hc1-before.md"
hc_ev vhc1 3 c; hc_ev vhc1 4 c2; hc_rem vhc1 '{"session_id":"aaaa1111-2222","transcript_path":"/h/.claude/p/x.jsonl"}'
t; assert_eq "T-931: the same id again replaces only its own card (still two cards, new body)" '2 yes 1' \
  "$(hc_cards vhc1) $(grep -q ' · 2 events · ' "$TMP/vhc1/Last-Session.md" && printf yes || printf no) $(grep -c ' · 1 events · ' "$TMP/vhc1/Last-Session.md" | tr -d ' ')"
hc_card() { awk -v id="$2" '/^## /{p = index($0, id)} /^$/{p = 0} p' "$1"; }
t; assert_eq "T-932: the other session's card is byte-identical and the updated card is now the newest (bottom)" 'yes yes' \
  "$([ -n "$(hc_card "$TMP/hc1-before.md" bbbb3333)" ] && [ "$(hc_card "$TMP/hc1-before.md" bbbb3333)" = "$(hc_card "$TMP/vhc1/Last-Session.md" bbbb3333)" ] && printf yes || printf no) $(awk '/^## /{h = $0} END{print h}' "$TMP/vhc1/Last-Session.md" | grep -q 'aaaa1111$' && printf yes || printf no)"

hc_mk vhc2
hc_ev vhc2 1 a; hc_rem vhc2 ''
t; assert_eq "T-933: no id in hook mode keeps the single marked block (no card heading)" '0 1' \
  "$(hc_cards vhc2) $(grep -c 'knotlog:start' "$TMP/vhc2/Last-Session.md")"
hc_ev vhc2 2 b; QUIPU_VAULT="$TMP/vhc2" QUIPU_LANG=en sh "$ROOT/knotlog" remember >/dev/null 2>&1
t; assert_eq "T-934: plain CLI remember still updates the one block in place" '0 1' \
  "$(hc_cards vhc2) $(grep -c 'knotlog:start' "$TMP/vhc2/Last-Session.md")"

hc_ev vhc2 3 c; hc_rem vhc2 '{"session_id":"cccc5555"}'
t; assert_eq "T-935: a card next to an old marked block leaves the block untouched" '1 1 yes' \
  "$(hc_cards vhc2) $(grep -c 'knotlog:start' "$TMP/vhc2/Last-Session.md") $(awk '/knotlog:start/{b=1;next} /knotlog:end/{b=0} b' "$TMP/vhc2/Last-Session.md" | grep -q ' · 1 events · ' && printf yes || printf no)"

hc_mk vhc3
hc_ev vhc3 1 a; hc_rem vhc3 '{"conversation_id":"c0ffee01-2345-6789"}'
hc_ev vhc3 2 b; hc_rem vhc3 '{"trajectory_id":"deadbeef-0001"}'
t; assert_eq "T-936: conversation_id names a cursor card, trajectory_id an antigravity card" 'yes yes' \
  "$(grep -q ' · cursor · c0ffee01$' "$TMP/vhc3/Last-Session.md" && printf yes || printf no) $(grep -q ' · antigravity · deadbeef$' "$TMP/vhc3/Last-Session.md" && printf yes || printf no)"

t; assert_eq "T-937: init creates .gitattributes with merge=union for the session file only (not Threads.md)" 'yes no' \
  "$(grep -Fxq '/Last-Session.md merge=union' "$TMP/vhc3/.gitattributes" && printf yes || printf no) $(grep -q 'Threads' "$TMP/vhc3/.gitattributes" && printf yes || printf no)"
QUIPU_VAULT="$TMP/vhc3" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
t; assert_eq "T-938: a second init does not duplicate the line" '1' "$(grep -c 'merge=union' "$TMP/vhc3/.gitattributes")"

mkdir -p "$TMP/vhc4"; printf '*.png binary' > "$TMP/vhc4/.gitattributes"
QUIPU_VAULT="$TMP/vhc4" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
t; assert_eq "T-939: user lines are kept (even without a final newline) and the union line is appended once" '*.png binary|/Last-Session.md merge=union' \
  "$(paste -sd'|' "$TMP/vhc4/.gitattributes")"

mkdir -p "$TMP/vhc5"; printf 'x\n' > "$TMP/vhc5/Journal.md"
QUIPU_VAULT="$TMP/vhc5" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
t; assert_eq "T-940: an existing journal gets merge=union too" 'yes' \
  "$(grep -Fxq '/Journal.md merge=union' "$TMP/vhc5/.gitattributes" && printf yes || printf no)"

hc_mk vhc6; rm -f "$TMP/vhc6/.gitattributes"; hc_ev vhc6 1 a; hc_rem vhc6 ''
HC_DOC_MSG=$(awk -F= '$1=="doc_union_missing"{sub(/^[^=]*=/,"");print;exit}' "$ROOT/i18n/en.txt")
t; assert_eq "T-941: doctor is silent about merge=union in a vault that is not a git repo" 'no' \
  "$(QUIPU_VAULT="$TMP/vhc6" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1 | grep -qF "$HC_DOC_MSG" && printf yes || printf no)"
(cd "$TMP/vhc6" && git init -q . >/dev/null 2>&1)
t; assert_eq "T-942: doctor warns once in a git vault whose .gitattributes lacks the line" '1' \
  "$(QUIPU_VAULT="$TMP/vhc6" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1 | grep -cF "$HC_DOC_MSG" | tr -d ' ')"
t; assert_eq "T-943: migrate lists the missing line in a dry run and adds it with --apply" 'no yes' \
  "$(QUIPU_VAULT="$TMP/vhc6" QUIPU_LANG=en sh "$ROOT/knotlog" migrate >/dev/null 2>&1; [ -f "$TMP/vhc6/.gitattributes" ] && printf yes || printf no) $(QUIPU_VAULT="$TMP/vhc6" QUIPU_LANG=en sh "$ROOT/knotlog" migrate --apply >/dev/null 2>&1; grep -Fxq '/Last-Session.md merge=union' "$TMP/vhc6/.gitattributes" && printf yes || printf no)"
t; assert_eq "T-944: doctor is silent once the line is there" '0' \
  "$(QUIPU_VAULT="$TMP/vhc6" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1 | grep -cF "$HC_DOC_MSG" | tr -d ' ')"

hc_mk vhc7
hc_ev vhc7 1 w; hc_rem vhc7 '{"session_id":"cccc5555-6666","transcript_path":"C:\\Users\\s\\.claude\\projects\\x.jsonl"}'
t; assert_eq "T-945: a Windows transcript_path (backslashes) still names the client" 'yes' \
  "$(grep -q '^## [0-9-]* [0-9:]* · claude-code · cccc5555$' "$TMP/vhc7/Last-Session.md" && printf yes || printf no)"

# ---- T-950..T-963: update --apply verifies the archive's SHA-256 -------------
# Fixtures live under $TMP/shaf: one good archive with a matching .sha256,
# plus variants. sha_apply HOME URL [flags] runs a tarball --apply offline.
SHAF="$TMP/shaf"
mkdir -p "$SHAF/pkg" "$SHAF/rel"
_q_seed_checkout "$SHAF/pkg/Knotlog-2.8.0" 2.8.0
tar -czf "$SHAF/rel/knotlog-2.8.0.tar.gz" -C "$SHAF/pkg" Knotlog-2.8.0
_q_mk_sha "$SHAF/rel/knotlog-2.8.0.tar.gz"
printf '{"tag_name": "v2.8.0"}\n' > "$SHAF/rel/rel.json"
case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*) SHAURL="file:///$(cygpath -m "$SHAF/rel")" ;;
  *) SHAURL="file://$SHAF/rel" ;;
esac
sha_apply() { # $1 = checkout, $2 = archive file name under rel/, rest = flags
  _sa_h=$1; _sa_f=$2; shift 2
  QUIPU_LANG=en QUIPU_HOME="$_sa_h" QUIPU_RELEASE_API_URL="$SHAURL/rel.json" \
    QUIPU_UPDATE_TARBALL_URL="$SHAURL/$_sa_f" \
    sh "$ROOT/knotlog" update --apply "$@" >"$SHAF/out" 2>"$SHAF/err"
}
sha_untouched() { # $1 = checkout: old version, no staging, no backup
  grep -qF '_q_version=2.7.3' "$1/knotlog" && [ ! -e "$1.quipu-update-staging" ] \
    && [ ! -e "$1.knotlog-previous" ] && printf yes || printf no
}

mkdir -p "$SHAF/ok"; _q_seed_checkout "$SHAF/ok/Knotlog" 2.7.3
t; sha_apply "$SHAF/ok/Knotlog" knotlog-2.8.0.tar.gz; RC950=$?
t; assert_eq "T-950: a matching .sha256 lets the update through" '0 yes' \
  "$RC950 $(grep -qF '_q_version=2.8.0' "$SHAF/ok/Knotlog/knotlog" && printf yes || printf no)"

# The wrong-hash archive is not even a tar: reaching the mismatch message
# proves the hash is checked before anything is extracted.
printf 'not a tarball\n' > "$SHAF/rel/knotlog-9.9.9.tar.gz"
printf '%064d  knotlog-9.9.9.tar.gz\n' 0 > "$SHAF/rel/knotlog-9.9.9.tar.gz.sha256"
mkdir -p "$SHAF/bad"; _q_seed_checkout "$SHAF/bad/Knotlog" 2.7.3
t; sha_apply "$SHAF/bad/Knotlog" knotlog-9.9.9.tar.gz; RC951=$?
t; assert_eq "T-951: a wrong hash refuses before extracting, the tree is untouched" 'yes yes' \
  "$([ "$RC951" -ne 0 ] && grep -qF 'SHA-256 mismatch' "$SHAF/err" && printf yes || printf no) $(sha_untouched "$SHAF/bad/Knotlog")"

cp "$SHAF/rel/knotlog-2.8.0.tar.gz" "$SHAF/rel/knotlog-nosha.tar.gz"
mkdir -p "$SHAF/miss"; _q_seed_checkout "$SHAF/miss/Knotlog" 2.7.3
t; sha_apply "$SHAF/miss/Knotlog" knotlog-nosha.tar.gz; RC952=$?
t; assert_eq "T-952: a missing .sha256 refuses and leaves the tree untouched" 'yes yes' \
  "$([ "$RC952" -ne 0 ] && grep -qF 'no usable SHA-256 file' "$SHAF/err" && printf yes || printf no) $(sha_untouched "$SHAF/miss/Knotlog")"

cp "$SHAF/rel/knotlog-2.8.0.tar.gz" "$SHAF/rel/knotlog-other.tar.gz"
cp "$SHAF/rel/knotlog-2.8.0.tar.gz.sha256" "$SHAF/rel/knotlog-other.tar.gz.sha256"
mkdir -p "$SHAF/name"; _q_seed_checkout "$SHAF/name/Knotlog" 2.7.3
t; sha_apply "$SHAF/name/Knotlog" knotlog-other.tar.gz; RC953=$?
t; assert_eq "T-953: a .sha256 that names another file refuses, tree untouched" 'yes yes' \
  "$([ "$RC953" -ne 0 ] && grep -qF 'names knotlog-2.8.0.tar.gz' "$SHAF/err" && printf yes || printf no) $(sha_untouched "$SHAF/name/Knotlog")"

# CRLF and the binary-mode "*" marker (Windows sha256sum) are accepted.
cp "$SHAF/rel/knotlog-2.8.0.tar.gz" "$SHAF/rel/knotlog-crlf.tar.gz"
printf '%s *knotlog-crlf.tar.gz\r\n' "$(cut -d' ' -f1 "$SHAF/rel/knotlog-2.8.0.tar.gz.sha256")" > "$SHAF/rel/knotlog-crlf.tar.gz.sha256"
mkdir -p "$SHAF/crlf"; _q_seed_checkout "$SHAF/crlf/Knotlog" 2.7.3
t; sha_apply "$SHAF/crlf/Knotlog" knotlog-crlf.tar.gz; RC954=$?
t; assert_eq "T-954: a CRLF .sha256 with a binary-mode marker is accepted" '0' "$RC954"

# No hash tool on PATH: every other tool is linked, the three hashers are not.
case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*) t; skip "T-955: no hash tool refuses" "PATH trick needs POSIX symlinks" ;;
  *)
    SHAB="$SHAF/nohash"; mkdir -p "$SHAB"
    _sa_oifs=$IFS; IFS=:
    for _sa_d in $PATH; do
      for _sa_p in "$_sa_d"/*; do
        _sa_n=${_sa_p##*/}
        case $_sa_n in sha256sum|shasum|openssl) continue ;; esac
        [ -x "$_sa_p" ] && [ ! -d "$_sa_p" ] && [ ! -e "$SHAB/$_sa_n" ] && ln -s "$_sa_p" "$SHAB/$_sa_n"
      done
    done
    IFS=$_sa_oifs
    mkdir -p "$SHAF/nh"; _q_seed_checkout "$SHAF/nh/Knotlog" 2.7.3
    t; (PATH="$SHAB"; sha_apply "$SHAF/nh/Knotlog" knotlog-2.8.0.tar.gz); RC955=$?
    t; assert_eq "T-955: no SHA-256 tool refuses before downloading, tree untouched" 'yes yes' \
      "$([ "$RC955" -ne 0 ] && grep -qF 'no SHA-256 tool' "$SHAF/err" && printf yes || printf no) $(sha_untouched "$SHAF/nh/Knotlog")"
    t; (PATH="$SHAB"; sha_apply "$SHAF/nh/Knotlog" knotlog-nosha.tar.gz --no-verify); RC956=$?
    t; assert_eq "T-956: --no-verify skips the check (no tool, no .sha256)" '0' "$RC956"
    ;;
esac

# A half-finished rollback (fixed-name tmp tree) blocks update; a leftover
# update staging dir is covered by T-522.
mkdir -p "$SHAF/rb"; _q_seed_checkout "$SHAF/rb/Knotlog" 2.7.3
mkdir -p "$SHAF/rb/Knotlog.quipu-rollback-tmp"
t; sha_apply "$SHAF/rb/Knotlog" knotlog-2.8.0.tar.gz; RC957=$?
t; assert_eq "T-957: a leftover rollback tree refuses and is left in place" 'yes yes yes' \
  "$([ "$RC957" -ne 0 ] && grep -qF 'rollback was interrupted' "$SHAF/err" && printf yes || printf no) $([ -d "$SHAF/rb/Knotlog.quipu-rollback-tmp" ] && printf yes || printf no) $(grep -qF '_q_version=2.7.3' "$SHAF/rb/Knotlog/knotlog" && printf yes || printf no)"

# Free space: a df that reports 1 KB refuses; one that prints junk is skipped.
SHADF="$SHAF/dfbin"; mkdir -p "$SHADF"
printf '#!/bin/sh\nprintf "Filesystem 1024-blocks Used Available Capacity Mounted\\nx 100 99 1 99%% /\\n"\n' > "$SHADF/df"
chmod +x "$SHADF/df"
mkdir -p "$SHAF/sp"; _q_seed_checkout "$SHAF/sp/Knotlog" 2.7.3
t; (PATH="$SHADF:$PATH"; sha_apply "$SHAF/sp/Knotlog" knotlog-2.8.0.tar.gz); RC958=$?
t; assert_eq "T-958: too little free space refuses before downloading, tree untouched" 'yes yes' \
  "$([ "$RC958" -ne 0 ] && grep -qF 'not enough free space' "$SHAF/err" && printf yes || printf no) $(sha_untouched "$SHAF/sp/Knotlog")"
printf '#!/bin/sh\necho garbage\n' > "$SHADF/df"
mkdir -p "$SHAF/sp2"; _q_seed_checkout "$SHAF/sp2/Knotlog" 2.7.3
t; (PATH="$SHADF:$PATH"; sha_apply "$SHAF/sp2/Knotlog" knotlog-2.8.0.tar.gz); RC959=$?
t; assert_eq "T-959: unusable df output is skipped silently" '0' "$RC959"

# Read-only parent: the swap renames the checkout inside it. Root ignores
# permissions, so the check is skipped for root and on Windows.
mkdir -p "$SHAF/ro"; _q_seed_checkout "$SHAF/ro/Knotlog" 2.7.3
case $(uname -s) in MINGW*|MSYS*|CYGWIN*) _sa_skip=1 ;; *) _sa_skip=0 ;; esac
[ "$(id -u 2>/dev/null)" != 0 ] || _sa_skip=1
if [ "$_sa_skip" -eq 1 ]; then
  t; skip "T-960: a read-only parent directory refuses" "needs a non-root POSIX user"
else
  chmod 555 "$SHAF/ro"
  t; sha_apply "$SHAF/ro/Knotlog" knotlog-2.8.0.tar.gz; RC960=$?
  chmod 755 "$SHAF/ro"
  t; assert_eq "T-960: a read-only parent directory refuses, tree untouched" 'yes yes' \
    "$([ "$RC960" -ne 0 ] && grep -qF 'not writable' "$SHAF/err" && printf yes || printf no) $(grep -qF '_q_version=2.7.3' "$SHAF/ro/Knotlog/knotlog" && printf yes || printf no)"
fi

# The default download address is the release's own asset, never taken from the reply.
t; assert_eq "T-961: the default archive URL is the release's knotlog-<version>.tar.gz asset" 'yes' \
  "$(grep -qF 'releases/download/v$_q_up_latest/knotlog-$_q_up_latest.tar.gz' "$ROOT/knotlog" && printf yes || printf no)"

# ---- profile= (T-965..T-970) ----
# One config key bundling hook injection: normal (default) / economical / manual.
prof_ctx() { # vault event -> hook stdout
  KNOTLOG_HOOK=1 QUIPU_VAULT="$1" sh "$ROOT/knotlog" context --json "$2"
}
mkvault vprof; mkvault vprofn
for _pv in vprof vprofn; do
  QUIPU_VAULT="$TMP/$_pv" sh "$ROOT/knotlog" init --plain >/dev/null 2>&1
  printf 'lang=en\n' >> "$TMP/$_pv/.knotlog/config"
  for _n in 1 2 3; do
    printf '2026-08-20T10:0%s | PostToolUse | Read | prof%s.md\n' "$_n" "$_n" >> "$TMP/$_pv/.knotlog/activity.log"
  done
  awk 'BEGIN { for (i=1; i<=200; i++) printf "thread line %03d padding padding padding padding\n", i }' > "$TMP/$_pv/Threads.md"
done
printf 'profile=normal\n' >> "$TMP/vprofn/.knotlog/config"
export QUIPU_NUDGE_AFTER=2
unset QUIPU_CTX_MAX KNOTLOG_CTX_MAX
# The "now: YYYY-MM-DD HH:MM" line is stripped too: a slow runner can cross a minute between the two calls.
t; assert_eq "T-965: profile=normal hook output is byte-identical to no profile (SessionStart and UserPromptSubmit)" 'yes' \
  "$([ "$(prof_ctx "$TMP/vprof" SessionStart | sed 's/[0-9:T-]\{16\}//g; s/[0-9-]\{10\} [0-9:]\{5\}//g')" = "$(prof_ctx "$TMP/vprofn" SessionStart | sed 's/[0-9:T-]\{16\}//g; s/[0-9-]\{10\} [0-9:]\{5\}//g')" ] && [ "$(prof_ctx "$TMP/vprof" UserPromptSubmit | sed 's/[0-9:T-]\{16\}//g; s/[0-9-]\{10\} [0-9:]\{5\}//g')" = "$(prof_ctx "$TMP/vprofn" UserPromptSubmit | sed 's/[0-9:T-]\{16\}//g; s/[0-9-]\{10\} [0-9:]\{5\}//g')" ] && printf yes || printf no)"
printf 'profile=economical\n' >> "$TMP/vprof/.knotlog/config"
t; P966=$(prof_ctx "$TMP/vprof" SessionStart | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" - | LC_ALL=C wc -c | tr -d ' ')
assert_eq "T-966: economical caps session-start context at 4000 bytes" 'yes' \
  "$([ "$P966" -gt 1000 ] && [ "$P966" -le 4000 ] && printf yes || printf no)"
t; assert_eq "T-966: economical silences UserPromptSubmit and Stop" '' "$(prof_ctx "$TMP/vprof" UserPromptSubmit)$(prof_ctx "$TMP/vprof" Stop)"
t; P967=$(QUIPU_CTX_MAX=3000 prof_ctx "$TMP/vprof" SessionStart | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" - | LC_ALL=C wc -c | tr -d ' ')
P967b=$(printf 'ctx_max=3500\n' >> "$TMP/vprof/.knotlog/config"; prof_ctx "$TMP/vprof" SessionStart | awk -f "$LIB/jsonfield.awk" -f "$DRV/hookctx.awk" - | LC_ALL=C wc -c | tr -d ' ')
assert_eq "T-967: explicit env or ctx_max= beats economical" 'yes' \
  "$([ "$P967" -le 3000 ] && [ "$P967b" -gt 3000 ] && [ "$P967b" -le 3500 ] && printf yes || printf no)"
mkvault vprofm; printf 'lang=en\nprofile=manual\n' > "$TMP/vprofm/.knotlog/config"
for _n in 1 2 3; do printf '2026-08-20T10:0%s | PostToolUse | Read | m%s.md\n' "$_n" "$_n" >> "$TMP/vprofm/.knotlog/activity.log"; done
t; assert_eq "T-968: manual silences SessionStart, UserPromptSubmit and Stop; manual 'context' still prints" 'no-hook yes' \
  "$([ -z "$(prof_ctx "$TMP/vprofm" SessionStart)$(prof_ctx "$TMP/vprofm" UserPromptSubmit)$(prof_ctx "$TMP/vprofm" Stop)" ] && printf no-hook) $(QUIPU_VAULT="$TMP/vprofm" sh "$ROOT/knotlog" context | grep -q 'm1.md' && printf yes || printf no)"
mkvault vprofb; printf 'lang=en\nprofile=bogus\n' > "$TMP/vprofb/.knotlog/config"
t; assert_eq "T-969: invalid profile runs as normal and doctor warns once" 'yes 1' \
  "$([ -n "$(prof_ctx "$TMP/vprofb" SessionStart)" ] && printf yes) $(QUIPU_VAULT="$TMP/vprofb" sh "$ROOT/knotlog" doctor | awk -F"$TAB" '$1=="warn" && $2=="profile"{n++} END{print n+0}')"
t; printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"cap.md"}}' | KNOTLOG_HOOK=1 QUIPU_VAULT="$TMP/vprofm" sh "$ROOT/knotlog" capture >/dev/null
assert_eq "T-970: capture still writes activity.log under manual" 'PostToolUse | Read | cap.md' "$(log_line "$TMP/vprofm")"
unset QUIPU_NUDGE_AFTER

# ---- Windsurf / Devin Desktop and OpenCode adapters (T-975..T-982) ----
ow_run() { # dir args... -> knotlog setup in an empty vault, English
  _ow_d=$1; shift
  (cd "$_ow_d" && QUIPU_LANG=en QUIPU_VAULT="$_ow_d" sh "$ROOT/knotlog" "$@" 2>&1 </dev/null)
}
mkvault vow
t; assert_eq "T-975: setup windsurf --dry-run writes nothing, then writes .devin/hooks.json byte-identical, then is up to date" 'yes yes yes' \
  "$(ow_run "$TMP/vow" setup windsurf --dry-run | grep -qF 'written to' && [ ! -e "$TMP/vow/.devin" ] && printf yes) $(ow_run "$TMP/vow" setup windsurf >/dev/null; cmp -s "$ROOT/adapters/windsurf/hooks.json" "$TMP/vow/.devin/hooks.json" && printf yes) $(ow_run "$TMP/vow" setup windsurf | grep -qF 'already up to date' && printf yes)"
mkvault vow2; mkdir "$TMP/vow2/.devin"; printf '{"mine":true}\n' > "$TMP/vow2/.devin/hooks.json"
t; assert_eq "T-975: a differing .devin/hooks.json is preserved; the devin alias is accepted" 'yes yes' \
  "$(ow_run "$TMP/vow2" setup windsurf | grep -qF 'preserved' && [ "$(cat "$TMP/vow2/.devin/hooks.json")" = '{"mine":true}' ] && printf yes) $(ow_run "$TMP/vow2" setup devin | grep -qF 'preserved' && printf yes)"
mkvault vow3
t; assert_eq "T-976: setup opencode --dry-run writes nothing, then writes .opencode/plugins/knotlog.js byte-identical, then is up to date" 'yes yes yes' \
  "$(ow_run "$TMP/vow3" setup opencode --dry-run | grep -qF 'written to' && [ ! -e "$TMP/vow3/.opencode" ] && printf yes) $(ow_run "$TMP/vow3" setup opencode >/dev/null; cmp -s "$ROOT/adapters/opencode/knotlog.js" "$TMP/vow3/.opencode/plugins/knotlog.js" && printf yes) $(ow_run "$TMP/vow3" setup opencode | grep -qF 'already up to date' && printf yes)"
mkvault vow4; mkdir -p "$TMP/vow4/.opencode/plugins"; printf '// mine\n' > "$TMP/vow4/.opencode/plugins/knotlog.js"
t; assert_eq "T-976: a differing OpenCode plugin is preserved" 'yes' \
  "$(ow_run "$TMP/vow4" setup opencode | grep -qF 'preserved' && [ "$(cat "$TMP/vow4/.opencode/plugins/knotlog.js")" = '// mine' ] && printf yes)"
OWW="$ROOT/adapters/windsurf/hooks.json"
t; assert_eq "T-977: windsurf adapter is balanced, binds the two events, mirrors each command in powershell, never exits 2" 'yes' \
  "$(o=$(tr -cd '{' < "$OWW" | wc -c); c=$(tr -cd '}' < "$OWW" | wc -c); [ "$o" -eq "$c" ] \
     && grep -qF '"post_write_code": [' "$OWW" && grep -qF '"post_cascade_response": [' "$OWW" \
     && [ "$(grep -c '"command": "KNOTLOG_HOOK=1 knotlog ' "$OWW")" = 2 ] && [ "$(grep -c '"powershell": "$env:KNOTLOG_HOOK=' "$OWW")" = 2 ] \
     && grep -qF 'knotlog capture; exit 0' "$OWW" && grep -qF 'knotlog remember; KNOTLOG_HOOK=1 knotlog index' "$OWW" \
     && [ "$(grep -c 'exit 0' "$OWW")" = 4 ] && ! grep -q 'exit 2' "$OWW" && printf yes || printf no)"
OWJ="$ROOT/adapters/opencode/knotlog.js"
t; assert_eq "T-978: opencode plugin names its events and runs capture, remember and index" 'yes' \
  "$(grep -qF '"file.edited"' "$OWJ" && grep -qF '"session.idle"' "$OWJ" && grep -qF '["capture", "--event", "file.edited"' "$OWJ" \
     && grep -qF 'run(["remember"])' "$OWJ" && grep -qF 'run(["index"])' "$OWJ" && grep -qF 'KNOTLOG_HOOK: "1"' "$OWJ" && grep -qF 'catch' "$OWJ" && printf yes || printf no)"
mkvault vowc
t; printf '%s\n' '{"agent_action_name":"post_write_code","trajectory_id":"abc12345-xyz","tool_info":{"file_path":"notes/a.md","edits":[{"old_string":"x","new_string":"y"}]}}' | KNOTLOG_HOOK=1 QUIPU_VAULT="$TMP/vowc" sh "$ROOT/knotlog" capture
assert_eq "T-979: capture records a Windsurf post_write_code payload's tool_info.file_path" 'post_write_code | Write | notes/a.md' "$(log_line "$TMP/vowc")"
t; assert_eq "T-980: hookid labels a Windsurf payload devin and an Antigravity one antigravity (id8 both)" 'abc12345 devin|abc12345 antigravity' \
  "$(printf '%s' '{"agent_action_name":"post_cascade_response","trajectory_id":"abc12345-0a0b"}' | awk -f "$LIB/jsonfield.awk" -f "$LIB/hookid.awk" | tr '\t' ' ')|$(printf '%s' '{"hook_event_name":"Stop","trajectory_id":"abc12345-0a0b"}' | awk -f "$LIB/jsonfield.awk" -f "$LIB/hookid.awk" | tr '\t' ' ')"
mkvault vowd; mkdir "$TMP/vowd/.devin" "$TMP/vowd/.opencode"
t; assert_eq "T-981: doctor sees ./.devin as windsurf and ./.opencode as opencode" 'opencode ./.opencode|windsurf ./.devin' \
  "$(cd "$TMP/vowd" && QUIPU_VAULT="$TMP/vowd" sh "$ROOT/knotlog" doctor 2>/dev/null | awk -F"$TAB" '$2=="windsurf"||$2=="opencode"{printf "%s%s %s", sep, $2, $3; sep="|"}')"
t; assert_eq "T-982: lib/capture.awk and lib/hookid.awk keep zero regex literals (T-163 pattern)" '0 0' \
  "$(for f in capture hookid; do awk '/(gsub|sub|match)\(\// || /~ *\// || /split\([^)]*, *\// {n++} END{print n+0}' "$LIB/$f.awk"; done | tr '\n' ' ' | sed 's/ $//')"


# ---- knotlog mcp: knotlog_note (T-985..T-988) ------------------------------
# The one writing tool: it runs `knotlog note <text>` and nothing else.
MN="$TMP/mcnote"; rm -rf "$MN"; mkdir -p "$MN/cli" "$MN/mcp"
(cd "$MN/cli" && QUIPU_LANG=en sh "$ROOT/knotlog" init </dev/null >/dev/null 2>&1)
(cd "$MN/mcp" && QUIPU_LANG=en sh "$ROOT/knotlog" init </dev/null >/dev/null 2>&1)
mn_req() { printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"knotlog_note","arguments":%s}}\n' "$1" "$2"; }
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
  mn_req 2 '{"text":"shipped the parser"}'
  mn_req 3 '{}'
  mn_req 4 '{"text":7}'
  mn_req 5 '{"text":""}'
  mn_req 6 '{"text":"--thread sneaky"}'
} > "$MN/req.jsonl"
QUIPU_LANG=en QUIPU_VAULT="$MN/mcp" sh "$ROOT/knotlog" mcp < "$MN/req.jsonl" > "$MN/out.jsonl" 2>/dev/null
QUIPU_LANG=en QUIPU_VAULT="$MN/cli" sh "$ROOT/knotlog" note "shipped the parser" </dev/null >/dev/null 2>&1
t; assert_eq "T-985: tools/list names knotlog_note with text as its only required argument" 'yes' \
  "$(sed -n 1p "$MN/out.jsonl" | grep -qF '{"name":"knotlog_note"' && sed -n 1p "$MN/out.jsonl" | grep -qF '"properties":{"text":{"type":"string","description":"One line to add"}},"required":["text"],"additionalProperties":false}' && printf yes || printf no)"
mn_tree() { (cd "$1" && find . -type f ! -path './.knotlog/*' ! -path './.git/*' | LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done); }
t; assert_eq "T-986: knotlog_note leaves the vault byte-identical to knotlog note (same files, same bytes)" 'yes no' \
  "$([ "$(mn_tree "$MN/cli")" = "$(mn_tree "$MN/mcp")" ] && printf yes || printf no) $(sed -n 2p "$MN/out.jsonl" | grep -qF '"isError":true' && printf yes || printf no)"
t; assert_eq "T-987: a missing or non-string text is a protocol error (-32602)" '2' \
  "$(sed -n '3,4p' "$MN/out.jsonl" | grep -c '"error":{"code":-32602')"
t; assert_eq "T-988: an empty text or one starting with a dash is a tool error and writes nothing new" '2 yes' \
  "$(sed -n '5,6p' "$MN/out.jsonl" | grep -c '"isError":true') $(grep -rqF 'sneaky' "$MN/mcp" && printf no || printf yes)"

# ---- knotlog tui: non-TTY paths (T-990..T-993) -----------------------------
mkvault vtui; mkdir -p "$TMP/vtui/📆 700-Sessions"
for d in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do : > "$TMP/vtui/📆 700-Sessions/2026-09-$d.md"; done
mkvault vtue
tui_run() { (cd "$1" && shift && env QUIPU_LANG=en "$@" sh "$ROOT/knotlog" tui </dev/null 2>&1); }
t; assert_eq "T-990: tui prints the newest 20 session notes once, newest first, when not on a terminal" '21 yes yes' \
  "$(o=$(tui_run "$TMP/vtui"); printf '%s ' "$(printf '%s\n' "$o" | wc -l | tr -d ' ')"; printf '%s\n' "$o" | sed -n 2p | grep -qF ' 1  📆 700-Sessions/2026-09-25.md' && printf 'yes '; printf '%s\n' "$o" | tail -n 1 | grep -qF '20  📆 700-Sessions/2026-09-06.md' && printf yes)"
t; assert_eq "T-991: TERM=dumb takes the same plain path; an empty vault prints the empty message" 'yes yes' \
  "$([ "$(tui_run "$TMP/vtui" TERM=dumb)" = "$(tui_run "$TMP/vtui")" ] && printf yes) $([ "$(tui_run "$TMP/vtue")" = 'no session notes yet' ] && printf yes)"
t; assert_eq "T-992: help lists tui in English and Turkish" 'yes' \
  "$(QUIPU_LANG=en sh "$ROOT/knotlog" help </dev/null | grep -q '^  tui ' && sh "$ROOT/knotlog" help --tr </dev/null | grep -q '^  tui ' && grep -q '^tui_hint=' "$ROOT/i18n/en.txt" && grep -q '^tui_hint=' "$ROOT/i18n/tr.txt" && printf yes || printf no)"
mkdir -p "$TMP/tuibin"; printf '#!/bin/sh\necho call >> "%s/stty.calls"\nexit 1\n' "$TMP" > "$TMP/tuibin/stty"; chmod +x "$TMP/tuibin/stty"
t; assert_eq "T-993: tui never calls stty when stdin is not a terminal" '0' \
  "$(tui_run "$TMP/vtui" PATH="$TMP/tuibin:$PATH" >/dev/null; tui_run "$TMP/vtui" TERM=xterm PATH="$TMP/tuibin:$PATH" >/dev/null; [ -f "$TMP/stty.calls" ] && wc -l < "$TMP/stty.calls" | tr -d ' ' || printf 0)"


# ---- hookid: Devin's word-slug trajectory ids (T-995) ----------------------
# Live payload (Devin Desktop 3.11.216, 2026-10-25): trajectory_id is a slug
# such as "flax-drip"; cutting it to 8 characters gave the card "actually".
hc_mk vhc8
hc_ev vhc8 1 m; hc_rem vhc8 '{"agent_action_name":"post_cascade_response","trajectory_id":"flax-drip","timestamp":"2026-10-24T21:14:39.336872403+00:00","execution_id":"bac4492c-990d-4c1a-a67f-c4d0aa530d0c","tool_info":{"response":"Eklendi."}}'
hc_ev vhc8 2 m; hc_rem vhc8 '{"agent_action_name":"post_cascade_response","trajectory_id":"flax-drip","tool_info":{"response":"again"}}'
t; assert_eq "T-995: a Devin slug id stays whole in the card and a second response updates the same card" '1 yes' \
  "$(hc_cards vhc8) $(grep -q '^## [0-9-]* [0-9:]* · devin · flax-drip$' "$TMP/vhc8/Last-Session.md" && printf yes || printf no)"


# ---- install.sh: `curl | sh` gives the wizard the terminal (T-996) ---------
# Live report (2026-10-25): the README one-liner stopped at "install needs a user
# name" because the script itself arrives on stdin. The handover must reopen
# /dev/tty when stdin is not a terminal and one exists (a pty proves it by hand;
# CI has no terminal, so this pins the guard and the redirect).
t; assert_eq "T-996: install.sh hands knotlog install the terminal when stdin is a pipe" 'yes yes' \
  "$(grep -qF 'if [ ! -t 0 ] && (: </dev/tty) 2>/dev/null; then' "$ROOT/install.sh" && printf yes || printf no) $(grep -qF 'exec "$_dest/knotlog" install "$@" </dev/tty' "$ROOT/install.sh" && printf yes || printf no)"

# ---- generic languages: the i18n/*.txt files ARE the language list (T-1000) --
# `xx` is a fixture language: en.txt plus a marker, created in a private copy of
# the repo and never committed. It ships no template/tone/persona/layout, so
# every one of those must fall back to English.
t; assert_eq "T-1000: every i18n/*.txt has the key set of en.txt" '' \
  "$(awk -F= 'NF >= 1 && $1 !~ /^#/ {print $1}' "$ROOT/i18n/en.txt" | sort > "$TMP/en.keys"
     for _f in "$ROOT"/i18n/*.txt; do
       awk -F= 'NF >= 1 && $1 !~ /^#/ {print $1}' "$_f" | sort | cmp -s - "$TMP/en.keys" || printf '%s ' "${_f##*/}"
     done)"
XXH="$TMP/xxhome"
mkdir -p "$XXH"
for _d in lib i18n fold layout persona templates tone flair icon hooks adapters; do cp -r "$ROOT/$_d" "$XXH/$_d"; done
cp "$ROOT/knotlog" "$ROOT/repair-hooks" "$ROOT/repair-hooks.ps1" "$XXH/"
sed 's/^usage_help=.*/&  XXMARK/' "$ROOT/i18n/en.txt" > "$XXH/i18n/xx.txt"
xx_run() { # language vault args...
  _xl=$1; _xv=$2; shift 2
  (cd "$_xv" && env -u LANG -u LC_ALL QUIPU_VAULT="$_xv" QUIPU_LANG="$_xl" sh "$XXH/knotlog" "$@" </dev/null 2>&1)
}
mkdir -p "$TMP/lg-xx" "$TMP/lg-en" "$TMP/lg-zz" "$TMP/lg-xl"
t; xx_run xx "$TMP/lg-xx" init --no-prompt --lang xx >/dev/null; XRC=$?
t; assert_eq "T-1001: init --lang xx exits 0 and pins lang=xx, fold=default" '0 yes yes' \
  "$XRC $(grep -q '^lang=xx$' "$TMP/lg-xx/.knotlog/config" && printf yes || printf no) $(grep -q '^fold=default$' "$TMP/lg-xx/.knotlog/config" && printf yes || printf no)"
xx_run en "$TMP/lg-en" init --no-prompt --lang en >/dev/null
t; assert_eq "T-1002: an xx vault is byte-identical to an en one (persona, rules, facts, templates by fallback)" '' \
  "$(diff -rq -x .knotlog -x .git "$TMP/lg-xx" "$TMP/lg-en")"
t; assert_eq "T-1003: doctor on an xx vault reports no failure" '0' \
  "$(xx_run xx "$TMP/lg-xx" doctor | awk -F"$TAB" '$1 == "fail" {n++} END {print n + 0}')"
t; assert_eq "T-1004: context works in xx" 'yes' \
  "$(xx_run xx "$TMP/lg-xx" context | grep -q . && printf yes || printf no)"
printf 'tone=dostane\n' >> "$TMP/lg-xx/.knotlog/config"
t; assert_eq "T-1005: a tone preset falls back to the English preset in xx" 'yes' \
  "$(xx_run xx "$TMP/lg-xx" context | grep -qF -- "$(sed -n 1p "$ROOT/tone/en/dostane.md")" && printf yes || printf no)"
t; assert_eq "T-1006: help --xx prints the xx file and --en stays English" '1 0' \
  "$(xx_run xx "$TMP/lg-xx" help --xx | grep -c XXMARK) $(xx_run xx "$TMP/lg-xx" help --en | grep -c XXMARK)"
xx_run zz "$TMP/lg-zz" init --no-prompt >/dev/null
t; assert_eq "T-1007: an unsupported code acts as English" 'yes' \
  "$(cmp -s "$TMP/lg-zz/Rules.md" "$TMP/lg-en/Rules.md" && printf yes || printf no)"
mkdir -p "$TMP/lg-xl2"
xx_run xx "$TMP/lg-xl" init --no-prompt --lang xx --layout en --scope full >/dev/null
xx_run en "$TMP/lg-xl2" init --no-prompt --lang en --layout en --scope full >/dev/null
t; assert_eq "T-1008: --layout en --scope full gives the same folders in xx as in en" '' \
  "$(diff -rq -x .knotlog -x .git "$TMP/lg-xl" "$TMP/lg-xl2")"
mkdir -p "$TMP/ixp" "$TMP/ixb"
t; printf 'xx\nAda\n\n\n' | PATH="$TMP/ixb:$INSTALL_TOOLS" QUIPU_FORCE_TTY=1 sh "$XXH/knotlog" install "$TMP/ixp" >"$TMP/ix.out" 2>&1
t; assert_eq "T-1009: the install language prompt lists xx and accepts it" 'yes yes' \
  "$(grep -qE 'Language / Dil \(en/([a-z-]+/)*xx[/)]' "$TMP/ix.out" && printf yes || printf no) $(cat "$TMP"/ixp/*/.knotlog/config 2>/dev/null | grep -q '^lang=xx$' && printf yes || printf no)"
t; assert_eq "T-1010: no hard-coded language or layout-name list is left in knotlog" '0' \
  "$(grep -cE 'emoji\|plain\|tr\|en|menu_codes=.en tr.|i18n/tr\.txt' "$ROOT/knotlog")"
# Fold profile by language, and locale spellings mapping onto lowercase codes.
for _c in es:latin pt-br:latin ja:default zh-cn:default tr:tr en:default; do
  cp "$ROOT/i18n/en.txt" "$XXH/i18n/${_c%%:*}.txt" 2>/dev/null
  mkdir -p "$TMP/lg-f-${_c%%:*}"
  xx_run "${_c%%:*}" "$TMP/lg-f-${_c%%:*}" init --no-prompt >/dev/null
  t; assert_eq "T-1011: fold profile for ${_c%%:*}" "${_c##*:}" "$(awk -F= '$1 == "fold" {print $2}' "$TMP/lg-f-${_c%%:*}/.knotlog/config")"
done
mkdir -p "$TMP/lg-loc"
(cd "$TMP/lg-loc" && env -u LC_ALL -u QUIPU_LANG LANG=pt_BR.UTF-8 QUIPU_VAULT="$TMP/lg-loc" sh "$XXH/knotlog" init --no-prompt </dev/null >/dev/null 2>&1)
t; assert_eq "T-1012: LANG=pt_BR.UTF-8 and --lang PT-BR both resolve to pt-br (fold latin)" 'latin latin' \
  "$(awk -F= '$1 == "fold" {print $2}' "$TMP/lg-loc/.knotlog/config") $(mkdir -p "$TMP/lg-loc2"; xx_run PT-BR "$TMP/lg-loc2" init --no-prompt --lang PT-BR >/dev/null; awk -F= '$1 == "fold" {print $2}' "$TMP/lg-loc2/.knotlog/config")"


# ---- every shipped language: a fresh vault is healthy (T-1013) -------------
# pt-br's own Rules.md seed was taken for a hand-written file because the
# "is this the untouched seed" checks only compared tr and en templates, so a
# clean pt-br vault failed doctor 3 times. Walk the real languages, not a fixture.
_l13=
for _l13_f in "$ROOT"/i18n/*.txt; do
  _l13_c=${_l13_f##*/}; _l13_c=${_l13_c%.txt}
  mkdir -p "$TMP/l13-$_l13_c"
  (cd "$TMP/l13-$_l13_c" && env -u LANG -u LC_ALL QUIPU_VAULT="$TMP/l13-$_l13_c" QUIPU_LANG="$_l13_c" sh "$ROOT/knotlog" init --no-prompt </dev/null >/dev/null 2>&1)
  (cd "$TMP/l13-$_l13_c" && env -u LANG -u LC_ALL QUIPU_VAULT="$TMP/l13-$_l13_c" QUIPU_LANG="$_l13_c" sh "$ROOT/knotlog" doctor </dev/null >"$TMP/l13-$_l13_c.out" 2>&1) || _l13="$_l13 $_l13_c"
done
t; assert_eq "T-1013: doctor passes on a fresh vault in every shipped language" '' "$_l13"

# ---- install over an occupied command: replace a foreign symlink, never a file (T-1020..T-1026) ----
# Seen live: `curl | sh` stopped on ~/.local/bin/knotlog (a symlink to a dev
# checkout) with no remedy, and the message glued onto the spinner line.
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  _l20_setup() { # name -> prepares $L20_BIN/$L20_PAR with a foreign symlink
    L20_BIN="$TMP/l20-$1-bin"; L20_PAR="$TMP/l20-$1-par"; L20_TGT="$TMP/l20-$1-target"
    mkdir -p "$L20_BIN" "$L20_PAR"
    printf 'dev checkout\n' > "$L20_TGT"
    make_true_symlink "$L20_TGT" "$L20_BIN/knotlog" || exit 1
  }
  _l20_setup a
  t; PATH="$L20_BIN:$INSTALL_TOOLS" HOME="$TMP/l20-a-home" QUIPU_LANG=en sh "$ROOT/knotlog" install "$L20_PAR" \
    --no-prompt --user L20 --force >"$TMP/l20-a.out" 2>"$TMP/l20-a.err"; IRC=$?
  assert_install_rc "T-1020: --force replaces a foreign symlink (exit 0)" '0' "$IRC" "$TMP/l20-a.err"
  t; assert_eq "T-1020: the link now runs this knotlog; its old target is untouched" 'yes' \
    "$([ -L "$L20_BIN/knotlog" ] && [ "$(PATH="$L20_BIN:$INSTALL_TOOLS" "$L20_BIN/knotlog" --version)" = 'knotlog 1.2.0' ] \
       && [ "$(cat "$L20_TGT")" = 'dev checkout' ] && printf yes || printf no)"

  _l20_setup b
  t; PATH="$L20_BIN:$INSTALL_TOOLS" HOME="$TMP/l20-b-home" QUIPU_LANG=en sh "$ROOT/knotlog" install "$L20_PAR" \
    --no-prompt --user L20 >"$TMP/l20-b.out" 2>"$TMP/l20-b.err"; IRC=$?
  assert_install_rc "T-1021: a foreign symlink without --force exits 2" '2' "$IRC" "$TMP/l20-b.err"
  t; assert_eq "T-1021: the refusal names --force and --no-link, shows the target; nothing changed" 'yes' \
    "$(grep -qF -- '--force' "$TMP/l20-b.err" && grep -qF -- '--no-link' "$TMP/l20-b.err" \
       && grep -qF "$L20_TGT" "$TMP/l20-b.err" && [ -L "$L20_BIN/knotlog" ] \
       && [ ! -e "$L20_PAR/L20's Knotlog" ] && printf yes || printf no)"

  _l20_setup c
  t; printf 'en\nL20\n\n\n\n\nn\n' | PATH="$L20_BIN:$INSTALL_TOOLS" HOME="$TMP/l20-c-home" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
    sh "$ROOT/knotlog" install "$L20_PAR" >"$TMP/l20-c.out" 2>"$TMP/l20-c.err"; IRC=$?
  assert_install_rc "T-1022: interactive answer n refuses (exit 2)" '2' "$IRC" "$TMP/l20-c.err"
  t; assert_eq "T-1022: the question showed the target and the link is unchanged" 'yes' \
    "$(grep -qF "$L20_TGT" "$TMP/l20-c.out" && grep -qF '[y/N]' "$TMP/l20-c.out" \
       && [ "$(readlink "$L20_BIN/knotlog")" = "$L20_TGT" ] && printf yes || printf no)"

  _l20_setup d
  t; printf 'en\nL20\n\n\n\n\ny\n' | PATH="$L20_BIN:$INSTALL_TOOLS" HOME="$TMP/l20-d-home" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
    sh "$ROOT/knotlog" install "$L20_PAR" >"$TMP/l20-d.out" 2>"$TMP/l20-d.err"; IRC=$?
  assert_install_rc "T-1023: interactive answer y replaces the link (exit 0)" '0' "$IRC" "$TMP/l20-d.err"
  t; assert_eq "T-1023: link replaced, old target untouched" 'yes' \
    "$([ "$(readlink "$L20_BIN/knotlog")" != "$L20_TGT" ] && [ "$(cat "$L20_TGT")" = 'dev checkout' ] && printf yes || printf no)"
fi

# A regular file is never replaced, with or without --force.
L20_BIN="$TMP/l20-e-bin"; L20_PAR="$TMP/l20-e-par"; mkdir -p "$L20_BIN" "$L20_PAR"
printf 'mine\n' > "$L20_BIN/knotlog"
t; PATH="$L20_BIN:$INSTALL_TOOLS" HOME="$TMP/l20-e-home" QUIPU_LANG=en sh "$ROOT/knotlog" install "$L20_PAR" \
  --no-prompt --user L20 --force >"$TMP/l20-e.out" 2>"$TMP/l20-e.err"; IRC=$?
assert_install_rc "T-1024: a regular file is refused even with --force (exit 2)" '2' "$IRC" "$TMP/l20-e.err"
t; assert_eq "T-1024: the file is untouched and the message says how to resolve" 'yes' \
  "$([ ! -L "$L20_BIN/knotlog" ] && [ "$(cat "$L20_BIN/knotlog")" = mine ] \
     && grep -qF -- '--no-link' "$TMP/l20-e.err" && ! grep -qF -- 'Rerun with --force' "$TMP/l20-e.err" && printf yes || printf no)"

# The error starts on its own line, not glued to the busy dots (needs a pty).
# Linux only: Windows Python has no pty, and on macOS this spawn loop hung the CI job for hours (2026-10-25).
if [ "$TRUE_SYMLINKS" -eq 1 ] && [ "$(uname -s)" = Linux ] && command -v python3 >/dev/null 2>&1; then
  _l20_setup g
  PATH="$L20_BIN:$INSTALL_TOOLS" HOME="$TMP/l20-g-home" QUIPU_LANG=en TERM=xterm L20_ROOT="$ROOT" L20_PAR="$L20_PAR" \
    python3 -I -c '
import os, pty, sys
out = []
def rd(fd):
    d = os.read(fd, 4096)
    out.append(d)
    return d
pid_status = pty.spawn(["sh", os.environ["L20_ROOT"] + "/knotlog", "install", os.environ["L20_PAR"], "--user", "L20", "--lang", "en"], rd, lambda fd: b"\n")
sys.stdout.buffer.write(b"".join(out))' </dev/null >"$TMP/l20-g.raw" 2>/dev/null
  # Any CR-terminated erase must come before the message: the message line
  # itself must not be preceded by dots on the same line.
  t; assert_eq "T-1025: the refusal is not glued to the busy line" 'yes' \
    "$(tr '\r' '\n' < "$TMP/l20-g.raw" | grep -F 'not replaced' | grep -vq '\.\.' \
       && tr '\r' '\n' < "$TMP/l20-g.raw" | grep -qF -- '--force' && printf yes || printf no)"
else
  t; skip "T-1025: busy line not glued" "needs Linux, symlinks and python3 for a pty"
fi

# Help line and version.
t; assert_eq "T-1026: usage_install mentions --force in every language" '' \
  "$(for _f in "$ROOT"/i18n/*.txt; do grep -q '^usage_install=.*--force' "$_f" || printf '%s ' "$_f"; done)"

# ---- flair: reply decoration independent of tone (T-1030..T-1037) ----
# The "now: YYYY-MM-DD HH:MM" line is stripped too: a slow runner can cross a minute between two calls.
fl_ctx() { QUIPU_VAULT="$TMP/$1" sh "$ROOT/knotlog" context 2>&1 | sed 's/[0-9:T-]\{16\}//g; s/[0-9-]\{10\} [0-9:]\{5\}//g'; }
fl_mk() { # name lang [extra config lines]
  mkvault "$1"; printf 'lang=%s\n' "$2" > "$TMP/$1/.knotlog/config"
  QUIPU_VAULT="$TMP/$1" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
}
fl_mk vfl0 en; fl_mk vfl1 en; fl_mk vfl2 en; fl_mk vfl3 en
printf 'flair=none\n' >> "$TMP/vfl1/.knotlog/config"
t; assert_eq "T-1030: flair unset and flair=none give the same context, with no flair section" 'yes' \
  "$([ "$(fl_ctx vfl0)" = "$(fl_ctx vfl1)" ] && ! fl_ctx vfl0 | grep -qF "$(men ctx_flair)" && printf yes || printf no)"
printf 'flair=kaomoji\n' >> "$TMP/vfl2/.knotlog/config"
printf 'flair=emoji\n' >> "$TMP/vfl3/.knotlog/config"
t; assert_eq "T-1031: kaomoji and emoji text reach context after the tone priority note" 'yes yes' \
  "$(for _f in vfl2:kaomoji vfl3:emoji; do _v=${_f%:*}; _k=${_f#*:}; fl_ctx "$_v" | awk -v p="$(men ctx_tone_priority)" -v h="$(men ctx_flair)" -v b="$(head -1 "$ROOT/flair/en/$_k.md")" \
       '$0==p{a=NR} $0==h{c=NR} $0==b{d=NR} END{exit !(a && c>a && d>c)}' && printf 'yes '; done | sed 's/ $//')"
fl_mk vfl4 en; printf 'tone=dostane\nflair=kaomoji\n' >> "$TMP/vfl4/.knotlog/config"
t; assert_eq "T-1032: tone=dostane and flair=kaomoji are both in context" 'yes yes' \
  "$(fl_ctx vfl4 | grep -qF -- "$(head -1 "$ROOT/tone/en/dostane.md")" && printf yes) $(fl_ctx vfl4 | grep -qF -- "$(head -1 "$ROOT/flair/en/kaomoji.md")" && printf yes)"
fl_mk vfl5 en; printf 'flair=bogus\n' >> "$TMP/vfl5/.knotlog/config"
t; assert_eq "T-1033: an invalid flair acts as none and doctor warns once" 'yes 1' \
  "$([ "$(fl_ctx vfl5)" = "$(fl_ctx vfl0)" ] && printf yes) $(QUIPU_VAULT="$TMP/vfl5" sh "$ROOT/knotlog" doctor | awk -F"$TAB" '$1=="warn" && $2=="flair"{n++} END{print n+0}')"
fl_mk vfl6 en
FL_B=$(cd "$TMP/vfl6" && QUIPU_VAULT="$TMP/vfl6" sh "$ROOT/knotlog" flair)
FL_L=$(cd "$TMP/vfl6" && QUIPU_VAULT="$TMP/vfl6" sh "$ROOT/knotlog" flair --list)
FL_S=$(cd "$TMP/vfl6" && QUIPU_VAULT="$TMP/vfl6" sh "$ROOT/knotlog" flair emoji)
t; assert_eq "T-1034: flair shows none, --list marks it, setting writes a single flair=" 'yes yes yes yes' \
  "$([ "$FL_B" = "$(memfmt en flair_current none)" ] && printf yes) $(printf '%s\n' "$FL_L" | grep -qF "* none" && printf yes) $(grep -qx 'flair=emoji' "$TMP/vfl6/.knotlog/config" && [ "$FL_S" = "$(memfmt en flair_set emoji)" ] && printf yes) $(QUIPU_VAULT="$TMP/vfl6" sh "$ROOT/knotlog" flair none >/dev/null; grep -qx 'flair=none' "$TMP/vfl6/.knotlog/config" && [ "$(grep -c '^flair=' "$TMP/vfl6/.knotlog/config")" = 1 ] && printf yes)"
mkvault vfl7; printf 'lang=en\n' > "$TMP/vfl7/.knotlog/config"
QUIPU_VAULT="$TMP/vfl7" sh "$ROOT/knotlog" init --no-prompt --flair kaomoji >/dev/null 2>&1
QUIPU_VAULT="$TMP/vfl7" sh "$ROOT/knotlog" init --no-prompt --flair loud >/dev/null 2>"$TMP/vfl7.err"; FRC=$?
t; assert_eq "T-1035: init --flair writes flair=; an unknown value exits 2" 'yes 2' \
  "$(grep -qx 'flair=kaomoji' "$TMP/vfl7/.knotlog/config" && printf yes) $FRC"
mkdir -p "$TMP/lg-fl"; xx_run xx "$TMP/lg-fl" init --no-prompt --lang xx --flair kaomoji >/dev/null
t; assert_eq "T-1036: a language without flair files (the xx fixture) falls back to the English text" 'yes' \
  "$(xx_run xx "$TMP/lg-fl" context | grep -qF -- "$(head -1 "$ROOT/flair/en/kaomoji.md")" && printf yes || printf no)"
fl_mk vfl9 en; printf 'tone=kaomoji\n' >> "$TMP/vfl9/.knotlog/config"
t; assert_eq "T-1037: tone=kaomoji still works and adds no flair section" 'yes yes' \
  "$(fl_ctx vfl9 | grep -qF -- "$(head -1 "$ROOT/tone/en/kaomoji.md")" && printf yes) $(! fl_ctx vfl9 | grep -qF "$(men ctx_flair)" && printf yes)"

t; assert_eq "T-1038: doctor lists every shipped flair file as ok" "$(find "$ROOT/flair" -name '*.md' -type f | wc -l | tr -d ' ')" \
  "$(QUIPU_VAULT="$TMP/vfl0" sh "$ROOT/knotlog" doctor 2>&1 | awk -F"$TAB" -v s="$(men doc_ok)" 'index($2,"flair/")==1 && $1==s{n++} END{print n+0}')"
# ---- install wizard: Style step (T-1040..T-1046) ----
# st_inst NAME ANSWERS [install args...] -- plain-text wizard over a pipe;
# output in $TMP/stN.out, vault in $TMP/stN/Ada's Knotlog.
st_inst() {
  _st_n=$1; _st_a=$2; shift 2
  mkdir -p "$TMP/$_st_n" "$TMP/$_st_n-bin"
  printf "$_st_a" | HOME="$TMP/$_st_n-bin" PATH="$TMP/$_st_n-bin:$INSTALL_TOOLS" QUIPU_LANG=en QUIPU_FORCE_TTY=1 \
    sh "$ROOT/knotlog" install --no-link "$TMP/$_st_n" "$@" >"$TMP/$_st_n.out" 2>"$TMP/$_st_n.err"
  ST_RC=$?
}
ST_V() { printf '%s' "$TMP/$1/Ada's Knotlog"; }
st_inst st1 'en\nAda\n\n3\n3\n2\n'
t; assert_eq "T-1040: choosing tone 3 + flair 3 + plain folders writes tone=, flair= and the plain folders" 'dostane emoji plain yes' \
  "$(for _k in tone flair layout; do sed -n "s/^$_k=//p" "$(ST_V st1)/.knotlog/config"; done | tr '\n' ' ')$([ -d "$(ST_V st1)/000-Inbox" ] && printf yes)"
st_inst st2 'en\nAda\n\n\n\n\n'
mkdir -p "$TMP/st3b"; HOME="$TMP/st3b" PATH="$TMP/st3b:$INSTALL_TOOLS" sh "$ROOT/knotlog" install --no-link --no-prompt --lang en --user Ada "$TMP/st3b" >"$TMP/st3b.out" 2>&1
t; assert_eq "T-1041: Enter on all three questions gives the flagless non-interactive result" 'yes yes' \
  "$([ "$(grep -v '^$' "$(ST_V st2)/.knotlog/config" | grep -v '^created')" = "$(grep -v '^$' "$(ST_V st3b)/.knotlog/config" | grep -v '^created')" ] && printf yes) $([ "$(cd "$(ST_V st2)" && find . -not -path './.git/*' | sort)" = "$(cd "$(ST_V st3b)" && find . -not -path './.git/*' | sort)" ] && printf yes)"
st_inst st4 'en\nAda\n\n\n\n' --tone ogretici
st_inst st5 'en\nAda\n\n\n\n' --flair kaomoji
st_inst st6 'en\nAda\n\n\n\n' --plain
st_inst st7 'en\nAda\n\n' --tone ogretici --flair emoji --plain
t; assert_eq "T-1042: each of --tone, --flair, --plain skips only its own menu; all three skip the step" 'no yes yes, yes no yes, yes yes no, nostep' \
  "$(_q() { grep -qF "$2" "$TMP/$1.out" && printf yes || printf no; }
     printf '%s %s %s, %s %s %s, %s %s %s, ' "$(_q st4 'Choose 1-8')" "$(_q st4 'Choose 1-3')" "$(_q st4 'Choose 1-2')" "$(_q st5 'Choose 1-8')" "$(_q st5 'Choose 1-3')" "$(_q st5 'Choose 1-2')" "$(_q st6 'Choose 1-8')" "$(_q st6 'Choose 1-3')" "$(_q st6 'Choose 1-2')"
     grep -qF 'Style' "$TMP/st7.out" && printf step || printf nostep)"
t; assert_eq "T-1043: flag-given values still land in config, and skipping the whole step renumbers to [4/4]" 'ogretici emoji plain yes' \
  "$(for _k in tone flair layout; do sed -n "s/^$_k=//p" "$(ST_V st7)/.knotlog/config"; done | tr '\n' ' ')$(grep -qF '[4/4] Install' "$TMP/st7.out" && printf yes)"
t; assert_eq "T-1044: --no-prompt prints no Style step and writes no tone=/flair=" 'yes yes' \
  "$(! grep -qF 'Style' "$TMP/st3b.out" && printf yes) $(! grep -qE '^(tone|flair)=' "$(ST_V st3b)/.knotlog/config" && printf yes)"
t; assert_eq "T-1045: the step counter shows five steps and the review box lists the three choices" 'yes yes' \
  "$(grep -qF '[4/5] Style' "$TMP/st1.out" && grep -qF '[5/5] Install' "$TMP/st1.out" && printf yes) $(grep -qF 'Tone: Friendly' "$TMP/st1.out" && grep -qF 'Flair: emoji' "$TMP/st1.out" && grep -qF 'Folders: Plain' "$TMP/st1.out" && printf yes)"
st_inst st8 'en\nAda\n\n99\n'
t; assert_eq "T-1046: an out-of-range Style answer exits 2" '2' "$ST_RC"
t; assert_eq "T-1047: every language has the Style keys" '' \
  "$(for _f in "$ROOT"/i18n/*.txt; do for _k in install_step_style install_ask_pick install_style_tone install_style_flair install_style_folders install_style_emoji install_style_emoji_ex install_style_plain install_review_tone install_review_flair install_review_folders err_install_style_invalid; do grep -q "^$_k=." "$_f" || printf '%s:%s ' "$_f" "$_k"; done; done)"
# ---- install summary: grouped, colour only on a real terminal (T-1050..T-1055) ----
# sm_inst NAME [ENV=VAL ...] -- install --no-link over a pipe, no git identity.
sm_inst() {
  _sm_n=$1; shift
  mkdir -p "$TMP/$_sm_n" "$TMP/$_sm_n-bin"
  # useConfigOnly: git on macOS otherwise guesses user@host.local and commits anyway.
  env HOME="$TMP/$_sm_n-bin" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PATH="$TMP/$_sm_n-bin:$INSTALL_TOOLS" \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true \
    QUIPU_LANG=en "$@" sh "$ROOT/knotlog" install --no-link --no-prompt --user Ada "$TMP/$_sm_n" >"$TMP/$_sm_n.out" 2>"$TMP/$_sm_n.err"
}
# sm_pty NAME [ENV=VAL ...] -- the same install on a pseudo-terminal (python3 pty; skipped without it).
sm_pty() {
  _sm_n=$1; shift
  mkdir -p "$TMP/$_sm_n" "$TMP/$_sm_n-bin"
  env HOME="$TMP/$_sm_n-bin" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PATH="$TMP/$_sm_n-bin:$INSTALL_TOOLS" \
    QUIPU_LANG=en TERM=xterm "$@" python3 -c 'import pty,sys; pty.spawn(sys.argv[1:])' \
    sh "$ROOT/knotlog" install --no-link --no-prompt --user Ada "$TMP/$_sm_n" >"$TMP/$_sm_n.out" 2>"$TMP/$_sm_n.err" </dev/null
}
SM_ESC=$(awk 'BEGIN { printf "%c", 27 }')
# Linux only, like T-1025: Windows Python has no pty and a macOS pty.spawn hung CI for hours (2026-10-25).
SM_PTY=0; [ "$(uname -s)" = Linux ] && command -v python3 >/dev/null 2>&1 && SM_PTY=1
sm_inst sm1
t; assert_eq "T-1050: the summary under a pipe has no ESC byte and no colour codes" 'no' \
  "$(grep -q "$SM_ESC" "$TMP/sm1.out" && printf yes || printf no)"
t; assert_eq "T-1051: groups print in order Vault, Hooks, Safety, Skipped, each item on one line" 'yes 5' \
  "$(awk '/^Vault$/ {a=NR} /^Hooks$/ {b=NR} /^Safety$/ {c=NR} /^Skipped$/ {d=NR} END {print (a && a<b && b<c && c<d) ? "yes" : "no"}' "$TMP/sm1.out") $(grep -c '^  ✔ ' "$TMP/sm1.out")"
# Outside $( ): bash 3.2 (macOS) cannot parse a case pattern's ')' inside a command substitution.
case $(uname -s) in
  MINGW* | MSYS* | CYGWIN*) SM52=yes ;;
  *) SM52=no; grep -qF '  ! Command: not linked (skipped because of --no-link)' "$TMP/sm1.out" && ! grep -qF 'install.ps1' "$TMP/sm1.out" && SM52=yes ;;
esac
t; assert_eq "T-1052: --no-link says it was skipped because of --no-link" 'yes' "$SM52"
t; assert_eq "T-1053: a missing git identity is a skipped item with a fix line" 'yes' \
  "$(grep -qF '  ! No baseline commit' "$TMP/sm1.out" && grep -qF '    fix: git config --global user.name' "$TMP/sm1.out" && printf yes || printf no)"
sm_inst sm2 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
t; assert_eq "T-1054: with an identity the baseline commit is a done item and no fix line prints" 'yes' \
  "$(grep -qF '  ✔ Baseline commit made' "$TMP/sm2.out" && ! grep -qF 'fix: git config' "$TMP/sm2.out" && printf yes || printf no)"
if [ "$SM_PTY" -eq 1 ]; then
  sm_pty sm3; sm_pty sm4 NO_COLOR=1; sm_pty sm5 TERM=dumb
  t; assert_eq "T-1055: on a terminal the marks are coloured; NO_COLOR=1 and TERM=dumb print none" 'yes yes yes' \
    "$(grep -q "${SM_ESC}\[32m✔" "$TMP/sm3.out" && grep -q "${SM_ESC}\[33m!" "$TMP/sm3.out" && printf yes) \
$(! grep -q "${SM_ESC}\[3[23]m" "$TMP/sm4.out" && grep -qF '✔ Vault: created' "$TMP/sm4.out" && printf yes) \
$(! grep -q "${SM_ESC}\[3[23]m" "$TMP/sm5.out" && grep -qF '✔ Vault: created' "$TMP/sm5.out" && printf yes)"
else
  t; skip "T-1055: coloured summary on a terminal" "needs Linux and python3 for a pty"
fi

# ---- style in the bridge, kaomoji rule, wizard menu, client hints (T-1060..T-1065) ----
BR_LAST=$(men bridge_proto_13)
BR_STYLE=$(men bridge_style)
br_mk() { # name [extra config lines] -- en vault with text around the bridge block
  mkvault "$1"; printf 'lang=en\n' > "$TMP/$1/.knotlog/config"; [ -z "${2:-}" ] || printf '%s\n' "$2" >> "$TMP/$1/.knotlog/config"
  printf 'USER TOP\n' > "$TMP/$1/AGENTS.md"; printf 'USER TOP\n' > "$TMP/$1/CLAUDE.md"
  QUIPU_VAULT="$TMP/$1" sh "$ROOT/knotlog" init --no-prompt >/dev/null 2>&1
  printf 'USER BOTTOM\n' | tee -a "$TMP/$1/AGENTS.md" >> "$TMP/$1/CLAUDE.md"
}
br_mk vbr0
t; assert_eq "T-1060: with no tone= and no flair= the bridge has no Style section and ends at the last protocol" 'yes yes' \
  "$(! grep -qxF "$BR_STYLE" "$TMP/vbr0/AGENTS.md" && printf yes) $(awk -v l="  $BR_LAST" '$0==l{f=1;next} f&&/knotlog:end/{ok=1} END{exit !ok}' "$TMP/vbr0/AGENTS.md" && printf yes)"
br_mk vbr1 'tone=dostane
flair=emoji'
t; assert_eq "T-1061: with tone=dostane and flair=emoji both bridge files carry both texts under Style" 'yes yes yes yes' \
  "$(for _f in AGENTS.md CLAUDE.md; do grep -qxF "$BR_STYLE" "$TMP/vbr1/$_f" && grep -qF -- "$(head -1 "$ROOT/tone/en/dostane.md")" "$TMP/vbr1/$_f" && printf 'yes '; grep -qF -- "$(head -1 "$ROOT/flair/en/emoji.md")" "$TMP/vbr1/$_f" && printf 'yes '; done | sed 's/ $//')"
br_mk vbr2; cp "$TMP/vbr2/AGENTS.md" "$TMP/vbr2.before"
BR_V="$TMP/vbr2"
QUIPU_VAULT="$BR_V" sh "$ROOT/knotlog" flair emoji >/dev/null
BR_MID=$(grep -cF -- "$(head -1 "$ROOT/flair/en/emoji.md")" "$BR_V/AGENTS.md")$(grep -cF -- "$(head -1 "$ROOT/flair/en/emoji.md")" "$BR_V/CLAUDE.md")$(grep -c '^USER ' "$BR_V/AGENTS.md")
QUIPU_VAULT="$BR_V" sh "$ROOT/knotlog" flair none >/dev/null
t; assert_eq "T-1062: flair emoji adds the text to the bridge, flair none removes it, and the text outside the markers stays identical" '112 yes' \
  "$BR_MID $(cmp -s "$BR_V/AGENTS.md" "$TMP/vbr2.before" && printf yes)"
br_mk vbr3 'tone=kaomoji
flair=emoji'
KP=$(grep -m1 'never pictorial emoji' "$ROOT/tone/en/kaomoji.md")
t; assert_eq "T-1063: tone=kaomoji with flair=emoji drops the tone's decoration lines from context and the bridge" 'no no yes yes' \
  "$(fl_ctx vbr3 | grep -qF -- "$KP" && printf yes || printf no) $(grep -qF -- "$KP" "$TMP/vbr3/AGENTS.md" && printf yes || printf no) $(fl_ctx vbr3 | grep -qF -- "$(head -1 "$ROOT/flair/en/emoji.md")" && printf yes) $(grep -qF -- "$(head -1 "$ROOT/flair/en/emoji.md")" "$TMP/vbr3/AGENTS.md" && printf yes)"
br_mk vbr4 'tone=kaomoji'
t; assert_eq "T-1064: tone=kaomoji alone keeps its text in context and the bridge, and the wizard tone menu no longer offers it" 'yes yes no yes' \
  "$(fl_ctx vbr4 | grep -qF -- "$KP" && printf yes) $(grep -qF -- "$KP" "$TMP/vbr4/AGENTS.md" && printf yes) $(grep -qF 'Kaomoji -- ' "$TMP/st1.out" && printf yes || printf no) $(grep -qF 'Choose 1-8' "$TMP/st1.out" && printf yes)"
# A PATH with every host tool except the three clients, so the test holds on a machine that has them.
mkdir -p "$TMP/ih-bin" "$TMP/ih-clean"
for _d in $(printf '%s' "$INSTALL_TOOLS" | tr ':' ' '); do for _f in "$_d"/*; do case ${_f##*/} in opencode | windsurf | devin-desktop) ;; *) ln -s "$_f" "$TMP/ih-clean/${_f##*/}" 2>/dev/null ;; esac; done; done
printf '#!/bin/sh\n' > "$TMP/ih-bin/opencode"; cp "$TMP/ih-bin/opencode" "$TMP/ih-bin/windsurf"; chmod +x "$TMP/ih-bin/opencode" "$TMP/ih-bin/windsurf"
sm_inst ih0 PATH="$TMP/ih0-bin:$TMP/ih-clean"
sm_inst ih1 PATH="$TMP/ih-bin:$TMP/ih1-bin:$TMP/ih-clean"
t; assert_eq "T-1065: a client on PATH gets a Skipped line with its setup remedy; without it nothing is added" 'yes yes yes no no' \
  "$(grep -qF '  ! OpenCode found' "$TMP/ih1.out" && printf yes) $(grep -qF 'fix: knotlog setup opencode' "$TMP/ih1.out" && printf yes) $(grep -qF 'fix: knotlog setup windsurf' "$TMP/ih1.out" && printf yes) $(grep -qF 'setup opencode' "$TMP/ih0.out" && printf yes || printf no) $(grep -qF 'setup windsurf' "$TMP/ih0.out" && printf yes || printf no)"
# ---- install scenarios from the 1.2.0 audit (T-1070..T-1075) ----
# T-1070: the arrow-key language menu used to hand an unshipped layout name on
# (es, ja, pt-br, zh-cn have a language but no layout file) and died with
# "unknown layout". Needs a pty: Linux and python3 only, like T-1025.
if [ "$(uname -s)" = Linux ] && command -v python3 >/dev/null 2>&1; then
  cat > "$TMP/menu-drive.py" <<'PYEOF'
import os, pty, sys, time, select
kl, home, target, downs = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
env = dict(os.environ, HOME=home, GIT_CONFIG_NOSYSTEM="1", TERM="xterm")
pid, fd = pty.fork()
if pid == 0:
    os.execve("/bin/sh", ["sh", kl, "install", "--no-link", "--no-git", "--user", "Ada", target], env)
seq = [b"\x1b[B"] * downs + [b"\r"] * 16
end = time.time() + 40
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.4)
    if r:
        try: d = os.read(fd, 4096)
        except OSError: d = b""
        if not d: break
    elif seq:
        os.write(fd, seq.pop(0))
    else:
        break
p, st = os.waitpid(pid, os.WNOHANG)
if p == 0:
    os.kill(pid, 9); os.waitpid(pid, 0); print(99)
else:
    print(os.waitstatus_to_exitcode(st))
PYEOF
  M70=
  for _m in es:1 ja:2 pt-br:3 zh-cn:5; do
    mkdir -p "$TMP/m70-${_m%:*}-h" "$TMP/m70-${_m%:*}"
    M70="$M70$(env PATH="$INSTALL_TOOLS" python3 -I "$TMP/menu-drive.py" "$ROOT/knotlog" "$TMP/m70-${_m%:*}-h" "$TMP/m70-${_m%:*}" "${_m#*:}" </dev/null 2>/dev/null | tail -1) "
  done
  t; assert_eq "T-1070: picking es, ja, pt-br or zh-cn in the arrow-key menu completes the install (exit 0)" '0 0 0 0 ' "$M70"
else
  t; skip "T-1070: language menu picks without a shipped layout" "needs Linux and python3 for a pty"
fi

# T-1071: tone/flair also refresh the dynamic context block (knotlog:context), not only the static one.
br_mk vbr5 'flair=emoji'
QUIPU_VAULT="$TMP/vbr5" sh "$ROOT/knotlog" context --bridge >/dev/null 2>&1
BR5_E=$(head -1 "$ROOT/flair/en/emoji.md"); BR5_K=$(head -1 "$ROOT/flair/en/kaomoji.md")
# br5_out FILE: the lines outside both marker pairs
br5_out() { awk '/^<!-- knotlog:(context:)?start -->$/ {s=1} !s {print} /^<!-- knotlog:(context:)?end -->$/ {s=0}' "$1"; }
br5_out "$TMP/vbr5/AGENTS.md" > "$TMP/vbr5.before"
t; assert_eq "T-1071 setup: both files carry the emoji text twice (static + context block) before the change" '2 2' \
  "$(grep -cF -- "$BR5_E" "$TMP/vbr5/AGENTS.md") $(grep -cF -- "$BR5_E" "$TMP/vbr5/CLAUDE.md")"
QUIPU_VAULT="$TMP/vbr5" sh "$ROOT/knotlog" flair kaomoji >/dev/null 2>&1
t; assert_eq "T-1071: after flair kaomoji the old emoji text is gone from both files, the new text is in both blocks, outside text is identical" '0 0 2 2 yes' \
  "$(grep -cF -- "$BR5_E" "$TMP/vbr5/AGENTS.md") $(grep -cF -- "$BR5_E" "$TMP/vbr5/CLAUDE.md") $(grep -cF -- "$BR5_K" "$TMP/vbr5/AGENTS.md") $(grep -cF -- "$BR5_K" "$TMP/vbr5/CLAUDE.md") $(br5_out "$TMP/vbr5/AGENTS.md" | cmp -s - "$TMP/vbr5.before" && printf yes || printf no)"

# T-1072: an older knotlog earlier on PATH shadows the link; hooks call plain `knotlog`, so say so.
SH72_OLD="$TMP/sh72-old"; SH72_BIN="$TMP/sh72-bin"; mkdir -p "$SH72_OLD" "$SH72_BIN" "$TMP/sh72-par"
printf '#!/bin/sh\necho "knotlog 1.1.1"\n' > "$SH72_OLD/knotlog"; chmod +x "$SH72_OLD/knotlog"
mkvault vsh72; QUIPU_VAULT="$TMP/vsh72" sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1
SH72_DOC=$(PATH="$SH72_OLD:$INSTALL_TOOLS" QUIPU_VAULT="$TMP/vsh72" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1); SH72_RC=$?
t; assert_eq "T-1072: doctor warns (exit 0) when an older knotlog is first on PATH, naming its path and both versions" 'yes 0' \
  "$(printf '%s\n' "$SH72_DOC" | grep -qF "warn	knotlog	hooks will run $SH72_OLD/knotlog (knotlog 1.1.1), but this is knotlog 1.2.0" && printf yes || printf no) $SH72_RC"
SH72_NOKL=$(printf '%s\n' "$INSTALL_TOOLS" | tr ':' '\n' | while IFS= read -r _d; do [ -e "$_d/knotlog" ] || printf '%s:' "$_d"; done)
SH72_DOC=$(PATH="${SH72_NOKL%:}" QUIPU_VAULT="$TMP/vsh72" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1)
t; assert_eq "T-1072: doctor warns when knotlog is not on PATH at all" 'yes' \
  "$(printf '%s\n' "$SH72_DOC" | grep -qF "warn	knotlog	knotlog is not on PATH" && printf yes || printf no)"
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  ln -s "$ROOT/knotlog" "$SH72_BIN/knotlog"
  SH72_DOC=$(PATH="$SH72_BIN:$INSTALL_TOOLS" QUIPU_VAULT="$TMP/vsh72" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1)
  t; assert_eq "T-1072: doctor adds no knotlog warning when PATH finds this version" 'no' \
    "$(printf '%s\n' "$SH72_DOC" | grep -q "warn	knotlog	" && printf yes || printf no)"
  rm -f "$SH72_BIN/knotlog"
  chmod 555 "$SH72_OLD"
  if [ -w "$SH72_OLD" ]; then
    t; skip "T-1072: install summary names the shadowing knotlog" "running as a user that ignores directory modes"
  else
    PATH="$SH72_OLD:$SH72_BIN:$INSTALL_TOOLS" HOME="$TMP/sh72-home" QUIPU_LANG=en sh "$ROOT/knotlog" install "$TMP/sh72-par" \
      --no-prompt --user Ada --no-git >"$TMP/sh72.out" 2>"$TMP/sh72.err"; IRC=$?
    assert_install_rc "T-1072: install past a shadowing knotlog still succeeds (exit 0)" '0' "$IRC" "$TMP/sh72.err"
    t; assert_eq "T-1072: the summary lists the shadowing path and version under Skipped with a fix line" 'yes yes' \
      "$(grep -qF "  ! Command: PATH finds $SH72_OLD/knotlog (knotlog 1.1.1) before the link above; hooks will run that one" "$TMP/sh72.out" && printf yes || printf no) $(grep -qF "    fix: remove $SH72_OLD/knotlog or put $(cd "$SH72_BIN" && pwd -P) before it on PATH" "$TMP/sh72.out" && printf yes || printf no)"
  fi
  chmod 755 "$SH72_OLD"
fi

# T-1073: the replace-the-link question accepts the language's own yes and shows its letters.
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  l73() { # name lang answer -> exit code; the foreign-symlink fixture of T-1020
    L20_BIN="$TMP/l73-$1-bin"; L20_PAR="$TMP/l73-$1-par"; L20_TGT="$TMP/l73-$1-target"
    mkdir -p "$L20_BIN" "$L20_PAR"; printf 'dev checkout\n' > "$L20_TGT"
    make_true_symlink "$L20_TGT" "$L20_BIN/knotlog" || exit 1
    printf '%s\nL73\n\n\n\n\n%s\n' "$2" "$3" | PATH="$L20_BIN:$INSTALL_TOOLS" HOME="$TMP/l73-$1-home" QUIPU_LANG="$2" QUIPU_FORCE_TTY=1 \
      sh "$ROOT/knotlog" install "$L20_PAR" >"$TMP/l73-$1.out" 2>"$TMP/l73-$1.err"
  }
  l73 tre tr e; R73A=$?; l73 trh tr H; R73B=$?; l73 tre2 tr evet; R73C=$?; l73 es es si; R73D=$?; l73 pt pt-br sim; R73E=$?
  t; assert_eq "T-1073: tr e, tr evet, es si and pt-br sim replace the link (exit 0); tr H refuses (2)" '0 2 0 0 0' "$R73A $R73B $R73C $R73D $R73E"
  t; assert_eq "T-1073: the tr question shows [e/H], es and pt-br show [s/N]; the link stays when refused" 'yes yes yes yes' \
    "$(grep -qF '[e/H]' "$TMP/l73-trh.out" && printf yes || printf no) $(grep -qF '[s/N]' "$TMP/l73-es.out" && printf yes || printf no) $(grep -qF '[s/N]' "$TMP/l73-pt.out" && printf yes || printf no) $([ "$(readlink "$TMP/l73-trh-bin/knotlog")" = "$TMP/l73-trh-target" ] && printf yes || printf no)"
fi

# T-1074: a PATH that names $HOME/.local/bin before it exists gets the directory made; a PATH with no usable directory gets a concrete remedy.
mkdir -p "$TMP/l74-home" "$TMP/l74-par"
PATH="$TMP/l74-home/.local/bin:$INSTALL_TOOLS" HOME="$TMP/l74-home" QUIPU_LANG=en sh "$ROOT/knotlog" install "$TMP/l74-par" \
  --no-prompt --user Ada --no-git >"$TMP/l74.out" 2>"$TMP/l74.err"; IRC=$?
assert_install_rc "T-1074: install creates a missing \$HOME/.local/bin that PATH names (exit 0)" '0' "$IRC" "$TMP/l74.err"
t; assert_eq "T-1074: the command is linked in that directory" 'yes' \
  "$([ -d "$TMP/l74-home/.local/bin" ] && [ -e "$TMP/l74-home/.local/bin/knotlog" ] && printf yes || printf no)"
# Tools only, in a directory nobody can write to (skipped where modes are ignored, e.g. root).
mkdir -p "$TMP/l74b-home" "$TMP/l74b-par" "$TMP/l74b-tools"
for _x in awk basename cat chmod cmp cp cut date dd dirname find git grep head ln ls mkdir mktemp mv paste rm sed sh sort stty tail touch tr uname wc; do
  _p=$(command -p -v "$_x" 2>/dev/null) && [ -f "$_p" ] && ln -s "$_p" "$TMP/l74b-tools/$_x"
done
chmod 555 "$TMP/l74b-tools"
if [ -w "$TMP/l74b-tools" ]; then
  t; skip "T-1074: no usable PATH directory names the remedy" "running as a user that ignores directory modes"
else
  PATH="$TMP/l74b-tools" HOME="$TMP/l74b-home" QUIPU_LANG=en "$INSTALL_SHELL" "$ROOT/knotlog" install "$TMP/l74b-par" \
    --no-prompt --user Ada --no-git >"$TMP/l74b.out" 2>"$TMP/l74b.err"; IRC=$?
  assert_install_rc "T-1074: no usable PATH directory still exits 2" '2' "$IRC" "$TMP/l74b.err"
  t; assert_eq "T-1074: the message names the mkdir and PATH commands and --no-link; nothing is created" 'yes' \
    "$(grep -qF 'mkdir -p "$HOME/.local/bin"' "$TMP/l74b.err" && grep -qF -- '--no-link' "$TMP/l74b.err" \
       && [ ! -e "$TMP/l74b-home/.local" ] && printf yes || printf no)"
fi
chmod 755 "$TMP/l74b-tools"

# The vault prefix is matched loosely: on macOS $TMP has "//" and the vault walk may resolve /private/var.
# T-1075: uninstall removes client hook files still identical to their template, keeps and names changed ones.
mkvault vun75; QUIPU_VAULT="$TMP/vun75" sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1
for _a in codex gemini omp cursor; do QUIPU_VAULT="$TMP/vun75" sh "$ROOT/knotlog" setup "$_a" >/dev/null 2>&1; done
printf '\n' >> "$TMP/vun75/.gemini/settings.json"
UN75_D=$(cd "$TMP/vun75" && PATH="$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" uninstall --dry-run 2>&1)
t; assert_eq "T-1075: --dry-run lists the unchanged hook files and removes nothing" 'yes yes' \
  "$(printf '%s\n' "$UN75_D" | grep -qE "^Would remove: .*/vun75/\.codex/hooks\.json \(hook file" && printf yes || printf no) $([ -f "$TMP/vun75/.codex/hooks.json" ] && [ -f "$TMP/vun75/.omp/hooks/pre/knotlog.ts" ] && printf yes || printf no)"
UN75=$(cd "$TMP/vun75" && PATH="$INSTALL_TOOLS" QUIPU_LANG=en sh "$ROOT/knotlog" uninstall 2>&1)
t; assert_eq "T-1075: unchanged hook files (and the directories they leave empty) are gone, the edited one stays and is named" 'yes yes yes' \
  "$([ ! -e "$TMP/vun75/.codex" ] && [ ! -e "$TMP/vun75/.cursor" ] && [ ! -e "$TMP/vun75/.omp/hooks" ] && printf yes || printf no) $(printf '%s\n' "$UN75" | grep -qE "^Kept: .*/vun75/\.gemini/settings\.json differs from the template" && [ -f "$TMP/vun75/.gemini/settings.json" ] && printf yes || printf no) $(printf '%s\n' "$UN75" | grep -qE "^Removed: .*/vun75/\.cursor/hooks\.json \(hook file" && printf yes || printf no)"
t; assert_eq "T-1075: the vault's config and bridge file are untouched" 'yes' \
  "$([ -f "$TMP/vun75/.knotlog/config" ] && [ -f "$TMP/vun75/AGENTS.md" ] && printf yes || printf no)"

# ---- 1.2.0 security: links inside a vault never carry a write out of it (T-1080..T-1086) ----
# A cloned repository is adopted as a vault by the walk-up and may carry symlinks.
# Each outside target is compared with cksum before and after; hook runs exit 0, manual runs 1.
SO="$TMP/sec-out"
mkdir -p "$SO"
D=$(date +%Y-%m-%d)
sec_vault() { # name -> vault with two activity rows, the second naming a hostile path
  mkvault "$1"
  printf '%s\n' '2026-10-27T01:00 | PostToolUse | Read | a.md' '2026-10-27T01:01 | PostToolUse | Read | x; touch pwned' > "$TMP/$1/.knotlog/activity.log"
}
sec_target() { printf 'ORIGINAL %s\n' "$1" > "$SO/$1"; cksum < "$SO/$1"; }
sec_same() { if [ "$(cksum < "$SO/$1")" = "$2" ]; then printf same; else printf changed; fi; }
sec_rem() { # name hook(0|1) -> exit code of remember run from inside the vault (walk-up)
  (cd "$TMP/$1" && unset QUIPU_VAULT KNOTLOG_VAULT && QUIPU_HOOK=$2 QUIPU_LANG=en sh "$ROOT/knotlog" remember </dev/null >/dev/null 2>"$TMP/$1.err$2"); printf '%s' "$?"
}
sec_slink() { MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -s "$1" "$2"; }
SEC_MSG=$(i18n err_state_link); SEC_MSG=${SEC_MSG#%s}

if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  # T-1080: .knotlog/remembered -> outside file (the ~/.bashrc case).
  sec_vault s80; C80=$(sec_target t80); sec_slink "$SO/t80" "$TMP/s80/.knotlog/remembered"
  R80="$(sec_rem s80 1) $(sec_rem s80 0)"
  t; assert_eq "T-1080: symlinked .knotlog/remembered: hook exits 0, manual exits 1, the outside file is byte-identical" '0 1 same' "$R80 $(sec_same t80 "$C80")"
  t; assert_eq "T-1080: the manual run names the reason and no session note is written" 'yes no' \
    "$(grep -qF -- "$SEC_MSG" "$TMP/s80.err0" && printf yes || printf no) $([ -e "$TMP/s80/📆 700-Sessions" ] && printf yes || printf no)"
  t; assert_eq "T-1080: doctor still runs and fails on the link (exit 1)" 'yes 1' \
    "$(QUIPU_VAULT="$TMP/s80" QUIPU_LANG=en sh "$ROOT/knotlog" doctor >"$TMP/s80.doc" 2>&1; R=$?; grep -qF -- "$(i18n doc_state_link)" "$TMP/s80.doc" && printf yes || printf no; printf ' %s' "$R")"

  # T-1081: .knotlog/activity.log -> outside file; capture appends there unguarded.
  mkvault s81; C81=$(sec_target t81); sec_slink "$SO/t81" "$TMP/s81/.knotlog/activity.log"
  R81H=$(printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"x;payload"}}' | (cd "$TMP/s81" && unset QUIPU_VAULT KNOTLOG_VAULT && QUIPU_HOOK=1 sh "$ROOT/knotlog" capture >/dev/null 2>&1); printf '%s' "$?")
  R81M=$( (cd "$TMP/s81" && unset QUIPU_VAULT KNOTLOG_VAULT && sh "$ROOT/knotlog" capture --event PostToolUse --tool Read --path 'x;payload' >/dev/null 2>&1); printf '%s' "$?")
  t; assert_eq "T-1081: symlinked .knotlog/activity.log: hook capture exits 0, manual exits 1, the outside file is byte-identical" '0 1 same' "$R81H $R81M $(sec_same t81 "$C81")"

  # T-1082: today's session note -> outside file (remember appends the file list to it),
  # and a dangling Last-Session.md link (remember would create its target).
  sec_vault s82; C82=$(sec_target t82); mkdir -p "$TMP/s82/📆 700-Sessions"; sec_slink "$SO/t82" "$TMP/s82/📆 700-Sessions/$D.md"
  R82="$(sec_rem s82 1) $(sec_rem s82 0)"
  t; assert_eq "T-1082: symlinked session note: hook exits 0, manual exits 1, the outside file is byte-identical" '0 1 same' "$R82 $(sec_same t82 "$C82")"
  sec_vault s82b; sec_slink "$SO/t82b-new" "$TMP/s82b/Last-Session.md"
  R82B="$(sec_rem s82b 1) $(sec_rem s82b 0)"
  t; assert_eq "T-1082: dangling Last-Session.md link: hook exits 0, manual exits 1, nothing is created outside" '0 1 no' \
    "$R82B $([ -e "$SO/t82b-new" ] && printf yes || printf no)"

  # T-1083: .knotlog itself -> an outside directory.
  mkdir -p "$TMP/s83" "$SO/sd83"; : > "$SO/sd83/config"
  printf '%s\n' '2026-10-27T01:00 | PostToolUse | Read | a.md' '2026-10-27T01:01 | PostToolUse | Read | b.md' > "$SO/sd83/activity.log"
  C83=$(cksum < "$SO/sd83/activity.log"); L83=$(ls -A "$SO/sd83")
  sec_slink "$SO/sd83" "$TMP/s83/.knotlog"
  R83="$(sec_rem s83 1) $(sec_rem s83 0)"
  t; assert_eq "T-1083: symlinked .knotlog directory: hook exits 0, manual exits 1, the outside directory gains no file" '0 1 yes yes' \
    "$R83 $([ "$(ls -A "$SO/sd83")" = "$L83" ] && printf yes || printf no) $([ "$(cksum < "$SO/sd83/activity.log")" = "$C83" ] && printf yes || printf no)"

  # T-1086: the vault root itself may be a link (a vault moved to another disk): unchanged behaviour.
  sec_vault s86real; sec_slink "$TMP/s86real" "$TMP/s86"
  R86=$(sec_rem s86 0)
  t; assert_eq "T-1086: a symlinked vault root still remembers (exit 0, session note and Last-Session.md in the real directory)" '0 yes yes' \
    "$R86 $([ -f "$TMP/s86real/📆 700-Sessions/$D.md" ] && printf yes || printf no) $([ -f "$TMP/s86real/Last-Session.md" ] && printf yes || printf no)"
else
  for _s in T-1080 T-1080 T-1080 T-1081 T-1082 T-1082 T-1083 T-1086; do
    t; skip "$_s: symlink write scenarios" "no native symlinks on this host"
  done
fi

# T-1084: an unshipped layout= (a path to a layout file of the repository's own) falls back to emoji
# in remember and note, so its sessions folder cannot point outside the vault.
UP84=$(printf '%s\n' "$ROOT/layout" | awk -F/ '{ for (i = 1; i <= NF + 10; i++) printf "../" }')
printf 'sessions\t../s84-out\n' > "$SO/lay84.txt"
sec_vault s84; printf 'layout=%s%s\n' "$UP84" "${SO#/}/lay84" > "$TMP/s84/.knotlog/config"
R84=$(QUIPU_VAULT="$TMP/s84" QUIPU_LANG=en sh "$ROOT/knotlog" remember >/dev/null 2>&1; printf '%s' "$?")
R84N=$(QUIPU_VAULT="$TMP/s84" QUIPU_LANG=en sh "$ROOT/knotlog" note "hello" >/dev/null 2>&1; printf '%s' "$?")
t; assert_eq "T-1084: bad layout=: remember and note exit 0, write today's note under the emoji sessions folder, nothing outside" '0 0 yes no' \
  "$R84 $R84N $(grep -q 'hello' "$TMP/s84/📆 700-Sessions/$D.md" 2>/dev/null && printf yes || printf no) $([ -e "$TMP/s84-out" ] && printf yes || printf no)"

# T-1085: a layout whose sessions folder climbs out (sessions=../x) is refused by remember and note.
H85="$TMP/home85"; mkdir -p "$H85"
cp -R "$ROOT/knotlog" "$ROOT/lib" "$ROOT/i18n" "$ROOT/layout" "$ROOT/fold" "$H85/"
printf 'sessions\t../s85-out\n' > "$H85/layout/evil.txt"
sec_vault s85; printf 'layout=evil\n' > "$TMP/s85/.knotlog/config"
R85M=$(QUIPU_HOME="$H85" QUIPU_VAULT="$TMP/s85" QUIPU_LANG=en sh "$H85/knotlog" remember >/dev/null 2>&1; printf '%s' "$?")
R85H=$(QUIPU_HOME="$H85" QUIPU_VAULT="$TMP/s85" QUIPU_HOOK=1 QUIPU_LANG=en sh "$H85/knotlog" remember </dev/null >/dev/null 2>&1; printf '%s' "$?")
R85N=$(QUIPU_HOME="$H85" QUIPU_VAULT="$TMP/s85" QUIPU_LANG=en sh "$H85/knotlog" note "hello" >/dev/null 2>&1; printf '%s' "$?")
t; assert_eq "T-1085: sessions=../x: manual remember exits 1, hook remember 0, note 1; nothing is written outside the vault" '1 0 1 no' \
  "$R85M $R85H $R85N $([ -e "$TMP/s85-out" ] && printf yes || printf no)"

# T-1087/T-1088: config values that name shipped files (fold=, tone=, lang=) are
# names, never paths -- a cloned repository's config must not pick a sed script
# for index to run, or a file outside the checkout for context to print.
SEC87_ABS=$(cd "$TMP" && pwd -P)
SEC87_UP=../../../../../../../../../../../../../../../../../../../..
mkdir -p "$SEC87_ABS/sec87-out"
printf 'w %s/sec87-out/ran\n' "$SEC87_ABS" > "$SEC87_ABS/sec87-out/evil.sed"
printf 'SEC87 PRIVATE NOTE\n' > "$SEC87_ABS/sec87-out/private.md"
mkvault vsec87; QUIPU_VAULT="$TMP/vsec87" sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1
printf '# n\n\nbody\n' > "$TMP/vsec87/n.md"
# init wrote fold=default and the first fold= wins; a hostile config carries only its own.
grep -v '^fold=' "$TMP/vsec87/.knotlog/config" > "$TMP/vsec87.cfg"
printf 'fold=%s%s/sec87-out/evil\n' "$SEC87_UP" "$SEC87_ABS" >> "$TMP/vsec87.cfg"
cat "$TMP/vsec87.cfg" > "$TMP/vsec87/.knotlog/config"
KNOTLOG_HOOK=1 QUIPU_VAULT="$TMP/vsec87" sh "$ROOT/knotlog" index --full >/dev/null 2>&1
QUIPU_VAULT="$TMP/vsec87" sh "$ROOT/knotlog" search body >/dev/null 2>&1
SEC87_DOC=$(QUIPU_VAULT="$TMP/vsec87" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1)
t; assert_eq "T-1087: a path in fold= never runs as index's or search's sed script, and doctor fails it" 'no yes' \
  "$([ -e "$SEC87_ABS/sec87-out/ran" ] && printf yes || printf no) $(printf '%s\n' "$SEC87_DOC" | grep -q '^fail	' && printf yes || printf no)"
mkvault vsec88; QUIPU_VAULT="$TMP/vsec88" sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1
printf 'tone=%s%s/sec87-out/private\n' "$SEC87_UP" "$SEC87_ABS" >> "$TMP/vsec88/.knotlog/config"
SEC88_A=$(KNOTLOG_HOOK=1 QUIPU_VAULT="$TMP/vsec88" sh "$ROOT/knotlog" context 2>&1)
mkvault vsec88b; QUIPU_VAULT="$TMP/vsec88b" sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1
mkdir -p "$SEC87_ABS/sec87-out/x"; cp "$SEC87_ABS/sec87-out/private.md" "$SEC87_ABS/sec87-out/x/dostane.md"
sed 's/^lang=.*//' "$TMP/vsec88b/.knotlog/config" > "$TMP/vsec88b.cfg" && cat "$TMP/vsec88b.cfg" > "$TMP/vsec88b/.knotlog/config"
printf 'lang=%s%s/sec87-out/x\ntone=dostane\n' "$SEC87_UP" "$SEC87_ABS" >> "$TMP/vsec88b/.knotlog/config"
SEC88_B=$(KNOTLOG_HOOK=1 QUIPU_VAULT="$TMP/vsec88b" sh "$ROOT/knotlog" context 2>&1)
# The lang= half is defence in depth: _q_lang already cut such a path at its first '-'.
t; assert_eq "T-1088: a path in tone= or lang= never pulls a file from outside the checkout into context" 'no no' \
  "$(printf '%s\n' "$SEC88_A" | grep -qF 'SEC87 PRIVATE NOTE' && printf yes || printf no) $(printf '%s\n' "$SEC88_B" | grep -qF 'SEC87 PRIVATE NOTE' && printf yes || printf no)"

# ---- 1.2.0 security: input validation (T-1090..T-1103) ----
# A cloned repository adopted as a vault, or a folder init/install is pointed at,
# may carry links and hostile state. Each outside target is a marker file under
# $SO; the test measures its bytes (cksum) or its absence from the output.
SEC_TAB=$(printf '\t')
SEC_COMP=$(awk -F"$SEC_TAB" '$1=="companion"{print $2;exit}' "$ROOT/layout/plain.txt")
sec_init() { mkvault "$1"; QUIPU_VAULT="$TMP/$1" sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1; }
sec_has() { if printf '%s\n' "$1" | grep -qF -- "$2"; then printf yes; else printf no; fi; }
sec_empty() { if [ -z "$(ls -A "$1")" ]; then printf empty; else printf filled; fi; }
sec_git() { HOME="$TMP/sec-home" GIT_CONFIG_GLOBAL="$TMP/sec-home/.gitconfig" GIT_CONFIG_SYSTEM=/dev/null "$@"; }
sec_gitc() { (cd "$1" && shift && sec_git git "$@"); } # no git -C: Git for Windows misreads POSIX paths
SEC_KNOW=$(awk -F"$SEC_TAB" '$1=="knowledge"{print $2;exit}' "$ROOT/layout/plain.txt")
mkdir -p "$TMP/sec-home"

if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  # T-1090: the hook's context never reads a linked Threads/Rules/Facts/companion file.
  sec_init s90
  printf '# Threads\n\nSEC90 OWN THREADS\n' > "$TMP/s90/Threads.md"
  O90A=$(KNOTLOG_HOOK=1 QUIPU_VAULT="$TMP/s90" sh "$ROOT/knotlog" context --json UserPromptSubmit 2>&1)
  printf '# Threads\n\nSEC90 THREADS\n' > "$SO/t90-thr"
  printf '# SEC90 RULES\n' > "$SO/t90-rul"
  printf -- '- Fact: SEC90 FACTS\n' > "$SO/t90-fts"
  printf '# c\n\n## Tone\n\nSEC90 TONE\n' > "$SO/t90-cmp"
  rm -f "$TMP/s90/Threads.md" "$TMP/s90/Rules.md" "$TMP/s90/Facts.md" "$TMP/s90/$SEC_COMP/companion.md"
  sec_slink "$SO/t90-thr" "$TMP/s90/Threads.md"; sec_slink "$SO/t90-rul" "$TMP/s90/Rules.md"
  sec_slink "$SO/t90-fts" "$TMP/s90/Facts.md"; sec_slink "$SO/t90-cmp" "$TMP/s90/$SEC_COMP/companion.md"
  O90=$(KNOTLOG_HOOK=1 QUIPU_VAULT="$TMP/s90" sh "$ROOT/knotlog" context --json UserPromptSubmit 2>&1); R90=$?
  t; assert_eq "T-1090: a real Threads.md reaches context; linked Threads/Rules/Facts/companion.md never do (hook exit 0)" 'yes 0 no no no no' \
    "$(sec_has "$O90A" 'SEC90 OWN THREADS') $R90 $(sec_has "$O90" 'SEC90 THREADS') $(sec_has "$O90" 'SEC90 RULES') $(sec_has "$O90" 'SEC90 FACTS') $(sec_has "$O90" 'SEC90 TONE')"

  # T-1091 (link half): a linked .githooks folder gets no pre-commit and no hooksPath.
  mkdir -p "$TMP/s91b" "$SO/hk91b"; sec_gitc "$TMP/s91b" init -q; sec_slink "$SO/hk91b" "$TMP/s91b/.githooks"
  sec_git env QUIPU_VAULT="$TMP/s91b" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1
  t; assert_eq "T-1091: a symlinked .githooks folder: the outside folder stays empty and core.hooksPath is unset" 'empty none' \
    "$(sec_empty "$SO/hk91b") $(sec_gitc "$TMP/s91b" config --local --get core.hooksPath || printf none)"

  # T-1092: init on a folder whose .knotlog is a link (no config, so the walk-up never saw it).
  mkdir -p "$TMP/s92" "$SO/sd92"; sec_slink "$SO/sd92" "$TMP/s92/.knotlog"
  R92=$(cd "$TMP/s92" && unset QUIPU_VAULT KNOTLOG_VAULT && QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>"$TMP/s92.err"; printf '%s' "$?")
  t; assert_eq "T-1092: init refuses a symlinked state directory (exit 1, reason named) and writes nothing through it" '1 yes empty' \
    "$R92 $(grep -qF -- "$SEC_MSG" "$TMP/s92.err" && printf yes || printf no) $(sec_empty "$SO/sd92")"

  # T-1093: init never reads or writes through links in the vault tree.
  mkdir -p "$TMP/s93"; C93=$(sec_target t93); sec_slink "$SO/t93" "$TMP/s93/AGENTS.md"
  R93=$(QUIPU_VAULT="$TMP/s93" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1; printf '%s' "$?")
  t; assert_eq "T-1093: a linked AGENTS.md: init exits 1, the outside file is byte-identical and its text is not copied in" '1 same no' \
    "$R93 $(sec_same t93 "$C93") $(grep -qF 'ORIGINAL t93' "$TMP/s93/AGENTS.md" 2>/dev/null && [ ! -L "$TMP/s93/AGENTS.md" ] && printf yes || printf no)"
  mkdir -p "$TMP/s93b" "$SO/cd93b"; sec_slink "$SO/cd93b" "$TMP/s93b/$SEC_COMP"
  QUIPU_VAULT="$TMP/s93b" sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1
  mkdir -p "$TMP/s93c"; sec_slink "$SO/t93c-new" "$TMP/s93c/Threads.md"
  QUIPU_VAULT="$TMP/s93c" sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1
  t; assert_eq "T-1093: a linked companion folder stays empty; a dangling Threads.md link creates nothing outside" 'empty no' \
    "$(sec_empty "$SO/cd93b") $([ -e "$SO/t93c-new" ] && printf yes || printf no)"

  # T-1094: uninstall never deletes a hook file through a linked folder (.claude -> elsewhere).
  sec_init s94; mkdir -p "$SO/cl94"; cp "$ROOT/adapters/claude-code.json" "$SO/cl94/settings.json"
  rm -rf "$TMP/s94/.claude"; sec_slink "$SO/cl94" "$TMP/s94/.claude"
  (cd "$TMP/s94" && unset QUIPU_VAULT KNOTLOG_VAULT && PATH="$INSTALL_TOOLS" HOME="$TMP/sec-home" QUIPU_LANG=en sh "$ROOT/knotlog" uninstall >/dev/null 2>&1)
  t; assert_eq "T-1094: uninstall leaves settings.json behind a symlinked .claude folder in place" 'yes' \
    "$([ -f "$SO/cl94/settings.json" ] && printf yes || printf no)"

  # T-1095: migrate --apply refuses a linked .gitattributes (it would append the union lines there).
  sec_init s95; C95=$(sec_target t95); rm -f "$TMP/s95/.gitattributes"; sec_slink "$SO/t95" "$TMP/s95/.gitattributes"
  R95=$(QUIPU_VAULT="$TMP/s95" QUIPU_LANG=en sh "$ROOT/knotlog" migrate --apply >/dev/null 2>&1; printf '%s' "$?")
  t; assert_eq "T-1095: migrate --apply with a symlinked .gitattributes exits 1 and the outside file is byte-identical" '1 same' \
    "$R95 $(sec_same t95 "$C95")"

  # T-1096: repair-hooks refuses a linked .icon folder.
  mkdir -p "$TMP/s96" "$SO/ic96"; cp "$ROOT/repair-hooks" "$TMP/s96/repair-hooks"; sec_slink "$SO/ic96" "$TMP/s96/.icon"
  R96=$(sh "$TMP/s96/repair-hooks" --knotlog "$ROOT" --metadata-only >/dev/null 2>&1; printf '%s' "$?")
  t; assert_eq "T-1096: repair-hooks with a symlinked .icon folder exits 1 and the outside folder stays empty" '1 empty' \
    "$R96 $(sec_empty "$SO/ic96")"

  # T-1097: a reinstall over a vault whose .omp folder is a link writes nothing through it.
  P97="$TMP/p97"; V97="$P97/Ada's Knotlog"; mkdir -p "$V97/.knotlog" "$SO/omp97"; : > "$V97/.knotlog/config"
  sec_slink "$SO/omp97" "$V97/.omp"
  R97=$(sec_git env PATH="$INSTALL_TOOLS" QUIPU_HOME="$ROOT" QUIPU_LANG=en sh "$ROOT/knotlog" install --no-link "$P97" --no-prompt --user Ada --lang en --no-git >/dev/null 2>&1; printf '%s' "$?")
  t; assert_eq "T-1097: install over a vault with a symlinked .omp folder exits 1 and the outside folder stays empty" '1 empty' \
    "$R97 $(sec_empty "$SO/omp97")"
else
  for _s in T-1090 T-1091 T-1092 T-1093 T-1093 T-1094 T-1095 T-1096 T-1097; do
    t; skip "$_s: symlink scenarios" "no native symlinks on this host"
  done
fi

# T-1091: .githooks holding hooks besides pre-commit is not armed with core.hooksPath.
mkdir -p "$TMP/s91/.githooks" "$TMP/s91c"; sec_gitc "$TMP/s91" init -q; sec_gitc "$TMP/s91c" init -q
printf '#!/bin/sh\nexit 0\n' > "$TMP/s91/.githooks/post-commit"
O91=$(sec_git env QUIPU_VAULT="$TMP/s91" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en 2>&1)
sec_git env QUIPU_VAULT="$TMP/s91c" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang en >/dev/null 2>&1
t; assert_eq "T-1091: a .githooks with other hooks: no hooksPath, no pre-commit, the reason is named; a clean repo still gets .githooks" 'none no yes .githooks' \
  "$(sec_gitc "$TMP/s91" config --local --get core.hooksPath || printf none) $([ -e "$TMP/s91/.githooks/pre-commit" ] && printf yes || printf no) $(sec_has "$O91" "$(i18n hooks_foreign)") $(sec_gitc "$TMP/s91c" config --local --get core.hooksPath)"

# T-1098: compile and doctor read only real .md files of the vault, whatever index.tsv names.
sec_init s98; printf '# Note\n\nbody\n' > "$TMP/s98/n.md"
printf '# Threads\n\n## SEC98 TOPIC\n' > "$TMP/s98/Threads.md"
QUIPU_VAULT="$TMP/s98" sh "$ROOT/knotlog" index >/dev/null 2>&1
# Threads.md's own row would date the topic today; only the hostile rows may.
grep -v '^Threads.md' "$TMP/s98/.knotlog/index.tsv" > "$TMP/s98.idx"; cat "$TMP/s98.idx" > "$TMP/s98/.knotlog/index.tsv"
printf '# SEC98 SECRET\n\n# SEC98 TOPIC\n' > "$SO/t98.md"
printf '../sec-out/t98.md\t\t\t1000000000\t\t\t\t\n' >> "$TMP/s98/.knotlog/index.tsv"
if [ "$TRUE_SYMLINKS" -eq 1 ]; then
  printf '# SEC98 LINKED\n' > "$SO/t98b.md"; sec_slink "$SO/t98b.md" "$TMP/s98/l98.md"
  printf 'l98.md\t\t\t1000000000\t\t\t\t\n' >> "$TMP/s98/.knotlog/index.tsv"
fi
QUIPU_VAULT="$TMP/s98" QUIPU_LANG=en sh "$ROOT/knotlog" compile >/dev/null 2>&1
D98=$(QUIPU_VAULT="$TMP/s98" QUIPU_LANG=en sh "$ROOT/knotlog" doctor 2>&1)
t; assert_eq "T-1098: compile writes no heading of a file outside the vault or behind a link; doctor never dates a topic from one" 'no no no' \
  "$(grep -rqF 'SEC98 SECRET' "$TMP/s98/$SEC_KNOW" && printf yes || printf no) $(grep -rqF 'SEC98 LINKED' "$TMP/s98/$SEC_KNOW" && printf yes || printf no) $(sec_has "$D98" 'SEC98 TOPIC')"

# T-1099: a number with a leading 0 in config (ctx_max) or state (checkpoint_nudged) never aborts the hook.
sec_init s99; printf 'ctx_max=08\n' >> "$TMP/s99/.knotlog/config"
O99=$(KNOTLOG_HOOK=1 QUIPU_VAULT="$TMP/s99" sh "$ROOT/knotlog" context --json SessionStart 2>&1); R99=$?
sec_init s99b; printf '08\n' > "$TMP/s99b/.knotlog/checkpoint_nudged"
O99B=$(KNOTLOG_HOOK=1 QUIPU_VAULT="$TMP/s99b" sh "$ROOT/knotlog" context --json UserPromptSubmit 2>&1); R99B=$?
t; assert_eq "T-1099: ctx_max=08 and checkpoint_nudged=08: context exits 0 with its usual output" '0 yes 0 yes' \
  "$R99 $(sec_has "$O99" 'additionalContext') $R99B $(sec_has "$O99B" 'additionalContext')"

# T-1100: an incremental index stats a note whose name starts with '-'.
sec_init s100; QUIPU_VAULT="$TMP/s100" sh "$ROOT/knotlog" index >/dev/null 2>&1
touch_at 1000000000 "$TMP/s100/.knotlog/index.tsv"
printf '# Dash\n\nsec100zebra\n' > "$TMP/s100/-L.md"
R100=$(QUIPU_VAULT="$TMP/s100" sh "$ROOT/knotlog" index >/dev/null 2>&1; printf '%s' "$?")
t; assert_eq "T-1100: index of a changed -L.md exits 0 and search finds it" '0 yes' \
  "$R100 $(QUIPU_VAULT="$TMP/s100" sh "$ROOT/knotlog" search sec100zebra 2>/dev/null | grep -qF -- '-L.md' && printf yes || printf no)"

# T-1101: capture keeps TAB/CR/LF out of the event and tool fields (one payload, one log row).
mkvault s101
printf '%s\n' '{"hook_event_name":"PostToolUse\n2026-01-01T00:00 | Fake | Read | forged.md","tool_name":"Re\tad\r","tool_input":{"file_path":"a.md"}}' |
  (cd "$TMP/s101" && unset QUIPU_VAULT KNOTLOG_VAULT && KNOTLOG_HOOK=1 sh "$ROOT/knotlog" capture >/dev/null 2>&1)
t; assert_eq "T-1101: an event name carrying a newline adds exactly one activity.log row, naming the real path" '1 a.md' \
  "$(wc -l < "$TMP/s101/.knotlog/activity.log" | tr -d ' ') $(awk -F' [|] ' 'END { print $NF }' "$TMP/s101/.knotlog/activity.log")"

# T-1102: the walk-up still adopts a vault the running user owns (another user's vault
# is refused by [ -O ]; a test cannot own a file as someone else, see the code comment).
sec_init s102; mkdir -p "$TMP/s102/sub/dir"
R102=$(cd "$TMP/s102/sub/dir" && unset QUIPU_VAULT KNOTLOG_VAULT && QUIPU_LANG=en sh "$ROOT/knotlog" context >/dev/null 2>&1; printf '%s' "$?")
t; assert_eq "T-1102: context from a subfolder of the user's own vault finds it (exit 0)" '0' "$R102"

# T-1103: init --lang takes a language code only (it lands in a sed replacement and config).
mkvault s103
R103=$(QUIPU_VAULT="$TMP/s103" QUIPU_LANG=en sh "$ROOT/knotlog" init --plain --no-prompt --user Ada --lang 'en/x' >/dev/null 2>&1; printf '%s' "$?")
t; assert_eq "T-1103: init --lang en/x exits 2 and writes no lang= line" '2 no' \
  "$R103 $(grep -q '^lang=' "$TMP/s103/.knotlog/config" && printf yes || printf no)"

# ---- search query normalization (T-1300..T-1313) ----
# Query terms get the same word-boundary treatment as the document side:
# leading ( ' " and trailing . , ; : ! ? ) ' " are dropped, inner punctuation
# stays, punctuation-only terms are dropped, repeated terms count once.
mk_qnorm_vault() { # dir fold
  mkvault "$1"; printf 'fold=%s\nlang=en\n' "$2" > "$TMP/$1/.knotlog/config"
}
mk_qnorm_vault qn1 tr
printf '# Music\n\nI use spotify for playlist building. Another playlist here.\n' > "$TMP/qn1/spot.md"
printf '# Songs\n\nA playlist of old songs.\n' > "$TMP/qn1/other.md"
printf '# Code\n\nc++ and node.js tips, see #etiket and the --tag flag. Version 3.14 on 2026-10-30.\n' > "$TMP/qn1/code.md"
printf '# Turkce\n\nÇalışma ğüşıöç notları.\n' > "$TMP/qn1/tr.md"
printf '# Filler one\n\nnothing to see.\n' > "$TMP/qn1/f1.md"
printf '# Filler two\n\nstill nothing.\n' > "$TMP/qn1/f2.md"
QUIPU_VAULT="$TMP/qn1" sh "$ROOT/knotlog" index >/dev/null 2>&1
qn() { QUIPU_VAULT="$TMP/$1" sh "$ROOT/knotlog" search "$2" 2>&1; }

QN_BASE=$(qn qn1 spotify)
t; assert_eq "T-1300: search 'spotify?' returns the same rows as 'spotify'" "$QN_BASE" "$(qn qn1 'spotify?')"
t; assert_eq "T-1301: search '(\"spotify\"),' returns the same rows as 'spotify'" "$QN_BASE" "$(qn qn1 '("spotify"),')"
t; assert_eq "T-1302: a repeated term scores like a single one" \
  "$(qn qn1 'playlist spotify')" "$(qn qn1 'playlist playlist spotify')"

# A term repeated more often than there are notes used to push df past n and log() below zero.
mk_qnorm_vault qn2 tr
printf '# One\n\nplaylist spotify\n' > "$TMP/qn2/one.md"
QUIPU_VAULT="$TMP/qn2" sh "$ROOT/knotlog" index >/dev/null 2>&1
QN2=$(qn qn2 'playlist playlist playlist')
t; assert_eq "T-1303: a thrice-repeated term in a one-note vault prints no nan and no awk warning" \
  "$(qn qn2 playlist)" "$QN2"

# Edge cases below are green on the old code too: they pin today's behavior.
qnp() { QUIPU_VAULT="$TMP/$1" sh "$ROOT/knotlog" search "$2" --paths 2>&1; }
t; assert_eq "T-1304: c++ keeps its trailing plus" 'code.md' "$(qnp qn1 'c++')"
t; assert_eq "T-1305: node.js keeps its inner dot" 'code.md' "$(qnp qn1 'node.js')"
t; assert_eq "T-1306: #etiket keeps its leading hash" 'code.md' "$(qnp qn1 '#etiket')"
t; assert_eq "T-1307: --tag keeps its leading dashes" 'code.md' "$(qnp qn1 'zzz --tag')"
t; assert_eq "T-1308: a number and a date match" 'code.md code.md' "$(qnp qn1 '3.14') $(qnp qn1 '2026-10-30')"
t; assert_eq "T-1309: folded Turkish letters match (fold=tr)" 'tr.md' "$(qnp qn1 'ğüşıöç')"
t; assert_eq "T-1310: a punctuation-only term is ignored" "$QN_BASE" "$(qn qn1 'spotify ?')"
t; QN_P=$(QUIPU_VAULT="$TMP/qn1" sh "$ROOT/knotlog" search '?!' 2>&1); RC=$?
assert_eq "T-1311: an all-punctuation query is a no-match (exit 0, no output)" '0 []' "$RC [$QN_P]"

mk_qnorm_vault qn3 default
printf '# Turkce\n\nÇalışma ğüşıöç notları.\n' > "$TMP/qn3/tr.md"
printf '# Other\n\nnothing here.\n' > "$TMP/qn3/o.md"
QUIPU_VAULT="$TMP/qn3" sh "$ROOT/knotlog" index >/dev/null 2>&1
t; assert_eq "T-1312: unfolded Turkish letters match (fold=default)" 'tr.md' "$(qnp qn3 'ğüşıöç')"
t; assert_eq "T-1313: trailing punctuation drops off an unfolded Turkish term (fold=default)" 'tr.md' "$(qnp qn3 'ğüşıöç?')"

printf '# pass %d, fail %d, skip %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
