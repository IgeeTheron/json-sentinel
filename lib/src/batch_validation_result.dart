import 'package:json_sentinel/src/json_validation_result.dart';

/// The aggregated result of a [JsonSentinel.validateBatch] call.
///
/// [failureCount] and [failureIndices] are convenience accessors derived from [results].
/// All list fields are unmodifiable.
class BatchValidationResult {
  /// Whether every item in the batch passed validation.
  final bool isValid;

  /// One [JsonValidationResult] per input item, in input order. Always unmodifiable.
  final List<JsonValidationResult> results;

  /// The number of items that failed validation.
  final int failureCount;

  /// Zero-based indices of the items that failed validation, in ascending order. Always unmodifiable.
  final List<int> failureIndices;

  const BatchValidationResult._({
    required this.isValid,
    required this.results,
    required this.failureCount,
    required this.failureIndices,
  });

  /// Creates a [BatchValidationResult] from a list of per-item [JsonValidationResult] values.
  ///
  /// [results] must be in the same order as the corresponding input items to ensure
  /// [failureIndices] correctly identifies each failing position.
  factory BatchValidationResult.fromResults(List<JsonValidationResult> results) {
    final List<int> failureIndices = [
      for (int i = 0; i < results.length; i++)
        if (!results[i].isValid) i,
    ];
    return BatchValidationResult._(
      isValid: failureIndices.isEmpty,
      results: List.unmodifiable(results),
      failureCount: failureIndices.length,
      failureIndices: List.unmodifiable(failureIndices),
    );
  }
}
