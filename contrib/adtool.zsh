# Optional shortcuts.  Source from ~/.zshrc:
#
#   [[ -f ~/.config/adtool/adtool.zsh ]] && . ~/.config/adtool/adtool.zsh
#
# Run 'adtool --help' for the full reference.
adfinduser()  { adtool user  "$@"; }
adfindgroup() { adtool group "$@"; }
adfindpc()    { adtool computer "$@"; }
adfind()      { adtool user  "$@"; }
