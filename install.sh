#!/bin/sh
# knotlog — one-line installer (B7).
#
#   curl -fsSL https://raw.githubusercontent.com/MSelmanSonmez/Knotlog/main/install.sh | sh
#
# Downloads the release tarball (curl, falling back to wget), verifies its
# contents against a text anchor, and hands over to `knotlog install`, which
# owns the guided setup. Any arguments are forwarded:
#
#   sh install.sh --no-prompt --user "Ada" --lang en
#
# Security shape (Fornhere plan B7, both details mandatory):
#   1. Everything lives inside main(); the ONLY top-level statements are
#      constants and the final call. A download truncated mid-stream leaves
#      bash/sh with a partial script in which main() is never defined — and
#      never called.
#   2. The extracted tree is verified BEFORE anything is installed: it must
#      contain an executable `knotlog` whose text matches the version anchor.
#      No anchor, no install.
#
# Env overrides (also how the test suite stays offline):
#   GITHUB_RELEASE_URL  tarball to download (default: the pinned release)
#   KNOTLOG_INSTALL_DIR where the checkout is unpacked for `knotlog install`
#                       to link from (default: ~/.local/share/knotlog)
#                       (the pre-rename QUIPU_INSTALL_DIR still works)
#
# Release discipline: the pinned default URL below must be bumped on every
# release. Keep the script POSIX sh; messages are English-only on
# purpose (piped shells have no language context; knotlog's own installer is
# the localized layer).

set -eu

_q_default_url='https://github.com/MSelmanSonmez/Knotlog/archive/refs/tags/v1.0.0.tar.gz'
# The --version line is stable text every release carries; grepping for it
# (never running the download) is the content check.
_q_anchor="--version) printf 'knotlog "
# A checkout installed before the rename carries quipu and this anchor.
_q_anchor_v2="--version) printf 'quipu "
_q_die() {
  printf 'knotlog-install: error: %s\n' "$1" >&2
  exit 1
}

_q_fetch() {
  # $1 = url, $2 = output file. curl first, wget as fallback, no third option.
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -- "$1" > "$2" || _q_die "download failed: $1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" -- "$1" || _q_die "download failed: $1"
  else
    _q_die 'need curl or wget to download the release tarball'
  fi
}

_q_find_knotlog() {
  # Print the path of the extracted executable, or nothing. Unmatched globs
  # survive as literals and fail the -f test, which is exactly what we want.
  # $1 = extracted root, $2 = anchor text.
  for _fq in "$1/knotlog" "$1"/*/knotlog; do
    if [ -f "$_fq" ] && [ -x "$_fq" ] && grep -qF -- "$2" "$_fq"; then
      printf '%s\n' "$_fq"
      return 0
    fi
  done
  return 1
}

main() {
  if [ -z "${HOME:-}" ]; then
    _q_die 'HOME is not set; refusing to guess an install directory'
  fi
  _url=${GITHUB_RELEASE_URL:-$_q_default_url}
  _dest=${KNOTLOG_INSTALL_DIR:-${QUIPU_INSTALL_DIR:-"$HOME/.local/share/knotlog"}}

  case $_url in
    *.zip) _q_die 'Windows archives belong to install.ps1, not this script' ;;
  esac
  # Work in a staging dir next to the destination: same filesystem, so the
  # final mv is atomic, and the EXIT trap sweeps every failure path.
  _dest_parent=$(dirname -- "$_dest")
  mkdir -p -- "$_dest_parent" || _q_die "cannot create $_dest_parent"
  _parent=$(CDPATH='' cd -- "$_dest_parent" && pwd)
  _staging=$_parent/.knotlog-install.$$
  mkdir -p -- "$_staging/src" || _q_die "cannot create staging dir $_staging"
  trap 'rm -rf -- "$_staging"' EXIT HUP INT TERM

  _tarball=$_staging/tarball
  _q_fetch "$_url" "$_tarball"

  case $_url in
    *.tar.gz|*.tgz|*.gz)
      if ! tar -xzf "$_tarball" -C "$_staging/src" 2>/dev/null; then
        _q_die 'the downloaded archive is not a readable .tar.gz (truncated or corrupt?)'
      fi
      ;;
    *)
      if ! tar -xf "$_tarball" -C "$_staging/src" 2>/dev/null; then
        _q_die 'the downloaded archive is not a readable tar (truncated or corrupt?)'
      fi
      ;;
  esac
  if ! _src=$(_q_find_knotlog "$_staging/src" "$_q_anchor"); then
    _q_die 'verification failed: the archive has no executable knotlog carrying the version anchor'
  fi
  _src_dir=$(CDPATH='' cd -- "$(dirname -- "$_src")" && pwd)

  # Only ever replace a directory that already looks like a checkout (a
  # knotlog one, or a quipu one from before the rename) or is missing /
  # empty — never an arbitrary user path.
  if [ -e "$_dest" ]; then
    if [ -n "$(ls -A -- "$_dest" 2>/dev/null)" ] &&
      ! grep -qF -- "$_q_anchor" "$_dest/knotlog" 2>/dev/null &&
      ! grep -qF -- "$_q_anchor_v2" "$_dest/quipu" 2>/dev/null; then
      _q_die "refusing to overwrite '$_dest': it exists, is not empty, and is not a knotlog checkout"
    fi
  fi

  rm -rf -- "$_dest"
  mv -- "$_src_dir" "$_dest"
  rm -rf -- "$_staging"
  trap - EXIT HUP INT TERM

  printf 'knotlog-install: verified and unpacked into %s\n' "$_dest"
  printf 'knotlog-install: handing over to knotlog install\n'
  exec "$_dest/knotlog" install "$@"
}

main "$@"
