import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MockEncryption mockEncryption;
  late MockCrossSigning mockCrossSigning;
  late MockKeyManager mockKeyManager;
  late MockSSSS mockSsss;
  late MockDatabaseApi mockDatabase;
  late MockBackupVersionManager mockBackupVersion;
  late CachedStreamController<SyncUpdate> syncController;
  late ChatBackupService service;
  late int changeCount;

  GetRoomKeysVersionCurrentResponse fakeBackupInfo() =>
      GetRoomKeysVersionCurrentResponse.fromJson({
        'algorithm': BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2.name,
        'auth_data': <String, dynamic>{'public_key': 'fake'},
        'count': 0,
        'etag': '0',
        'version': '1',
      });

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    mockEncryption = MockEncryption();
    mockCrossSigning = MockCrossSigning();
    mockKeyManager = MockKeyManager();
    mockSsss = MockSSSS();
    mockDatabase = MockDatabaseApi();
    mockBackupVersion = MockBackupVersionManager();
    syncController = CachedStreamController<SyncUpdate>();
    changeCount = 0;
    when(mockClient.onSync).thenReturn(syncController);
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.encryption).thenReturn(mockEncryption);
    when(mockClient.database).thenReturn(mockDatabase);
    when(mockDatabase.getEventList(any,
            start: anyNamed('start'),
            onlySending: anyNamed('onlySending'),
            limit: anyNamed('limit'),),)
        .thenAnswer((_) async => <Event>[]);
    when(mockEncryption.crossSigning).thenReturn(mockCrossSigning);
    when(mockEncryption.keyManager).thenReturn(mockKeyManager);
    when(mockEncryption.ssss).thenReturn(mockSsss);
    when(mockKeyManager.getRoomKeysBackupInfo(any))
        .thenAnswer((_) async => fakeBackupInfo());
    when(mockBackupVersion.ensureExists())
        .thenAnswer((_) async => fakeBackupInfo());
    when(mockBackupVersion.cachedSecretMatchesServer())
        .thenAnswer((_) async => true);
    when(mockBackupVersion.hasVersion()).thenAnswer((_) async => true);
    service = ChatBackupService(
      client: mockClient,
      storage: mockStorage,
      backupVersion: mockBackupVersion,
    );
    service.addListener(() => changeCount++);
  });

  group('checkChatBackupStatus', () {
    test('sets chatBackupNeeded false when initialized and connected',
        () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);

      await service.checkChatBackupStatus();

      expect(service.chatBackupNeeded, isFalse);
      expect(service.chatBackupEnabled, isTrue);
      expect(changeCount, greaterThan(0));
    });

    test('sets chatBackupNeeded true when not initialized', () async {
      when(mockCrossSigning.enabled).thenReturn(false);
      when(mockKeyManager.enabled).thenReturn(false);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => false);
      when(mockKeyManager.isCached()).thenAnswer((_) async => false);

      await service.checkChatBackupStatus();

      expect(service.chatBackupNeeded, isTrue);
    });

    test('leaves chatBackupNeeded unchanged when an inner call throws',
        () async {
      when(mockBackupVersion.hasVersion())
          .thenThrow(Exception('sync glitch'));

      await service.checkChatBackupStatus();

      // Previous behavior forced `true` here, producing false positives.
      // The new contract is "transient errors leave the last value in place".
      expect(service.chatBackupNeeded, isNull);
    });

    test(
        'leaves chatBackupNeeded unchanged when hasVersion returns null '
        '(transient lookup failure)', () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);

      // First call: backup exists, so banner is hidden.
      await service.checkChatBackupStatus();
      expect(service.chatBackupNeeded, isFalse);

      // Second call: hasVersion lookup fails — must not flip to true.
      when(mockBackupVersion.hasVersion()).thenAnswer((_) async => null);
      await service.checkChatBackupStatus();

      expect(service.chatBackupNeeded, isFalse);
    });

    test(
        'sets chatBackupNeeded true when identity is initialized+connected '
        'but server has no backup version',
        () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);
      when(mockBackupVersion.hasVersion()).thenAnswer((_) async => false);

      await service.checkChatBackupStatus();

      expect(service.chatBackupNeeded, isTrue);
    });
  });

  group('account-data refresh', () {
    test('refreshes when sync brings a m.megolm_backup.v1 account-data event',
        () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);
      when(mockBackupVersion.hasVersion()).thenAnswer((_) async => true);

      syncController.add(
        SyncUpdate(
          nextBatch: 'tok',
          accountData: [
            BasicEvent(type: 'm.megolm_backup.v1', content: const {}),
          ],
        ),
      );
      // Let the listener's microtask drain.
      await Future<void>.delayed(Duration.zero);

      verify(mockBackupVersion.invalidateCache()).called(1);
      expect(service.chatBackupNeeded, isFalse);
    });

    test('ignores sync updates without backup-relevant account-data', () async {
      syncController.add(
        SyncUpdate(
          nextBatch: 'tok',
          accountData: [
            BasicEvent(type: 'm.push_rules', content: const {}),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      verifyNever(mockBackupVersion.invalidateCache());
      verifyNever(mockBackupVersion.hasVersion());
    });

    test('refreshes on m.secret_storage.key.* (SSSS root) events', () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);
      when(mockBackupVersion.hasVersion()).thenAnswer((_) async => true);

      syncController.add(
        SyncUpdate(
          nextBatch: 'tok',
          accountData: [
            BasicEvent(
              type: 'm.secret_storage.key.AbCdEf',
              content: const {},
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      verify(mockBackupVersion.invalidateCache()).called(1);
    });

    test('throttles repeated sync-driven refreshes within 5s', () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);
      when(mockBackupVersion.hasVersion()).thenAnswer((_) async => true);

      for (var i = 0; i < 3; i++) {
        syncController.add(
          SyncUpdate(
            nextBatch: 'tok$i',
            accountData: [
              BasicEvent(type: 'm.megolm_backup.v1', content: const {}),
            ],
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);

      verify(mockBackupVersion.invalidateCache()).called(1);
      verify(mockBackupVersion.hasVersion()).called(1);
    });
  });

  group('concurrent checkChatBackupStatus', () {
    test('second concurrent call is a no-op while the first is in flight',
        () async {
      final completer = Completer<bool?>();
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);
      when(mockBackupVersion.hasVersion())
          .thenAnswer((_) => completer.future);

      final first = service.checkChatBackupStatus();
      final second = service.checkChatBackupStatus();
      completer.complete(true);
      await Future.wait([first, second]);

      verify(mockBackupVersion.hasVersion()).called(1);
    });
  });

  group('refreshOnResume', () {
    test('runs checkChatBackupStatus on first call', () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);

      await service.refreshOnResume();

      verify(mockBackupVersion.invalidateCache()).called(1);
      verify(mockBackupVersion.hasVersion()).called(1);
    });

    test('throttles repeat calls within 30s', () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);

      await service.refreshOnResume();
      await service.refreshOnResume();

      verify(mockBackupVersion.invalidateCache()).called(1);
      verify(mockBackupVersion.hasVersion()).called(1);
    });
  });

  group('tryAutoUnlockBackup', () {
    test('checks backup status even when no stored recovery key', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => null);
      when(mockCrossSigning.enabled).thenReturn(false);
      when(mockKeyManager.enabled).thenReturn(false);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => false);
      when(mockKeyManager.isCached()).thenAnswer((_) async => false);

      await service.tryAutoUnlockBackup();

      expect(service.chatBackupNeeded, isTrue);
    });

    test('skips restore when already connected', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => 'recovery-key');
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);

      await service.tryAutoUnlockBackup();

      expect(service.chatBackupNeeded, isFalse);
    });

    test('handles errors silently', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => 'recovery-key');
      when(mockClient.encryption).thenReturn(null);

      await service.tryAutoUnlockBackup();

      expect(service.chatBackupNeeded, isTrue);
    });

    test('requests missing room keys when no stored key', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => null);
      when(mockCrossSigning.enabled).thenReturn(false);
      when(mockKeyManager.enabled).thenReturn(false);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => false);
      when(mockKeyManager.isCached()).thenAnswer((_) async => false);

      final mockRoom = MockRoom();
      when(mockClient.rooms).thenReturn([mockRoom]);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockDatabase.getEventList(mockRoom,
              start: anyNamed('start'),
              onlySending: anyNamed('onlySending'),
              limit: anyNamed('limit'),),)
          .thenAnswer((_) async => [
                Event(
                  type: EventTypes.Encrypted,
                  content: {
                    'msgtype': MessageTypes.BadEncrypted,
                    'can_request_session': true,
                    'session_id': 'session123',
                    'sender_key': 'key456',
                  },
                  senderId: '@user:example.com',
                  eventId: r'$ev1',
                  originServerTs: DateTime.now(),
                  room: mockRoom,
                ),
              ],);

      await service.tryAutoUnlockBackup();
      await untilCalled(mockKeyManager.maybeAutoRequest(any, any, any));

      verify(
        mockKeyManager.maybeAutoRequest(
          '!room:example.com',
          'session123',
          'key456',
        ),
      ).called(1);
    });
  });

  group('recovery key storage', () {
    test('getStoredRecoveryKey reads from storage', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => 'test-key');

      final key = await service.getStoredRecoveryKey();

      expect(key, 'test-key');
    });

    test('storeRecoveryKey writes to storage', () async {
      when(mockClient.userID).thenReturn('@user:example.com');

      await service.storeRecoveryKey('new-key');

      verify(
        mockStorage.write(
          key: 'ssss_recovery_key_@user:example.com',
          value: 'new-key',
        ),
      ).called(1);
    });

    test('deleteStoredRecoveryKey deletes from storage', () async {
      when(mockClient.userID).thenReturn('@user:example.com');

      await service.deleteStoredRecoveryKey();

      verify(
        mockStorage.delete(
          key: 'ssss_recovery_key_@user:example.com',
        ),
      ).called(1);
    });

    test('getStoredRecoveryKey returns null when no userID', () async {
      when(mockClient.userID).thenReturn(null);

      final key = await service.getStoredRecoveryKey();

      expect(key, isNull);
    });
  });

  group('disableChatBackup', () {
    test('handles M_NOT_FOUND gracefully', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockKeyManager.getRoomKeysBackupInfo()).thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_NOT_FOUND',
          'error': 'No backup found',
        }),
      );

      await service.disableChatBackup();

      expect(service.chatBackupNeeded, isTrue);
      expect(service.chatBackupError, isNull);
      expect(service.chatBackupLoading, isFalse);
    });

    test('sets error on failure', () async {
      when(mockClient.encryption).thenReturn(null);

      await service.disableChatBackup();

      expect(service.chatBackupError, isNotNull);
      expect(service.chatBackupLoading, isFalse);
    });

    test('invalidates BackupVersionManager cache after deletion', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockKeyManager.getRoomKeysBackupInfo())
          .thenAnswer((_) async => fakeBackupInfo());
      when(mockClient.deleteRoomKeysVersion(any))
          .thenAnswer((_) async {});

      await service.disableChatBackup();

      verify(mockBackupVersion.invalidateCache()).called(1);
    });
  });

  group('resetChatBackupState', () {
    test('resets chatBackupNeeded to null', () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);

      await service.checkChatBackupStatus();
      expect(service.chatBackupNeeded, isFalse);

      service.resetChatBackupState();

      expect(service.chatBackupNeeded, isNull);
    });
  });

  group('requestMissingRoomKeys', () {
    test('is a no-op when encryption is null', () async {
      when(mockClient.encryption).thenReturn(null);

      await service.requestMissingRoomKeys();
    });

    test('requests keys for undecryptable cached events', () async {
      final mockRoom = MockRoom();
      when(mockClient.rooms).thenReturn([mockRoom]);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockDatabase.getEventList(mockRoom,
              start: anyNamed('start'),
              onlySending: anyNamed('onlySending'),
              limit: anyNamed('limit'),),)
          .thenAnswer((_) async => [
                Event(
                  type: EventTypes.Encrypted,
                  content: {
                    'msgtype': MessageTypes.BadEncrypted,
                    'can_request_session': true,
                    'session_id': 'session123',
                    'sender_key': 'key456',
                  },
                  senderId: '@user:example.com',
                  eventId: r'$ev1',
                  originServerTs: DateTime.now(),
                  room: mockRoom,
                ),
              ],);

      await service.requestMissingRoomKeys();

      verify(
        mockKeyManager.maybeAutoRequest(
          '!room:example.com',
          'session123',
          'key456',
        ),
      ).called(1);
    });

    test('scans cached history, not just lastEvent', () async {
      final mockRoom = MockRoom();
      when(mockClient.rooms).thenReturn([mockRoom]);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockDatabase.getEventList(mockRoom,
              start: anyNamed('start'),
              onlySending: anyNamed('onlySending'),
              limit: anyNamed('limit'),),)
          .thenAnswer((_) async => [
                Event(
                  type: EventTypes.Encrypted,
                  content: {
                    'msgtype': MessageTypes.BadEncrypted,
                    'can_request_session': true,
                    'session_id': 'old_session',
                    'sender_key': 'old_key',
                  },
                  senderId: '@user:example.com',
                  eventId: r'$old',
                  originServerTs: DateTime.now(),
                  room: mockRoom,
                ),
                Event(
                  type: EventTypes.Encrypted,
                  content: {
                    'msgtype': MessageTypes.BadEncrypted,
                    'can_request_session': true,
                    'session_id': 'new_session',
                    'sender_key': 'new_key',
                  },
                  senderId: '@user:example.com',
                  eventId: r'$new',
                  originServerTs: DateTime.now(),
                  room: mockRoom,
                ),
              ],);

      await service.requestMissingRoomKeys();

      verify(mockKeyManager.maybeAutoRequest(
        '!room:example.com',
        'old_session',
        'old_key',
      ),).called(1);
      verify(mockKeyManager.maybeAutoRequest(
        '!room:example.com',
        'new_session',
        'new_key',
      ),).called(1);
    });

    test('second call within cooldown is skipped without force', () async {
      final mockRoom = MockRoom();
      when(mockClient.rooms).thenReturn([mockRoom]);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockDatabase.getEventList(mockRoom,
              start: anyNamed('start'),
              onlySending: anyNamed('onlySending'),
              limit: anyNamed('limit'),),)
          .thenAnswer((_) async => [
                Event(
                  type: EventTypes.Encrypted,
                  content: {
                    'msgtype': MessageTypes.BadEncrypted,
                    'can_request_session': true,
                    'session_id': 'sess',
                    'sender_key': 'key',
                  },
                  senderId: '@user:example.com',
                  eventId: r'$ev1',
                  originServerTs: DateTime.now(),
                  room: mockRoom,
                ),
              ],);

      await service.requestMissingRoomKeys();
      await service.requestMissingRoomKeys();

      verify(mockKeyManager.maybeAutoRequest(any, any, any)).called(1);
    });

    test('force: true bypasses cooldown', () async {
      final mockRoom = MockRoom();
      when(mockClient.rooms).thenReturn([mockRoom]);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockDatabase.getEventList(mockRoom,
              start: anyNamed('start'),
              onlySending: anyNamed('onlySending'),
              limit: anyNamed('limit'),),)
          .thenAnswer((_) async => [
                Event(
                  type: EventTypes.Encrypted,
                  content: {
                    'msgtype': MessageTypes.BadEncrypted,
                    'can_request_session': true,
                    'session_id': 'sess',
                    'sender_key': 'key',
                  },
                  senderId: '@user:example.com',
                  eventId: r'$ev1',
                  originServerTs: DateTime.now(),
                  room: mockRoom,
                ),
              ],);

      await service.requestMissingRoomKeys();
      await service.requestMissingRoomKeys(force: true);

      verify(mockKeyManager.maybeAutoRequest(any, any, any)).called(2);
    });
  });

  group('runKeyRecovery', () {
    test('calls BackupVersionManager.ensureExists before loadAllKeys',
        () async {
      await service.runKeyRecovery();

      verifyInOrder([
        mockBackupVersion.ensureExists(),
        mockKeyManager.loadAllKeys(),
      ]);
    });

    test('continues to loadAllKeys when ensureExists returns null', () async {
      when(mockBackupVersion.ensureExists()).thenAnswer((_) async => null);

      await service.runKeyRecovery();

      verify(mockKeyManager.loadAllKeys()).called(1);
    });

    test('loadAllKeys failure does not skip requestMissingRoomKeys',
        () async {
      when(mockKeyManager.loadAllKeys())
          .thenThrow(Exception('network error'));

      final room = MockRoom();
      when(room.id).thenReturn('!room:example.com');
      when(mockClient.rooms).thenReturn([room]);
      when(mockDatabase.getEventList(room,
              start: anyNamed('start'),
              onlySending: anyNamed('onlySending'),
              limit: anyNamed('limit'),),)
          .thenAnswer((_) async => [
                Event(
                  type: EventTypes.Encrypted,
                  content: {
                    'msgtype': MessageTypes.BadEncrypted,
                    'can_request_session': true,
                    'session_id': 'sess',
                    'sender_key': 'key',
                  },
                  senderId: '@user:example.com',
                  eventId: r'$e',
                  originServerTs: DateTime.now(),
                  room: room,
                ),
              ],);

      await service.runKeyRecovery();

      verify(mockKeyManager.maybeAutoRequest(
        '!room:example.com',
        'sess',
        'key',
      ),).called(1);
    });

    test('no-ops when encryption is null', () async {
      when(mockClient.encryption).thenReturn(null);

      await service.runKeyRecovery();

      verifyNever(mockBackupVersion.ensureExists());
      verifyNever(mockKeyManager.loadAllKeys());
    });
  });
}
