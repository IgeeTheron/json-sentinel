#!/usr/bin/env bash
# shellcheck shell=bash
#
# test_scripts.sh — Test suite for json_sentinel shell scripts
#
# Tests lib.sh and publish.sh without executing real pub operations.
# Run from the package root: bash scripts/test_scripts.sh
#

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()   { echo "  ✅ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $*"; FAIL=$((FAIL + 1)); }

run_test() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    ok "$desc"
  else
    fail "$desc"
  fi
}

run_test_fails() {
  local desc="$1"; shift
  if ! "$@" >/dev/null 2>&1; then
    ok "$desc"
  else
    fail "$desc"
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 json_sentinel script tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

########################################
# lib.sh
########################################

echo ""
echo "▶ lib.sh"

run_test_fails "direct execution is blocked" \
  bash "$ROOT/scripts/lib.sh"

run_test "hr() prints a separator line" \
  bash -c "
    die() { exit 1; }
    DRY_RUN=false
    source '$ROOT/scripts/lib.sh'
    output=\$(hr)
    echo \"\$output\" | grep -q '━'
  "

run_test "require_cmd passes for an available command" \
  bash -c "
    die() { exit 1; }
    DRY_RUN=false
    source '$ROOT/scripts/lib.sh'
    require_cmd echo
  "

run_test_fails "require_cmd fails for a non-existent command" \
  bash -c "
    die() { exit 1; }
    DRY_RUN=false
    source '$ROOT/scripts/lib.sh'
    require_cmd __command_that_does_not_exist__
  "

run_test "run_pretty in DRY_RUN=true prints command without executing" \
  bash -c "
    die() { exit 1; }
    DRY_RUN=true
    source '$ROOT/scripts/lib.sh'
    # Use a command that would fail if actually executed — proving it was not run
    output=\$(run_pretty 'test title' __command_that_does_not_exist__ --flag)
    echo \"\$output\" | grep -q '__command_that_does_not_exist__'
  "

run_test "run_pretty DRY_RUN=true formats flags on continuation lines" \
  bash -c "
    die() { exit 1; }
    DRY_RUN=true
    source '$ROOT/scripts/lib.sh'
    output=\$(run_pretty 'test' some_cmd --flag-a --flag-b)
    echo \"\$output\" | grep -q '\-\-flag-a'
    echo \"\$output\" | grep -q '\-\-flag-b'
  "

########################################
# publish.sh — help
########################################

echo ""
echo "▶ publish.sh --help"

run_test "--help exits 0" \
  bash "$ROOT/scripts/publish.sh" --help

run_test "--help output contains 'Usage'" \
  bash -c "bash '$ROOT/scripts/publish.sh' --help | grep -q 'Usage'"

run_test "--help output contains '--dry-run'" \
  bash -c "bash '$ROOT/scripts/publish.sh' --help | grep -q '\-\-dry-run'"

########################################
# publish.sh — argument validation
########################################

echo ""
echo "▶ publish.sh — argument validation"

run_test_fails "unknown argument exits non-zero" \
  bash "$ROOT/scripts/publish.sh" --unknown-flag

run_test "recognises --dry-run without error" \
  bash -c "
    cd '$ROOT'
    # --dry-run will proceed past arg parsing but may fail at dart pub publish --dry-run
    # We only test that the flag is accepted (no 'Unknown argument' error)
    output=\$(bash scripts/publish.sh --dry-run 2>&1 || true)
    ! echo \"\$output\" | grep -q 'Unknown argument'
  "

run_test "recognises --force without error" \
  bash -c "
    output=\$(bash '$ROOT/scripts/publish.sh' --force 2>&1 || true)
    ! echo \"\$output\" | grep -q 'Unknown argument'
  "

########################################
# publish.sh — version validation
########################################

echo ""
echo "▶ publish.sh — version validation"

_run_publish_in_tmpdir() {
  local version="$1"; shift
  local tmp
  tmp=$(mktemp -d)
  printf 'name: json_sentinel\nversion: %s\n' "$version" > "$tmp/pubspec.yaml"
  (cd "$tmp" && bash "$ROOT/scripts/publish.sh" "$@" 2>&1)
  local status=$?
  rm -rf "$tmp"
  return $status
}

run_test "accepts MAJOR.MINOR.PATCH version" \
  bash -c "
    tmp=\$(mktemp -d)
    printf 'name: json_sentinel\nversion: 1.0.0\n' > \"\$tmp/pubspec.yaml\"
    output=\$(cd \"\$tmp\" && bash '$ROOT/scripts/publish.sh' --dry-run 2>&1 || true)
    rm -rf \"\$tmp\"
    ! echo \"\$output\" | grep -q 'not publishable'
  "

run_test "accepts MAJOR.MINOR.PATCH+BUILD version" \
  bash -c "
    tmp=\$(mktemp -d)
    printf 'name: json_sentinel\nversion: 0.1.0+1\n' > \"\$tmp/pubspec.yaml\"
    output=\$(cd \"\$tmp\" && bash '$ROOT/scripts/publish.sh' --dry-run 2>&1 || true)
    rm -rf \"\$tmp\"
    ! echo \"\$output\" | grep -q 'not publishable'
  "

run_test_fails "rejects pre-release version (1.0.0-beta)" \
  bash -c "
    tmp=\$(mktemp -d)
    printf 'name: json_sentinel\nversion: 1.0.0-beta\n' > \"\$tmp/pubspec.yaml\"
    result=0
    (cd \"\$tmp\" && bash '$ROOT/scripts/publish.sh' --dry-run 2>&1) || result=\$?
    rm -rf \"\$tmp\"
    exit \$result
  "

run_test_fails "rejects pre-release version (0.1.0-dev)" \
  bash -c "
    tmp=\$(mktemp -d)
    printf 'name: json_sentinel\nversion: 0.1.0-dev\n' > \"\$tmp/pubspec.yaml\"
    result=0
    (cd \"\$tmp\" && bash '$ROOT/scripts/publish.sh' --dry-run 2>&1) || result=\$?
    rm -rf \"\$tmp\"
    exit \$result
  "

run_test_fails "fails when pubspec.yaml is missing" \
  bash -c "
    tmp=\$(mktemp -d)
    result=0
    (cd \"\$tmp\" && bash '$ROOT/scripts/publish.sh' --dry-run 2>&1) || result=\$?
    rm -rf \"\$tmp\"
    exit \$result
  "

run_test_fails "fails when version line is missing from pubspec.yaml" \
  bash -c "
    tmp=\$(mktemp -d)
    printf 'name: json_sentinel\n' > \"\$tmp/pubspec.yaml\"
    result=0
    (cd \"\$tmp\" && bash '$ROOT/scripts/publish.sh' --dry-run 2>&1) || result=\$?
    rm -rf \"\$tmp\"
    exit \$result
  "

########################################
# publish.sh — dry-run (real package)
########################################

echo ""
echo "▶ publish.sh --dry-run (against real package)"

run_test "--dry-run exits 0 from package root" \
  bash -c "cd '$ROOT' && bash scripts/publish.sh --dry-run"

run_test "--dry-run output confirms dry-run complete" \
  bash -c "cd '$ROOT' && bash scripts/publish.sh --dry-run 2>&1 | grep -q 'Dry-run complete'"

########################################
# Summary
########################################

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$(( PASS + FAIL ))
echo "Results: $PASS/$TOTAL passed"
if [[ $FAIL -gt 0 ]]; then
  echo "❌ $FAIL test(s) failed"
  exit 1
else
  echo "✅ All tests passed"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
