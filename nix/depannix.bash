# Bash completion for depannix.
#
# Found through $XDG_DATA_DIRS/bash-completion/completions/, which is how bash
# loads completions on demand on NixOS — not /etc/profile.d, which this system
# does not source.
_data="@DATA@"

_depannix() {
  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"

  case "${COMP_WORDS[1]:-}" in
    help)
      local subjects
      subjects="$(find "$_data/help" -name '*.txt' -printf '%f\n' 2>/dev/null | awk '{ sub(/\.txt$/, ""); if ($0 != "index") print }' | sort)"
      COMPREPLY=($(compgen -W "$subjects" -- "$cur"))
      ;;
    missing | which)
      COMPREPLY=($(compgen -c -- "$cur"))
      ;;
    tools)
      local categories
      categories="$(awk '/^[a-z]+ / { print $1 }' "$_data/tools.txt" 2>/dev/null)"
      COMPREPLY=($(compgen -W "--search --category --json $categories" -- "$cur"))
      ;;
    *)
      COMPREPLY=($(compgen -W "tools help missing version" -- "$cur"))
      ;;
  esac
  return 0
}

complete -F _depannix depannix
