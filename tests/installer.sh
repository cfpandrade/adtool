#!/usr/bin/env bash
# Installer tests. Author: Carlos Andrade <carlos@perezandrade.com>
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/adtool-installer.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

for executable in ldapsearch ldapmodify ldapwhoami klist python3 iconv base64; do
  ln -s "$(command -v true)" "$TMP/bin/$executable"
done

export PATH="$TMP/bin:/usr/bin:/bin"
PREFIX=$TMP/prefix
CONFIG_DIR=$TMP/config

"$ROOT/install.sh" --prefix "$PREFIX" --config-dir "$CONFIG_DIR" >/dev/null
test -x "$PREFIX/bin/adtool"
test -f "$PREFIX/share/bash-completion/completions/adtool"
test -f "$PREFIX/share/zsh/site-functions/_adtool"
test -f "$PREFIX/share/man/man1/adtool.1"
test -f "$CONFIG_DIR/config"

printf '\n# preserved\n' >>"$CONFIG_DIR/config"
"$ROOT/install.sh" --prefix "$PREFIX" --config-dir "$CONFIG_DIR" >/dev/null
grep -F '# preserved' "$CONFIG_DIR/config" >/dev/null

"$ROOT/install.sh" --prefix "$PREFIX" --config-dir "$CONFIG_DIR" --uninstall >/dev/null
test ! -e "$PREFIX/bin/adtool"
test -f "$CONFIG_DIR/config"

"$ROOT/install.sh" --prefix "$PREFIX" --config-dir "$CONFIG_DIR" --uninstall --purge >/dev/null
test ! -e "$CONFIG_DIR"

printf 'Installer tests passed.\n'
