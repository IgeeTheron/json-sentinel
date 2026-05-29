import 'dart:convert';
import 'dart:developer' as developer;

import 'package:json_sentinel/src/batch_validation_result.dart';
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
/// The fallback logger (used when neither [configure] nor [silence] has been
/// called) writes to `dart:developer` and is suppressed in release builds —
/// always call [configure] or [silence] in production code.
///
/// Pass `verbose: true` to either [configure] or [silence] to enable
/// trace-level `dart:developer` logs: a confirmation on initialisation, a
/// success trace on every passing [validate] call, and a diagnostic when
/// `jsonEncode` fails. Verbose output is orthogonal to [silence].
///
/// ## Quick start
///
/// ```dart
/// // 1. Wire in your logger once at startup:
/// JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
///   myLogger.warn(message, stackTrace: stackTrace, extras: extras, escalate: escalate ?? false);
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
  static bool _verbose = false;

  /// The configured [JsonLogFn], or `null` if neither [configure] nor [silence] has been called.
  static JsonLogFn? get logger => _logger;

  /// Configures the logger used for all validation failures.
  ///
  /// Call once at app startup as an alternative to [silence] — never both.
  /// Asserts in debug mode if called after [configure] or [silence] has already
  /// been called. In release mode the second call is silently ignored — the
  /// first registration wins. Tests should call [resetLoggerForTesting] in
  /// `tearDown` to allow re-configuration across test cases.
  ///
  /// Set [verbose] to `true` to enable trace-level `dart:developer` logs:
  /// a confirmation on initialisation, a success trace on every passing
  /// [validate] call, and a diagnostic when `jsonEncode` fails in the
  /// JSON preview. Verbose output is independent of [silence] — the two
  /// are orthogonal controls.
  static void configure(JsonLogFn logFn, {bool verbose = false}) {
    assert(
      _logger == null,
      'JsonSentinel is already initialised — configure() or silence() has already been called. '
      'Call JsonSentinel.resetLoggerForTesting() in tearDown if overriding in tests.',
    );
    if (_logger != null) return;
    _verbose = verbose;
    _logger = logFn;
    if (_verbose) developer.log('Logger configured.', name: 'JsonSentinel');
  }

  /// Resets the logger and verbose flag to their initial state. For use in tests only.
  static void resetLoggerForTesting() {
    _logger = null;
    _verbose = false;
  }

  /// Suppresses all validation log output.
  ///
  /// Call once at startup as a standalone alternative to [configure] — never
  /// in addition to it. Useful when [validate] is used purely for programmatic
  /// error access via [JsonValidationResult.errors] and no logging is wanted.
  ///
  /// Pass `verbose: true` to enable `dart:developer` trace logs while still
  /// suppressing the [JsonLogFn]. Verbose output is independent of silencing.
  static void silence({bool verbose = false}) => configure((_, {error, stackTrace, extras, escalate}) {}, verbose: verbose);

  /// Validates [json] against [expectedTypes] and returns a [JsonValidationResult].
  ///
  /// All failures are collected before logging — a single log entry is emitted
  /// per call with every problem listed as a bullet. Returns
  /// [JsonValidationResult.success] when all validations pass.
  ///
  /// [expectedTypes] defines the schema. Keys are the JSON field names; values
  /// are lists of allowed types. Including `null` in the list marks the field
  /// nullable. A `null` or empty list checks key existence only.
  ///
  /// [optional] lists keys that are skipped when absent from [json] but still
  /// type-checked when present. Defaults to `{}`.
  ///
  /// When [strict] is `true`, keys present in [json] but absent from
  /// [expectedTypes] are reported as errors. Defaults to `false`.
  ///
  /// [escalate] is forwarded to the logger as a hint that this failure warrants
  /// elevated capture (e.g. a Sentry event rather than a breadcrumb).
  /// Defaults to `false`.
  ///
  /// [context] identifies the model in log output. Defaults to `'UnknownModel'`.
  ///
  /// When verbose logging is enabled via [configure] or [silence], a
  /// `dart:developer` trace is emitted on each passing call.
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
    bool escalate = false,
    String context = 'UnknownModel',
  }) {
    final StackTrace stackTrace = StackTrace.current;
    final List<String> errors = _validateCore(
      json: json,
      expectedTypes: expectedTypes,
      optional: optional,
      strict: strict,
    );

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

    if (_verbose) {
      developer.log(
        '[$context] validate() passed — ${expectedTypes.length} key(s) checked.',
        name: 'JsonSentinel',
      );
    }
    return JsonValidationResult.success;
  }

  /// Validates each item in [jsons] against [expectedTypes] and returns a [BatchValidationResult].
  ///
  /// Runs all validations before emitting a single consolidated log entry, preventing one
  /// log event per failure when processing a list of API payloads.
  ///
  /// Item indices in [BatchValidationResult.failureIndices] and in the log message are
  /// zero-based offsets into [jsons].
  ///
  /// [optional], [strict], and [escalate] behave identically to [validate].
  /// [context] identifies the model in log output.
  ///
  /// No log is emitted when all items pass.
  ///
  /// Example log output when 2 of 5 items fail:
  /// ```
  /// [OrderResponse] JSON batch validation failed (2 of 5 items failed):
  ///   Item 1 (1 error):
  ///     • Missing required key 'id'.
  ///   Item 4 (2 errors):
  ///     • Key 'status' has invalid type. Expected: String; Actual: int.
  ///     • Key 'amount' cannot be null.
  /// ```
  static BatchValidationResult validateBatch({
    required List<Map<String, dynamic>> jsons,
    required Map<String, List<Type?>?> expectedTypes,
    required String context,
    Set<String> optional = const {},
    bool strict = false,
    bool escalate = false,
  }) {
    final StackTrace stackTrace = StackTrace.current;
    final List<JsonValidationResult> results = [];
    for (final Map<String, dynamic> json in jsons) {
      final List<String> errors = _validateCore(
        json: json,
        expectedTypes: expectedTypes,
        optional: optional,
        strict: strict,
      );
      results.add(errors.isEmpty ? JsonValidationResult.success : JsonValidationResult.failure(errors));
    }

    final BatchValidationResult batch = BatchValidationResult.fromResults(results);

    if (batch.failureCount == 0) {
      if (_verbose) {
        developer.log(
          '[$context] validateBatch() passed — ${jsons.length} item(s) checked.',
          name: 'JsonSentinel',
        );
      }
      return batch;
    }

    final String itemsWord = jsons.length == 1 ? 'item' : 'items';
    final StringBuffer buffer = StringBuffer(
      '[$context] JSON batch validation failed (${batch.failureCount} of ${jsons.length} $itemsWord failed):',
    );
    for (final int i in batch.failureIndices) {
      final List<String> errors = results[i].errors;
      final String errWord = errors.length == 1 ? 'error' : 'errors';
      buffer.write('\n  Item $i (${errors.length} $errWord):');
      for (final String e in errors) {
        buffer.write('\n    • $e');
      }
    }

    _log(
      buffer.toString(),
      stackTrace: stackTrace,
      extras: <String, Object?>{
        'context': context,
        'failure_count': batch.failureCount,
        'total_count': jsons.length,
      },
      escalate: escalate,
    );

    return batch;
  }

  /// Runs key-existence and type checks on [json] against [expectedTypes].
  ///
  /// Returns the collected error strings without any logging side-effects.
  static List<String> _validateCore({
    required Map<String, dynamic> json,
    required Map<String, List<Type?>?> expectedTypes,
    Set<String> optional = const {},
    bool strict = false,
  }) {
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

    return errors;
  }

  /// Whether [val] matches [type].
  ///
  /// Supported types: `null` (matches only null values), [bool], [int],
  /// [double], [num], [String], [Map] (any implementation), [List] (any
  /// implementation). Any other [Type] triggers an assert in debug mode and
  /// falls back to `runtimeType` equality in release builds.
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
      final buffer = StringBuffer(message);
      if (extras != null && extras.isNotEmpty) {
        for (final MapEntry<String, Object?> entry in extras.entries) {
          buffer.write('\n  ${entry.key}: ${entry.value}');
        }
      }
      developer.log(buffer.toString(), name: 'JsonSentinel', stackTrace: stackTrace);
    }
  }

  /// Truncated JSON preview (max 600 chars) for structured log extras.
  ///
  /// Falls back to [Map.toString] when [jsonEncode] throws (e.g. [DateTime]).
  /// Emits a `dart:developer` diagnostic on the fallback path when verbose is enabled.
  static String _jsonPreview(Map<String, dynamic> json) {
    const int maxLen = 600;
    String raw;
    try {
      raw = jsonEncode(json);
    } catch (e) {
      if (_verbose) {
        developer.log(
          'json_preview: jsonEncode failed, falling back to toString(). '
          'Check the validated map for non-serialisable values (e.g. DateTime).',
          name: 'JsonSentinel',
          error: e,
        );
      }
      raw = json.toString();
    }
    return raw.length <= maxLen ? raw : '${raw.substring(0, maxLen)}…';
  }
}
