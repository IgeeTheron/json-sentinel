/// A logging callback invoked by [JsonSentinel] on every validation failure.
///
/// Register an implementation once at app startup via [JsonSentinel.configure]:
///
/// ```dart
/// JsonSentinel.configure((message, {error, stackTrace, extras, escalate}) {
///   myLogger.warn(message, stackTrace: stackTrace, extras: extras);
/// });
/// ```
///
/// [message] is the formatted validation failure report. For [JsonSentinel.validate]
/// it has the form `[Model] JSON validation failed (N errors):\n  • …`. For
/// [JsonSentinel.validateBatch] it has the form
/// `[Model] JSON batch validation failed (N of M items failed):\n  Item I (K errors):\n    • …`.
///
/// [error] is reserved for potential future exception-based callers; both
/// [JsonSentinel.validate] and [JsonSentinel.validateBatch] always pass `null`.
/// Treat it as always null in current implementations.
///
/// [stackTrace] is a stack trace captured inside [JsonSentinel] at the point
/// where the failure is detected.
///
/// [extras] carries structured data about the failure. The keys depend on
/// which method fired the callback:
///
/// - [JsonSentinel.validate]: always `'context'` (model name) and
///   `'json_preview'` (truncated JSON string of the validated map).
/// - [JsonSentinel.validateBatch]: always `'context'`, `'failure_count'` (int),
///   `'total_count'` (int), and `'item_previews'` (`List<String>` of truncated
///   JSON strings for each failing item, in `failureIndices` order).
///   Does **not** include `'json_preview'`. Absent when `generatePreviews: false`.
///
/// [escalate] hints that the failure warrants elevated capture (e.g. a Sentry
/// event rather than a breadcrumb). Nullable so implementations may omit it
/// from their signature; treat `null` as `false`.
typedef JsonLogFn = void Function(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?>? extras, bool? escalate});
