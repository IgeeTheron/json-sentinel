import 'package:json_sentinel/json_sentinel.dart';

void main() {
  // Wire in a logger once at startup (replace with your own logging solution).
  JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
    print('[WARN] $message');
    if (extras != null) {
      extras.forEach((k, v) => print('  $k: $v'));
    }
  });

  // Validate an API response map before deserialising it.
  final json = <String, dynamic>{'orderId': 42, 'depotCode': 'CPT01', 'litres': 500, 'notes': null};

  final result = JsonSentinel.validate(
    json: json,
    expectedTypes: {
      'orderId': [int],
      'depotCode': [String],
      'litres': [int, double],
      'notes': [String, null],
    },
    optional: {'notes'},
    context: 'OrderResponse',
  );

  if (result.isValid) {
    print('Validation passed — safe to deserialise.');
  } else {
    print('Validation failed (${result.errors.length} errors):');
    for (final e in result.errors) {
      print('  • $e');
    }
  }

  // Strict mode rejects keys not declared in the schema.
  // escalate: false treats the failure as a breadcrumb rather than a capture.
  final strictJson = <String, dynamic>{'id': 1, 'unexpected': 'surprise'};

  JsonSentinel.validate(
    json: strictJson,
    expectedTypes: {
      'id': [int],
    },
    strict: true,
    escalate: false,
    context: 'StrictExample',
  );
}
