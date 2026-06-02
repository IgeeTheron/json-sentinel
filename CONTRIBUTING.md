# Contributing

Thanks for considering a contribution to `json_sentinel`.

## Prerequisites

- Dart SDK ≥ 3.0.0

## Before you start

Open an issue before starting any significant work. This avoids duplicated effort and ensures the change aligns with the project direction.

## Local development

```bash
dart pub get                          # install dependencies
dart format .                         # format code
dart analyze --fatal-infos --fatal-warnings  # static analysis
dart test                             # run all tests
bash scripts/publish.sh --dry-run    # pre-flight publish check
```

All four commands must pass before opening a PR. The CI pipeline runs the same steps.

## Code standards

- **Line length:** 150 characters
- **Public API docs:** every public member in `lib/` requires a `///` doc comment
- **Type annotations:** all declarations in `lib/src/` must carry explicit type annotations (`always_specify_types` is enforced)
- **No runtime dependencies:** this is a zero-dependency package — do not add entries under `dependencies:` in `pubspec.yaml`
- **Imports:** use `package:json_sentinel/...` — relative imports are not permitted (`always_use_package_imports` is enforced)

## Tests

Tests live in `test/src/`. Add or update tests for every user-visible change. The project uses a capturing-logger pattern — no mocking framework is used or required.

Run a single test file:

```bash
dart test test/src/json_sentinel_test.dart
```

## CHANGELOG

Update `CHANGELOG.md` under `[Unreleased]` for every user-visible change. Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format:

```markdown
### Added
- Brief description of what was added.
```

Permitted headings: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.

## Versioning

This package follows [Semantic Versioning](https://semver.org/). Until v1.0.0 the public API is not yet frozen — breaking changes require a minor version bump. After v1.0.0, breaking changes require a major version bump.
