import 'package:json_sentinel/json_sentinel.dart';
import 'package:test/test.dart';

void main() {
  // region Helpers

  late List<String> logs;
  late List<Object?> errors;
  late List<StackTrace?> stackTraces;
  late List<Map<String, Object?>?> capturedExtras;
  late List<bool?> escalations;

  final Map<String, List<Type?>?> schema = {
    'id': [int],
    'name': [String],
  };

  final Map<String, dynamic> validItem = {'id': 1, 'name': 'Alice'};
  final Map<String, dynamic> validItem2 = {'id': 2, 'name': 'Bob'};
  final Map<String, dynamic> missingId = {'name': 'Alice'};
  final Map<String, dynamic> wrongType = {'id': 'bad', 'name': 'Alice'};

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

  tearDown(JsonSentinel.resetLoggerForTesting);

  // endregion

  // region Tests

  group('JsonSentinel.validateBatch — happy paths (no log emitted) —', () {
    test('all items valid: isValid true, no log', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [validItem, validItem2],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('empty list: isValid true, no log, results empty', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(result.results, isEmpty);
      expect(result.failureCount, 0);
      expect(logs, isEmpty);
    });

    test('single item valid: isValid true, no log', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [validItem],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('optional key absent: isValid true, no log', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [
          {'id': 1, 'name': 'Alice'},
          {'id': 2},
        ],
        expectedTypes: {
          'id': [int],
          'name': [String],
        },
        optional: {'name'},
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('strict mode all items exactly match schema: isValid true, no log', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [validItem, validItem2],
        expectedTypes: schema,
        strict: true,
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });
  });

  group('JsonSentinel.validateBatch — results structure —', () {
    test('results length always equals jsons length', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [validItem, missingId, validItem2],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.results.length, 3);
    });

    test('passing items have isValid true in results', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [validItem, missingId, validItem2],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.results[0].isValid, isTrue);
      expect(result.results[2].isValid, isTrue);
    });

    test('failing items have isValid false in results', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [validItem, missingId, validItem2],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.results[1].isValid, isFalse);
    });

    test('failing item errors are populated correctly', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.results[0].errors, contains("Missing required key 'id'."));
    });

    test('1 of 3 failing: failureCount is 1, failureIndices is [1]', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [validItem, missingId, validItem2],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(result.failureCount, 1);
      expect(result.failureIndices, [1]);
    });

    test('all failing: failureCount equals jsons length', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [missingId, wrongType],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(result.failureCount, 2);
    });
  });

  group('JsonSentinel.validateBatch — exactly one log call —', () {
    test('emits exactly one log call regardless of how many items fail', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId, wrongType, missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(logs.length, 1);
    });

    test('emits no log when all items pass', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem, validItem2],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(logs, isEmpty);
    });
  });

  group('JsonSentinel.validateBatch — log message format —', () {
    test('message contains [context] prefix', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'UserRecord',
      );

      // Assert
      expect(logs.first, contains('[UserRecord]'));
    });

    test('message contains "batch validation failed"', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(logs.first, contains('batch validation failed'));
    });

    test('message contains "N of M items failed" with correct counts', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem, missingId, validItem2, wrongType],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(logs.first, contains('2 of 4 items failed'));
    });

    test('message contains Item <i> with zero-based index for each failing item', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem, missingId, validItem2, wrongType],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(logs.first, contains('Item 1'));
      expect(logs.first, contains('Item 3'));
    });

    test('message does not mention passing item indices', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem, missingId, validItem2, wrongType],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert — items 0 and 2 passed; their indices should not appear as "Item 0" or "Item 2"
      expect(logs.first, isNot(contains('Item 0')));
      expect(logs.first, isNot(contains('Item 2')));
    });

    test('message contains error count for each failing item', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(logs.first, contains('1 error'));
    });

    test('message uses plural "errors" for items with multiple errors', () {
      // Arrange — missing both keys
      final Map<String, dynamic> missingBoth = {};

      // Act
      JsonSentinel.validateBatch(
        jsons: [missingBoth],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(logs.first, contains('2 errors'));
    });

    test('message contains bullet for each error in failing items', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(logs.first, contains("• Missing required key 'id'."));
    });

    test('singular: "1 of 1 items" uses "items" (total is the count word)', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(logs.first, contains('1 of 1 item'));
    });

    test('omitting context defaults to UnknownModel in log output', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
      );

      // Assert
      expect(logs.first, contains('[UnknownModel]'));
    });
  });

  group('JsonSentinel.validateBatch — extras map —', () {
    test('extras is non-null on failure', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(capturedExtras.first, isNotNull);
    });

    test('extras[context] equals the provided context string', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'UserRecord',
      );

      // Assert
      expect(capturedExtras.first!['context'], 'UserRecord');
    });

    test('extras[failure_count] equals number of failing items', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem, missingId, wrongType],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(capturedExtras.first!['failure_count'], 2);
    });

    test('extras[total_count] equals jsons.length', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem, missingId, wrongType],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(capturedExtras.first!['total_count'], 3);
    });

    test('extras does not contain json_preview', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(capturedExtras.first!.containsKey('json_preview'), isFalse);
    });

    test('extras contains item_previews on failure', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(capturedExtras.first!.containsKey('item_previews'), isTrue);
    });

    test('item_previews length equals failureCount', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem, missingId, wrongType],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      final previews = capturedExtras.first!['item_previews'] as List<String>;
      expect(previews.length, 2);
    });

    test('item_previews contains JSON content of each failing item', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert — missingId is {'name': 'Alice'}, preview should contain 'name'
      final previews = capturedExtras.first!['item_previews'] as List<String>;
      expect(previews.first, contains('name'));
    });

    test('item_previews is in failureIndices order', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [validItem, missingId, wrongType],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert — failureIndices are [1, 2]; preview[0] should be for missingId, preview[1] for wrongType
      final previews = capturedExtras.first!['item_previews'] as List<String>;
      expect(previews.length, result.failureIndices.length);
      expect(previews[0], contains('Alice')); // missingId has 'name': 'Alice'
      expect(previews[1], contains('bad')); // wrongType has 'id': 'bad'
    });

    test('item_previews is absent when all items pass (no logger call)', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(capturedExtras, isEmpty);
    });

    test('extras[context] equals UnknownModel when context is omitted', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
      );

      // Assert
      expect(capturedExtras.first!['context'], 'UnknownModel');
    });

    test('item_previews is absent when generatePreviews is false', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
        generatePreviews: false,
      );

      // Assert
      expect(capturedExtras.first!.containsKey('item_previews'), isFalse);
    });

    test('other extras keys are still present when generatePreviews is false', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId, wrongType],
        expectedTypes: schema,
        context: 'Model',
        generatePreviews: false,
      );

      // Assert
      expect(capturedExtras.first!['context'], 'Model');
      expect(capturedExtras.first!['failure_count'], 2);
      expect(capturedExtras.first!['total_count'], 2);
    });
  });

  group('JsonSentinel.validateBatch — escalate parameter —', () {
    test('defaults to false', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(escalations.first, isFalse);
    });

    test('explicit false passes false to logger', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
        escalate: false,
      );

      // Assert
      expect(escalations.first, isFalse);
    });

    test('explicit true passes true to logger', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
        escalate: true,
      );

      // Assert
      expect(escalations.first, isTrue);
    });

    test('no escalation call when all items pass', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem],
        expectedTypes: schema,
        context: 'Model',
        escalate: true,
      );

      // Assert
      expect(escalations, isEmpty);
    });
  });

  group('JsonSentinel.validateBatch — stack trace —', () {
    test('stack trace is non-null on failure', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [missingId],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(stackTraces.first, isNotNull);
    });

    test('no stack trace captured when all items pass (logger not invoked)', () {
      // Act
      JsonSentinel.validateBatch(
        jsons: [validItem],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(stackTraces, isEmpty);
    });
  });

  group('JsonSentinel.validateBatch — optional and strict parity —', () {
    test('optional key absent across all items: isValid true', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [
          {'id': 1},
          {'id': 2},
        ],
        expectedTypes: {
          'id': [int],
          'name': [String],
        },
        optional: {'name'},
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('optional key present with wrong type: isValid false', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [
          {'id': 1, 'name': 123},
        ],
        expectedTypes: {
          'id': [int],
          'name': [String],
        },
        optional: {'name'},
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isFalse);
    });

    test('strict mode rejects unexpected keys', () {
      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [
          {'id': 1, 'name': 'Alice', 'extra': true},
        ],
        expectedTypes: schema,
        strict: true,
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(result.results[0].errors, contains("Unexpected key 'extra'."));
    });
  });

  group('JsonSentinel.validateBatch — logger fallback —', () {
    test('does not throw when _logger is null and items fail', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(
        () => JsonSentinel.validateBatch(jsons: [missingId], expectedTypes: schema, context: 'Model'),
        returnsNormally,
      );
    });

    test('does not throw when _logger is null and all items pass', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(
        () => JsonSentinel.validateBatch(jsons: [validItem], expectedTypes: schema, context: 'Model'),
        returnsNormally,
      );
    });
  });

  group('JsonSentinel.validateBatch — verbose —', () {
    setUp(JsonSentinel.resetLoggerForTesting);

    test('success trace does not throw and does not affect isValid', () {
      // Arrange
      JsonSentinel.silence(verbose: true);

      // Act
      final result = JsonSentinel.validateBatch(
        jsons: [validItem, validItem2],
        expectedTypes: schema,
        context: 'Model',
      );

      // Assert
      expect(result.isValid, isTrue);
    });

    test('failure path does not throw with verbose enabled', () {
      // Arrange
      JsonSentinel.silence(verbose: true);

      // Act & Assert
      expect(
        () => JsonSentinel.validateBatch(jsons: [missingId], expectedTypes: schema, context: 'Model'),
        returnsNormally,
      );
    });
  });

  group('JsonSentinel.validateBatch — redaction —', () {
    setUp(JsonSentinel.resetLoggerForTesting);

    test('item_previews should contain the redaction placeholder for a redacted key', () {
      // Arrange
      JsonSentinel.configure(
        (message, {error, stackTrace, extras, escalate}) {
          capturedExtras.add(extras);
        },
        redactKeys: {'password'},
      );

      // Act
      JsonSentinel.validateBatch(
        jsons: [
          {'id': 1, 'password': 'secret'},
        ],
        expectedTypes: {
          'missing': [int],
        },
        context: 'BatchRedact',
      );

      // Assert
      final previews = capturedExtras.first!['item_previews'] as List<String>;
      expect(previews.first, contains('[REDACTED]'));
      expect(previews.first, isNot(contains('secret')));
    });

    test('item_previews should leave non-redacted key values unchanged', () {
      // Arrange
      JsonSentinel.configure(
        (message, {error, stackTrace, extras, escalate}) {
          capturedExtras.add(extras);
        },
        redactKeys: {'password'},
      );

      // Act
      JsonSentinel.validateBatch(
        jsons: [
          {'id': 99, 'password': 'secret'},
        ],
        expectedTypes: {
          'missing': [int],
        },
        context: 'BatchRedact',
      );

      // Assert — 'id' is not in redactKeys; its value must appear in full.
      final previews = capturedExtras.first!['item_previews'] as List<String>;
      expect(previews.first, contains('99'));
    });
  });

  // endregion
}
