# adtool

Read and write Active Directory from a Linux terminal, over your existing
Kerberos ticket, and get aligned tables instead of LDIF.

```
$ adtool user smi
LOGIN     NAME            EMAIL     DEPT         TITLE              OU           STATUS    PWD EXPIRES
--------  --------------  --------  -----------  -----------------  -----------  --------  ----------------
jsmith    John Smith      jsmith    Engineering  Platform Engineer  STAFF/ENG    enabled   2026-11-04 (47d)
ksmith    Kate Smith      ksmith    Sales        Account Manager    STAFF/SALES  LOCKED    2026-10-02 (14d)
rsmithe   Rob Smithers    rsmithe   Engineering  QA Engineer        STAFF/ENG    DISABLED  never

(emails omit @example.lan)
3 entries
```

No password prompt, no bind DN, no `-D`/`-w` in your shell history: it uses the
ticket you already have from `kinit`.

## Why this exists

`ldapsearch` against AD works, but every real question turns into a filter you
have to remember and output you then have to read:

```
ldapsearch -LLL -Y GSSAPI -H ldap://dc1.example.lan -b DC=example,DC=lan \
  '(&(objectCategory=person)(objectClass=user)(sAMAccountName=jsmith*))' \
  sAMAccountName displayName mail department
```

and the answers you actually want — *is this account locked right now*, *whose
password expires this month*, *which machines have not checked in since July* —
are not attributes you can just read. Three things get in the way, and `adtool`
handles each one:

**Lockout is a timestamp, not a flag.** AD stores `lockoutTime`, the moment the
account tripped the bad-password threshold. It is never cleared when the
lockout expires, so a non-zero value tells you nothing on its own. On current
domain controllers, `adtool` asks for `msDS-User-Account-Control-Computed`, so
the controller's effective policy is authoritative (including indefinite
lockouts). `AD_LOCKOUT_MINUTES` provides a client-side fallback for older DCs.

**Password expiry is constructed.** `msDS-UserPasswordExpiryTimeComputed` is
not stored anywhere; the DC calculates it per request from `pwdLastSet` and the
effective policy, including any fine-grained (PSO) policy that overrides the
domain default. You can ask for it and read it, but you cannot filter on it
server-side — so `--expiring N` filters the entries the DC already sent.

**Group membership is a graph.** `memberOf` lists direct memberships only. A
user in *Engineering* which is in *VPN Users* does not show *VPN Users*. `-g`
and `-m` use the AD nested-membership matching rule
(`1.2.840.113556.1.4.1941`, `LDAP_MATCHING_RULE_IN_CHAIN`), which makes the DC
walk the chain for you. One caveat it cannot fix: *Domain Users* is a primary
group and never appears in `memberOf` at all.

**FILETIME everywhere.** `lastLogonTimestamp`, `pwdLastSet` and the policy
durations are 100-nanosecond intervals since 1601, sometimes negative,
sometimes `0x7FFFFFFFFFFFFFFF` to mean "never". They become dates and
`14 days` in the table.

One more thing worth knowing before you trust `--stale`:
`lastLogonTimestamp` is replicated lazily and can sit up to 14 days behind, so
use 30 or more. The precise `lastLogon` is per-DC and not replicated at all.

## Install

```sh
git clone https://github.com/cfpandrade/adtool
cd adtool
./install.sh
```

That puts `adtool` in `~/.local/bin`, drops a starter config in
`~/.config/adtool/config`, and tells you if any dependency is missing.

Needs `ldapsearch`, `ldapmodify`, `klist`, `python3` and `iconv`:

```sh
sudo apt install ldap-utils krb5-user python3      # Debian/Ubuntu
sudo dnf install openldap-clients krb5-workstation python3   # Fedora/RHEL
```

## Configure

`~/.config/adtool/config` is plain shell. See
[`adtool.config.example`](adtool.config.example):

```sh
AD_LDAP_URI=ldap://dc1.example.lan
AD_BASE_DN=DC=example,DC=lan
AD_KINIT_PRINCIPAL=admin@EXAMPLE.LAN
AD_LOCKOUT_MINUTES=15
```

`AD_LOCKOUT_MINUTES` is only used when a controller does not return its
computed lockout state. Set it to the domain's lockout duration, or `0` when
an administrator must unlock accounts.

Setting any of these in the environment overrides the file for that run, which
is handy for reaching a second domain:

```sh
AD_LDAP_URI=ldap://dc1.other.lan AD_BASE_DN=DC=other,DC=lan adtool user smi
```

Then get a ticket and check the plumbing:

```sh
kinit you@YOUR.REALM
adtool whoami
```

## Use

`adtool --help` is the full reference. The shape of it:

```sh
adtool user [pattern] [filters] [-g] [-c[=KEY]] [--csv | --json]
adtool user <login> --reset | --lock | --unlock
adtool group [pattern] [-m] [-c]
adtool computer [pattern] [-s | -w] [-c[=os|version|ou]]
adtool password policy
adtool whoami
```

A pattern matches the *start* of a login, name, surname or email. With no
pattern you get everything.

```sh
adtool user jsmith -g              # every group, nested included
adtool user --dept Engineering     # filtered by the DC
adtool user --expiring 14          # password expires within 14 days
adtool user --locked               # locked out right now
adtool user --stale 90             # no logon in 90+ days, adds LAST LOGON
adtool user -c=status              # counts per status, with percentages
adtool group vpn -m                # every member, nested included
adtool computer -s -c=ou           # servers, counted per OU
adtool password policy             # the live policy, including PSOs
```

For groups whose direct `member` attribute exceeds the DC's range limit, the
MEMBERS column shows the returned lower bound with a `+` (for example,
`1500+`) instead of pretending that a truncated value is exact. `-m` still
uses a server-side nested-membership query.

Tables shrink to your terminal so every entry stays on one line, with clipped
values ending in `…`. For anything you intend to process, ask for
`--csv` or `--json` instead — those carry full values, no clipping, no folded
email domain:

```sh
adtool user --dept Sales --json | jq -r '.[].mail'
adtool user --expiring 30 --csv > expiring.csv
```

## Writes

Three actions change the directory. Each needs an exact login, prints the
account first, and asks before doing anything:

```sh
adtool user jsmith --unlock    # clear lockoutTime and re-enable
adtool user jsmith --lock      # disable the account
adtool user jsmith --reset     # set a new password, prompted twice, never echoed
```

They go out over `ldapmodify -Y GSSAPI -O minssf=128`, so the session is sealed
— AD refuses to set `unicodePwd` otherwise, and the password is never written
to disk, a file or your history. You need the rights delegated in AD; without
them the DC rejects the change and `adtool` says so.

`--unlock` also clears the disabled bit, because an account that was locked and
then disabled is the common case, and unlocking without enabling leaves you
wondering why the user still cannot log in.

## Notes

- `ldap://` is fine here. GSSAPI signs reads and seals writes, so nothing
  crosses the wire in the clear. `ldaps://` works too if your DC has a
  certificate you trust.
- Searches are paged at 1000 entries, so listing a whole domain does not stop
  at the DC's `MaxPageSize`.
- Piping through `grep` drops the header. Keep it with
  `adtool user | grep -E 'LOGIN|^--|Engineering'`.
- If lookups suddenly fail on a domain-joined laptop, check
  `sudo sssctl domain-status your.domain` before assuming the join broke.

## License

MIT. Carlos Andrade  ---  carlos@perezandrade.com
