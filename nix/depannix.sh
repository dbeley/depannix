#!/usr/bin/env bash
# depannix - what this medium carries, and what to do about a failure.
#
# The data lives beside the script, in a store path baked in at build time
# (@DATA@ is substituted): no evaluation, no network, nothing to resolve at
# run time. This file is plain shell on purpose, so it can be read and tested
# without any Nix in the way.
set -euo pipefail

DATA="@DATA@"
FLAVOUR="@FLAVOUR@"
no_pager=0

# Page long output when a human reads it, and never when a program does: a
# pager in the middle of a pipe is a bug. `less -F` quits at once when the text
# fits one screen, so short answers behave exactly like cat.
pager="${DEPANNIX_PAGER:-${PAGER:-less}}"
case "$pager" in
  *less) pager_flags="-RFX" ;;
  *) pager_flags="" ;;
esac
command -v "$pager" >/dev/null 2>&1 || pager=""

page() {
  if [ -n "$pager" ] && [ "$no_pager" = 0 ] && [ -t 1 ]; then
    "$pager" $pager_flags
  else
    cat
  fi
}

usage() {
  cat <<'EOF'
depannix - what this image carries, and what to do with it

  depannix tools [--search WORD] [--category NAME] [--no-pager]
                              the catalogue, grouped by capability
  depannix tools --json       the same, for jq
  depannix help [subject]     the subjects covered, or one of them in full
  depannix missing <command>  is it here? and how to get it if not
  depannix gui                a Wayland session on this screen (minimal image)
  depannix version            which release this is

The catalogue and the help are also plain files, in the home directory you land
in: ~/depannix-tools.txt, ~/depannix-help.txt. The same two files sit at the
root of the stick, which is readable from any machine that mounts it.
EOF
}

cmd_tools() {
  local mode=text search="" category=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-pager) no_pager=1 ;;
      --json) mode=json ;;
      --search)
        [ $# -ge 2 ] || { echo "depannix: --search needs a word" >&2; return 2; }
        search="$2"; shift
        ;;
      --category)
        [ $# -ge 2 ] || { echo "depannix: --category needs a name" >&2; return 2; }
        category="$2"; shift
        ;;
      *) echo "depannix: unknown option \"$1\"" >&2; return 2 ;;
    esac
    shift
  done

  if [ "$mode" = json ]; then
    if command -v jq >/dev/null 2>&1; then jq . "$DATA/tools.json"; else cat "$DATA/tools.json"; fi
    return 0
  fi

  if [ -n "$category" ]; then
    # The text catalogue is already grouped: print the requested section only.
    awk -v want="$category" '
      /^[a-z]+ / { section = ($1 == want); next }
      section { print }
    ' "$DATA/tools.txt" | page
    return 0
  fi

  if [ -n "$search" ]; then
    # fzf is in this image when it is enabled: use its fuzzy filter, which
    # accepts a typo, and fall back to grep otherwise.
    if command -v fzf >/dev/null 2>&1; then
      fzf --filter="$search" <"$DATA/tools.txt" | page || true
    else
      grep -i -- "$search" "$DATA/tools.txt" | page || true
    fi
    return 0
  fi

  page <"$DATA/tools.txt"
}

cmd_help() {
  local slug=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-pager) no_pager=1 ;;
      *) slug="$1" ;;
    esac
    shift
  done

  if [ -z "$slug" ]; then
    page <"$DATA/help/index.txt"
    return 0
  fi

  # Accept the subject however it is typed: with its file extension, or in
  # another case. Pure bash: no sed, no tr, nothing to install.
  slug="${slug,,}"
  slug="${slug%.txt}"
  if [ -f "$DATA/help/$slug.txt" ]; then
    page <"$DATA/help/$slug.txt"
    return 0
  fi
  printf 'depannix: no subject named "%s".\n\n' "$slug" >&2
  cat "$DATA/help/index.txt" >&2
  return 1
}

# Deliberately short: this is also the message a shell prints for a command it
# could not find, and a wall of text after every typo would be worse than
# silence.
cmd_missing() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    echo "depannix: missing needs a command name" >&2
    return 2
  fi

  # Present in this image? Ask the shell, not the catalogue: the catalogue
  # lists packages, and several of them provide more than one command.
  local where
  if where="$(command -v "$name" 2>/dev/null)"; then
    printf '%s is here: %s\n' "$name" "$where"
    return 0
  fi

  # Known but not built in: say so, rather than pretending it does not exist.
  if command -v jq >/dev/null 2>&1; then
    local line
    if line="$(jq -r --arg n "$name" '
          .tools[] | select(.name == $n)
          | "  \(.category): \(.gesture)" + (if .figure then "  [\(.figure)]" else "" end)
        ' "$DATA/tools.json" 2>/dev/null)" && [ -n "$line" ]; then
      printf '%s: in the catalogue, but not in this image.\n' "$name"
      printf '%s\n' "$line"
      printf '  with network:  nix shell nixpkgs#%s\n' "$name"
      return 0
    fi
  fi

  printf '%s: not in this image. With network:  nix shell nixpkgs#%s\n' "$name" "$name"
  printf '  (the nixpkgs name is not always the command name: photorec comes from\n'
  printf '   testdisk, gdisk from gptfdisk, mkfs.vfat from dosfstools)\n'
  return 1
}

# A graphical session, on demand. The desktop image boots into one; the minimal
# image does not, by choice, so this is the command that changes it. Both cases
# are covered here rather than in the greeting, so that neither flavour can tell
# the operator to run something that does not exist there.
cmd_gui() {
  if [ "$FLAVOUR" = desktop ]; then
    cat <<'EOF'
This is the desktop image: GNOME starts by itself, with Firefox in it.

Take the minimal image if you wanted a console that stays a console.
EOF
    return 0
  fi

  if ! command -v depannix-session >/dev/null 2>&1; then
    printf 'depannix: this image carries no graphical session.\n' >&2
    printf 'What it does carry is one command away:  depannix tools\n' >&2
    return 1
  fi

  exec depannix-session "$@"
}

case "${1:-}" in
  tools) shift; cmd_tools "$@" ;;
  help) shift; cmd_help "$@" ;;
  missing | which) shift; cmd_missing "$@" ;;
  gui) shift; cmd_gui "$@" ;;
  version | --version | -V) cat "$DATA/version.txt" ;;
  -h | --help | "") usage ;;
  *)
    printf 'depannix: unknown command "%s"\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac
