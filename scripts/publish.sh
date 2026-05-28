#!/usr/bin/env bash
# shellcheck shell=bash
#
# publish.sh — Publish json_sentinel to pub.dev
#
# Usage: bash scripts/publish.sh [--dry-run] [--force] [--help]
#
#   --dry-run   Run dart pub publish --dry-run (no actual publish)
#   --force     Skip confirmation prompt (required in CI)
#   --help      Print this message
#
# In CI (Codemagic publish workflow):
#   Set PUB_DEV_CREDENTIALS to the content of ~/.pub-cache/credentials.json
#   (obtained via `dart pub login` locally), store it in the pub_dev_credentials
#   environment variable group, and write it before calling this script:
#
#     echo "$PUB_DEV_CREDENTIALS" > "$HOME/.pub-cache/credentials.json"
#     bash ./scripts/publish.sh --force
#

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

########################################
# Config / defaults
########################################

DRY_RUN="false"
FORCE="false"

########################################
# Error handler
########################################

die() { echo "❌ [publish] $*" >&2; exit 1; }

########################################
# Argument parsing
########################################

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="true" ;;
    --force)   FORCE="true" ;;
    --help)
      echo "Usage: bash scripts/publish.sh [--dry-run] [--force]"
      echo ""
      echo "  --dry-run  Run dart pub publish --dry-run (no actual publish)"
      echo "  --force    Skip confirmation prompt (required in CI)"
      echo "  --help     Print this message"
      exit 0
      ;;
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

echo "📦 Package version: $VERSION"

# Allow MAJOR.MINOR.PATCH and MAJOR.MINOR.PATCH+BUILD (Dart pubspec format).
# Reject pre-release suffixes (-alpha, -beta, -dev, etc.).
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$'; then
  die "Version '$VERSION' is not publishable. Expected format: MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH+BUILD. Remove pre-release suffixes before publishing."
fi

########################################
# Publish
########################################

hr
echo "📦 Publishing json_sentinel $VERSION to pub.dev"
hr

if [[ "$DRY_RUN" == "true" ]]; then
  run_pretty "dart pub publish --dry-run" dart pub publish --dry-run
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
