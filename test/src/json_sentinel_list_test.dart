import 'package:json_sentinel/json_sentinel.dart';
import 'package:test/test.dart';

void main() {
  // region Tests

  group('JsonSentinel.validateList —', () {
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

    tearDown(JsonSentinel.resetLoggerForTesting);

    // region Happy paths.

    test('should return isValid true when all items are valid Maps', () {
      // Act
      final result = JsonSentinel.validateList(
        raw: [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ],
        expectedTypes: {
          'id': [int],
          'name': [String],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(logs, isEmpty);
    });

    test('should return isValid true for an empty raw list', () {
      // Act
      final result = JsonSentinel.validateList(
        raw: [],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.isValid, isTrue);
      expect(result.failureCount, 0);
      expect(logs, isEmpty);
    });

    test('should return results length equal to raw list length', () {
      // Act
      final result = JsonSentinel.validateList(
        raw: [
          {'id': 1},
          {'id': 2},
          {'id': 3},
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.results.length, 3);
    });

    // endregion

    // region Non-Map items — failure with descriptive error.

    test('should return isValid false when raw list contains a non-Map item', () {
      // Act
      final result = JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(result.failureCount, 1);
    });

    test('should include item index in the non-Map failure error message', () {
      // Act
      final result = JsonSentinel.validateList(
        raw: [42],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.results.first.errors.first, contains('Item 0'));
      expect(result.results.first.errors.first, contains('not a Map<String, dynamic>'));
    });

    test('should produce failure for null item in raw list', () {
      // Act
      final result = JsonSentinel.validateList(
        raw: [null],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(result.failureIndices, [0]);
    });

    test('should produce failure for integer item in raw list', () {
      // Act
      final result = JsonSentinel.validateList(
        raw: [1, 2, 3],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.isValid, isFalse);
      expect(result.failureCount, 3);
      expect(result.failureIndices, [0, 1, 2]);
    });

    // endregion

    // region Mixed Map and non-Map items.

    test('should count only non-Map and schema-failing items in failureIndices', () {
      // Act
      final result = JsonSentinel.validateList(
        raw: [
          {'id': 1},
          'oops',
          {'id': 3},
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.failureIndices, [1]);
      expect(result.failureCount, 1);
    });

    test('should include both non-Map failures and schema failures in failureIndices', () {
      // Act
      final result = JsonSentinel.validateList(
        raw: [
          {'id': 1},
          'not-a-map',
          {'id': 'wrong-type'},
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(result.failureIndices, [1, 2]);
    });

    test('should support tryFromListJson pattern using failureIndices to skip bad items', () {
      // Arrange
      final List<dynamic> raw = [
        {'id': 1},
        'not-a-map',
        {'id': 3},
      ];

      // Act
      final result = JsonSentinel.validateList(
        raw: raw,
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Simulate fromValidListJson: build only from non-failing, Map items
      final List<Map<String, dynamic>> valid = [
        for (int i = 0; i < raw.length; i++)
          if (!result.failureIndices.contains(i) && raw[i] is Map<String, dynamic>) raw[i] as Map<String, dynamic>,
      ];

      // Assert
      expect(valid.length, 2);
      expect(valid.first['id'], 1);
      expect(valid.last['id'], 3);
    });

    // endregion

    // region Error log format — mirrors validateBatch.

    test('should use UnknownModel as default context when none is provided', () {
      // Act
      JsonSentinel.validateList(
        raw: [
          {'id': 'wrong'},
        ],
        expectedTypes: {
          'id': [int],
        },
      );

      // Assert
      expect(logs.first, contains('UnknownModel'));
    });

    test('should emit exactly one log entry on failure', () {
      // Act
      JsonSentinel.validateList(
        raw: [
          {'id': 'wrong'},
          'not-a-map',
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(logs.length, 1);
    });

    test('should include [context] prefix in log message', () {
      // Act
      JsonSentinel.validateList(
        raw: [
          {'id': 'wrong'},
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(logs.first, startsWith('[UserRecord]'));
    });

    test('should include "list validation failed" in log message', () {
      // Act
      JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(logs.first, contains('list validation failed'));
    });

    test('should include "N of M items failed" counts in log message', () {
      // Act
      JsonSentinel.validateList(
        raw: [
          {'id': 1},
          'oops',
          {'id': 3},
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(logs.first, contains('1 of 3'));
    });

    test('should include context key in extras on failure', () {
      // Act
      JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(capturedExtras.first!['context'], 'UserRecord');
    });

    test('should include failure_count and total_count in extras', () {
      // Act
      JsonSentinel.validateList(
        raw: [
          {'id': 1},
          'oops',
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(capturedExtras.first!['failure_count'], 1);
      expect(capturedExtras.first!['total_count'], 2);
    });

    test('should pass null for the error parameter to the logger', () {
      // Act
      JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(errors.first, isNull);
    });

    test('should pass a non-null stack trace to the logger on failure', () {
      // Act
      JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(stackTraces.first, isNotNull);
    });

    // endregion

    // region item_previews for non-Map items.

    test('should include item_previews in extras by default', () {
      // Act
      JsonSentinel.validateList(
        raw: [
          {'id': 'wrong'},
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(capturedExtras.first!.containsKey('item_previews'), isTrue);
    });

    test('should use "[non-Map item]" as preview for non-Map failures', () {
      // Act
      JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      final previews = capturedExtras.first!['item_previews'] as List<String>;
      expect(previews.first, '[non-Map item]');
    });

    test('should use JSON preview string for Map item failures', () {
      // Act
      JsonSentinel.validateList(
        raw: [
          {'id': 'wrong'},
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      final previews = capturedExtras.first!['item_previews'] as List<String>;
      expect(previews.first, contains('"id"'));
    });

    test('should mix JSON preview and "[non-Map item]" when both types fail', () {
      // Act
      JsonSentinel.validateList(
        raw: [
          {'id': 'wrong'},
          42,
        ],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      final previews = capturedExtras.first!['item_previews'] as List<String>;
      expect(previews.length, 2);
      expect(previews[0], contains('"id"'));
      expect(previews[1], '[non-Map item]');
    });

    // endregion

    // region generatePreviews: false.

    test('should omit item_previews when generatePreviews is false', () {
      // Act
      JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
        generatePreviews: false,
      );

      // Assert
      expect(capturedExtras.first!.containsKey('item_previews'), isFalse);
    });

    test('should still include failure_count and total_count when generatePreviews is false', () {
      // Act
      JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
        generatePreviews: false,
      );

      // Assert
      expect(capturedExtras.first!['failure_count'], 1);
      expect(capturedExtras.first!['total_count'], 1);
    });

    // endregion

    // region Logger fallback.

    test('should not throw when logger is null and validation fails', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(
        () => JsonSentinel.validateList(
          raw: ['not-a-map'],
          expectedTypes: {
            'id': [int],
          },
          context: 'UserRecord',
        ),
        returnsNormally,
      );
    });

    test('should not throw when logger is null and all items pass', () {
      // Arrange
      JsonSentinel.resetLoggerForTesting();

      // Act & Assert
      expect(
        () => JsonSentinel.validateList(
          raw: [
            {'id': 1},
          ],
          expectedTypes: {
            'id': [int],
          },
          context: 'UserRecord',
        ),
        returnsNormally,
      );
    });

    // endregion

    // region Escalation.

    test('should pass escalate false to logger by default', () {
      // Act
      JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
      );

      // Assert
      expect(escalations.first, isFalse);
    });

    test('should pass escalate true to logger when explicitly set', () {
      // Act
      JsonSentinel.validateList(
        raw: ['not-a-map'],
        expectedTypes: {
          'id': [int],
        },
        context: 'UserRecord',
        escalate: true,
      );

      // Assert
      expect(escalations.first, isTrue);
    });

    // endregion

    // region warnUnexpected propagated from validateList.

    group('warnUnexpected —', () {
      setUp(JsonSentinel.resetLoggerForTesting);

      test('should return isValid true when Map items have unexpected keys and warnUnexpected is true', () {
        // Arrange
        JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
          logs.add(message);
        });

        // Act
        final result = JsonSentinel.validateList(
          raw: [
            {'id': 1, 'extra': 'x'},
          ],
          expectedTypes: {
            'id': [int],
          },
          warnUnexpected: true,
          context: 'UserRecord',
        );

        // Assert
        expect(result.isValid, isTrue);
        expect(logs.length, 1);
        expect(logs.first, contains('warning'));
      });

      test('should throw AssertionError when both strict and warnUnexpected are true', () {
        // Arrange
        JsonSentinel.silence();

        // Act & Assert
        expect(
          () => JsonSentinel.validateList(
            raw: [
              {'id': 1},
            ],
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
    });

    // endregion

    // region Per-field validators propagated from validateList.

    group('validators —', () {
      setUp(JsonSentinel.resetLoggerForTesting);

      test('should fail item when validator returns false for a Map item', () {
        // Arrange
        JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
          logs.add(message);
        });

        // Act
        final result = JsonSentinel.validateList(
          raw: [
            {'status': 'invalid'},
          ],
          expectedTypes: {
            'status': [String],
          },
          validators: {'status': (Object? v) => v == 'active'},
          context: 'OrderRecord',
        );

        // Assert
        expect(result.isValid, isFalse);
        expect(logs.first, contains('failed custom validation'));
      });

      test('should not apply validator to non-Map items', () {
        // Arrange — non-Map item gets a "not a Map" failure, not a validator error
        var validatorCalled = false;
        JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {});

        // Act
        final result = JsonSentinel.validateList(
          raw: ['not-a-map'],
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
        expect(result.results.first.errors.first, contains('not a Map<String, dynamic>'));
      });
    });

    // endregion

    // region verbose.

    group('verbose —', () {
      setUp(JsonSentinel.resetLoggerForTesting);

      test('should not throw when verbose is true and all items pass', () {
        // Arrange
        JsonSentinel.silence(verbose: true);

        // Act & Assert
        expect(
          () => JsonSentinel.validateList(
            raw: [
              {'id': 1},
            ],
            expectedTypes: {
              'id': [int],
            },
            context: 'UserRecord',
          ),
          returnsNormally,
        );
      });

      test('should not throw when verbose is true and items fail', () {
        // Arrange
        JsonSentinel.silence(verbose: true);

        // Act & Assert
        expect(
          () => JsonSentinel.validateList(
            raw: ['not-a-map'],
            expectedTypes: {
              'id': [int],
            },
            context: 'UserRecord',
          ),
          returnsNormally,
        );
      });

      test('should not throw when verbose is true and warnUnexpected finds unexpected keys', () {
        // Arrange — covers the verbose developer.log on the warnUnexpected path
        JsonSentinel.silence(verbose: true);

        // Act & Assert
        expect(
          () => JsonSentinel.validateList(
            raw: [
              {'id': 1, 'extra': 'x'},
            ],
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
  });

  // endregion
}
