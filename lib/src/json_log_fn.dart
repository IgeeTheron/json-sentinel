/// The function signature for logging JSON validation failures.
///
/// - [message] — the formatted validation report.
/// - [error] — the exception object, if applicable.
/// - [stackTrace] — call-site stack trace captured at the point
///   [JsonSentinel.validate] was invoked.
/// - [extras] — structured key/value context (e.g. `json_preview`, `context`).
/// - [escalate] — hint to the logger that this failure warrants more than a
///   breadcrumb (e.g. a Sentry capture). Nullable so callers can omit it;
///   treat `null` as `false` in your implementation.
typedef JsonLogFn = void Function(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?>? extras, bool? escalate});
