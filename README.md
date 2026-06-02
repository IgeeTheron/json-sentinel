# json_sentinel

[![CI](https://github.com/IgeeTheron/json-sentinel/actions/workflows/ci.yml/badge.svg)](https://github.com/IgeeTheron/json-sentinel/actions/workflows/ci.yml)
[![pub.dev](https://img.shields.io/pub/v/json_sentinel.svg)](https://pub.dev/packages/json_sentinel)

Lightweight runtime JSON key and type validation for Dart — no code generation required.

Validates a `Map<String, dynamic>` against an expected schema before you deserialise it,
catching malformed API responses early with a single, readable log entry per failure.

## Features

- Checks key existence and value types in one call
- Nullable fields, union types (`[int, double]`), and optional fields all supported
- Strict mode flags unexpected keys not declared in your schema
- Single log entry per call listing every problem as a bullet — nothing hidden by an early return
- **`validateBatch()`** — validates a list of payloads against a shared schema and emits one consolidated log entry for all failures, preventing duplicate Sentry/Crashlytics events when processing list endpoints
- `json_preview` attached to single-item extras; `item_previews` (`List<String>`) attached to batch extras — one JSON preview per failing item (opt out with `generatePreviews: false`)
- `parentContext` — chain `validate()` calls across nested models to produce `[UserPage.data[2] > MetaModel]` log prefixes, pinpointing failures in paginated or deeply-nested responses without extra logging code
- `redactKeys` — mask sensitive top-level field values (passwords, tokens, API keys) in `json_preview` and `item_previews` before they reach Sentry/Crashlytics; custom `redactionPlaceholder` supported
- Configurable `escalate` flag per call — control whether a failure is a breadcrumb or a full capture
- Returns `JsonValidationResult` with `isValid` + programmatic `errors` list; `validateBatch()` returns `BatchValidationResult` with per-item `results`, `failureCount`, and `failureIndices`
- `silence()` for pure programmatic use with no log output
- Optional `verbose: true` for debug-mode traces via `dart:developer` — fires on init, every passing and failing call, and `json_preview` serialisation fallback
- Zero runtime dependencies — pure Dart, works in Flutter, server, and CLI

## Getting started

```yaml
dependencies:
  json_sentinel: ^0.3.0
```

## Usage

### 1. Wire in your logger once at startup

```dart
JsonSentinel.configure(
  (message, {error, stackTrace, extras, escalate}) {
    // escalate: true → full capture; false → breadcrumb
    if (escalate == true) {
      Sentry.captureMessage(message, hint: Hint.withMap(extras ?? {}));
    } else {
      Sentry.addBreadcrumb(Breadcrumb(message: message));
    }
  },
  verbose: true, // optional: dart:developer traces in debug mode
);
```

If `configure()` has not been called, failures fall back to `dart:developer` (visible in
DevTools Logging; suppressed in release builds). Always call `configure()` or `silence()` in
production code. Use `JsonSentinel.logger` to check whether a logger is already registered.

#### No logging needed?

Use `silence()` when you only want programmatic access to `result.errors`:

```dart
JsonSentinel.silence(); // installs a no-op logger — no output of any kind
```

`silence()` and `configure()` are mutually exclusive — call one or the other, never both.

### 2. Validate

No model class required — validate any `Map<String, dynamic>` directly:

```dart
final result = JsonSentinel.validate(
  json: responseMap,
  expectedTypes: {'id': [int], 'name': [String], 'active': [bool]},
  context: 'UserInput',
);
if (result.isValid) {
  // types confirmed — safe to cast and use
  final id = responseMap['id'] as int;
}
```

Useful for scripts, middleware, configuration checks, and tests where you don't need
a full model class — just a shape check before you proceed.

#### In a `tryFromJson` factory

For structured deserialisation, validate before casting:

```dart
static ProductListing? tryFromJson(Map<String, dynamic> json) {
  final result = JsonSentinel.validate(
    json: json,
    expectedTypes: {
      'productId':   [int],
      'sku':         [String],
      'price':       [int, double],   // union — API may return either
      'description': [String, null],  // nullable
    },
    optional: {'description'},        // absent is fine; type-checked if present
    context: 'ProductListing',
    escalate: true,
  );
  if (!result.isValid) return null;

  return ProductListing(
    productId:   json['productId'] as int,
    sku:         json['sku'] as String,
    price:       (json['price'] as num).toDouble(),
    description: json['description'] as String?,
  );
}
```

### 3. Batch validation

`validateBatch()` validates a list of payloads against a shared schema and emits exactly
**one** consolidated log entry — no matter how many items fail. Use it instead of calling
`validate()` in a loop when failures should produce a single Sentry event.

```dart
final batch = JsonSentinel.validateBatch(
  jsons: payloads,              // List<Map<String, dynamic>>
  expectedTypes: {
    'id':   [int],
    'name': [String],
    'role': [String],
  },
  optional: {'role'},           // same optional/strict/escalate semantics as validate()
  context: 'UserRecord',
  escalate: true,
  generatePreviews: true,       // set false to skip jsonEncode on each failing item
);
```

`BatchValidationResult` fields:

| Field | Type | Description |
|---|---|---|
| `isValid` | `bool` | `true` only when every item passed |
| `results` | `List<JsonValidationResult>` | One result per input item, in order |
| `failureCount` | `int` | Number of failing items |
| `failureIndices` | `List<int>` | Zero-based indices of failing items |

#### Converting results to models

```dart
// Pattern A — strict: abort if any item is invalid
if (!batch.isValid) return null;

// Pattern B — lenient: skip invalid items, convert passing ones
final users = [
  for (var i = 0; i < payloads.length; i++)
    if (batch.results[i].isValid) UserRecord.fromValidJson(payloads[i]),
];

// Pattern C — all failed
if (batch.failureCount == payloads.length) {
  // nothing valid to process
}
```

#### Batch extras for Sentry

On failure the logger receives `extras` with `'context'`, `'failure_count'` (int),
`'total_count'` (int), and `'item_previews'` — a `List<String>` of truncated JSON
snapshots for each failing item, in `failureIndices` order. Pass
`generatePreviews: false` to omit `item_previews` and skip JSON serialisation for
all failing items (useful for large high-failure batches):

```dart
Sentry.captureMessage(message, hint: Hint.withMap({
  'previews': extras?['item_previews'], // List<String>
}));
```

### Paginated responses

When a list endpoint wraps items in an envelope object, use `validate()` for the outer
shape and `validateBatch()` for the items inside. This produces at most two log entries —
one if the envelope itself is malformed (worth escalating), one covering all item failures
combined (a single breadcrumb, not one Sentry capture per bad record).

```dart
static PaginatedUserResponse? tryFromJson(Map<String, dynamic> json) {
  // Step 1: validate the outer envelope — structural errors here are worth escalating.
  final envelope = JsonSentinel.validate(
    json: json,
    expectedTypes: {
      'current_page': [int],
      'total':        [int],
      'data':         [List],
    },
    context: 'UserPage',
    escalate: true,
  );
  if (!envelope.isValid) return null;

  // Step 2: validate every item inside data — one breadcrumb for all failures combined.
  // Filter non-Map elements rather than using a lazy cast that throws at runtime.
  final items = [
    for (final item in json['data'] as List)
      if (item is Map<String, dynamic>) item,
  ];
  final batch = JsonSentinel.validateBatch(
    jsons: items,
    expectedTypes: {
      'id':   [int],
      'name': [String],
      'role': [String],
    },
    context: 'UserRecord',
    escalate: false,
  );

  // Step 3: return the page with valid items (lenient: skip bad records, keep good ones).
  return PaginatedUserResponse(
    currentPage: json['current_page'] as int,
    total:       json['total'] as int,
    users: [
      for (var i = 0; i < items.length; i++)
        if (batch.results[i].isValid) UserRecord.fromValidJson(items[i]),
    ],
  );
}
```

### Nested JSON

Validate the outer shape at each level; let child models validate their own fields.
Failures carry the child's own `context` string, so log entries are always pinpointed.

```dart
// Parent: validates top-level keys as List/Map only.
static PaginatedResponse? tryFromJson(Map<String, dynamic> json) {
  final result = JsonSentinel.validate(
    json: json,
    expectedTypes: {
      'data':  [List],
      'links': [Map],
      'meta':  [Map],
    },
    context: 'PaginatedResponse',
    escalate: true,
  );
  if (!result.isValid) return null;

  final meta = MetaModel.tryFromJson(
    Map<String, dynamic>.from(json['meta'] as Map),
  );
  if (meta == null) return null;
  // ...
}

// Child: validates its own schema, including nullable fields.
static MetaModel? tryFromJson(Map<String, dynamic> json) {
  final result = JsonSentinel.validate(
    json: json,
    expectedTypes: {
      'current_page': [int],
      'from':         [null, int],  // null when page is empty
      'last_page':    [int],
      'links':        [List],
      'path':         [String],
      'per_page':     [int],
      'to':           [null, int],  // null when page is empty
      'total':        [int],
    },
    context: 'MetaModel',
    escalate: true,
  );
  if (!result.isValid) return null;
  // ...
}
```

### parentContext — chained paths across nested models

When calling `validate()` in a loop over nested items, pass `parentContext` to include
the parent path in every log entry. Without it, errors from index 1, 2, and 19 all read
`[MetaModel]` — with it, the log pinpoints each one:

```dart
for (var i = 0; i < items.length; i++) {
  JsonSentinel.validate(
    json: items[i]['meta'] as Map<String, dynamic>,
    expectedTypes: {'total': [int], 'per_page': [int]},
    context: 'MetaModel',
    parentContext: 'UserPage.data[$i]',
  );
}
// [UserPage.data[1] > MetaModel] JSON validation failed (1 error):
//   • Missing required key 'total'.
```

The combined path is also stored in `extras['context']`, so Sentry breadcrumbs and
fingerprints are accurate without any extra work.

`validateBatch()` does not accept `parentContext` — it builds its own indexed path
(`Item 1`, `Item 2`, …) internally.

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
  strict: true,
);
```

### Redaction

Pass `redactKeys` to `configure()` to mask sensitive top-level field values in every
`json_preview` and `item_previews` snapshot sent to your error reporter. Values matching
a listed key are replaced with `'[REDACTED]'` (or your custom placeholder) before the
JSON is encoded — the validated data itself is never modified.

```dart
JsonSentinel.configure(
  (message, {error, stackTrace, extras, escalate}) { ... },
  redactKeys: {'password', 'token', 'apiKey', 'secret'},
  redactionPlaceholder: '[REDACTED]', // optional, this is the default
);
```

Given `{'userId': 42, 'password': 'hunter2', 'token': 'abc123'}`, the `json_preview`
in extras becomes:

```json
{"userId": 42, "password": "[REDACTED]", "token": "[REDACTED]"}
```

Redaction applies to both `json_preview` (single-item) and `item_previews` (batch) — no
separate configuration needed. Only top-level keys are redacted; nested object contents
are not inspected.

`silence()` accepts the same `redactKeys` and `redactionPlaceholder` parameters for
consistency.

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

Single-item failure:

```text
[ProductListing] JSON validation failed (2 errors):
  • Key 'productId' has invalid type. Expected: int; Actual: String.
  • Missing required key 'sku'.
```

Single-item failure with `parentContext`:

```text
[UserPage.data[2] > MetaModel] JSON validation failed (1 error):
  • Missing required key 'total'.
```

Batch failure:

```text
[UserRecord] JSON batch validation failed (2 of 4 items failed):
  Item 1 (1 error):
    • Missing required key 'role'.
  Item 2 (1 error):
    • Key 'id' has invalid type. Expected: int; Actual: String.
```

### Testing

`configure()` and `silence()` both assert in debug mode if called twice. Call
`JsonSentinel.resetLoggerForTesting()` in `tearDown` to allow re-configuration across test cases:

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
| `[num]` | Required, `int` or `double` — prefer `[int, double]` when you want to signal intent explicitly |
| `[int, double]` | Required, `int` or `double` (explicit union) |
| `[Map]` | Required, any `Map` |
| `[List]` | Required, any `List` |
| `[String, null]` | Required, `String` or `null` |
| `[null, int]` | Required, `null` or `int` |
| `null` or `[]` | Required key, type not checked |

Add the key to `optional` to make presence itself optional.

## Additional information

- [pub.dev package page](https://pub.dev/packages/json_sentinel)
- [File issues](https://github.com/IgeeTheron/json-sentinel/issues)
- [Changelog](https://github.com/IgeeTheron/json-sentinel/blob/main/CHANGELOG.md)
- Contributions welcome — open an issue before starting significant work
