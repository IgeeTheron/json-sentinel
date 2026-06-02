# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
dart test                                             # run all tests (auto-discovers test/src/)
dart test test/src/json_sentinel_test.dart            # validate() tests only
dart test test/src/json_sentinel_batch_test.dart      # validateBatch() tests only
dart test test/src/json_validation_result_test.dart   # JsonValidationResult tests only
dart test test/src/batch_validation_result_test.dart  # BatchValidationResult tests only
dart analyze                                          # static analysis
dart format .                                         # format all Dart files
dart fix --apply .                                    # apply automated fixes

bash scripts/publish.sh --dry-run                    # pub.dev pre-flight (safe — no publish)
bash scripts/publish.sh --force                      # publish locally (CI uses OIDC — see publish.yml)
bash scripts/test_scripts.sh                         # run shell script test suite
dart run example/json_sentinel_example.dart           # run the example
dart doc --dry-run                                    # verify all /// comments parse with 0 warnings/errors
dart doc --output doc/api                             # generate API docs locally (output gitignored)
```

## Architecture

Pure Dart package, zero runtime dependencies. Four source files under `lib/src/`, all re-exported from the `lib/json_sentinel.dart` barrel:

- **`json_sentinel_base.dart`** — `JsonSentinel`, the only class callers interact with. All methods are static; the class cannot be instantiated. Owns four global mutable fields: `_logger` (`JsonLogFn?`), `_verbose` (`bool`), `_redactKeys` (`Set<String>?`), and `_redactionPlaceholder` (`String`). Public API: `configure()`, `silence()`, `resetLoggerForTesting()`, `logger` getter, `validate()`, and `validateBatch()`.
- **`json_validation_result.dart`** — `JsonValidationResult`, returned by `validate()` and stored per-item inside `BatchValidationResult`. Two named constructors: `JsonValidationResult.success` (a `const` singleton) and `JsonValidationResult.failure(errors)`. The `errors` list is always unmodifiable.
- **`batch_validation_result.dart`** — `BatchValidationResult`, returned by `validateBatch()`. Public factory `fromResults(List<JsonValidationResult>)` computes `isValid`, `failureCount`, and `failureIndices` in one pass. All list fields are unmodifiable.
- **`json_log_fn.dart`** — `JsonLogFn` typedef only. Kept separate so consumers can reference the function signature without importing the full library.

### Key design decisions

- **Four fields are global mutable state: `_logger`, `_verbose`, `_redactKeys`, `_redactionPlaceholder`.** Tests install a capturing logger in `setUp` and must call `resetLoggerForTesting()` in `tearDown`. `resetLoggerForTesting()` resets all four fields; omitting it in `tearDown` causes cross-test pollution.
- **`configure()` / `silence()` dual guard.** An `assert` fires in debug mode (tests always run with asserts) and a `if (_logger != null) return` guard silently prevents overwrite in release builds — first registration wins. The assert message names both `configure()` and `silence()` as initialisation paths.
- **`configure()` and `silence()` are mutually exclusive.** `silence()` delegates to `configure()` with a no-op lambda. Calling both asserts in debug mode. Both accept optional `verbose: bool` (default `false`), `redactKeys: Set<String>?` (default `null`), and `redactionPlaceholder: String` (default `'[REDACTED]'`) parameters.
- **`redactKeys` masks sensitive top-level field values in previews.** When set, `_jsonPreview()` replaces matching key values with `_redactionPlaceholder` before encoding — the validated `Map` is never mutated. Applies to both `json_preview` (single-item) and `item_previews` (batch). An empty or null `redactKeys` is a no-op.
- **`verbose` controls all `dart:developer` output independently of `silence()`.** When `true`: emits a confirmation on init, a success or failure trace on every `validate()` / `validateBatch()` call, and a diagnostic when `jsonEncode` fails in `_jsonPreview`. `silence()` has no effect on `developer.log` — the two are orthogonal. The failure traces fire in addition to the configured `JsonLogFn`, so DevTools Logging reflects failures even when a Sentry/Crashlytics logger is registered.
- **Fallback logger uses `dart:developer`, not `print`.** When no logger is configured, `_log` emits via `developer.log(name: 'JsonSentinel')`. This is suppressed in release builds — always call `configure()` or `silence()` in production code.
- **`validate()` and `validateBatch()` never return early.** All errors are collected before any log call is emitted. For `validateBatch()` this means all items are validated first; a single consolidated log entry fires at the end only if at least one item fails.
- **`JsonValidationResult.failure()` asserts non-empty errors in debug mode.** A failure result with an empty errors list is semantically contradictory and is caught by an `assert` at construction time. Tests always run with asserts active, so any test that passes `failure([])` will throw an `AssertionError`.
- **`_validateCore()` is the shared private validation loop.** Both `validate()` and `validateBatch()` delegate to it. It returns `List<String>` errors with no logging side-effects; each caller handles logging itself. Adding a new validation rule requires a change here only.
- **`escalate` defaults to `false`.** Opt-in to elevated capture (e.g. Sentry event vs breadcrumb) per call-site by passing `escalate: true`.
- **`_isTypeOf` uses explicit dispatch.** Supported types: `null`, `bool`, `int`, `double`, `num`, `String`, `Map<dynamic, dynamic>`, `List<dynamic>`. The type comparisons use fully parameterised forms (`type == Map<dynamic, dynamic>`) to satisfy `always_specify_types`. Any other `Type` triggers an `assert` in debug mode and falls back to `runtimeType` equality in release. Adding a new supported type requires a new branch here.
- **`parentContext` on `validate()` computes `effectiveContext` for all log output.** When `parentContext` is non-null, `effectiveContext = '$parentContext > $context'`; otherwise `effectiveContext = context`. Both the log message prefix (`[$effectiveContext]`) and `extras['context']` use `effectiveContext`. `validateBatch()` does not accept `parentContext` — it builds its own indexed path internally.
- **`extras` keys differ between `validate()` and `validateBatch()`.** `validate()` always provides `'context'` and `'json_preview'`; when `parentContext` is set, `'context'` holds the full chained string (e.g. `'UserPage.data[2] > MetaModel'`). `validateBatch()` always provides `'context'`, `'failure_count'` (int), and `'total_count'` (int). It also provides `'item_previews'` (`List<String>` of truncated JSON per failing item in `failureIndices` order) **unless** `generatePreviews: false` is passed — in which case `item_previews` is absent entirely. Neither method includes the other's unique keys. Logger implementations must handle both shapes; never assume either key is always present.
- **`StackTrace.current` is captured as the very first statement in both `validate()` and `validateBatch()`.** This ensures the top frame always points to the call boundary, not library internals, for accurate Sentry/Crashlytics culprit attribution. The minor cost on the all-pass path is accepted.
- **The `error` parameter in `JsonLogFn` is reserved API surface** — both `validate()` and `validateBatch()` always pass `null` for it.

## Code Style

- Line length: **150 characters** (`formatter: page_width: 150` in `analysis_options.yaml`)
- **Package imports only** — `always_use_package_imports` is enforced; use `package:json_sentinel/...` not relative paths
- Trailing commas required on multi-line parameter lists (`require_trailing_commas`)
- **`// region Name` / `// endregion`** blocks are the project-wide structural convention — used in all `test/src/` files and in `example/json_sentinel_example.dart`

### Lint structure — two-tier analysis options

- **`analysis_options.yaml`** (root) — applies to the whole repo. Includes `lints/recommended`, plus correctness (`avoid_bool_literals_in_conditional_expressions`, `noop_primitive_operations`, `unawaited_futures`, etc.), immutability (`prefer_final_fields`, `prefer_final_locals`), and style rules.
- **`lib/analysis_options.yaml`** — inherits root, then adds `always_specify_types` and `public_member_api_docs`. These stricter rules apply **only to `lib/`**; `test/` and `example/` are intentionally exempt. All `lib/src/` code must carry explicit type annotations on every declaration and `///` on every public member.

## CI

Three GitHub Actions workflows in `.github/workflows/`:

- **`ci.yml`** — runs on every PR and push to `main`. Steps in order: format check → analyze → `dart doc --dry-run` → tests with coverage collection → Codecov upload → `dart pub publish --dry-run`. Failing tests appear as inline annotations in the PR diff (`--reporter=github`). `dart pub publish --dry-run` exits 65 on any warning — zero warnings is enforced.
- **`publish.yml`** — triggered by a `v[0-9]+.[0-9]+.[0-9]+` tag: runs a lighter CI job (format + analyze + test, no coverage or doc steps), then publishes via the official `dart-lang/setup-dart/.github/workflows/publish.yml@v1` reusable workflow using OIDC (no long-lived secret). Requires one-time setup on `pub.dev/packages/json_sentinel/admin` — enable automated publishing, set repo to `IgeeTheron/json-sentinel`, tag pattern `v{{version}}`.
- **`docs.yml`** — runs on push to `main` and `workflow_dispatch`. Generates the API reference via `dart doc --output doc/api` and deploys to GitHub Pages at `https://igeetheron.github.io/json-sentinel/`. Never cancels in-progress deployments (`cancel-in-progress: false`). The `doc/` output directory is gitignored.

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
    errors.add(error);
    stackTraces.add(stackTrace);
    capturedExtras.add(extras);
    escalations.add(escalate);
  });
});
tearDown(JsonSentinel.resetLoggerForTesting);
```

`resetLoggerForTesting()` must be called in `tearDown` whether the test used `configure()` or `silence()` — both set `_logger` and both must be reset. It resets all four global fields (`_logger`, `_verbose`, `_redactKeys`, `_redactionPlaceholder`).

The test for double-`configure()` (and double-`silence()`) relies on Dart asserts being active (they always are in `dart test`).

`json_sentinel_batch_test.dart` and `json_sentinel_test.dart` both have groups (`verbose`, `redaction`) that call `setUp(JsonSentinel.resetLoggerForTesting)` directly (overriding the outer `setUp`) so they can call `configure()` or `silence()` with non-default options without triggering the double-configure assert.

`example/json_sentinel_example.dart` calls `resetLoggerForTesting()` multiple times mid-file to switch between logger configurations for different demonstration sections. This is the only legitimate live use of `resetLoggerForTesting()` outside tests.
