// ignore_for_file: avoid_print
import 'package:json_sentinel/json_sentinel.dart';

// ---------------------------------------------------------------------------
// Setup — call once at app startup.
// ---------------------------------------------------------------------------
//
// Configure a real logger before your first validate() call.
// In a Flutter app this would forward to Sentry, Crashlytics, etc.
//
//   JsonSentinel.configure(
//     (message, {error, stackTrace, extras, escalate}) {
//       if (escalate == true) {
//         Sentry.captureMessage(message, hint: Hint.withMap(extras ?? {}));
//       } else {
//         Sentry.addBreadcrumb(Breadcrumb(message: message));
//       }
//     },
//     verbose: true, // emits dart:developer traces in debug mode
//   );
//
// If you only want programmatic access to result.errors and no log output:
//
//   JsonSentinel.silence();   // or silence(verbose: true) for dev traces

void main() {
  JsonSentinel.configure(
    (message, {error, stackTrace, extras, escalate}) {
      print('[${escalate == true ? 'ERROR' : 'WARN'}] $message');
    },
    verbose: true,
  );

  // --- 1. Basic flat response -----------------------------------------------

  final orderJson = <String, dynamic>{
    'orderId': 42,
    'depotCode': 'CPT01',
    'litres': 500.0,
    'notes': null,
  };

  final order = OrderResponse.tryFromJson(orderJson);
  if (order != null) {
    print('Order ${order.orderId} — ${order.litres} L from ${order.depotCode}');
  }

  // --- 2. Nested / paginated response ---------------------------------------

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
  }

  // --- 3. Strict mode -------------------------------------------------------

  // Rejects keys present in the JSON but not declared in the schema.
  JsonSentinel.validate(
    json: <String, dynamic>{'id': 1, 'unexpected': 'surprise'},
    expectedTypes: {
      'id': [int],
    },
    strict: true,
    context: 'StrictExample',
  );
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

// Validate the top-level paginated shape (data/links/meta as List/Map) here.
// Each nested model validates its own fields — failures carry their own context.
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
