import 'package:json_sentinel/json_sentinel.dart';
import 'package:test/test.dart';

void main() {
  // region Tests

  group('JsonValidationResult.success —', () {
    test('isValid is true', () {
      // Act & Assert
      expect(JsonValidationResult.success.isValid, isTrue);
    });

    test('errors is empty', () {
      // Act & Assert
      expect(JsonValidationResult.success.errors, isEmpty);
    });

    test('errors throws UnsupportedError on add()', () {
      // Act & Assert
      expect(() => JsonValidationResult.success.errors.add('x'), throwsUnsupportedError);
    });

    test('errors throws UnsupportedError on remove()', () {
      // Act & Assert
      expect(() => JsonValidationResult.success.errors.remove('x'), throwsUnsupportedError);
    });

    test('errors throws UnsupportedError on clear()', () {
      // Act & Assert
      expect(() => JsonValidationResult.success.errors.clear(), throwsUnsupportedError);
    });

    test('is the same const instance on every access', () {
      // Act & Assert
      expect(identical(JsonValidationResult.success, JsonValidationResult.success), isTrue);
    });
  });

  group('JsonValidationResult.failure() —', () {
    test('isValid is false', () {
      // Act & Assert
      expect(JsonValidationResult.failure(['e1']).isValid, isFalse);
    });

    test('errors contains the provided items', () {
      // Act
      final result = JsonValidationResult.failure(['first', 'second']);

      // Assert
      expect(result.errors, ['first', 'second']);
    });

    test('errors preserves insertion order', () {
      // Act
      final result = JsonValidationResult.failure(['c', 'a', 'b']);

      // Assert
      expect(result.errors, ['c', 'a', 'b']);
    });

    test('errors throws UnsupportedError on add()', () {
      // Arrange
      final result = JsonValidationResult.failure(['e1']);

      // Act & Assert
      expect(() => result.errors.add('extra'), throwsUnsupportedError);
    });

    test('errors throws UnsupportedError on remove()', () {
      // Arrange
      final result = JsonValidationResult.failure(['e1']);

      // Act & Assert
      expect(() => result.errors.remove('e1'), throwsUnsupportedError);
    });

    test('errors throws UnsupportedError on clear()', () {
      // Arrange
      final result = JsonValidationResult.failure(['e1']);

      // Act & Assert
      expect(() => result.errors.clear(), throwsUnsupportedError);
    });

    test('wrapping an empty list gives isValid false and empty errors', () {
      // Act
      final result = JsonValidationResult.failure([]);

      // Assert
      expect(result.isValid, isFalse);
      expect(result.errors, isEmpty);
    });

    test('should not alias the source list when mutations occur after construction', () {
      // Arrange
      final source = ['original'];
      final result = JsonValidationResult.failure(source);

      // Act — mutate the source list after the result was constructed
      source.add('added');

      // Assert — result.errors must not reflect the mutation
      expect(result.errors, ['original']);
    });
  });

  // endregion
}
