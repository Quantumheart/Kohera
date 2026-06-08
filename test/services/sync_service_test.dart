import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/sync_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late CachedStreamController<SyncUpdate> syncController;
  late int changeCount;
  late int postSyncBackupCount;
  late bool postSyncBackupThrows;

  late SyncService service;

  setUp(() {
    mockClient = MockClient();
    syncController = CachedStreamController<SyncUpdate>();
    when(mockClient.onSync).thenReturn(syncController);
    changeCount = 0;
    postSyncBackupCount = 0;
    postSyncBackupThrows = false;

    service = SyncService(
      client: mockClient,
      onPostSyncBackup: () async {
        postSyncBackupCount++;
        if (postSyncBackupThrows) throw Exception('backup failed');
      },
    );
    service.addListener(() => changeCount++);
  });

  group('startSync', () {
    test('sets syncing true and notifies listeners', () async {
      Future<void>.delayed(
        Duration.zero,
        () => syncController.add(SyncUpdate(nextBatch: 'b1')),
      );

      await service.startSync();

      expect(service.syncing, isTrue);
      expect(changeCount, greaterThan(0));
    });

    test('waits for first sync from client stream', () async {
      final future = service.startSync();

      expect(service.syncing, isTrue);

      syncController.add(SyncUpdate(nextBatch: 'b1'));

      await future;
    });

    test('calls onPostSyncBackup after first sync', () async {
      Future<void>.delayed(
        Duration.zero,
        () => syncController.add(SyncUpdate(nextBatch: 'b1')),
      );

      await service.startSync();

      await Future<void>.delayed(Duration.zero);
      expect(postSyncBackupCount, 1);
    });

    test('with timeout throws TimeoutException if no sync arrives',
        () async {
      expect(
        () => service.startSync(timeout: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('sets autoUnlockError if onPostSyncBackup throws', () async {
      postSyncBackupThrows = true;

      Future<void>.delayed(
        Duration.zero,
        () => syncController.add(SyncUpdate(nextBatch: 'b1')),
      );

      await service.startSync();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.autoUnlockError, isNotNull);
      expect(service.autoUnlockError, contains('backup failed'));
    });
  });

  group('cancelSyncSub', () {
    test('cancels the sync subscription', () async {
      Future<void>.delayed(
        Duration.zero,
        () => syncController.add(SyncUpdate(nextBatch: 'b1')),
      );

      await service.startSync();

      service.cancelSyncSub();

      expect(service.syncing, isFalse);
    });
  });

  group('startSync retries', () {
    late SyncService retryService;

    setUp(() {
      retryService = SyncService(
        client: mockClient,
        sleep: (_) async {},
        onPostSyncBackup: () async {},
      );
    });

    test('does not retry by default', () async {
      var retries = 0;

      await expectLater(
        retryService.startSync(
          timeout: const Duration(milliseconds: 1),
          onRetry: (_, __, ___) => retries++,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(retries, 0);
    });

    test('retries with backoff then recovers when sync lands late', () async {
      var retries = 0;

      // Emitting from inside onRetry guarantees the first attempt times out
      // before the sync arrives, making retry-then-recover deterministic.
      await retryService.startSync(
        timeout: const Duration(milliseconds: 50),
        retrySchedule: const [Duration(seconds: 1)],
        onRetry: (_, __, ___) {
          retries++;
          syncController.add(SyncUpdate(nextBatch: 'b1'));
        },
      );

      expect(retries, 1);
    });

    test('throws TimeoutException after exhausting retries', () async {
      var retries = 0;

      await expectLater(
        retryService.startSync(
          timeout: const Duration(milliseconds: 20),
          retrySchedule: const [Duration(seconds: 1), Duration(seconds: 1)],
          onRetry: (_, __, ___) => retries++,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(retries, 2);
    });
  });
}
