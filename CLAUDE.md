# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
dart test                                             # run all tests (auto-discovers test/src/)
dart test test/src/json_sentinel_test.dart            # sentinel class tests only
dart test test/src/json_validation_result_test.dart   # result class tests only
dart analyze                                          # static analysis
dart format .                                         # format all Dart files
dart fix --apply .                                    # apply automated fixes

bash scripts/publish.sh --dry-run                    # pub.dev pre-flight (safe — no publish)
bash scripts/publish.sh --force                      # publish locally (CI uses OIDC — see publish.yml)
bash scripts/test_scripts.sh                         # run shell script test suite
dart run example/json_sentinel_example.dart           # run the example
```

## Architecture

Pure Dart package, zero runtime dependencies. Three source files under `lib/src/`, all re-exported from the `lib/json_sentinel.dart` barrel:

- **`json_sentinel_base.dart`** — `JsonSentinel`, the only class callers interact with. All methods are static; the class cannot be instantiated. Owns two global mutable fields: `_logger` (`JsonLogFn?`) and `_verbose` (`bool`). Public API: `configure()`, `silence()`, `resetLoggerForTesting()`, `logger` getter, and `validate()`.
- **`json_validation_result.dart`** — `JsonValidationResult`, returned by `validate()`. Two named constructors: `JsonValidationResult.success` (a `const` singleton) and `JsonValidationResult.failure(errors)`. The `errors` list is always unmodifiable.
- **`json_log_fn.dart`** — `JsonLogFn` typedef only. Kept separate so consumers can reference the function signature without importing the full library.

### Key design decisions

- **`_logger` and `_verbose` are global mutable state.** Tests install a capturing logger in `setUp` and must call `resetLoggerForTesting()` in `tearDown`. `resetLoggerForTesting()` resets both fields; omitting it in `tearDown` causes cross-test pollution.
- **`configure()` / `silence()` dual guard.** An `assert` fires in debug mode (tests always run with asserts) and a `if (_logger != null) return` guard silently prevents overwrite in release builds — first registration wins. The assert message names both `configure()` and `silence()` as initialisation paths.
- **`configure()` and `silence()` are mutually exclusive.** `silence()` delegates to `configure()` with a no-op lambda. Calling both asserts in debug mode. Both accept an optional `verbose: bool` parameter (default `false`).
- **`verbose` controls all `dart:developer` output independently of `silence()`.** When `true`: emits a confirmation on init, a success trace on every passing `validate()` call, and a diagnostic when `jsonEncode` fails in `_jsonPreview`. `silence()` has no effect on `developer.log` — the two are orthogonal.
- **Fallback logger uses `dart:developer`, not `print`.** When no logger is configured, `_log` emits via `developer.log(name: 'JsonSentinel')`. This is suppressed in release builds — always call `configure()` or `silence()` in production code.
- **`validate()` never returns early.** All errors are collected into a list before a single log entry is emitted. This is intentional — callers see the full picture, not just the first failure.
- **`escalate` defaults to `false`.** Opt-in to elevated capture (e.g. Sentry event vs breadcrumb) per call-site by passing `escalate: true`.
- **`_isTypeOf` uses explicit dispatch.** Supported types: `null`, `bool`, `int`, `double`, `num`, `String`, `Map`, `List`. Any other `Type` triggers an `assert` in debug mode and falls back to `runtimeType` equality in release. Adding a new supported type requires a new branch here.
- **`json_preview` lives in `extras`, not in the message string.** This keeps the log message human-readable while still passing structured data (context label + truncated JSON) to Sentry/Crashlytics via the `extras` map. The `error` parameter in `JsonLogFn` is reserved API surface — `validate()` always passes `null` for it.

## Code Style

- Line length: **150 characters** (`formatter: page_width: 150` in `analysis_options.yaml`)
- **Package imports only** — `always_use_package_imports` is enforced; use `package:json_sentinel/...` not relative paths
- Trailing commas required on multi-line parameter lists (`require_trailing_commas`)

## CI

Two GitHub Actions workflows in `.github/workflows/`:

- **`ci.yml`** — runs on every PR and push to `main`: format check, analyze, script tests, dart tests. Failing tests appear as inline annotations in the PR diff (`--reporter=github`).
- **`publish.yml`** — triggered by a `v[0-9]+.[0-9]+.[0-9]+` tag: runs the full check suite in a `ci` job, then publishes via the official `dart-lang/setup-dart/.github/workflows/publish.yml@v1` reusable workflow using OIDC (no long-lived secret). Requires one-time setup on `pub.dev/packages/json_sentinel/admin` — enable automated publishing, set repo to `My-Fuel-Orders/json_sentinel`, tag pattern `v{{version}}`.

## Changelog

Follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [SemVer](https://semver.org/).
- New entries go under `[Unreleased]`
- Permitted headings only: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`
- Each release entry requires a `YYYY-MM-DD` date
- Do not modify past release entries

## Tests

Tests live in `test/src/`. No mocking framework — uses a capturing-logger pattern:

```dart
setUp(() {
  JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
    logs.add(message);
    // capture other params as needed
  });
});
tearDown(JsonSentinel.resetLoggerForTesting);
```

`resetLoggerForTesting()` must be called in `tearDown` whether the test used `configure()` or `silence()` — both set `_logger` and both must be reset. The `verbose` flag is also reset by `resetLoggerForTesting()`.

The test for double-`configure()` (and double-`silence()`) relies on Dart asserts being active (they always are in `dart test`).
