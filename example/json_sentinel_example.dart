// ignore_for_file: avoid_print
import 'package:json_sentinel/json_sentinel.dart';

// Configure once at app startup. In production forward to your error reporter:
//
//   JsonSentinel.configure(
//     (message, {error, stackTrace, extras, escalate}) {
//       if (escalate == true) {
//         Sentry.captureMessage(message, hint: Hint.withMap(extras ?? {}));
//       } else {
//         Sentry.addBreadcrumb(Breadcrumb(message: message));
//       }
//     },
//   );
//
// To suppress all log output and read errors from result.errors instead:
//
//   JsonSentinel.silence();

void main() {
  JsonSentinel.configure(
    (message, {error, stackTrace, extras, escalate}) {
      print('[${escalate == true ? 'ERROR' : 'WARN'}] $message');
    },
  );

  // --- 1. validate() in a tryFromJson factory --------------------------------
  //
  // The typical pattern: validate once, return null on failure.
  // Each failing key is reported in a single log entry.

  final orderJson = <String, dynamic>{
    'orderId': 42,
    'depotCode': 'CPT01',
    'litres': 500.0,
    'notes': null,
  };

  final order = OrderResponse.tryFromJson(orderJson);
  if (order != null) {
    print('Order ${order.orderId} — ${order.litres}L from ${order.depotCode}');
    // → Order 42 — 500.0L from CPT01
  }

  // --- 2. Nested response — each level validates its own fields --------------
  //
  // PaginatedResponse checks the top-level shape, then delegates to MetaModel
  // for the meta sub-object. Failures are logged under separate context labels.

  final pageJson = <String, dynamic>{
    'data': <dynamic>[],
    'links': <String, dynamic>{'first': 'https://api.example.com/orders?page=1', 'last': null, 'prev': null, 'next': null},
    'meta': <String, dynamic>{
      'current_page': 1,
      'from': null, // null when the page is empty
      'last_page': 1,
      'links': <dynamic>[],
      'path': 'https://api.example.com/orders',
      'per_page': 15,
      'to': null, // null when the page is empty
      'total': 0,
    },
  };

  final page = PaginatedResponse.tryFromJson(pageJson);
  if (page != null) {
    print('Page ${page.meta.currentPage} of ${page.meta.lastPage} — ${page.meta.total} total');
    // → Page 1 of 1 — 0 total
  }

  // --- 3. validateBatch() — one log entry for all failures combined ----------
  //
  // When iterating over a list of API payloads, validateBatch() fires a single
  // consolidated log entry instead of one per failing record. This prevents
  // duplicate Sentry/Crashlytics events when 20 payloads share the same fault.

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
  );

  // One consolidated log entry fires above (not one per failing record).
  print('${batch.failureCount} of ${records.length} records invalid (indices: ${batch.failureIndices})');
  // → 2 of 4 records invalid (indices: [1, 2])

  // Per-item results are still accessible for programmatic handling:
  for (final i in batch.failureIndices) {
    print('  Record $i: ${batch.results[i].errors.join('; ')}');
  }
  // → Record 1: Missing required key 'role'.
  // → Record 2: Key 'id' has invalid type. Expected: int; Actual: String.

  // --- 4. Strict mode — reject unexpected keys ------------------------------

  final strictResult = JsonSentinel.validate(
    json: <String, dynamic>{'id': 1, 'unexpected': 'surprise'},
    expectedTypes: {
      'id': [int],
    },
    strict: true,
    context: 'StrictExample',
  );
  print('Strict check valid: ${strictResult.isValid}');
  // → [WARN] [StrictExample] JSON validation failed (1 error):
  // →   • Unexpected key 'unexpected'.
  // → Strict check valid: false
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class OrderResponse {
  final int orderId;
  final String depotCode;
  final double litres;
  final String? notes;

  OrderResponse({
    required this.orderId,
    required this.depotCode,
    required this.litres,
    this.notes,
  });

  static OrderResponse? tryFromJson(Map<String, dynamic> json) {
    final result = JsonSentinel.validate(
      json: json,
      expectedTypes: {
        'orderId': [int],
        'depotCode': [String],
        'litres': [int, double], // union — API may return either
        'notes': [String, null], // nullable
      },
      optional: {'notes'}, // absent is fine; type-checked when present
      context: 'OrderResponse',
      escalate: true,
    );
    if (!result.isValid) return null;

    return OrderResponse(
      orderId: json['orderId'] as int,
      depotCode: json['depotCode'] as String,
      litres: (json['litres'] as num).toDouble(),
      notes: json['notes'] as String?,
    );
  }
}

// Validates the top-level paginated shape; delegates to MetaModel for the
// meta sub-object so each level logs failures under its own context label.
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
