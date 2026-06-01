// ignore_for_file: avoid_print
import 'package:json_sentinel/json_sentinel.dart';

// Captures the last extras map received by the logger — used in the batch
// section to print item_previews. In a real app, forward extras directly
// inside your configure() callback.
Map<String, Object?>? _lastExtras;

void main() {
  // region Setup: configure() -----------------------------------------------
  //
  // Call configure() OR silence() exactly once at app startup — never both.
  // configure() registers a JsonLogFn that receives every validation failure.
  //
  // In production, forward to your error reporter:
  //
  //   JsonSentinel.configure(
  //     (message, {error, stackTrace, extras, escalate}) {
  //       if (escalate == true) {
  //         Sentry.captureMessage(message, hint: Hint.withMap(extras ?? {}));
  //       } else {
  //         Sentry.addBreadcrumb(Breadcrumb(message: message));
  //       }
  //     },
  //     verbose: true, // emits dart:developer traces on init, each validate/
  //                    // validateBatch call (pass or fail), and json_preview
  //                    // fallback — independent of silence()
  //   );
  //
  // Use resetLoggerForTesting() in test tearDown to allow re-configuration:
  //
  //   tearDown(JsonSentinel.resetLoggerForTesting);
  //   // resets _logger, _verbose, _redactKeys, and _redactionPlaceholder

  JsonSentinel.configure(
    (message, {error, stackTrace, extras, escalate}) {
      _lastExtras = extras;
      print('[${escalate == true ? 'ERROR' : 'WARN'}] $message');
    },
  );

  // logger getter — null until configure() or silence() is called.
  print('Logger configured: ${JsonSentinel.logger != null}');
  // → Logger configured: true

  // endregion

  // region validate(): single-item validation --------------------------------
  //
  // All parameters:
  //   json          — the Map<String, dynamic> to validate
  //   expectedTypes — schema: key → allowed types (include null to allow null)
  //   context       — model name shown in log output; defaults to 'UnknownModel'
  //   optional      — keys skipped when absent, type-checked when present
  //   strict        — flag keys in json not declared in expectedTypes (see region 6)
  //   escalate      — hint to logger for elevated capture; defaults to false
  //
  // All errors are collected before a single log entry fires — validate()
  // never returns early. result.isValid is the primary guard.

  // Standalone — no model class needed. Useful for scripts, middleware, tests,
  // and config validation where you just need a shape check before proceeding.
  final eventJson = <String, dynamic>{'event': 'page_view', 'screen': 'home', 'duration_ms': 320};
  final check = JsonSentinel.validate(
    json: eventJson,
    expectedTypes: {
      'event': [String],
      'screen': [String],
      'duration_ms': [int],
    },
    context: 'AnalyticsEvent',
  );
  if (check.isValid) {
    print('Event: ${eventJson['event']} — screen: ${eventJson['screen']} (${eventJson['duration_ms']}ms)');
  }
  // → Event: page_view — screen: home (320ms)

  // Happy path — all types correct, optional key absent:
  final listing = ProductListing.tryFromJson({'productId': 42, 'sku': 'WIDGET-XL', 'price': 19.99});
  if (listing != null) {
    print('Product ${listing.productId} — ${listing.sku} at \$${listing.price}');
    // → Product 42 — WIDGET-XL at $19.99
  }

  // Failure path — missing required key + type mismatch, one log entry covers both:
  final badResult = JsonSentinel.validate(
    json: <String, dynamic>{'sku': 'WIDGET-XL', 'price': 'not-a-number'},
    expectedTypes: {
      'productId': [int],
      'sku': [String],
      'price': [int, double], // union — int or double accepted
    },
    context: 'ProductListing',
    escalate: true,
  );
  print('badResult.isValid: ${badResult.isValid}');
  // → [ERROR] [ProductListing] JSON validation failed (2 errors):
  // →   • Missing required key 'productId'.
  // →   • Key 'price' has invalid type. Expected: int, double; Actual: String.
  // → badResult.isValid: false

  // optional — keys skipped when absent, but type-checked when present.
  // Absent key → passes silently. Present key with wrong type → logged as normal.
  final optAbsent = JsonSentinel.validate(
    json: <String, dynamic>{'id': 1},
    expectedTypes: {
      'id': [int],
      'nickname': [String],
    },
    optional: {'nickname'},
    context: 'Profile',
  );
  print('optional absent: ${optAbsent.isValid}');
  // → optional absent: true   (no log — absent optional key is fine)

  final optWrongType = JsonSentinel.validate(
    json: <String, dynamic>{'id': 1, 'nickname': 99},
    expectedTypes: {
      'id': [int],
      'nickname': [String],
    },
    optional: {'nickname'},
    context: 'Profile',
  );
  print('optional present+wrong type: ${optWrongType.isValid}');
  // → [WARN] [Profile] JSON validation failed (1 error):
  // →   • Key 'nickname' has invalid type. Expected: String; Actual: int.
  // → optional present+wrong type: false

  // expectedTypes type syntax quick reference:
  //   [int]          — exact single type
  //   [int, double]  — union (either accepted)
  //   [String, null] — nullable (String or null)
  //   null or []     — existence-only (any value accepted, just checks key is present)

  // endregion

  // region silence(): programmatic error access ------------------------------
  //
  // silence() is the alternative to configure() — installs a no-op logger.
  // Use it when you only need result.errors and do not want any log output.
  //
  // In a real app you would call silence() instead of configure() at startup.
  // Here, resetLoggerForTesting() is used to switch modes within a single
  // runnable file — it is a test-only API and should not appear in production.

  JsonSentinel.resetLoggerForTesting(); // test-only: resets _logger, _verbose, and redaction state
  JsonSentinel.silence();

  final silentResult = JsonSentinel.validate(
    json: <String, dynamic>{'id': 'not-an-int', 'name': 42},
    expectedTypes: {
      'id': [int],
      'name': [String],
    },
    context: 'SilentModel',
  );

  // No logger fires — read errors directly from result.errors:
  if (!silentResult.isValid) {
    print('${silentResult.errors.length} validation error(s):');
    for (final error in silentResult.errors) {
      print('  — $error');
    }
  }
  // → 2 validation error(s):
  // →   — Key 'id' has invalid type. Expected: int; Actual: String.
  // →   — Key 'name' has invalid type. Expected: String; Actual: int.

  // Restore configure() for the remaining sections.
  JsonSentinel.resetLoggerForTesting();
  JsonSentinel.configure(
    (message, {error, stackTrace, extras, escalate}) {
      _lastExtras = extras;
      print('[${escalate == true ? 'ERROR' : 'WARN'}] $message');
    },
  );

  // endregion

  // region Nested model validation -------------------------------------------
  //
  // Each model validates its own fields independently. Failures carry distinct
  // context labels ('PaginatedResponse', 'MetaModel') so log entries are always
  // attributable to the layer that produced them.

  final page = PaginatedResponse.tryFromJson(<String, dynamic>{
    'data': <dynamic>[],
    'links': <String, dynamic>{'first': 'https://api.example.com/products?page=1', 'last': null, 'prev': null, 'next': null},
    'meta': <String, dynamic>{
      'current_page': 1,
      'from': null, // null when the page is empty
      'last_page': 1,
      'links': <dynamic>[],
      'path': 'https://api.example.com/products',
      'per_page': 15,
      'to': null, // null when the page is empty
      'total': 0,
    },
  });

  if (page != null) {
    print('Page ${page.meta.currentPage} of ${page.meta.lastPage} — ${page.meta.total} total');
    // → Page 1 of 1 — 0 total
  }

  // endregion

  // region validateBatch(): batch validation ---------------------------------
  //
  // validateBatch() validates a list of payloads against a shared schema and
  // emits exactly ONE consolidated log entry covering all failures. This prevents
  // one Sentry event per bad record when processing a list endpoint.
  //
  // The returned BatchValidationResult carries:
  //   isValid        — true only when every item passed
  //   results        — one JsonValidationResult per input item, in order
  //   failureCount   — number of failing items
  //   failureIndices — zero-based indices of failing items (ascending)
  //
  // On failure the logger extras map contains:
  //   'context'       — model name (String)
  //   'failure_count' — number of failing items (int)
  //   'total_count'   — total items in the batch (int)
  //   'item_previews' — truncated JSON per failing item in failureIndices order
  //                     (List<String>); absent when generatePreviews: false

  final records = <Map<String, dynamic>>[
    {'id': 1, 'name': 'Alice', 'role': 'admin'},
    {'id': 2, 'name': 'Bob'}, // missing 'role'
    {'id': 'three', 'name': 'Carol', 'role': 'viewer'}, // wrong type for 'id'
    {'id': 4, 'name': 'Dave', 'role': 'editor'},
  ];

  final batch = JsonSentinel.validateBatch(
    jsons: records,
    expectedTypes: {
      'id': [int],
      'name': [String],
      'role': [String],
    },
    context: 'UserRecord',
    escalate: true,
  );
  // → [ERROR] [UserRecord] JSON batch validation failed (2 of 4 items failed):
  // →   Item 1 (1 error):
  // →     • Missing required key 'role'.
  // →   Item 2 (1 error):
  // →     • Key 'id' has invalid type. Expected: int; Actual: String.

  // Per-item error detail from batch.results:
  print('${batch.failureCount} of ${records.length} invalid:');
  for (final i in batch.failureIndices) {
    print('  Item $i: ${batch.results[i].errors.join('; ')}');
  }
  // → 2 of 4 invalid:
  // →   Item 1: Missing required key 'role'.
  // →   Item 2: Key 'id' has invalid type. Expected: int; Actual: String.

  // item_previews — one JSON snapshot per failing item, in failureIndices order.
  // Forward them to Sentry in your configure() callback:
  //
  //   Sentry.captureMessage(message, hint: Hint.withMap({
  //     'previews': extras?['item_previews'], // List<String>
  //   }));
  final previews = _lastExtras?['item_previews'] as List<String>?;
  if (previews != null) {
    for (var k = 0; k < previews.length; k++) {
      print('  Preview[${batch.failureIndices[k]}]: ${previews[k]}');
    }
  }
  // →   Preview[1]: {"id":2,"name":"Bob"}
  // →   Preview[2]: {"id":"three","name":"Carol","role":"viewer"}

  // --- Converting batch results to models -----------------------------------

  // Pattern A — strict: abort entirely if any item is invalid.
  if (!batch.isValid) {
    print('Strict: ${batch.failureCount} invalid — aborting all');
    // → Strict: 2 invalid — aborting all
  }

  // Pattern B — lenient: skip invalid items, convert passing ones.
  // batch.results[i].isValid confirms all types — casts in fromValidJson are safe.
  final users = <UserRecord>[
    for (var i = 0; i < records.length; i++)
      if (batch.results[i].isValid) UserRecord.fromValidJson(records[i]),
  ];
  print('Lenient: converted ${users.length} of ${records.length} records:');
  for (final user in users) {
    print('  ${user.id} — ${user.name} (${user.role})');
  }
  // → Lenient: converted 2 of 4 records:
  // →   1 — Alice (admin)
  // →   4 — Dave (editor)

  // Pattern C — all failed: nothing to convert.
  if (batch.failureCount == records.length) {
    print('All records invalid — nothing to process');
  }

  // --- optional and strict apply per-item, same semantics as validate() -----

  // optional: key absent across all items → passes; present with wrong type → fails.
  final batchOpt = JsonSentinel.validateBatch(
    jsons: [
      {'id': 1, 'role': 'admin'}, // nickname absent — fine
      {'id': 2, 'role': 'editor', 'nickname': 99}, // nickname present + wrong type
    ],
    expectedTypes: {
      'id': [int],
      'role': [String],
      'nickname': [String],
    },
    optional: {'nickname'},
    context: 'BatchOptional',
  );
  print('batch optional: ${batchOpt.failureCount} of 2 failed');
  // → [WARN] [BatchOptional] JSON batch validation failed (1 of 2 items failed): ...
  // → batch optional: 1 of 2 failed

  // generatePreviews: false — skip jsonEncode for every failing item.
  // Use for large high-failure batches where preview generation would be costly.
  JsonSentinel.validateBatch(
    jsons: records,
    expectedTypes: {
      'id': [int],
      'name': [String],
      'role': [String],
    },
    context: 'UserRecord',
    generatePreviews: false,
  );
  // → Same log message as above, but extras has no 'item_previews' key.
  print('item_previews absent: ${!(_lastExtras?.containsKey('item_previews') ?? false)}');
  // → item_previews absent: true

  // strict: unexpected keys in any item are reported as errors.
  final batchStrict = JsonSentinel.validateBatch(
    jsons: [
      {'id': 1, 'role': 'admin'},
      {'id': 2, 'role': 'editor', 'extra': true}, // unexpected key
    ],
    expectedTypes: {
      'id': [int],
      'role': [String],
    },
    strict: true,
    context: 'BatchStrict',
  );
  print('batch strict: ${batchStrict.failureCount} of 2 failed');
  // → [WARN] [BatchStrict] JSON batch validation failed (1 of 2 items failed): ...
  // → batch strict: 1 of 2 failed

  // endregion

  // region Paginated responses: validate() + validateBatch() together ----------
  //
  // The canonical combined pattern: validate() checks the outer envelope once,
  // then validateBatch() validates every item inside data[], producing exactly
  // one log entry for all item failures — not one Sentry capture per bad record.
  //
  // Envelope failure (wrong type for current_page) → escalate: true → full capture.
  // Item failures (bad records inside data) → escalate: false → single breadcrumb.

  final userPage = PaginatedUserResponse.tryFromJson(<String, dynamic>{
    'current_page': 1,
    'total': 4,
    'data': <dynamic>[
      {'id': 1, 'name': 'Alice', 'role': 'admin'},
      {'id': 2, 'name': 'Bob'}, // missing 'role'
      {'id': 'three', 'name': 'Carol', 'role': 'viewer'}, // wrong type for 'id'
      {'id': 4, 'name': 'Dave', 'role': 'editor'},
    ],
  });
  // → [WARN] [UserRecord] JSON batch validation failed (2 of 4 items failed):
  // →   Item 1 (1 error):
  // →     • Missing required key 'role'.
  // →   Item 2 (1 error):
  // →     • Key 'id' has invalid type. Expected: int; Actual: String.

  if (userPage != null) {
    print('Page ${userPage.currentPage} — ${userPage.users.length} of ${userPage.total} valid:');
    for (final user in userPage.users) {
      print('  ${user.name} (${user.role})');
    }
  }
  // → Page 1 — 2 of 4 valid:
  // →   Alice (admin)
  // →   Dave (editor)

  // endregion

  // region Strict mode -------------------------------------------------------
  //
  // When strict: true, keys present in json but absent from expectedTypes are
  // reported as errors. Catches API response drift and unexpected fields early.

  final strictResult = JsonSentinel.validate(
    json: <String, dynamic>{'id': 1, 'name': 'Alice', 'unexpected': 'surprise'},
    expectedTypes: {
      'id': [int],
      'name': [String],
    },
    strict: true,
    context: 'StrictModel',
  );
  print('Strict isValid: ${strictResult.isValid}');
  // → [WARN] [StrictModel] JSON validation failed (1 error):
  // →   • Unexpected key 'unexpected'.
  // → Strict isValid: false

  // endregion

  // region redactKeys: mask sensitive values in json_preview -----------------
  //
  // Pass redactKeys to configure() to mask named top-level fields before any
  // json_preview or item_previews snapshot is sent to Sentry/Crashlytics.
  // The redaction placeholder defaults to '[REDACTED]' and can be overridden.
  // The validated data itself is never modified — only the preview string is affected.
  //
  // In a real app call configure() once at startup with redactKeys.
  // Here, resetLoggerForTesting() lets us switch configurations mid-file.

  JsonSentinel.resetLoggerForTesting();
  JsonSentinel.configure(
    (message, {error, stackTrace, extras, escalate}) {
      _lastExtras = extras;
      print('[${escalate == true ? 'ERROR' : 'WARN'}] $message');
    },
    redactKeys: {'apiKey', 'password'},
  );

  JsonSentinel.validate(
    json: <String, dynamic>{
      'userId': 7,
      'email': 'alice@example.com',
      'apiKey': 'sk-live-abc123', // sensitive — will be masked in json_preview
      'password': 'hunter2', // sensitive — will be masked in json_preview
    },
    expectedTypes: {
      'missing_field': [int], // deliberately missing to trigger the log
    },
    context: 'LoginPayload',
  );
  // → [WARN] [LoginPayload] JSON validation failed (1 error): ...
  // → json_preview: {"userId":7,"email":"alice@example.com","apiKey":"[REDACTED]","password":"[REDACTED]"}
  final redactedPreview = _lastExtras?['json_preview'] as String?;
  print('preview contains [REDACTED]: ${redactedPreview?.contains('[REDACTED]') ?? false}');
  // → preview contains [REDACTED]: true
  print('preview hides password: ${!(redactedPreview?.contains('hunter2') ?? true)}');
  // → preview hides password: true

  // Custom placeholder — override the default '[REDACTED]' string.
  JsonSentinel.resetLoggerForTesting();
  JsonSentinel.configure(
    (message, {error, stackTrace, extras, escalate}) {
      _lastExtras = extras;
      print('[${escalate == true ? 'ERROR' : 'WARN'}] $message');
    },
    redactKeys: {'token'},
    redactionPlaceholder: '***',
  );
  JsonSentinel.validate(
    json: <String, dynamic>{'userId': 1, 'token': 'bearer-xyz'},
    expectedTypes: {
      'missing': [int],
    },
    context: 'TokenPayload',
  );
  final tokenPreview = _lastExtras?['json_preview'] as String?;
  print('custom placeholder present: ${tokenPreview?.contains('***') ?? false}');
  // → custom placeholder present: true

  // item_previews in validateBatch() are also redacted automatically —
  // no separate configuration needed.
  JsonSentinel.resetLoggerForTesting();
  JsonSentinel.configure(
    (message, {error, stackTrace, extras, escalate}) {
      _lastExtras = extras;
      print('[${escalate == true ? 'ERROR' : 'WARN'}] $message');
    },
    redactKeys: {'password'},
  );
  JsonSentinel.validateBatch(
    jsons: [
      {'userId': 1, 'password': 'topsecret'},
    ],
    expectedTypes: {
      'missing': [int],
    },
    context: 'BatchRedact',
  );
  final batchPreviews = _lastExtras?['item_previews'] as List<String>?;
  print('batch preview redacted: ${batchPreviews?.first.contains('[REDACTED]') ?? false}');
  // → batch preview redacted: true

  // Restore a plain logger for any code that follows.
  JsonSentinel.resetLoggerForTesting();
  JsonSentinel.configure(
    (message, {error, stackTrace, extras, escalate}) {
      _lastExtras = extras;
      print('[${escalate == true ? 'ERROR' : 'WARN'}] $message');
    },
  );

  // endregion
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

// Used by the validateBatch() and paginated-responses sections.
// fromValidJson() performs no validation — call it only after the relevant
// validate/validateBatch call confirms the item passed.
class UserRecord {
  final int id;
  final String name;
  final String role;

  UserRecord({required this.id, required this.name, required this.role});

  factory UserRecord.fromValidJson(Map<String, dynamic> json) => UserRecord(
        id: json['id'] as int,
        name: json['name'] as String,
        role: json['role'] as String,
      );
}

// Used by the 'Paginated responses' region. Demonstrates validate() +
// validateBatch() combined — envelope validation followed by per-item batch
// validation, producing at most two log entries regardless of item count.
class PaginatedUserResponse {
  final int currentPage;
  final int total;
  final List<UserRecord> users;

  PaginatedUserResponse({
    required this.currentPage,
    required this.total,
    required this.users,
  });

  static PaginatedUserResponse? tryFromJson(Map<String, dynamic> json) {
    // Step 1: validate the outer envelope — structural errors worth escalating.
    final envelope = JsonSentinel.validate(
      json: json,
      expectedTypes: {
        'current_page': [int],
        'total': [int],
        'data': [List],
      },
      context: 'UserPage',
      escalate: true,
    );
    if (!envelope.isValid) return null;

    // Step 2: validate every item inside data — one breadcrumb for all failures.
    // Filter non-Map elements out rather than using a lazy cast that would throw
    // inside validateBatch() if the API returns unexpected element types.
    final items = [
      for (final item in json['data'] as List)
        if (item is Map<String, dynamic>) item,
    ];
    final batch = JsonSentinel.validateBatch(
      jsons: items,
      expectedTypes: {
        'id': [int],
        'name': [String],
        'role': [String],
      },
      context: 'UserRecord',
      escalate: false,
    );

    // Step 3: return the page — skip invalid items, keep valid ones.
    return PaginatedUserResponse(
      currentPage: json['current_page'] as int,
      total: json['total'] as int,
      users: [
        for (var i = 0; i < items.length; i++)
          if (batch.results[i].isValid) UserRecord.fromValidJson(items[i]),
      ],
    );
  }
}

// Used by the single-item validate() happy-path section. Demonstrates the
// tryFromJson pattern: validate first, cast only after isValid is confirmed.
class ProductListing {
  final int productId;
  final String sku;
  final double price;
  final String? description;

  ProductListing({
    required this.productId,
    required this.sku,
    required this.price,
    this.description,
  });

  static ProductListing? tryFromJson(Map<String, dynamic> json) {
    final result = JsonSentinel.validate(
      json: json,
      expectedTypes: {
        'productId': [int],
        'sku': [String],
        'price': [int, double], // union — API may return either
        'description': [String, null], // nullable
      },
      optional: {'description'}, // absent is fine; type-checked when present
      context: 'ProductListing',
      escalate: true,
    );
    if (!result.isValid) return null;

    return ProductListing(
      productId: json['productId'] as int,
      sku: json['sku'] as String,
      price: (json['price'] as num).toDouble(),
      description: json['description'] as String?,
    );
  }
}

// Used by the 'Nested model validation' region. Demonstrates nested model
// delegation — each level validates its own fields with a separate context label.
// Compare PaginatedUserResponse above, which uses validateBatch() on the items.
class PaginatedResponse {
  final List<dynamic> data;
  final Map<String, dynamic> links;
  final MetaModel meta;

  PaginatedResponse({required this.data, required this.links, required this.meta});

  static PaginatedResponse? tryFromJson(Map<String, dynamic> json) {
    final result = JsonSentinel.validate(
      json: json,
      expectedTypes: {
        'data': [List],
        'links': [Map],
        'meta': [Map],
      },
      context: 'PaginatedResponse',
      escalate: true,
    );
    if (!result.isValid) return null;

    final meta = MetaModel.tryFromJson(Map<String, dynamic>.from(json['meta'] as Map));
    if (meta == null) return null;

    return PaginatedResponse(
      data: List<dynamic>.from(json['data'] as List),
      links: Map<String, dynamic>.from(json['links'] as Map),
      meta: meta,
    );
  }
}

class MetaModel {
  final int currentPage;
  final int? from; // null when the page contains no items
  final int lastPage;
  final int perPage;
  final int? to; // null when the page contains no items
  final int total;

  MetaModel({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    this.from,
    this.to,
  });

  static MetaModel? tryFromJson(Map<String, dynamic> json) {
    final result = JsonSentinel.validate(
      json: json,
      expectedTypes: {
        'current_page': [int],
        'from': [null, int], // nullable — no items on this page
        'last_page': [int],
        'links': [List],
        'path': [String],
        'per_page': [int],
        'to': [null, int], // nullable — no items on this page
        'total': [int],
      },
      context: 'MetaModel',
      escalate: true,
    );
    if (!result.isValid) return null;

    return MetaModel(
      currentPage: json['current_page'] as int,
      from: json['from'] as int?,
      lastPage: json['last_page'] as int,
      perPage: json['per_page'] as int,
      to: json['to'] as int?,
      total: json['total'] as int,
    );
  }
}
