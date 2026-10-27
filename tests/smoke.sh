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

run() { PATH="$TMP/bin:$PATH" AD_CONFIG=/dev/null XDG_CACHE_HOME="$TMP/cache" "$ROOT/adtool" "$@"; }
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

# --- shell completion ------------------------------------------------------
# the packaged scripts are generated from adtool: they must not drift
run completion bash | cmp -s - "$ROOT/contrib/adtool.bash" \
  || fail 'contrib/adtool.bash is stale: run make completions'
run completion zsh | cmp -s - "$ROOT/contrib/_adtool" \
  || fail 'contrib/_adtool is stale: run make completions'
if run completion fish >/dev/null 2>&1; then fail 'unknown shell should fail'; fi

# every option in the help text of a command must be offered by completion
for section in user:USER group:GROUP computer:COMPUTER; do
  cmd=${section%%:*}
  run --help | python3 -I -c '
import re, subprocess, sys
cmd, title, adtool = sys.argv[1:4]
text = sys.stdin.read().split("\n")
start = next(i for i, l in enumerate(text) if l.startswith(title + " ---"))
known = set()
for line in subprocess.run([adtool, "__flags", cmd], capture_output=True, text=True).stdout.splitlines():
    known.add(line.split("|")[0])
missing = []
for line in text[start + 1:]:
    if re.match(r"[A-Z ]+ -{3,}", line):
        break
    m = re.match(r"\s+((?:-\w|--[\w-]+)(?:,\s*(?:-\w|--[\w-]+))*)(\s|$)", line)
    if m:
        missing += [o for o in re.split(r",\s*", m.group(1)) if o not in known]
if missing:
    sys.exit("completion does not know: " + " ".join(missing))
' "$cmd" "${section##*:}" "$ROOT/adtool" >/dev/null 2>"$TMP/err" || { cat "$TMP/err" >&2; fail "completion lacks options of $cmd"; }
done

# names come from the directory, are cached, and a missing ticket is silent
ADTOOL_TEST_FIXTURE=user run __complete users j | grep -Fx jgarcia >/dev/null || fail 'complete users'
ADTOOL_TEST_FIXTURE=user run __complete users J | grep -Fx jgarcia >/dev/null || fail 'complete is case-insensitive'
ADTOOL_TEST_FIXTURE=user run __complete depts | grep -Fx Engineering >/dev/null || fail 'complete depts'
ADTOOL_TEST_FIXTURE=user run __complete titles e | grep -Fx Engineer >/dev/null || fail 'complete titles'
ADTOOL_TEST_FIXTURE=group run __complete groups | grep -Fx large >/dev/null || fail 'complete groups'
[[ -z $(run __complete users zzz) ]] || fail 'prefix filter'
[[ -z $(run __complete nonsense) ]] || fail 'unknown kind should print nothing'
ls "$TMP"/cache/adtool/*.users >/dev/null 2>&1 || fail 'completion cache file'
[[ $(stat -c %a "$TMP"/cache/adtool/*.users) == 600 ]] || fail 'cache must be private'
ADTOOL_TEST_FIXTURE=error run __complete users j >"$TMP/out" 2>"$TMP/err" || fail 'complete must never fail'
[[ ! -s $TMP/err ]] || fail 'complete must stay silent on errors'
rm -rf "$TMP/cache"
mkdir -p "$TMP/nokinit"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/nokinit/klist"
chmod +x "$TMP/nokinit/klist"
[[ -z $(PATH="$TMP/nokinit:$TMP/bin:$PATH" AD_CONFIG=/dev/null XDG_CACHE_HOME="$TMP/cache" \
          "$ROOT/adtool" __complete users) ]] || fail 'no ticket, no suggestions'

# the Bash script itself, driven the way readline drives it
cat >"$TMP/complete.sh" <<'SH'
source <("$ADTOOL" completion bash)
t() { COMP_WORDS=("$@"); COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 )); _adtool_complete; echo "${COMPREPLY[*]}"; }
SH
bt() { PATH="$TMP/bin:$PATH" ADTOOL="$ROOT/adtool" AD_CONFIG=/dev/null XDG_CACHE_HOME="$TMP/cache" \
         ADTOOL_TEST_FIXTURE=${FIXTURE:-user} bash -c 'source "$1"; shift; t "$@"' _ "$TMP/complete.sh" "$@"; }
# the completion calls "adtool" by the first word, so point that at the script
ln -sf "$ROOT/adtool" "$TMP/bin/adtool"
[[ $(bt adtool us) == user ]] || fail 'bash: command'
[[ $(bt adtool user --de) == '--dept --department' ]] || fail 'bash: option'
[[ $(bt adtool user --dept '') == Engineering ]] || fail 'bash: --dept value'
[[ $(bt adtool user --lock '') == jgarcia ]] || fail 'bash: login for an action'
[[ $(bt adtool user --count = '') == 'dept title ou status' ]] || fail 'bash: --count value'
[[ $(FIXTURE=group bt adtool group la) == large ]] || fail 'bash: group name'

printf 'All smoke tests passed.\n'
