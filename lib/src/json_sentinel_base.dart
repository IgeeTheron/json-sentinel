import 'dart:convert';
import 'dart:developer' as developer;

import 'package:json_sentinel/src/batch_validation_result.dart';
import 'package:json_sentinel/src/json_log_fn.dart';
import 'package:json_sentinel/src/json_validation_result.dart';

/// Lightweight runtime JSON key and type validation with a configurable logger.
///
/// Validates a [Map<String, dynamic>] against an expected schema — checking
/// key existence and value types — without code generation. Designed for use
/// in `tryFromJson` methods to catch malformed API responses early.
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
///     'productId': [int],
///     'sku':       [String],
///     'price':     [int, double],
///     'description': [String, null], // nullable
///   },
///   optional: {'description'}, // present-or-absent is fine
///   context: 'ProductListing',
/// );
/// if (!result.isValid) return null;
/// ```
class JsonSentinel {
  JsonSentinel._();

  static JsonLogFn? _logger;
  static bool _verbose = false;
  static Set<String>? _redactKeys;
  static String _redactionPlaceholder = '[REDACTED]';

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
  ///
  /// Pass [redactKeys] to mask sensitive top-level field values in `json_preview`
  /// and `item_previews` extras before they are forwarded to the logger. Any key
  /// present in [redactKeys] has its value replaced with [redactionPlaceholder]
  /// (defaults to `'[REDACTED]'`) in the preview string — the validated data
  /// itself is never modified. Keys absent from [redactKeys] appear in previews
  /// unchanged.
  static void configure(
    JsonLogFn logFn, {
    bool verbose = false,
    Set<String>? redactKeys,
    String redactionPlaceholder = '[REDACTED]',
  }) {
    assert(
      _logger == null,
      'JsonSentinel is already initialised — configure() or silence() has already been called. '
      'Call JsonSentinel.resetLoggerForTesting() in tearDown if overriding in tests.',
    );
    if (_logger != null) return;
    _verbose = verbose;
    _logger = logFn;
    _redactKeys = redactKeys;
    _redactionPlaceholder = redactionPlaceholder;
    if (_verbose) developer.log('Logger configured.', name: 'JsonSentinel');
  }

  /// Resets the logger, verbose flag, and redaction state to their initial values.
  ///
  /// Clears the registered [JsonLogFn], resets `verbose` to `false`, and clears
  /// any `redactKeys` and `redactionPlaceholder` settings applied by a prior
  /// [configure] or [silence] call. For use in tests only — call in `tearDown`
  /// to allow re-configuration across test cases.
  static void resetLoggerForTesting() {
    _logger = null;
    _verbose = false;
    _redactKeys = null;
    _redactionPlaceholder = '[REDACTED]';
  }

  /// Suppresses all validation log output.
  ///
  /// Call once at startup as a standalone alternative to [configure] — never
  /// in addition to it. Useful when [validate] is used purely for programmatic
  /// error access via [JsonValidationResult.errors] and no logging is wanted.
  ///
  /// Pass `verbose: true` to enable `dart:developer` trace logs while still
  /// suppressing the [JsonLogFn]. Verbose output is independent of silencing.
  ///
  /// [redactKeys] and [redactionPlaceholder] behave identically to the
  /// same-named parameters on [configure] and are passed through unchanged.
  static void silence({
    bool verbose = false,
    Set<String>? redactKeys,
    String redactionPlaceholder = '[REDACTED]',
  }) =>
      configure(
        (String _, {Object? error, StackTrace? stackTrace, Map<String, Object?>? extras, bool? escalate}) {},
        verbose: verbose,
        redactKeys: redactKeys,
        redactionPlaceholder: redactionPlaceholder,
      );

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
  /// Mutually exclusive with [warnUnexpected].
  ///
  /// When [warnUnexpected] is `true`, keys present in [json] but absent from
  /// [expectedTypes] are logged as warnings without failing validation —
  /// [JsonValidationResult.isValid] remains `true`. Mutually exclusive with
  /// [strict]; asserted in debug mode.
  ///
  /// [validators] is an optional map of per-key predicate functions run after
  /// type validation passes for that key. Each predicate receives the field value
  /// as `Object?` and must return `false` to fail. A failing predicate adds a
  /// bullet error for the key. Predicates are skipped for absent optional keys
  /// and for keys that already failed type validation.
  ///
  /// [escalate] is forwarded to the logger as a hint that this failure warrants
  /// elevated capture (e.g. a Sentry event rather than a breadcrumb).
  /// Defaults to `false`. Warning logs always use `escalate: false`.
  ///
  /// [context] identifies the model in log output. Defaults to `'UnknownModel'`.
  ///
  /// [parentContext] is an optional parent path prepended to [context] in log
  /// output and in the logger's `extras` map. When provided, the effective context
  /// becomes `'$parentContext > $context'` — useful when chaining [validate] calls
  /// across nested models to show the full path to the failing item
  /// (e.g. `UserPage.data[2] > MetaModel`).
  ///
  /// When verbose logging is enabled via [configure] or [silence], a
  /// `dart:developer` trace is emitted on each passing call.
  ///
  /// Example log output:
  /// ```text
  /// [ProductListing] JSON validation failed (2 errors):
  ///   • Key 'productId' has invalid type. Expected: int; Actual: String.
  ///   • Missing required key 'sku'.
  /// ```
  static JsonValidationResult validate({
    required Map<String, dynamic> json,
    required Map<String, List<Type?>?> expectedTypes,
    Set<String> optional = const <String>{},
    bool strict = false,
    bool warnUnexpected = false,
    bool escalate = false,
    String context = 'UnknownModel',
    String? parentContext,
    Map<String, bool Function(Object?)>? validators,
  }) {
    final StackTrace stackTrace = StackTrace.current;
    assert(
      !(strict && warnUnexpected),
      'JsonSentinel.validate: strict and warnUnexpected are mutually exclusive — '
      'use strict to fail on unexpected keys, or warnUnexpected to log without failing, not both.',
    );
    final String effectiveContext = parentContext != null ? '$parentContext > $context' : context;
    final ({List<String> errors, List<String> warnings}) core = _validateCore(
      json: json,
      expectedTypes: expectedTypes,
      optional: optional,
      strict: strict,
      warnUnexpected: warnUnexpected,
      validators: validators,
    );

    if (core.warnings.isNotEmpty) {
      final String warnCount = '${core.warnings.length} unexpected key${core.warnings.length == 1 ? '' : 's'}';
      final String warnBullets = core.warnings.map((String w) => '  • $w').join('\n');
      _log(
        '[$effectiveContext] JSON validation warning ($warnCount):\n$warnBullets',
        stackTrace: stackTrace,
        extras: <String, Object?>{'context': effectiveContext, 'json_preview': _jsonPreview(json)},
        escalate: false,
      );
      if (_verbose) {
        developer.log(
          '[$effectiveContext] validate() warned — ${core.warnings.length} unexpected key(s).',
          name: 'JsonSentinel',
        );
      }
    }

    if (core.errors.isNotEmpty) {
      final String count = '${core.errors.length} error${core.errors.length == 1 ? '' : 's'}';
      final String bullets = core.errors.map((String e) => '  • $e').join('\n');
      _log(
        '[$effectiveContext] JSON validation failed ($count):\n$bullets',
        stackTrace: stackTrace,
        extras: <String, Object?>{'context': effectiveContext, 'json_preview': _jsonPreview(json)},
        escalate: escalate,
      );
      if (_verbose) {
        developer.log(
          '[$effectiveContext] validate() failed — ${core.errors.length} error(s).',
          name: 'JsonSentinel',
        );
      }
      return JsonValidationResult.failure(core.errors);
    }

    if (_verbose && core.warnings.isEmpty) {
      developer.log(
        '[$effectiveContext] validate() passed — ${expectedTypes.length} key(s) checked.',
        name: 'JsonSentinel',
      );
    }
    return JsonValidationResult.success;
  }

  /// Validates each item in [jsons] against [expectedTypes] and returns a [BatchValidationResult].
  ///
  /// Runs all validations before emitting a single consolidated log entry, preventing one
  /// log event per failure when processing a list of API payloads. No log is emitted when
  /// all items pass, including the vacuously-valid case of an empty [jsons] list (which
  /// returns `isValid: true` with `failureCount: 0` immediately).
  ///
  /// Item indices in [BatchValidationResult.failureIndices] and in the log message are
  /// zero-based offsets into [jsons].
  ///
  /// [optional], [strict], [warnUnexpected], [validators], and [escalate] behave
  /// identically to [validate]. [context] identifies the model in log output.
  /// Defaults to `'UnknownModel'`.
  ///
  /// When [warnUnexpected] is `true`, a consolidated warning log is emitted after
  /// validation listing every item that contained unexpected keys. This is separate
  /// from the error log and does not affect [BatchValidationResult.isValid].
  ///
  /// When [generatePreviews] is `true` (the default), the logger receives an
  /// `'item_previews'` key in [extras] containing a truncated JSON string for each
  /// failing item — equivalent to the `'json_preview'` that [validate] attaches for
  /// single-item calls. Set [generatePreviews] to `false` to skip JSON serialisation
  /// for all failing items; useful for large high-failure batches where preview
  /// generation would be costly.
  ///
  /// On failure the logger receives an [extras] map containing:
  /// - `'context'` — the model name.
  /// - `'failure_count'` — number of failing items (int).
  /// - `'total_count'` — total items in the batch (int).
  /// - `'item_previews'` — truncated JSON strings for each failing item, in
  ///   `failureIndices` order (`List<String>`). Absent when [generatePreviews] is `false`.
  ///
  /// Example log output when 2 of 5 items fail:
  /// ```text
  /// [UserRecord] JSON batch validation failed (2 of 5 items failed):
  ///   Item 1 (1 error):
  ///     • Missing required key 'name'.
  ///   Item 4 (2 errors):
  ///     • Key 'role' has invalid type. Expected: String; Actual: int.
  ///     • Key 'active' cannot be null.
  /// ```
  static BatchValidationResult validateBatch({
    required List<Map<String, dynamic>> jsons,
    required Map<String, List<Type?>?> expectedTypes,
    String context = 'UnknownModel',
    Set<String> optional = const <String>{},
    bool strict = false,
    bool warnUnexpected = false,
    bool escalate = false,
    bool generatePreviews = true,
    Map<String, bool Function(Object?)>? validators,
  }) {
    final StackTrace stackTrace = StackTrace.current;
    assert(
      !(strict && warnUnexpected),
      'JsonSentinel.validateBatch: strict and warnUnexpected are mutually exclusive — '
      'use strict to fail on unexpected keys, or warnUnexpected to log without failing, not both.',
    );
    final List<JsonValidationResult> results = <JsonValidationResult>[];
    final List<List<String>> itemWarnings = <List<String>>[];
    for (final Map<String, dynamic> json in jsons) {
      final ({List<String> errors, List<String> warnings}) core = _validateCore(
        json: json,
        expectedTypes: expectedTypes,
        optional: optional,
        strict: strict,
        warnUnexpected: warnUnexpected,
        validators: validators,
      );
      itemWarnings.add(core.warnings);
      results.add(core.errors.isEmpty ? JsonValidationResult.success : JsonValidationResult.failure(core.errors));
    }

    final BatchValidationResult batch = BatchValidationResult.fromResults(results);

    if (batch.failureCount == 0) {
      if (_verbose) {
        developer.log(
          '[$context] validateBatch() passed — ${jsons.length} item(s) checked.',
          name: 'JsonSentinel',
        );
      }
    } else {
      final String itemsWord = jsons.length == 1 ? 'item' : 'items';
      final StringBuffer buffer = StringBuffer(
        '[$context] JSON batch validation failed (${batch.failureCount} of ${jsons.length} $itemsWord failed):',
      );
      for (final int i in batch.failureIndices) {
        final List<String> errors = results[i].errors;
        if (errors.isEmpty) continue;
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
          if (generatePreviews)
            'item_previews': <String>[
              for (final int i in batch.failureIndices) _jsonPreview(jsons[i]),
            ],
        },
        escalate: escalate,
      );

      if (_verbose) {
        developer.log(
          '[$context] validateBatch() failed — ${batch.failureCount} of ${jsons.length} item(s) invalid.',
          name: 'JsonSentinel',
        );
      }
    }

    final List<int> warningIndices = <int>[
      for (int i = 0; i < itemWarnings.length; i++)
        if (itemWarnings[i].isNotEmpty) i,
    ];
    if (warningIndices.isNotEmpty) {
      final String itemsWord = jsons.length == 1 ? 'item' : 'items';
      final StringBuffer wb = StringBuffer(
        '[$context] JSON batch validation warning (${warningIndices.length} of ${jsons.length} $itemsWord had unexpected keys):',
      );
      for (final int i in warningIndices) {
        final List<String> ws = itemWarnings[i];
        final String keyWord = ws.length == 1 ? 'key' : 'keys';
        wb.write('\n  Item $i (${ws.length} unexpected $keyWord):');
        for (final String w in ws) {
          wb.write('\n    • $w');
        }
      }
      _log(wb.toString(), stackTrace: stackTrace, extras: <String, Object?>{'context': context}, escalate: false);
      if (_verbose) {
        developer.log(
          '[$context] validateBatch() warned — ${warningIndices.length} of ${jsons.length} item(s) had unexpected keys.',
          name: 'JsonSentinel',
        );
      }
    }

    return batch;
  }

  /// Validates each element in [raw] against [expectedTypes], treating non-`Map` items as failures.
  ///
  /// Accepts a `List<dynamic>` as returned directly by [jsonDecode], without
  /// requiring manual casting or filtering before calling [validateBatch].
  /// Non-`Map<String, dynamic>` items at index N produce a [JsonValidationResult.failure]
  /// with the message `"Item N is not a Map<String, dynamic>."` and are counted in
  /// [BatchValidationResult.failureCount] and [BatchValidationResult.failureIndices].
  /// `Map` items are validated against [expectedTypes] identically to [validateBatch].
  ///
  /// Use [BatchValidationResult.failureIndices] to skip invalid items when mapping
  /// [raw] to model instances:
  ///
  /// ```dart
  /// // Full-or-nothing: return null if any item fails.
  /// static List<UserModel>? tryFromListJson(List<dynamic> raw) {
  ///   final BatchValidationResult batch = JsonSentinel.validateList(
  ///     raw: raw,
  ///     expectedTypes: {'id': [int], 'name': [String]},
  ///     context: 'UserModel',
  ///   );
  ///   if (!batch.isValid) return null;
  ///   return [for (final Object? item in raw) if (item is Map<String, dynamic>) UserModel.fromJson(item)];
  /// }
  ///
  /// // Skip-bad-items: return only the valid ones.
  /// static List<UserModel> fromValidListJson(List<dynamic> raw) {
  ///   final BatchValidationResult batch = JsonSentinel.validateList(
  ///     raw: raw,
  ///     expectedTypes: {'id': [int], 'name': [String]},
  ///     context: 'UserModel',
  ///   );
  ///   return [
  ///     for (int i = 0; i < raw.length; i++)
  ///       if (!batch.failureIndices.contains(i) && raw[i] is Map<String, dynamic>)
  ///         UserModel.fromJson(raw[i] as Map<String, dynamic>),
  ///   ];
  /// }
  /// ```
  ///
  /// [optional], [strict], [warnUnexpected], [validators], [escalate], and
  /// [generatePreviews] behave identically to [validateBatch].
  ///
  /// When [generatePreviews] is `true`, `item_previews` in the logger [extras]
  /// contains a JSON preview for Map items and the literal string `'[non-Map item]'`
  /// for non-Map items.
  static BatchValidationResult validateList({
    required List<dynamic> raw,
    required Map<String, List<Type?>?> expectedTypes,
    String context = 'UnknownModel',
    Set<String> optional = const <String>{},
    bool strict = false,
    bool warnUnexpected = false,
    bool escalate = false,
    bool generatePreviews = true,
    Map<String, bool Function(Object?)>? validators,
  }) {
    final StackTrace stackTrace = StackTrace.current;
    assert(
      !(strict && warnUnexpected),
      'JsonSentinel.validateList: strict and warnUnexpected are mutually exclusive — '
      'use strict to fail on unexpected keys, or warnUnexpected to log without failing, not both.',
    );
    final List<JsonValidationResult> results = <JsonValidationResult>[];
    final List<List<String>> itemWarnings = <List<String>>[];
    for (int i = 0; i < raw.length; i++) {
      final Object? item = raw[i];
      if (item is Map<String, dynamic>) {
        final ({List<String> errors, List<String> warnings}) core = _validateCore(
          json: item,
          expectedTypes: expectedTypes,
          optional: optional,
          strict: strict,
          warnUnexpected: warnUnexpected,
          validators: validators,
        );
        itemWarnings.add(core.warnings);
        results.add(core.errors.isEmpty ? JsonValidationResult.success : JsonValidationResult.failure(core.errors));
      } else {
        itemWarnings.add(<String>[]);
        results.add(JsonValidationResult.failure(<String>['Item $i is not a Map<String, dynamic>.']));
      }
    }

    final BatchValidationResult batch = BatchValidationResult.fromResults(results);

    if (batch.failureCount == 0) {
      if (_verbose) {
        developer.log(
          '[$context] validateList() passed — ${raw.length} item(s) checked.',
          name: 'JsonSentinel',
        );
      }
    } else {
      final String itemsWord = raw.length == 1 ? 'item' : 'items';
      final StringBuffer buffer = StringBuffer(
        '[$context] JSON list validation failed (${batch.failureCount} of ${raw.length} $itemsWord failed):',
      );
      for (final int i in batch.failureIndices) {
        final List<String> errors = results[i].errors;
        if (errors.isEmpty) continue;
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
          'total_count': raw.length,
          if (generatePreviews)
            'item_previews': <String>[
              for (final int i in batch.failureIndices)
                if (raw[i] is Map<String, dynamic>) _jsonPreview(raw[i] as Map<String, dynamic>) else '[non-Map item]',
            ],
        },
        escalate: escalate,
      );

      if (_verbose) {
        developer.log(
          '[$context] validateList() failed — ${batch.failureCount} of ${raw.length} item(s) invalid.',
          name: 'JsonSentinel',
        );
      }
    }

    final List<int> warningIndices = <int>[
      for (int i = 0; i < itemWarnings.length; i++)
        if (itemWarnings[i].isNotEmpty) i,
    ];
    if (warningIndices.isNotEmpty) {
      final String itemsWord = raw.length == 1 ? 'item' : 'items';
      final StringBuffer wb = StringBuffer(
        '[$context] JSON list validation warning (${warningIndices.length} of ${raw.length} $itemsWord had unexpected keys):',
      );
      for (final int i in warningIndices) {
        final List<String> ws = itemWarnings[i];
        final String keyWord = ws.length == 1 ? 'key' : 'keys';
        wb.write('\n  Item $i (${ws.length} unexpected $keyWord):');
        for (final String w in ws) {
          wb.write('\n    • $w');
        }
      }
      _log(wb.toString(), stackTrace: stackTrace, extras: <String, Object?>{'context': context}, escalate: false);
      if (_verbose) {
        developer.log(
          '[$context] validateList() warned — ${warningIndices.length} of ${raw.length} item(s) had unexpected keys.',
          name: 'JsonSentinel',
        );
      }
    }

    return batch;
  }

  /// Runs key-existence, type, and custom-validator checks on [json] against [expectedTypes].
  ///
  /// Returns collected errors and warnings without any logging side-effects.
  /// When [warnUnexpected] is `true`, unexpected keys are added to [warnings] rather than
  /// [errors], leaving [errors] empty for those keys. [validators] predicates are run only
  /// after the key passes type validation.
  static ({List<String> errors, List<String> warnings}) _validateCore({
    required Map<String, dynamic> json,
    required Map<String, List<Type?>?> expectedTypes,
    Set<String> optional = const <String>{},
    bool strict = false,
    bool warnUnexpected = false,
    Map<String, bool Function(Object?)>? validators,
  }) {
    final List<String> errors = <String>[];
    final List<String> warnings = <String>[];

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
        continue;
      }

      if (validators != null) {
        final bool Function(Object?)? fn = validators[key];
        if (fn != null && !fn(value)) {
          errors.add("Key '$key' failed custom validation.");
        }
      }
    }

    if (strict) {
      for (final String key in json.keys) {
        if (!expectedTypes.containsKey(key)) {
          errors.add("Unexpected key '$key'.");
        }
      }
    } else if (warnUnexpected) {
      for (final String key in json.keys) {
        if (!expectedTypes.containsKey(key)) {
          warnings.add("Unexpected key '$key'.");
        }
      }
    }

    return (errors: errors, warnings: warnings);
  }

  /// Whether [val] matches [type].
  ///
  /// Supported types: `null` (matches only null values), [bool], [int],
  /// [double], [num], [String], [Map] (any implementation), [List] (any
  /// implementation). Any other [Type] triggers an assert in debug mode and
  /// falls back to `runtimeType` equality in release builds.
  static bool _isTypeOf(Object? val, Type? type) {
    if (type == null) return val == null;

    if (type == Map<dynamic, dynamic>) return val is Map<dynamic, dynamic>;
    if (type == List<dynamic>) return val is List<dynamic>;

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
      final StringBuffer buffer = StringBuffer(message);
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
  /// If `redactKeys` was supplied to [configure] or [silence], values for any
  /// matching top-level key are replaced with the configured `redactionPlaceholder`
  /// before encoding — the original [json] map is not modified.
  ///
  /// Falls back to `json.toString()` when [jsonEncode] throws (e.g. [DateTime]).
  /// Emits a `dart:developer` diagnostic on the fallback path when verbose is enabled.
  static String _jsonPreview(Map<String, dynamic> json) {
    const int maxLen = 600;
    final Map<String, dynamic> source = _redactKeys != null && _redactKeys!.isNotEmpty
        ? <String, dynamic>{
            for (final MapEntry<String, dynamic> entry in json.entries)
              entry.key: _redactKeys!.contains(entry.key) ? _redactionPlaceholder : entry.value,
          }
        : json;
    String raw;
    try {
      raw = jsonEncode(source);
    } catch (e) {
      if (_verbose) {
        developer.log(
          'json_preview: jsonEncode failed, falling back to toString(). '
          'Check the validated map for non-serialisable values (e.g. DateTime).',
          name: 'JsonSentinel',
          error: e,
        );
      }
      raw = source.toString();
    }
    return raw.length <= maxLen ? raw : '${raw.substring(0, maxLen)}…';
  }
}
