# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `JsonSentinel.validate()` — validates a `Map<String, dynamic>` against an expected key/type schema at runtime, without code generation.
- `JsonValidationResult` — structured result with `isValid` flag and programmatically accessible `errors` list.
- `JsonLogFn` typedef — configurable logging hook; wire in any logger via `JsonSentinel.configure()`.
- `JsonSentinel.logger` getter — exposes the currently configured `JsonLogFn?`; `null` until `configure()` is called.
- `JsonSentinel.resetLoggerForTesting()` — resets the configured logger to `null`; for use in test `tearDown`.
- `optional` parameter on `validate()` — mark keys as present-or-absent without failing validation.
- `strict` mode on `validate()` — flag unexpected keys not declared in the schema.
- `escalate` parameter on `validate()` — per-call hint to the logger for elevated capture (e.g. Sentry).
- Zero runtime dependencies — pure Dart, works in Flutter, server, and CLI projects.

[Unreleased]: https://github.com/My-Fuel-Orders/json_sentinel/compare/main...HEAD