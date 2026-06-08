import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/retry.dart';

void main() {
  group('retryWithBackoff', () {
    test('returns immediately on first success without sleeping', () async {
      var calls = 0;
      var slept = 0;

      final result = await retryWithBackoff(
        () async {
          calls++;
          return 'ok';
        },
        retryIf: (_) => true,
        sleep: (_) async => slept++,
      );

      expect(result, 'ok');
      expect(calls, 1);
      expect(slept, 0);
    });

    test('retries until success and backs off between attempts', () async {
      var calls = 0;
      final delays = <Duration>[];

      final result = await retryWithBackoff(
        () async {
          calls++;
          if (calls < 3) throw Exception('transient');
          return calls;
        },
        retryIf: (_) => true,
        schedule: const [
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 8),
        ],
        sleep: (d) async => delays.add(d),
      );

      expect(result, 3);
      expect(calls, 3);
      expect(delays, const [Duration(seconds: 2), Duration(seconds: 4)]);
    });

    test('rethrows immediately when retryIf rejects the error', () async {
      var calls = 0;

      await expectLater(
        retryWithBackoff(
          () async {
            calls++;
            throw StateError('permanent');
          },
          retryIf: (_) => false,
          sleep: (_) async {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
    });

    test('rethrows the last error after exhausting the schedule', () async {
      var calls = 0;
      var slept = 0;

      await expectLater(
        retryWithBackoff(
          () async {
            calls++;
            throw Exception('always');
          },
          retryIf: (_) => true,
          schedule: const [Duration(seconds: 1), Duration(seconds: 1)],
          sleep: (_) async => slept++,
        ),
        throwsA(isA<Exception>()),
      );

      // 2 retries -> 3 total attempts, 2 sleeps.
      expect(calls, 3);
      expect(slept, 2);
    });

    test('reports the attempt number to onRetry', () async {
      final attempts = <int>[];
      var calls = 0;

      await retryWithBackoff(
        () async {
          calls++;
          if (calls < 3) throw Exception('x');
        },
        retryIf: (_) => true,
        schedule: const [Duration(seconds: 1), Duration(seconds: 1)],
        sleep: (_) async {},
        onRetry: (_, __, attempt) => attempts.add(attempt),
      );

      expect(attempts, const [1, 2]);
    });
  });
}
