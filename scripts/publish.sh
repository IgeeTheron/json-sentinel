#!/usr/bin/env bash
# shellcheck shell=bash
#
# publish.sh — Publish json_sentinel to pub.dev
#
# Usage: bash scripts/publish.sh [--dry-run] [--force] [--help]
#
# In CI, publishing is handled automatically via GitHub Actions OIDC
# (see .github/workflows/publish.yml). This script is for local use.
#

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

########################################
# Config / defaults
########################################

DRY_RUN="false"          # lib.sh run_pretty control — always false in publish.sh
PUBLISH_DRY_RUN="false"  # whether to pass --dry-run to dart pub publish
FORCE="false"

########################################
# Helpers
########################################

die() {
  hr
  echo "❌ PUBLISH FAILED"
  hr
  echo "  $*" >&2
  hr
  exit 1
}

kv() { printf "  %-14s: %s\n" "$1" "$2"; }

print_help() {
  hr
  echo "📘 publish.sh — Publish json_sentinel to pub.dev"
  hr
  echo ""
  echo "  USAGE"
  echo "    bash scripts/publish.sh [OPTIONS]"
  echo ""
  echo "  OPTIONS"
  echo "    --dry-run   Validate the package without publishing"
  echo "    --force     Skip confirmation prompt (required in CI)"
  echo "    --help      Print this message"
  echo ""
  echo "  EXAMPLES"
  echo "    bash scripts/publish.sh --dry-run"
  echo "    bash scripts/publish.sh --force"
  echo ""
  hr
}

########################################
# Argument parsing
########################################

for arg in "$@"; do
  case "$arg" in
    --dry-run) PUBLISH_DRY_RUN="true" ;;
    --force)   FORCE="true" ;;
    --help)    print_help; exit 0 ;;
    *) die "Unknown argument: '$arg'. Run with --help for usage." ;;
  esac
done

########################################
# Prerequisites
########################################

require_cmd dart

test -f pubspec.yaml || die "pubspec.yaml not found. Run from the package root."

########################################
# Version validation
########################################

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
[[ -n "$VERSION" ]] || die "Could not read version from pubspec.yaml."

# Allow MAJOR.MINOR.PATCH and MAJOR.MINOR.PATCH+BUILD (Dart pubspec format).
# Reject pre-release suffixes (-alpha, -beta, -dev, etc.).
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$'; then
  die "Version '$VERSION' is not publishable. Expected format: MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH+BUILD. Remove pre-release suffixes before publishing."
fi

########################################
# Summary
########################################

hr
echo "📦 Publishing json_sentinel"
hr
kv "Version" "$VERSION"
kv "Mode"    "$( [[ "$PUBLISH_DRY_RUN" == "true" ]] && echo "dry-run" || echo "publish" )"
kv "Force"   "$FORCE"
hr

########################################
# Publish
########################################

if [[ "$PUBLISH_DRY_RUN" == "true" ]]; then
  hr
  echo "🛠  dart pub publish --dry-run"
  hr
  # Allow warnings (exit 65) without aborting — output is still shown.
  dart pub publish --dry-run 2>&1 | sed 's/^/  │ /' || true
  echo ""
  echo "✅ Dry-run complete — no package was published."
  exit 0
fi

if [[ "$FORCE" == "true" ]]; then
  run_pretty "dart pub publish" dart pub publish --force
else
  run_pretty "dart pub publish" dart pub publish
fi

echo ""
echo "✅ Published json_sentinel $VERSION to pub.dev"
