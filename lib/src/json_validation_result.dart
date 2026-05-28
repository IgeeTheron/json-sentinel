/// The result of a [JsonSentinel.validate] call.
///
/// On success, [isValid] is `true` and [errors] is empty.
/// On failure, [isValid] is `false` and [errors] lists every problem found.
///
/// ```dart
/// final result = JsonSentinel.validate(json: map, expectedTypes: schema);
/// if (!result.isValid) {
///   for (final e in result.errors) print(e);
/// }
/// ```
class JsonValidationResult {
  /// Whether all validations passed.
  final bool isValid;

  /// Every validation error found, in the order they were detected.
  ///
  /// Empty when [isValid] is `true`. Unmodifiable.
  final List<String> errors;

  const JsonValidationResult._({required this.isValid, required this.errors});

  /// A successful result with no errors.
  static const JsonValidationResult success = JsonValidationResult._(isValid: true, errors: <String>[]);

  /// A failed result carrying [errors].
  factory JsonValidationResult.failure(List<String> errors) => JsonValidationResult._(isValid: false, errors: List.unmodifiable(errors));
}
