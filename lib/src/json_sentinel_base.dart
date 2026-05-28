import 'dart:convert';

import 'package:json_sentinel/src/json_log_fn.dart';
import 'package:json_sentinel/src/json_validation_result.dart';

/// Lightweight runtime JSON key and type validation with a configurable logger.
///
/// Validates a [Map<String, dynamic>] against an expected schema — checking
/// key existence and value types — without code generation. Designed for use
/// in [tryFromJson] methods to catch malformed API responses early.
///
/// All methods are static; this class cannot be instantiated.
///
/// ## Quick start
///
/// ```dart
/// // 1. Wire in your logger once at startup:
/// JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
///   myLogger.warn(message, stackTrace: stackTrace, extras: extras);
/// });
///
/// // 2. Validate in tryFromJson:
/// final result = JsonSentinel.validate(
///   json: responseJson,
///   expectedTypes: {
///     'orderId': [int],
///     'depotCode': [String],
///     'litres': [int, double],
///     'notes': [String, null], // nullable
///   },
///   optional: {'notes'},       // present-or-absent is fine
///   context: 'OrderResponse',
/// );
/// if (!result.isValid) return null;
/// ```
class JsonSentinel {
  JsonSentinel._();

  static JsonLogFn? _logger;

  /// The configured [JsonLogFn], or `null` if [configure] has not been called.
  static JsonLogFn? get logger => _logger;

  /// Configures the logger used for all validation failures.
  ///
  /// Call exactly once at app startup. Asserts in debug mode on a second call.
  /// In release mode a second call is silently ignored — the first registration
  /// wins. Tests should call [resetLoggerForTesting] in `tearDown` to allow
  /// re-configuration across test cases.
  static void configure(JsonLogFn logFn) {
    assert(
      _logger == null,
      'JsonSentinel.configure() has already been called. '
      'Call JsonSentinel.resetLoggerForTesting() in tearDown if overriding in tests.',
    );
    if (_logger != null) return;
    _logger = logFn;
  }

  /// Resets the logger to `null`. For use in tests only.
  static void resetLoggerForTesting() => _logger = null;

  /// Validates [json] against [expectedTypes] and returns a [JsonValidationResult].
  ///
  /// All failures are collected before logging — a single log entry is emitted
  /// per call with every problem listed as a bullet. Returns
  /// [JsonValidationResult.success] when all validations pass.
  ///
  /// **[expectedTypes]** defines the schema:
  /// - Keys are the JSON field names.
  /// - Values are lists of allowed types. Including `null` marks the field
  ///   nullable. A `null` or empty list checks key existence only.
  ///
  /// **[optional]** — keys listed here are skipped when absent from [json],
  /// but still type-checked when present. Defaults to `{}`.
  ///
  /// **[strict]** — when `true`, keys present in [json] but absent from
  /// [expectedTypes] are reported as errors. Defaults to `false`.
  ///
  /// **[escalate]** — forwarded to the logger as a hint that this failure
  /// warrants more than a breadcrumb. Defaults to `true`.
  ///
  /// **[context]** — identifies the model in log output. Defaults to
  /// `'UnknownModel'`.
  ///
  /// Example log output:
  /// ```
  /// [OrderResponse] JSON validation failed (2 errors):
  ///   • Key 'id' has invalid type. Expected: int; Actual: String.
  ///   • Missing required key 'depotCode'.
  /// ```
  static JsonValidationResult validate({
    required Map<String, dynamic> json,
    required Map<String, List<Type?>?> expectedTypes,
    Set<String> optional = const {},
    bool strict = false,
    bool escalate = true,
    String context = 'UnknownModel',
  }) {
    final StackTrace stackTrace = StackTrace.current;
    final List<String> errors = [];

    for (final MapEntry<String, List<Type?>?> entry in expectedTypes.entries) {
      final String key = entry.key;
      final List<Type?>? expectedTypeList = entry.value;

      if (!json.containsKey(key)) {
        if (optional.contains(key)) continue;
        errors.add("Missing required key '$key'.");
        continue;
      }

      if (expectedTypeList == null || expectedTypeList.isEmpty) continue;

      final Object? value = json[key];
      final bool allowsNull = expectedTypeList.contains(null);

      if (!allowsNull && value == null) {
        errors.add("Key '$key' cannot be null.");
        continue;
      }

      final bool matches = expectedTypeList.any((Type? t) => _isTypeOf(value, t));
      if (!matches) {
        errors.add(
          "Key '$key' has invalid type. "
          "Expected: ${expectedTypeList.join(', ')}; "
          "Actual: ${value.runtimeType}.",
        );
      }
    }

    if (strict) {
      for (final String key in json.keys) {
        if (!expectedTypes.containsKey(key)) {
          errors.add("Unexpected key '$key'.");
        }
      }
    }

    if (errors.isNotEmpty) {
      final String count = '${errors.length} error${errors.length == 1 ? '' : 's'}';
      final String bullets = errors.map((e) => '  • $e').join('\n');
      _log(
        '[$context] JSON validation failed ($count):\n$bullets',
        stackTrace: stackTrace,
        extras: <String, Object?>{'context': context, 'json_preview': _jsonPreview(json)},
        escalate: escalate,
      );
      return JsonValidationResult.failure(errors);
    }

    return JsonValidationResult.success;
  }

  /// Whether [val] matches [type].
  ///
  /// - `null` type matches only `null` values.
  /// - [Map] and [List] match any implementation.
  /// - Primitives use `is` checks.
  /// - Unknown types fall back to `runtimeType` equality and trigger an assert
  ///   in debug mode to prompt adding an explicit `is` check.
  static bool _isTypeOf(Object? val, Type? type) {
    if (type == null) return val == null;

    if (type == Map) return val is Map;
    if (type == List) return val is List;

    if (type == String) return val is String;
    if (type == bool) return val is bool;
    if (type == int) return val is int;
    if (type == double) return val is double;
    if (type == num) return val is num;

    assert(
      false,
      'JsonSentinel._isTypeOf: unsupported type "$type" — '
      'add an explicit `is` check in _isTypeOf for this type.',
    );
    return val.runtimeType == type;
  }

  static void _log(String message, {StackTrace? stackTrace, Map<String, Object?>? extras, bool escalate = false}) {
    if (_logger != null) {
      _logger!(message, stackTrace: stackTrace, extras: extras, escalate: escalate);
    } else {
      // ignore: avoid_print
      print(message);
      if (extras != null && extras.isNotEmpty) {
        for (final MapEntry<String, Object?> entry in extras.entries) {
          // ignore: avoid_print
          print('  ${entry.key}: ${entry.value}');
        }
      }
      // ignore: avoid_print
      if (stackTrace != null) print(stackTrace.toString());
    }
  }

  /// Truncated JSON preview (max 600 chars) for structured log extras.
  ///
  /// Falls back to [Map.toString] when [jsonEncode] throws (e.g. [DateTime]).
  static String _jsonPreview(Map<String, dynamic> json) {
    const int maxLen = 600;
    String raw;
    try {
      raw = jsonEncode(json);
    } catch (_) {
      raw = json.toString();
    }
    return raw.length <= maxLen ? raw : '${raw.substring(0, maxLen)}…';
  }
}
