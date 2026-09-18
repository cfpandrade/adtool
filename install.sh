#!/usr/bin/env bash
# Installs adtool into the current user account.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/adtool"
CONFIG="${CONF_DIR}/config"

mkdir -p "$BIN_DIR" "$CONF_DIR"

install -m 755 "$SRC/adtool" "$BIN_DIR/adtool"
install -m 644 "$SRC/contrib/adtool.zsh" "$CONF_DIR/adtool.zsh"

if [ ! -f "$CONFIG" ]; then
    install -m 600 "$SRC/adtool.config.example" "$CONFIG"
    echo "Wrote a starter config to $CONFIG - point it at your domain before first run."
else
    echo "Kept the existing config at $CONFIG."
fi

missing=()
for c in ldapsearch ldapmodify ldapwhoami klist python3 iconv base64; do
    command -v "$c" >/dev/null || missing+=("$c")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo
    echo "Missing commands: ${missing[*]}"
    echo "  Debian/Ubuntu:  sudo apt install ldap-utils krb5-user python3"
    echo "  Fedora/RHEL:    sudo dnf install openldap-clients krb5-workstation python3"
fi

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo; echo "Note: $BIN_DIR is not on your PATH." ;;
esac

echo
echo "Installed. Useful next steps:"
echo "  \$EDITOR $CONFIG"
echo "  kinit you@YOUR.REALM"
echo "  adtool whoami"
echo "  adtool --help"
echo
echo "Optional shell shortcuts - add to ~/.zshrc or ~/.bashrc:"
echo "  [[ -f $CONF_DIR/adtool.zsh ]] && . $CONF_DIR/adtool.zsh"
