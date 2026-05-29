import 'package:json_sentinel/json_sentinel.dart';
import 'package:test/test.dart';

void main() {
  // region Tests

  group('BatchValidationResult.fromResults — empty list —', () {
    test('isValid is true', () {
      // Act & Assert
      expect(BatchValidationResult.fromResults([]).isValid, isTrue);
    });

    test('failureCount is 0', () {
      // Act & Assert
      expect(BatchValidationResult.fromResults([]).failureCount, 0);
    });

    test('results is empty', () {
      // Act & Assert
      expect(BatchValidationResult.fromResults([]).results, isEmpty);
    });

    test('failureIndices is empty', () {
      // Act & Assert
      expect(BatchValidationResult.fromResults([]).failureIndices, isEmpty);
    });
  });

  group('BatchValidationResult.fromResults — all pass —', () {
    late BatchValidationResult result;

    setUp(() {
      result = BatchValidationResult.fromResults([
        JsonValidationResult.success,
        JsonValidationResult.success,
        JsonValidationResult.success,
      ]);
    });

    test('isValid is true', () {
      expect(result.isValid, isTrue);
    });

    test('failureCount is 0', () {
      expect(result.failureCount, 0);
    });

    test('failureIndices is empty', () {
      expect(result.failureIndices, isEmpty);
    });

    test('results length matches input', () {
      expect(result.results.length, 3);
    });

    test('results throws UnsupportedError on add()', () {
      expect(() => result.results.add(JsonValidationResult.success), throwsUnsupportedError);
    });

    test('failureIndices throws UnsupportedError on add()', () {
      expect(() => result.failureIndices.add(0), throwsUnsupportedError);
    });
  });

  group('BatchValidationResult.fromResults — mixed pass/fail —', () {
    late BatchValidationResult result;

    setUp(() {
      result = BatchValidationResult.fromResults([
        JsonValidationResult.success,
        JsonValidationResult.failure(['e1']),
        JsonValidationResult.success,
        JsonValidationResult.failure(['e2', 'e3']),
        JsonValidationResult.success,
      ]);
    });

    test('isValid is false', () {
      expect(result.isValid, isFalse);
    });

    test('failureCount equals number of failing items', () {
      expect(result.failureCount, 2);
    });

    test('failureIndices contains the correct zero-based indices', () {
      expect(result.failureIndices, [1, 3]);
    });

    test('failureIndices does not contain indices of passing items', () {
      expect(result.failureIndices, isNot(contains(0)));
      expect(result.failureIndices, isNot(contains(2)));
      expect(result.failureIndices, isNot(contains(4)));
    });

    test('results length matches input', () {
      expect(result.results.length, 5);
    });

    test('results preserves per-item isValid', () {
      expect(result.results[0].isValid, isTrue);
      expect(result.results[1].isValid, isFalse);
      expect(result.results[2].isValid, isTrue);
      expect(result.results[3].isValid, isFalse);
      expect(result.results[4].isValid, isTrue);
    });

    test('results preserves per-item errors', () {
      expect(result.results[1].errors, ['e1']);
      expect(result.results[3].errors, ['e2', 'e3']);
    });

    test('results preserves input order', () {
      for (int i = 0; i < result.results.length; i++) {
        expect(result.results[i], isNotNull);
      }
      expect(result.results[0].isValid, isTrue);
      expect(result.results[1].isValid, isFalse);
    });

    test('results throws UnsupportedError on add()', () {
      expect(() => result.results.add(JsonValidationResult.success), throwsUnsupportedError);
    });

    test('failureIndices throws UnsupportedError on add()', () {
      expect(() => result.failureIndices.add(99), throwsUnsupportedError);
    });
  });

  group('BatchValidationResult.fromResults — all fail —', () {
    late BatchValidationResult result;

    setUp(() {
      result = BatchValidationResult.fromResults([
        JsonValidationResult.failure(['e1']),
        JsonValidationResult.failure(['e2']),
      ]);
    });

    test('isValid is false', () {
      expect(result.isValid, isFalse);
    });

    test('failureCount equals results length', () {
      expect(result.failureCount, result.results.length);
    });

    test('failureIndices length equals results length', () {
      expect(result.failureIndices.length, result.results.length);
    });

    test('failureIndices contains all indices', () {
      expect(result.failureIndices, [0, 1]);
    });
  });

  group('BatchValidationResult.fromResults — source list mutation —', () {
    test('mutating source list after construction does not affect results', () {
      // Arrange
      final source = <JsonValidationResult>[JsonValidationResult.success];
      final result = BatchValidationResult.fromResults(source);

      // Act
      source.add(JsonValidationResult.failure(['extra']));

      // Assert
      expect(result.results.length, 1);
      expect(result.failureCount, 0);
    });
  });

  // endregion
}
