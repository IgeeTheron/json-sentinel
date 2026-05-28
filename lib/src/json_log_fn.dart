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
/// [message] is the formatted validation report, for example:
/// `[OrderResponse] JSON validation failed (1 error):\n  • Missing required key 'id'.`
///
/// [error] is reserved for potential future exception-based callers;
/// [JsonSentinel.validate] always passes `null`. Treat it as always null in
/// current implementations.
///
/// [stackTrace] is the call-site stack trace captured at the moment
/// [JsonSentinel.validate] was invoked.
///
/// [extras] always contains `context` (the model name) and `json_preview`
/// (a truncated JSON string of the validated map).
///
/// [escalate] hints that the failure warrants elevated capture (e.g. a Sentry
/// event rather than a breadcrumb). Nullable so implementations may omit it
/// from their signature; treat `null` as `false`.
typedef JsonLogFn = void Function(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?>? extras, bool? escalate});
