# json_sentinel

[![CI](https://github.com/My-Fuel-Orders/json_sentinel/actions/workflows/ci.yml/badge.svg)](https://github.com/My-Fuel-Orders/json_sentinel/actions/workflows/ci.yml)
[![pub.dev](https://img.shields.io/pub/v/json_sentinel.svg)](https://pub.dev/packages/json_sentinel)

Lightweight runtime JSON key and type validation for Dart — no code generation required.

Validates a `Map<String, dynamic>` against an expected schema before you deserialise it,
catching malformed API responses early with a single, readable log entry per failure.

## Features

- Checks key existence and value types in one call
- Nullable fields, union types (`[int, double]`), and optional fields all supported
- Strict mode flags unexpected keys not declared in your schema
- Single log entry per call listing every problem as a bullet — nothing hidden by an early return
- Structured `json_preview` and `context` passed as extras for searchable Sentry/Crashlytics context
- Configurable `escalate` flag per call — control whether a failure is a breadcrumb or a capture
- Returns `JsonValidationResult` with `isValid` + programmatic `errors` list
- Zero runtime dependencies — pure Dart, works in Flutter, server, and CLI

## Getting started

```yaml
dependencies:
  json_sentinel: ^0.1.0
```

## Usage

### 1. Wire in your logger once at startup

```dart
JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
  // Forward to whatever logging solution you use:
  myLogger.warn(
    message,
    stackTrace: stackTrace,
    extras: extras,
    escalate: escalate ?? false,
  );
});
```

If `configure()` has not been called, failures fall back to `print()`. Use `JsonSentinel.logger` to check whether a logger is already configured before calling `configure()`.

### 2. Validate in `tryFromJson`

```dart
static OrderResponse? tryFromJson(Map<String, dynamic> json) {
  final result = JsonSentinel.validate(
    json: json,
    expectedTypes: {
      'orderId':   [int],
      'depotCode': [String],
      'litres':    [int, double],
      'notes':     [String, null], // nullable
    },
    optional: {'notes'},           // absent is fine; type-checked if present
    context: 'OrderResponse',
  );
  if (!result.isValid) return null;

  return OrderResponse(
    orderId:   json['orderId'] as int,
    depotCode: json['depotCode'] as String,
    litres:    (json['litres'] as num).toDouble(),
    notes:     json['notes'] as String?,
  );
}
```

### Optional fields

Keys listed in `optional` are skipped when absent but still type-checked when present:

```dart
JsonSentinel.validate(
  json: json,
  expectedTypes: {'id': [int], 'nickname': [String]},
  optional: {'nickname'},
);
```

### Strict mode

Reject keys present in the JSON but not declared in your schema:

```dart
JsonSentinel.validate(
  json: json,
  expectedTypes: {'id': [int]},
  strict: true, // errors on any extra key
);
```

### Programmatic error access

```dart
final result = JsonSentinel.validate(json: json, expectedTypes: schema);
if (!result.isValid) {
  for (final error in result.errors) {
    print(error);
  }
}
```

### Example log output

```
[OrderResponse] JSON validation failed (2 errors):
  • Key 'orderId' has invalid type. Expected: int; Actual: String.
  • Missing required key 'depotCode'.
```

### Testing

`configure()` asserts in debug mode if called twice — tests always run with asserts enabled. Call `JsonSentinel.resetLoggerForTesting()` in `tearDown` to allow re-configuration across test cases:

```dart
setUp(() {
  JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
    logs.add(message);
  });
});
tearDown(JsonSentinel.resetLoggerForTesting);
```

## Schema reference

| Type list value | Meaning |
|---|---|
| `[int]` | Required, must be `int` |
| `[String]` | Required, must be `String` |
| `[bool]` | Required, must be `bool` |
| `[double]` | Required, must be `double` |
| `[num]` | Required, `int` or `double` |
| `[int, double]` | Required, `int` or `double` (explicit union) |
| `[Map]` | Required, any `Map` |
| `[List]` | Required, any `List` |
| `[String, null]` | Required, `String` or `null` |
| `null` or `[]` | Required key, type not checked |

Add the key to `optional` to make presence itself optional.

## Additional information

- File issues at the [GitHub repository](https://github.com/My-Fuel-Orders/json_sentinel)
- Contributions welcome