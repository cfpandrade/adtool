#!/usr/bin/env bash
# Portable adtool installer. Author: Carlos Andrade <carlos@perezandrade.com>
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREFIX=${HOME}/.local
BIN_DIR=
CONF_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/adtool
SYSTEM=0
UNINSTALL=0
PURGE=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Install adtool for the current user (the default) or system-wide.

Usage: ./install.sh [OPTIONS]

  --prefix DIR       Installation prefix (default: ~/.local)
  --bin-dir DIR      Executable directory (default: PREFIX/bin)
  --config-dir DIR   Configuration directory (default: ~/.config/adtool)
  --system           Install below /usr/local and use /etc/adtool
  --uninstall        Remove files installed by this script
  --purge            With --uninstall, also remove the configuration directory
  --dry-run          Print operations without changing files
  -h, --help         Show this help

Examples:
  ./install.sh
  ./install.sh --prefix "$HOME/.local"
  sudo ./install.sh --system
  ./install.sh --uninstall
EOF
}

while (( $# )); do
  case $1 in
    --prefix)     shift; (( $# )) || { echo '--prefix needs a directory' >&2; exit 2; }; PREFIX=$1 ;;
    --prefix=*)   PREFIX=${1#*=} ;;
    --bin-dir)    shift; (( $# )) || { echo '--bin-dir needs a directory' >&2; exit 2; }; BIN_DIR=$1 ;;
    --bin-dir=*)  BIN_DIR=${1#*=} ;;
    --config-dir) shift; (( $# )) || { echo '--config-dir needs a directory' >&2; exit 2; }; CONF_DIR=$1 ;;
    --config-dir=*) CONF_DIR=${1#*=} ;;
    --system)     SYSTEM=1; PREFIX=/usr/local; CONF_DIR=/etc/adtool ;;
    --uninstall)  UNINSTALL=1 ;;
    --purge)      PURGE=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

(( PURGE == 0 || UNINSTALL == 1 )) || { echo '--purge requires --uninstall' >&2; exit 2; }
BIN_DIR=${BIN_DIR:-$PREFIX/bin}
SHARE_DIR=$PREFIX/share
BASH_COMPLETION_DIR=$SHARE_DIR/bash-completion/completions
ZSH_COMPLETION_DIR=$SHARE_DIR/zsh/site-functions
MAN_DIR=$SHARE_DIR/man/man1
CONFIG=$CONF_DIR/config

quote_command() { printf ' %q' "$@"; printf '\n'; }
run() {
  if (( DRY_RUN )); then quote_command "$@"; else "$@"; fi
}

installed_files=(
  "$BIN_DIR/adtool"
  "$BASH_COMPLETION_DIR/adtool"
  "$ZSH_COMPLETION_DIR/_adtool"
  "$MAN_DIR/adtool.1"
  "$CONF_DIR/adtool.zsh"
)

if (( UNINSTALL )); then
  for path in "${installed_files[@]}"; do
    [[ -e $path || -L $path ]] && run rm -f "$path"
  done
  if (( PURGE )); then
    [[ -d $CONF_DIR ]] && run rm -rf "$CONF_DIR"
    echo "Removed installed files and configuration from $CONF_DIR."
  else
    echo "Removed installed files. Configuration was kept at $CONF_DIR."
  fi
  exit 0
fi

missing=()
for executable in ldapsearch ldapmodify ldapwhoami klist python3 iconv base64; do
  command -v "$executable" >/dev/null || missing+=("$executable")
done
if (( ${#missing[@]} )); then
  echo "Missing runtime commands: ${missing[*]}" >&2
  echo "  Debian/Ubuntu: sudo apt install ldap-utils krb5-user python3 coreutils libc-bin" >&2
  echo "  Fedora/RHEL:   sudo dnf install openldap-clients krb5-workstation python3 coreutils glibc-common" >&2
  exit 1
fi

run mkdir -p "$BIN_DIR" "$CONF_DIR" "$BASH_COMPLETION_DIR" "$ZSH_COMPLETION_DIR" "$MAN_DIR"
run install -m 755 "$SRC/adtool" "$BIN_DIR/adtool"
run install -m 644 "$SRC/contrib/adtool.bash" "$BASH_COMPLETION_DIR/adtool"
run install -m 644 "$SRC/contrib/_adtool" "$ZSH_COMPLETION_DIR/_adtool"
run install -m 644 "$SRC/man/adtool.1" "$MAN_DIR/adtool.1"
run install -m 644 "$SRC/contrib/adtool.zsh" "$CONF_DIR/adtool.zsh"

if [[ ! -f $CONFIG ]]; then
  run install -m 600 "$SRC/adtool.config.example" "$CONFIG"
  echo "Wrote a starter config to $CONFIG."
else
  echo "Kept the existing config at $CONFIG."
fi

case :$PATH: in
  *:$BIN_DIR:*) ;;
  *) echo "Note: $BIN_DIR is not on PATH." ;;
esac

echo "Installed adtool below $PREFIX."
echo "Next: edit $CONFIG, run kinit, then run adtool whoami."
if (( SYSTEM == 0 )); then
  echo "Optional shortcuts: source $CONF_DIR/adtool.zsh from your shell profile."
fi
