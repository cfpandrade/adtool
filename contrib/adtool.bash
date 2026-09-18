# Bash completion for adtool. Maintainer: Carlos Andrade <carlos@perezandrade.com>
# Word splitting is intentional for compgen output and keeps Bash 3.2 support.
# shellcheck disable=SC2207
_adtool_complete() {
  local current previous command
  current=${COMP_WORDS[COMP_CWORD]}
  previous=${COMP_WORDS[COMP_CWORD-1]:-}
  command=${COMP_WORDS[1]:-}

  case $previous in
    --dept|--department|--title|--expiring|--stale) return ;;
  esac
  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W 'user group computer password policy whoami --help --version' -- "$current") )
    return
  fi
  case $command in
    user|u)
      COMPREPLY=( $(compgen -W '--groups --count --count=dept --count=title --count=ou --count=status --dept --department --title --expiring --stale --locked --csv --json --reset --lock --unlock --help' -- "$current") ) ;;
    group|g)
      COMPREPLY=( $(compgen -W '--members --count --count=ou --help' -- "$current") ) ;;
    computer|c|pc)
      COMPREPLY=( $(compgen -W '--servers --workstations --count --count=os --count=version --count=ou --help' -- "$current") ) ;;
    password|pw)
      COMPREPLY=( $(compgen -W 'policy' -- "$current") ) ;;
  esac
}
complete -F _adtool_complete adtool
