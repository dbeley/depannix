#!/usr/bin/env bash
# depannix — what this medium carries, and what to do about a failure.
#
# The data lives beside the script, in a store path baked in at build time
# (@DATA@ is substituted): no evaluation, no network, nothing to resolve at
# run time. This file is plain shell on purpose, so it can be read and tested
# without any Nix in the way.
set -euo pipefail

DATA="@DATA@"

usage() {
  cat <<'EOF'
depannix — what this image carries, and what to do with it

  depannix tools [--search WORD] [--category NAME]
                              the catalogue, grouped by capability
  depannix tools --json       the same, for jq
  depannix help               the subjects covered
  depannix help <subject>     one of them, in full
  depannix missing <command>  is it here? and how to get it if not
  depannix version            which release this is

The same catalogue and the same help are plain files on the medium:
  /depannix-tools.txt
  /depannix-help.txt
EOF
}

cmd_tools() {
  local mode=text search="" category=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) mode=json ;;
      --search) [ $# -ge 2 ] || { echo "depannix: --search needs a word" >&2; return 2; }; search="$2"; shift ;;
      --category) [ $# -ge 2 ] || { echo "depannix: --category needs a name" >&2; return 2; }; category="$2"; shift ;;
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
    ' "$DATA/tools.txt"
    return 0
  fi

  if [ -n "$search" ]; then
    # fzf is in this image when it is enabled: use its fuzzy filter, which
    # accepts a typo, and fall back to grep otherwise.
    if command -v fzf >/dev/null 2>&1; then
      fzf --filter="$search" <"$DATA/tools.txt" || true
    else
      grep -i -- "$search" "$DATA/tools.txt" || true
    fi
    return 0
  fi

  cat "$DATA/tools.txt"
}

cmd_help() {
  local slug="${1:-}"
  if [ -z "$slug" ]; then
    cat "$DATA/help/index.txt"
    printf '\nFull help: %s/help.txt, and /depannix-help.txt on the medium.\n' "$DATA"
    return 0
  fi
  # Accept the subject however it is typed: with its file extension, or in
  # another case. Pure bash: no sed, no tr, nothing to install.
  slug="${slug,,}"
  slug="${slug%.txt}"
  if [ -f "$DATA/help/$slug.txt" ]; then
    cat "$DATA/help/$slug.txt"
    return 0
  fi
  printf 'depannix: no subject named "%s".\n\n' "$slug" >&2
  cat "$DATA/help/index.txt" >&2
  return 1
}

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

  # Known but not enabled: say so, rather than pretending it does not exist.
  if command -v jq >/dev/null 2>&1; then
    local line
    if line="$(jq -r --arg n "$name" '.tools[] | select(.name == $n) | "\(.name) — \(.category): \(.gesture)\(if .figure then " (\(.figure))" else "" end)"' "$DATA/tools.json" 2>/dev/null)" && [ -n "$line" ]; then
      printf '%s is in the catalogue but not enabled in this image:\n  %s\n' "$name" "$line"
      printf 'It can be enabled at build time (depannix.optionalTools), at a size cost.\n'
      return 0
    fi
  fi

  cat <<EOF
$name is not in this image.
On a machine that has network, it is one command away:

    nix shell nixpkgs#$name

The name to give nixpkgs is the package name, which is not always the command
name: photorec comes from testdisk, gdisk from gptfdisk, mkfs.vfat from
dosfstools.
EOF
}

case "${1:-}" in
  tools) shift; cmd_tools "$@" ;;
  help) shift; cmd_help "$@" ;;
  missing | which) shift; cmd_missing "$@" ;;
  version | --version | -V) cat "$DATA/version.txt" ;;
  -h | --help | "") usage ;;
  *)
    printf 'depannix: unknown command "%s"\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac
