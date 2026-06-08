import 'dart:async';

/// Bounded exponential backoff schedule shared by the auth lifecycle, matching
/// the repository's network-op convention (2s/4s/8s/16s).
const List<Duration> kAuthBackoffSchedule = [
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
];

typedef RetryPredicate = bool Function(Object error);
typedef RetryCallback = void Function(
  Object error,
  Duration delay,
  int attempt,
);
typedef SleepFn = Future<void> Function(Duration delay);

Future<void> _defaultSleep(Duration delay) => Future<void>.delayed(delay);

/// Runs [action], retrying on failure while [retryIf] accepts the error and the
/// [schedule] still has delays left. Waits [schedule]`[attempt]` between tries
/// before re-running. The last error is rethrown once retries are exhausted or
/// [retryIf] rejects it.
///
/// [sleep] is injectable so tests can advance without real delays.
Future<T> retryWithBackoff<T>(
  Future<T> Function() action, {
  required RetryPredicate retryIf,
  List<Duration> schedule = kAuthBackoffSchedule,
  RetryCallback? onRetry,
  SleepFn sleep = _defaultSleep,
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await action();
    } catch (error) {
      if (attempt >= schedule.length || !retryIf(error)) rethrow;
      final delay = schedule[attempt];
      attempt++;
      onRetry?.call(error, delay, attempt);
      await sleep(delay);
    }
  }
}
