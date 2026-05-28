#!/usr/bin/env bash
# shellcheck shell=bash
#
# lib.sh — Shared helpers for json_sentinel scripts
#
# SOURCE THIS FILE from publish.sh and test_scripts.sh:
#
#   # shellcheck source=scripts/lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# REQUIRES callers to define:
#   die()     — fatal error handler (each script uses its own label)
#   DRY_RUN   — "true" | "false" (required by run_pretty)
#
# DO NOT execute this file directly.
#

[[ "${BASH_SOURCE[0]}" != "${0}" ]] \
  || { echo "❌ lib.sh must be sourced, not executed directly"; exit 1; }

#############################################
# hr
#
# Print a horizontal separator.
#############################################

hr() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

#############################################
# require_cmd
#
# Ensure a required CLI tool is available.
# Delegates to the caller's die() on failure.
#############################################

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

#############################################
# run_pretty <title> <command...>
#
# - Prints a labeled section header
# - Executes the command
# - Prefixes stdout lines with visual markers
# - Prefixes stderr lines with error markers
# - Honors $DRY_RUN: prints flags on separate
#   continuation lines instead of executing
#############################################

run_pretty() {
  local title="$1"
  shift

  hr
  echo "🛠  $title"
  hr

  if [[ "$DRY_RUN" == "true" ]]; then
    local cmd_parts=() flag_parts=()
    for arg in "$@"; do
      [[ "$arg" == --* ]] && flag_parts+=("$arg") || cmd_parts+=("$arg")
    done
    if [[ ${#flag_parts[@]} -eq 0 ]]; then
      printf '  %s\n' "${cmd_parts[*]}"
    else
      printf '  %s \\\n' "${cmd_parts[*]}"
      local last=$(( ${#flag_parts[@]} - 1 ))
      for i in "${!flag_parts[@]}"; do
        [[ $i -eq $last ]] \
          && printf '    %s\n'    "${flag_parts[$i]}" \
          || printf '    %s \\\n' "${flag_parts[$i]}"
      done
    fi
    return
  fi

  set +e
  "$@" \
    2> >(sed 's/^/  ❌ /' >&2) \
    | sed 's/^/  │ /'
  local status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    die "$title failed"
  fi
}
