# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `JsonSentinel.validateBatch()` — validates a list of `Map<String, dynamic>` payloads against a shared schema and emits a single consolidated log entry covering all failures, preventing one Sentry/Crashlytics event per failure when validating API response lists. Accepts the same `optional`, `strict`, `escalate`, and `context` parameters as `validate()` (including the same `'UnknownModel'` default for `context`). Accepts `generatePreviews: false` to skip per-item JSON serialisation for high-volume batches. Returns a `BatchValidationResult`.
- `BatchValidationResult` — result type for `validateBatch()`. Fields: `isValid` (true only when every item passed), `results` (one `JsonValidationResult` per input item in order), `failureCount`, and `failureIndices` (zero-based indices of failing items). All list fields are unmodifiable.
- `validateBatch()` logger extras include `'context'`, `'failure_count'` (int), `'total_count'` (int), and `'item_previews'` — a `List<String>` of truncated JSON previews for each failing item in `failureIndices` order. `item_previews` is absent when `generatePreviews: false` is passed.

### Changed
- `JsonValidationResult.failure()` now asserts in debug mode that the `errors` list is non-empty. A failure result with no errors is semantically contradictory. Callers passing `failure([])` will receive an `AssertionError` in debug builds (including `dart test`); release builds are unaffected.
- `verbose: true` now emits a `dart:developer` trace on every **failing** `validate()` and `validateBatch()` call in addition to the existing passing-call traces. Failures are now visible in DevTools Logging even when a Sentry/Crashlytics logger is registered.

## [0.1.1] - 2026-05-28

### Fixed
- Corrected repository and issue tracker URLs to point to `IgeeTheron/json-sentinel`.

## [0.1.0] - 2026-05-28

### Added
- `JsonSentinel.validate()` — validates a `Map<String, dynamic>` against an expected key/type schema at runtime without code generation. Collects all errors before logging so callers always see the full picture in a single log entry.
- `JsonValidationResult` — structured result returned by `validate()`, with an `isValid` flag and an unmodifiable `errors` list for programmatic access.
- `JsonLogFn` typedef — function signature for the logging callback. Carries `message`, `stackTrace`, `extras` (including `context` label and `json_preview`), and `escalate` hint.
- `JsonSentinel.configure()` — registers a `JsonLogFn` for all validation failures. Asserts in debug mode if called more than once; first registration wins in release.
- `JsonSentinel.silence()` — no-op alternative to `configure()`; suppresses all log output for purely programmatic use via `result.errors`. Mutually exclusive with `configure()`.
- `JsonSentinel.logger` getter — exposes the currently configured `JsonLogFn?`; `null` until `configure()` or `silence()` is called.
- `JsonSentinel.resetLoggerForTesting()` — resets the logger and verbose flag to their initial state; for use in test `tearDown`.
- `context` parameter on `validate()` — labels each log entry and the `context` extras key with the model name for searchable Sentry/Crashlytics context. Defaults to `'UnknownModel'`.
- `optional` parameter on `validate()` — keys marked optional are skipped when absent but still type-checked when present.
- `strict` mode on `validate()` — flags unexpected keys not declared in the schema.
- `escalate` parameter on `validate()` — per-call hint to the logger for elevated capture (e.g. a Sentry event rather than a breadcrumb). Defaults to `false`.
- Nullable fields and union types via the `expectedTypes` type-list syntax: `[String, null]` for nullable, `[int, double]` for unions, `null` or `[]` for existence-only checks.
- `verbose` parameter on `configure()` and `silence()` — enables trace-level `dart:developer` logs in debug mode: a confirmation on initialisation, a success trace on every passing `validate()` call, and a diagnostic when JSON serialisation fails.
- Fallback logging via `dart:developer` when no logger is configured; suppressed in release builds — always call `configure()` or `silence()` in production code.
- Zero runtime dependencies — pure Dart, works in Flutter, server, and CLI projects.

[Unreleased]: https://github.com/IgeeTheron/json-sentinel/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/IgeeTheron/json-sentinel/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/IgeeTheron/json-sentinel/releases/tag/v0.1.0
