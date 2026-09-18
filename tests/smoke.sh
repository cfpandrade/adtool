#!/usr/bin/env bash
# Smoke tests for adtool. Author: Carlos Andrade <carlos@perezandrade.com>
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/adtool-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/klist" <<'SH'
#!/usr/bin/env bash
exit 0
SH

cat >"$TMP/bin/ldapsearch" <<'SH'
#!/usr/bin/env bash
case ${ADTOOL_TEST_FIXTURE:-user} in
  user)
    cat <<'LDIF'
dn:: Q049Sm9zw6kgR2FyY8OtYSxPVT1QZW9wbGUsREM9ZXhhbXBsZSxEQz1sYW4=
sAMAccountName: jgarcia
displayName:: Sm9zw6kgR2FyY8OtYQ==
mail: jgarcia@example.lan
department: Engineering
title: Engineer
userAccountControl: 512
lockoutTime: 0
msDS-User-Account-Control-Computed: 16
msDS-UserPasswordExpiryTimeComputed: 9223372036854775807

LDIF
    ;;
  group)
    cat <<'LDIF'
dn: CN=Large Group,OU=Groups,DC=example,DC=lan
sAMAccountName: large
description: Large group
member;range=0-1: CN=One,OU=People,DC=example,DC=lan
member;range=0-1: CN=Two,OU=People,DC=example,DC=lan

LDIF
    ;;
  error)
    echo 'ldap_sasl_interactive_bind: Cannot contact LDAP server (-1)' >&2
    exit 1
    ;;
esac
SH
cat >"$TMP/bin/ldapmodify" <<'SH'
#!/usr/bin/env bash
cat >"$ADTOOL_MODIFY_CAPTURE"
SH
chmod +x "$TMP/bin/klist" "$TMP/bin/ldapsearch" "$TMP/bin/ldapmodify"

run() { PATH="$TMP/bin:$PATH" AD_CONFIG=/dev/null "$ROOT/adtool" "$@"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash -n "$ROOT/adtool"
run --version | grep -F 'Carlos Andrade' >/dev/null || fail 'version author'

if run computer -s -w >"$TMP/out" 2>"$TMP/err"; then
  fail 'computer -s -w should fail'
fi
grep -F -- '-s and -w are exclusive' "$TMP/err" >/dev/null || fail 'exclusive options message'

ADTOOL_TEST_FIXTURE=user run user --json >"$TMP/user.json"
python3 - "$TMP/user.json" <<'PY'
import json, sys
row = json.load(open(sys.argv[1], encoding='utf-8'))[0]
assert row['sAMAccountName'] == 'jgarcia'
assert row['userAccountControl'] == 'LOCKED'
PY

printf 'y\n' | ADTOOL_TEST_FIXTURE=user ADTOOL_MODIFY_CAPTURE="$TMP/modify.ldif" \
  run user jgarcia --lock >"$TMP/action.txt"
grep -F 'dn:: Q049Sm9zw6kgR2FyY8OtYSxPVT1QZW9wbGUsREM9ZXhhbXBsZSxEQz1sYW4=' \
  "$TMP/modify.ldif" >/dev/null || fail 'base64 DN modification'

ADTOOL_TEST_FIXTURE=group run group large >"$TMP/group.txt"
grep -E 'large.*2\+' "$TMP/group.txt" >/dev/null || fail 'ranged member count'

if ADTOOL_TEST_FIXTURE=error run user >"$TMP/out" 2>"$TMP/err"; then
  fail 'LDAP failure should propagate'
fi
grep -F 'LDAP search failed' "$TMP/err" >/dev/null || fail 'LDAP diagnostic'
grep -F 'could not search users' "$TMP/err" >/dev/null || fail 'search context'

printf 'All smoke tests passed.\n'
