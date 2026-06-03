import 'package:json_sentinel/json_sentinel.dart';
import 'package:test/test.dart';

void main() {
  // region Tests

  // JsonSentinel._logger is global mutable state. Each test group installs a
  // capturing logger in setUp and resets it in tearDown to prevent pollution.

  group('JsonSentinel.validate —', () {
    late List<String> logs;
    late List<Object?> errors;
    late List<StackTrace?> stackTraces;
    late List<Map<String, Object?>?> capturedExtras;
    late List<bool?> escalations;

    setUp(() {
      logs = [];
      errors = [];
      stackTraces = [];
      capturedExtras = [];
      escalations = [];
      JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
        logs.add(message);
        errors.add(error);
        stackTraces.add(stackTrace);
        capturedExtras.add(extras);
        escalations.add(escalate);
      });
    });

    tearDown(() {
      JsonSentinel.resetLoggerForTesting();
    });

    // region Happy paths — isValid true, no log emitted.

    test('should return isValid true when all keys are present with correct types', () {
      // Arrange
      final json = {'id': 1, 'name': 'Alice', 'active': true, 'score': 9.5};

      // Act
      final result = JsonSentinel.validate(
        json: json,
        expectedTypes: {
          'id': [int],
          'name': [String],
          'active': [bool],
          'score': [double],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true when expectedTypes is empty', () {
      // Act
      final result = JsonSentinel.validate(json: {'anything': 123}, expectedTypes: {});

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true when type list is null (key-existence-only check)', () {
      // Act
      final result = JsonSentinel.validate(json: {'key': 42}, expectedTypes: {'key': null});

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true when type list is empty (key-existence-only check)', () {
      // Act
      final result = JsonSentinel.validate(json: {'key': 'value'}, expectedTypes: {'key': []});

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true for nullable field that is null', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'notes': null},
        expectedTypes: {
          'notes': [String, null],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true for nullable field that has a value', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'notes': 'some note'},
        expectedTypes: {
          'notes': [String, null],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true when value matches one of multiple allowed types', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'price': 50},
        expectedTypes: {
          'price': [int, double],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true for Map type', () {
      // Act
      final result = JsonSentinel.validate(
        json: {
          'meta': {'k': 'v'},
        },
        expectedTypes: {
          'meta': [Map],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true for List type', () {
      // Act
      final result = JsonSentinel.validate(
        json: {
          'tags': ['a', 'b'],
        },
        expectedTypes: {
          'tags': [List],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true for num type with int value', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'amount': 10},
        expectedTypes: {
          'amount': [num],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true for num type with double value', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'amount': 10.5},
        expectedTypes: {
          'amount': [num],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    // endregion

    // region One log entry per validate call.

    test('should emit exactly one log entry per failing call regardless of error count', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'a': [int],
          'b': [String],
          'c': [bool],
        },
        context: 'MultiMissing',
      );

      // Assert
      expect(logs.length, 1);
    });

    test('should include context and error count in the log entry', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'a': [int],
          'b': [String],
          'c': [bool],
        },
        context: 'MultiMissing',
      );

      // Assert
      expect(logs.first, contains('[MultiMissing]'));
      expect(logs.first, contains('3 errors'));
    });

    test('should use "1 error" (singular) when exactly one validation fails', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'only': [int],
        },
        context: 'Singular',
      );

      // Assert
      expect(logs.first, contains('1 error)'));
      expect(logs.first, isNot(contains('1 errors')));
    });

    test('should use UnknownModel as default context when none is provided', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'missing': [int],
        },
      );

      // Assert
      expect(logs.first, contains('[UnknownModel]'));
    });

    // endregion

    // region Error bullet list — all failures listed in the single log entry.

    test('should list all missing keys as bullets in one log entry', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'a': [int],
          'b': [String],
          'c': [bool],
        },
        context: 'MultiMissing',
      );

      // Assert
      final log = logs.first;
      expect(log, contains("• Missing required key 'a'."));
      expect(log, contains("• Missing required key 'b'."));
      expect(log, contains("• Missing required key 'c'."));
    });

    test('should list all type mismatches as bullets in one log entry', () {
      // Act
      JsonSentinel.validate(
        json: {'x': 'wrong', 'y': 'wrong'},
        expectedTypes: {
          'x': [int],
          'y': [bool],
        },
        context: 'MultiType',
      );

      // Assert
      final log = logs.first;
      expect(log, contains("• Key 'x' has invalid type."));
      expect(log, contains("• Key 'y' has invalid type."));
    });

    test('should list mixed errors (missing key + type mismatch) together', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 'oops'},
        expectedTypes: {
          'id': [int],
          'name': [String],
        },
        context: 'Mixed',
      );

      // Assert
      final log = logs.first;
      expect(log, contains('invalid type'));
      expect(log, contains("Missing required key 'name'."));
      expect(log, contains('2 errors'));
    });

    // endregion

    // region Message format — JSON preview lives in extras, not the message string.

    test('should not contain JSON preview inline in the message', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 'bad'},
        expectedTypes: {
          'id': [int],
        },
      );

      // Assert
      expect(logs.first, isNot(contains('JSON preview:')));
    });

    // endregion

    // region Missing key.

    test('should return isValid false when a required key is missing', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1},
        expectedTypes: {
          'id': [int],
          'name': [String],
        },
        context: 'UserResponse',
      );

      // Assert
      expect(result.isValid, isFalse);
    });

    test('should include the missing key name in the log entry', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1},
        expectedTypes: {
          'id': [int],
          'name': [String],
        },
        context: 'UserResponse',
      );

      // Assert
      expect(logs.first, contains("Missing required key 'name'."));
    });

    // endregion

    // region Null violations.

    test('should return isValid false when non-nullable field is null', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'name': null},
        expectedTypes: {
          'name': [String],
        },
        context: 'NullCheck',
      );

      // Assert
      expect(result.isValid, isFalse);
    });

    test('should include the null violation key name in the log entry', () {
      // Act
      JsonSentinel.validate(
        json: {'name': null},
        expectedTypes: {
          'name': [String],
        },
        context: 'NullCheck',
      );

      // Assert
      expect(logs.first, contains("Key 'name' cannot be null."));
    });

    // endregion

    // region Type mismatches.

    test('should return isValid false when value has wrong type', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 'not-an-int'},
        expectedTypes: {
          'id': [int],
        },
        context: 'TypeMismatch',
      );

      // Assert
      expect(result.isValid, isFalse);
    });

    test('should include expected and actual type in the log entry when type mismatches', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 'not-an-int'},
        expectedTypes: {
          'id': [int],
        },
        context: 'TypeMismatch',
      );

      // Assert
      final log = logs.first;
      expect(log, contains('[TypeMismatch]'));
      expect(log, contains("'id'"));
      expect(log, contains('Expected:'));
      expect(log, contains('Actual:'));
    });

    test('should return isValid false when value does not match any type in a union', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'count': 'many'},
        expectedTypes: {
          'count': [int, double],
        },
      );

      // Assert
      expect(result.isValid, isFalse);
    });

    // endregion

    // region Stack trace.

    test('should pass a non-null stack trace to the logger on failure', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'key': [int],
        },
        context: 'StackCheck',
      );

      // Assert
      expect(stackTraces.first, isNotNull);
    });

    test('should not invoke the logger on success', () {
      // Act
      JsonSentinel.validate(
        json: {'key': 1},
        expectedTypes: {
          'key': [int],
        },
      );

      // Assert
      expect(stackTraces, isEmpty);
    });

    // endregion

    // region Logger parameters — all five captured correctly.

    test('should pass null for the error parameter on validation failure', () {
      // The error param is reserved for exception-based callers;
      // validate() never populates it. Document this behaviour explicitly.

      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'key': [int],
        },
      );

      // Assert
      expect(errors.first, isNull);
    });

    test('should capture all five JsonLogFn parameters on a single failure', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'key': [int],
        },
        context: 'FullCapture',
        escalate: false,
      );

      // Assert
      expect(logs, hasLength(1));
      expect(logs.first, contains('[FullCapture]'));
      expect(errors.first, isNull);
      expect(stackTraces.first, isNotNull);
      expect(capturedExtras.first, isNotNull);
      expect(capturedExtras.first!['context'], 'FullCapture');
      expect(escalations.first, isFalse);
    });

    // endregion

    // region Escalation — configurable per call.

    test('should pass escalate: false to the logger on failure by default', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'key': [int],
        },
      );

      // Assert
      expect(escalations.first, isFalse);
    });

    test('should pass escalate: false to the logger when explicitly set', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'key': [int],
        },
        escalate: false,
      );

      // Assert
      expect(escalations.first, isFalse);
    });

    test('should pass escalate: true to the logger when explicitly set', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'key': [int],
        },
        escalate: true,
      );

      // Assert
      expect(escalations.first, isTrue);
    });

    test('should not invoke the logger on success', () {
      // Act
      JsonSentinel.validate(
        json: {'key': 1},
        expectedTypes: {
          'key': [int],
        },
      );

      // Assert
      expect(escalations, isEmpty);
    });

    // endregion

    // region Extras — JSON and context passed as structured data, not inline text.

    test('should include a context key in extras on failure', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 'bad'},
        expectedTypes: {
          'id': [int],
        },
        context: 'ProductListing',
      );

      // Assert
      expect(capturedExtras.first, isNotNull);
      expect(capturedExtras.first!['context'], 'ProductListing');
    });

    test('should include a json_preview key in extras on failure', () {
      // Act
      JsonSentinel.validate(
        json: {'name': 'Alice'},
        expectedTypes: {
          'missing': [int],
        },
      );

      // Assert
      expect(capturedExtras.first, isNotNull);
      expect(capturedExtras.first!.containsKey('json_preview'), isTrue);
    });

    test('should encode json_preview with quoted keys (valid JSON format)', () {
      // Act
      JsonSentinel.validate(
        json: {'name': 'Alice'},
        expectedTypes: {
          'missing': [int],
        },
      );

      // Assert — jsonEncode produces {"name":"Alice"}, not {name: Alice}
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview, contains('"name"'));
    });

    test('should truncate json_preview to at most 601 characters when JSON exceeds 600 characters', () {
      // Arrange
      final bigJson = {for (var i = 0; i < 50; i++) 'key_$i': 'a' * 20};

      // Act
      JsonSentinel.validate(
        json: bigJson,
        expectedTypes: {
          'missing_key': [int],
        },
      );

      // Assert
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview, endsWith('…'));
      expect(preview.length, lessThanOrEqualTo(601));
    });

    test('should not truncate json_preview when JSON is under 600 characters', () {
      // Act
      JsonSentinel.validate(
        json: {'x': 1},
        expectedTypes: {
          'missing': [int],
        },
      );

      // Assert
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview, isNot(contains('…')));
    });

    test('should not truncate json_preview when JSON is exactly 600 characters', () {
      // {"a":"<592 x's>"} encodes to exactly 600 characters.
      final exactJson = {'a': 'x' * 592};

      // Act
      JsonSentinel.validate(
        json: exactJson,
        expectedTypes: {
          'missing': [int],
        },
      );

      // Assert — exactly 600 chars must not be truncated.
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview.length, 600);
      expect(preview, isNot(endsWith('…')));
    });

    test('should not invoke the logger on success', () {
      // Act
      JsonSentinel.validate(
        json: {'key': 1},
        expectedTypes: {
          'key': [int],
        },
      );

      // Assert
      expect(capturedExtras, isEmpty);
    });

    // endregion

    // region parentContext — chained path in log message and extras.

    test('should use chained path in log message when parentContext is provided', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'total': [int],
        },
        context: 'MetaModel',
        parentContext: 'UserPage.data[2]',
      );

      // Assert
      expect(logs.first, contains('[UserPage.data[2] > MetaModel]'));
    });

    test('should set extras context to full chained path when parentContext is provided', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'total': [int],
        },
        context: 'MetaModel',
        parentContext: 'UserPage.data[2]',
      );

      // Assert
      expect(capturedExtras.first!['context'], 'UserPage.data[2] > MetaModel');
    });

    test('should use plain context in log message when parentContext is omitted', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'total': [int],
        },
        context: 'MetaModel',
      );

      // Assert
      expect(logs.first, contains('[MetaModel]'));
      expect(logs.first, isNot(contains('>')));
    });

    test('should set extras context to plain context when parentContext is omitted', () {
      // Act
      JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'total': [int],
        },
        context: 'MetaModel',
      );

      // Assert
      expect(capturedExtras.first!['context'], 'MetaModel');
    });

    test('should still include json_preview in extras when parentContext is provided', () {
      // Arrange — json_preview must survive unchanged; only the context key changes.
      final json = <String, dynamic>{'id': 42};

      // Act
      JsonSentinel.validate(
        json: json,
        expectedTypes: {
          'total': [int],
        },
        context: 'MetaModel',
        parentContext: 'UserPage',
      );

      // Assert
      expect(capturedExtras.first!.containsKey('json_preview'), isTrue);
    });

    test('should not invoke the logger on success when parentContext is provided', () {
      // Act
      JsonSentinel.validate(
        json: {'total': 10},
        expectedTypes: {
          'total': [int],
        },
        context: 'MetaModel',
        parentContext: 'UserPage',
      );

      // Assert
      expect(logs, isEmpty);
    });

    // endregion

    // region Logger fallback — when logger is null, print is used (no crash).

    test('should not throw when logger is null and validation fails', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(
        () => JsonSentinel.validate(
          json: {},
          expectedTypes: {
            'key': [int],
          },
        ),
        returnsNormally,
      );
    });

    test('should not throw when logger is null and failure extras are printed', () {
      // validate() always passes a non-null extras map on failure,
      // exercising the extras iteration loop in the print fallback.
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(
        () => JsonSentinel.validate(
          json: {'name': 'Alice'},
          expectedTypes: {
            'missing': [int],
          },
          context: 'FallbackExtras',
        ),
        returnsNormally,
      );
    });

    test('should not throw when logger is null and stack trace is printed', () {
      // validate() always captures StackTrace.current and passes it to _log,
      // exercising the stackTrace print branch in the fallback path.
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(
        () => JsonSentinel.validate(
          json: {},
          expectedTypes: {
            'key': [int],
          },
        ),
        returnsNormally,
      );
    });

    // endregion

    // region configure() / resetLoggerForTesting() / logger getter.

    test('should return null from logger getter before configure() is called', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(JsonSentinel.logger, isNull);
    });

    test('should return non-null from logger getter after configure() is called', () {
      // Act & Assert — configure() was called in setUp
      expect(JsonSentinel.logger, isNotNull);
    });

    test('should return non-null from logger getter after silence() is called', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.silence();

      // Act & Assert — silence() installs a no-op logger, so getter is non-null
      expect(JsonSentinel.logger, isNotNull);
    });

    test('should throw AssertionError when configure() is called twice in debug mode', () {
      // Tests always run with asserts enabled, so a second configure() after
      // the one in setUp must throw AssertionError.

      // Act & Assert
      expect(() => JsonSentinel.configure((msg, {error, stackTrace, extras, escalate}) {}), throwsA(isA<AssertionError>()));
    });

    test('should allow configure() to be called again after resetLoggerForTesting()', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(() => JsonSentinel.configure((msg, {error, stackTrace, extras, escalate}) {}), returnsNormally);
    });

    // endregion

    // region json_preview fallback — non-JSON-encodable values fall back to toString().

    test('should fall back to Map.toString() for json_preview when jsonEncode throws', () {
      // Arrange — DateTime is not JSON-encodable; triggers the catch(_) fallback.
      final nonEncodable = <String, dynamic>{'timestamp': DateTime(2024)};

      // Act
      JsonSentinel.validate(
        json: nonEncodable,
        expectedTypes: {
          'missing': [int],
        },
      );

      // Assert — Map.toString() preserves the key name
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview, contains('timestamp'));
    });

    // endregion

    // region Edge cases in type matching.

    test('should throw AssertionError when an unsupported type is used in debug mode', () {
      // _isTypeOf asserts on unknown types; dart test always runs with asserts enabled.

      // Act & Assert
      expect(
        () => JsonSentinel.validate(
          json: {'field': DateTime(2024)},
          expectedTypes: {
            'field': [DateTime],
          },
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('should return isValid false when type list is [null] only and value is non-null', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'field': 'not-null'},
        expectedTypes: {
          'field': [null],
        },
      );

      // Assert
      expect(result.isValid, isFalse);
    });

    test('should return isValid true when type list is [null] only and value is null', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'field': null},
        expectedTypes: {
          'field': [null],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
    });

    test('should allow null value when null token is at start of type list', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'notes': null},
        expectedTypes: {
          'notes': [null, String],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
    });

    test('should validate non-null value against remaining types when null token is at start of type list', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'notes': 'hello'},
        expectedTypes: {
          'notes': [null, String],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
    });

    // endregion

    // region Optional fields.

    test('should return isValid true when an optional key is absent', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1},
        expectedTypes: {
          'id': [int],
          'nickname': [String],
        },
        optional: {'nickname'},
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid false when an optional key is present with the wrong type', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'nickname': 42},
        expectedTypes: {
          'id': [int],
          'nickname': [String],
        },
        optional: {'nickname'},
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(logs.first, contains("Key 'nickname' has invalid type."));
    });

    test('should return isValid true when an optional key is present with the correct type', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'nickname': 'Igee'},
        expectedTypes: {
          'id': [int],
          'nickname': [String],
        },
        optional: {'nickname'},
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should still require non-optional keys when an optional set is provided', () {
      // Act
      final result = JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'id': [int],
          'nickname': [String],
        },
        optional: {'nickname'},
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(logs.first, contains("Missing required key 'id'."));
      expect(logs.first, isNot(contains("'nickname'")));
    });

    // endregion

    // region Strict mode.

    test('should return isValid true for unexpected keys when strict is false (default)', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'extra': 'surprise'},
        expectedTypes: {
          'id': [int],
        },
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid false when an unexpected key is present and strict is true', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'extra': 'surprise'},
        expectedTypes: {
          'id': [int],
        },
        strict: true,
      );

      // Assert
      expect(result.isValid, isFalse);
    });

    test('should name the unexpected key in the log entry when strict is true', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1, 'extra': 'surprise'},
        expectedTypes: {
          'id': [int],
        },
        strict: true,
      );

      // Assert
      expect(logs.first, contains("Unexpected key 'extra'."));
    });

    test('should return isValid true when json exactly matches expectedTypes in strict mode', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'name': 'Alice'},
        expectedTypes: {
          'id': [int],
          'name': [String],
        },
        strict: true,
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    // endregion

    // region Optional + strict combined.

    test('should not flag an absent optional key as unexpected when strict is true', () {
      // An optional key declared in expectedTypes is not "unexpected" even when
      // absent — strict only flags keys in json that are NOT in expectedTypes.

      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'surprise': 'x'},
        expectedTypes: {
          'id': [int],
          'nickname': [String],
        },
        optional: {'nickname'},
        strict: true,
      );

      // Assert — 'surprise' triggers strict; absent 'nickname' does not.
      expect(result.isValid, isFalse);
      expect(logs.first, contains("Unexpected key 'surprise'."));
      expect(logs.first, isNot(contains("'nickname'")));
    });

    test('should return isValid true when an optional key is present with correct type in strict mode', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'nickname': 'Igee'},
        expectedTypes: {
          'id': [int],
          'nickname': [String],
        },
        optional: {'nickname'},
        strict: true,
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    // endregion

    // region verbose flag — trace-level developer.log, controlled independently of silence().

    test('should not throw when configure() is called with verbose: true', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(
        () => JsonSentinel.configure((_, {error, stackTrace, extras, escalate}) {}, verbose: true),
        returnsNormally,
      );
    });

    test('should not throw when silence() is called with verbose: true', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(() => JsonSentinel.silence(verbose: true), returnsNormally);
    });

    test('should reset verbose state so configure() can be called again after resetLoggerForTesting()', () {
      // Arrange — configure with verbose, then reset
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.configure((_, {error, stackTrace, extras, escalate}) {}, verbose: true);
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert — must not assert after reset
      expect(
        () => JsonSentinel.configure((_, {error, stackTrace, extras, escalate}) {}),
        returnsNormally,
      );
    });

    test('should return isValid true on a passing validate() call when verbose: true', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.configure((_, {error, stackTrace, extras, escalate}) {}, verbose: true);

      // Act
      final result = JsonSentinel.validate(
        json: {'key': 1},
        expectedTypes: {
          'key': [int],
        },
        context: 'VerboseSuccess',
      );

      // Assert — verbose mode must not alter validation result
      expect(result.isValid, isTrue);
    });

    test('should return isValid false on a failing validate() call when verbose: true', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.configure((_, {error, stackTrace, extras, escalate}) {}, verbose: true);

      // Act
      final result = JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'key': [int],
        },
        context: 'VerboseFailure',
      );

      // Assert — verbose mode must not alter validation result
      expect(result.isValid, isFalse);
    });

    test('should return isValid false when silence() is called with verbose: true and validation fails', () {
      // Arrange — silence suppresses the JsonLogFn; verbose only affects developer.log
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.silence(verbose: true);

      // Act
      final result = JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'key': [int],
        },
      );

      // Assert — verbose must not alter the result
      expect(result.isValid, isFalse);
    });

    // endregion

    // region Redaction — sensitive key values masked in json_preview.

    test('should replace a redacted key value with the default placeholder in json_preview', () {
      // Arrange — reset so configure() can be called with redactKeys.
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.configure(
        (message, {error, stackTrace, extras, escalate}) {
          capturedExtras.add(extras);
        },
        redactKeys: {'password'},
      );

      // Act
      JsonSentinel.validate(
        json: {'id': 42, 'password': 'secret123'},
        expectedTypes: {
          'missing': [int],
        },
        context: 'LoginPayload',
      );

      // Assert
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview, contains('"password"'));
      expect(preview, contains('[REDACTED]'));
      expect(preview, isNot(contains('secret123')));
    });

    test('should leave non-redacted key values unchanged in json_preview', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.configure(
        (message, {error, stackTrace, extras, escalate}) {
          capturedExtras.add(extras);
        },
        redactKeys: {'password'},
      );

      // Act
      JsonSentinel.validate(
        json: {'id': 42, 'password': 'secret123'},
        expectedTypes: {
          'missing': [int],
        },
        context: 'LoginPayload',
      );

      // Assert — 'id' is not in redactKeys; its value must appear in full.
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview, contains('42'));
    });

    test('should use a custom redactionPlaceholder when provided', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.configure(
        (message, {error, stackTrace, extras, escalate}) {
          capturedExtras.add(extras);
        },
        redactKeys: {'token'},
        redactionPlaceholder: '***',
      );

      // Act
      JsonSentinel.validate(
        json: {'userId': 1, 'token': 'abc123'},
        expectedTypes: {
          'missing': [int],
        },
        context: 'TokenPayload',
      );

      // Assert
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview, contains('***'));
      expect(preview, isNot(contains('abc123')));
    });

    test('should not redact any values when redactKeys is not configured', () {
      // Act — setUp installs a standard logger with no redactKeys.
      JsonSentinel.validate(
        json: {'id': 1, 'password': 'plain'},
        expectedTypes: {
          'missing': [int],
        },
        context: 'NoRedaction',
      );

      // Assert — 'password' value appears in the preview untouched.
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview, contains('plain'));
    });

    test('should clear redactKeys after resetLoggerForTesting() so subsequent configure() shows plain values', () {
      // Arrange — configure with redactKeys, then reset and reconfigure without.
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.configure(
        (message, {error, stackTrace, extras, escalate}) {},
        redactKeys: {'secret'},
      );
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.configure(
        (message, {error, stackTrace, extras, escalate}) {
          capturedExtras.add(extras);
        },
      );

      // Act
      JsonSentinel.validate(
        json: {'secret': 'value'},
        expectedTypes: {
          'missing': [int],
        },
        context: 'AfterReset',
      );

      // Assert — redactKeys was cleared; 'value' must appear in the preview.
      final preview = capturedExtras.first!['json_preview'] as String;
      expect(preview, contains('value'));
    });

    test('should not throw when silence() is called with redactKeys', () {
      // silence() passes redactKeys through to configure(), but installs a no-op
      // logger — capturedExtras is never populated, so only no-throw can be asserted
      // here. Redaction behaviour is covered by the configure() tests above.
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.silence(redactKeys: {'apiKey'});

      expect(
        () => JsonSentinel.validate(
          json: {'userId': 1, 'apiKey': 'sk-live-abc'},
          expectedTypes: {
            'missing': [int],
          },
          context: 'SilenceRedact',
        ),
        returnsNormally,
      );
    });

    // endregion

    // region silence() — standalone no-op logger.

    test('should return isValid false after silence() is called and validation fails', () {
      // Arrange — reset so silence() can be called as the sole initialisation.
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.silence();

      // Act
      final result = JsonSentinel.validate(
        json: {},
        expectedTypes: {
          'key': [int],
        },
      );

      // Assert
      expect(result.isValid, isFalse);
    });

    test('should not throw when silence() is called and validation fails', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(
        () {
          JsonSentinel.silence();
          JsonSentinel.validate(
            json: {},
            expectedTypes: {
              'key': [int],
            },
          );
        },
        returnsNormally,
      );
    });

    test('should assert when silence() is called after configure() in debug mode', () {
      // configure() was already called in setUp — a second registration must assert.

      // Act & Assert
      expect(() => JsonSentinel.silence(), throwsA(isA<AssertionError>()));
    });

    test('should allow silence() after resetLoggerForTesting()', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(JsonSentinel.silence, returnsNormally);
    });

    // endregion
  });

  // region warnUnexpected — logs warning without failing isValid.

  group('JsonSentinel.validate — warnUnexpected —', () {
    late List<String> logs;
    late List<Map<String, Object?>?> capturedExtras;
    late List<bool?> escalations;

    setUp(() {
      logs = [];
      capturedExtras = [];
      escalations = [];
      JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
        logs.add(message);
        capturedExtras.add(extras);
        escalations.add(escalate);
      });
    });

    tearDown(JsonSentinel.resetLoggerForTesting);

    test('should return isValid true when unexpected key is present and warnUnexpected is true', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'extra': 'surprise'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(result.isValid, isTrue);
    });

    test('should emit one log entry containing "warning" when unexpected key is found', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1, 'extra': 'surprise'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(logs.length, 1);
      expect(logs.first, contains('warning'));
      expect(logs.first, contains('[UserRecord]'));
    });

    test('should include the unexpected key name in the warning message', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1, 'new_api_field': 'v2'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(logs.first, contains("'new_api_field'"));
    });

    test('should list all unexpected keys as bullets in one warning log when multiple are present', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1, 'fieldA': 'x', 'fieldB': 'y'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(logs.length, 1);
      expect(logs.first, contains("'fieldA'"));
      expect(logs.first, contains("'fieldB'"));
    });

    test('should use singular "key" in warning count for one unexpected key', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1, 'extra': 'x'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(logs.first, contains('1 unexpected key'));
      expect(logs.first, isNot(contains('1 unexpected keys')));
    });

    test('should use plural "keys" in warning count for multiple unexpected keys', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1, 'a': 1, 'b': 2},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(logs.first, contains('2 unexpected keys'));
    });

    test('should not emit any log when there are no unexpected keys and warnUnexpected is true', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(logs, isEmpty);
    });

    test('should not emit a warning log when warnUnexpected is false (default) and unexpected key is present', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'extra': 'surprise'},
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should include context key in warning log extras', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1, 'extra': 'x'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(capturedExtras.first, isNotNull);
      expect(capturedExtras.first!['context'], 'UserRecord');
    });

    test('should include json_preview key in warning log extras', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1, 'extra': 'x'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(capturedExtras.first!.containsKey('json_preview'), isTrue);
    });

    test('should always pass escalate false for warning log regardless of call-site escalate value', () {
      // Act
      JsonSentinel.validate(
        json: {'id': 1, 'extra': 'x'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        escalate: true,
        context: 'UserRecord',
      );

      // Assert — warning log always escalate: false; no error log emitted (isValid true)
      expect(logs.length, 1);
      expect(escalations.first, isFalse);
    });

    test('should throw AssertionError when both strict and warnUnexpected are true', () {
      // Act & Assert
      expect(
        () => JsonSentinel.validate(
          json: {'id': 1, 'extra': 'x'},
          expectedTypes: {
            'id': [int],
          },
          strict: true,
          warnUnexpected: true,
          context: 'UserRecord',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('should emit both a warning log and an error log when unexpected keys and schema errors coexist', () {
      // Arrange — unexpected key AND a missing required key
      // Act
      final result = JsonSentinel.validate(
        json: {'extra': 'x'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(logs.length, 2);
      expect(logs.any((String m) => m.contains('warning')), isTrue);
      expect(logs.any((String m) => m.contains('failed')), isTrue);
    });

    test('should not emit a log when warnUnexpected is true and validation fails without unexpected keys', () {
      // Arrange — only a schema error, no unexpected keys
      JsonSentinel.validate(
        json: {'id': 'wrong'},
        expectedTypes: {
          'id': [int],
        },
        warnUnexpected: true,
        context: 'UserRecord',
      );

      // Assert — only the failure log, no warning log
      expect(logs.length, 1);
      expect(logs.first, contains('failed'));
      expect(logs.first, isNot(contains('warning')));
    });

    test('should emit verbose developer.log when unexpected keys are found and verbose is true', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();
      JsonSentinel.configure(
        (message, {error, stackTrace, extras, escalate}) {},
        verbose: true,
      );

      // Act & Assert — should not throw
      expect(
        () => JsonSentinel.validate(
          json: {'id': 1, 'extra': 'x'},
          expectedTypes: {
            'id': [int],
          },
          warnUnexpected: true,
          context: 'UserRecord',
        ),
        returnsNormally,
      );
    });
  });

  // endregion

  // region Per-field validators — value-level checks after type validation.

  group('JsonSentinel.validate — validators —', () {
    late List<String> logs;

    setUp(() {
      logs = [];
      JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
        logs.add(message);
      });
    });

    tearDown(JsonSentinel.resetLoggerForTesting);

    test('should return isValid true when validator passes', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'status': 'active'},
        expectedTypes: {
          'status': [String],
        },
        validators: {'status': (Object? v) => v == 'active'},
        context: 'OrderRecord',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid false and log an error when validator fails', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'status': 'unknown'},
        expectedTypes: {
          'status': [String],
        },
        validators: {
          'status': (Object? v) => ['active', 'inactive', 'pending'].contains(v),
        },
        context: 'OrderRecord',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(logs.length, 1);
      expect(logs.first, contains("Key 'status' failed custom validation."));
    });

    test('should produce a bullet error identifying the key that failed custom validation', () {
      // Act
      JsonSentinel.validate(
        json: {'litres': -5},
        expectedTypes: {
          'litres': [int],
        },
        validators: {'litres': (Object? v) => (v as num) > 0},
        context: 'OrderRecord',
      );

      // Assert
      expect(logs.first, contains("'litres'"));
      expect(logs.first, contains('failed custom validation'));
    });

    test('should skip validator for absent optional key', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1},
        expectedTypes: {
          'id': [int],
          'tag': [String],
        },
        optional: {'tag'},
        validators: {'tag': (Object? v) => false},
        context: 'OrderRecord',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should skip validator when key fails type validation', () {
      // Arrange — type check fails; validator must NOT run (which would double-error)
      var validatorCalled = false;

      // Act
      final result = JsonSentinel.validate(
        json: {'status': 42},
        expectedTypes: {
          'status': [String],
        },
        validators: {
          'status': (Object? v) {
            validatorCalled = true;
            return false;
          },
        },
        context: 'OrderRecord',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(validatorCalled, isFalse);
      expect(logs.first, contains('invalid type'));
      expect(logs.first, isNot(contains('failed custom validation')));
    });

    test('should collect errors from multiple failing validators in one log entry', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'status': 'unknown', 'litres': -1},
        expectedTypes: {
          'status': [String],
          'litres': [int],
        },
        validators: {
          'status': (Object? v) => ['active', 'inactive'].contains(v),
          'litres': (Object? v) => (v as num) > 0,
        },
        context: 'OrderRecord',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(logs.length, 1);
      expect(logs.first, contains("'status'"));
      expect(logs.first, contains("'litres'"));
    });

    test('should behave identically to no validators when validators map is null', () {
      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1},
        expectedTypes: {
          'id': [int],
        },
        validators: null,
        context: 'OrderRecord',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should not call validator for a key that is in the validators map but not in expectedTypes', () {
      // Validators only run for keys iterated from expectedTypes; a validator for a
      // key absent from expectedTypes is silently ignored.
      var validatorCalled = false;

      // Act
      final result = JsonSentinel.validate(
        json: {'id': 1, 'extra': 'value'},
        expectedTypes: {
          'id': [int],
        },
        validators: {
          'extra': (Object? v) {
            validatorCalled = true;
            return false;
          },
        },
        context: 'OrderRecord',
      );

      // Assert — validator was never called, result is valid
      expect(validatorCalled, isFalse);
      expect(result.isValid, isTrue);
    });
  });

  // endregion

  // endregion
}
