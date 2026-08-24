import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/repositories/key_backup_repository.dart';
import 'package:kohera/features/e2ee/services/recovery_key_handler.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/cross_signing.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<KeyBackupRepository>(),
  MockSpec<Bootstrap>(),
  MockSpec<OpenSSSS>(),
  MockSpec<Client>(),
  MockSpec<Encryption>(),
  MockSpec<CrossSigning>(),
])
import 'recovery_key_handler_test.mocks.dart';

void main() {
  late MockKeyBackupRepository mockKeyBackup;
  late MockClient mockClient;
  late RecoveryKeyHandler handler;

  setUp(() {
    mockKeyBackup = MockKeyBackupRepository();
    mockClient = MockClient();
    handler = RecoveryKeyHandler(keyBackup: mockKeyBackup);
  });

  group('RecoveryKeyHandler', () {
    test('generateNewKey populates newRecoveryKey', () async {
      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.newSsss()).thenAnswer((_) async {});
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.recoveryKey).thenReturn('EsTc ABCD 1234 5678');

      await handler.generateNewKey(mockBootstrap);

      expect(handler.newRecoveryKey, 'EsTc ABCD 1234 5678');
      expect(handler.generatingKey, isFalse);
    });

    test('unlockExisting with empty key sets error', () async {
      final mockBootstrap = MockBootstrap();
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);

      final result = await handler.unlockExisting(mockBootstrap, '');

      expect(result, isFalse);
      expect(handler.recoveryKeyError, 'Please enter a recovery key');
    });

    test('unlockExisting with invalid key sets error', () async {
      final mockBootstrap = MockBootstrap();
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(
        mockSsssKey.unlock(keyOrPassphrase: anyNamed('keyOrPassphrase')),
      ).thenThrow(Exception('bad key'));

      final result = await handler.unlockExisting(mockBootstrap, 'bad-key');

      expect(result, isFalse);
      expect(handler.recoveryKeyError, 'Invalid recovery key');
    });

    test('unlockExisting with valid key and saveToDevice stores key', () async {
      final mockBootstrap = MockBootstrap();
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(
        mockSsssKey.unlock(keyOrPassphrase: anyNamed('keyOrPassphrase')),
      ).thenAnswer((_) async {});
      when(mockBootstrap.openExistingSsss()).thenAnswer((_) async {});
      when(mockKeyBackup.storeRecoveryKey(any)).thenAnswer((_) async {});
      when(mockClient.encryption).thenReturn(null);

      handler.setSaveToDevice(true);
      final result = await handler.unlockExisting(mockBootstrap, 'valid-key');

      expect(result, isTrue);
      verify(mockKeyBackup.storeRecoveryKey('valid-key')).called(1);
      expect(handler.unlockedSsssKey, mockSsssKey);
    });

    test('unlockExisting returns false when newSsssKey is null', () async {
      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.newSsssKey).thenReturn(null);

      final result = await handler.unlockExisting(mockBootstrap, 'key');

      expect(result, isFalse);
    });

    test('markUnlocking exposes busy state until unlock completes', () async {
      final mockBootstrap = MockBootstrap();
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.unlock(keyOrPassphrase: anyNamed('keyOrPassphrase')))
          .thenAnswer((_) async {});
      when(mockBootstrap.openExistingSsss()).thenAnswer((_) async {});

      handler.markUnlocking();
      expect(handler.unlocking, isTrue);

      await handler.unlockExisting(mockBootstrap, 'valid-key');

      expect(handler.unlocking, isFalse);
    });

    test(
      'storeIfNeeded stores key when saveToDevice and newRecoveryKey set',
      () async {
        final mockBootstrap = MockBootstrap();
        when(mockBootstrap.newSsss()).thenAnswer((_) async {});
        final mockSsssKey = MockOpenSSSS();
        when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
        when(mockSsssKey.recoveryKey).thenReturn('KEY');
        when(mockKeyBackup.storeRecoveryKey(any)).thenAnswer((_) async {});

        await handler.generateNewKey(mockBootstrap);
        handler.setSaveToDevice(true);
        await handler.storeIfNeeded();

        verify(mockKeyBackup.storeRecoveryKey('KEY')).called(1);
      },
    );

    test('storeIfNeeded is no-op when saveToDevice is false', () async {
      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.newSsss()).thenAnswer((_) async {});
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.recoveryKey).thenReturn('KEY');

      await handler.generateNewKey(mockBootstrap);
      await handler.storeIfNeeded();

      verifyNever(mockKeyBackup.storeRecoveryKey(any));
    });

    test('reset clears all state', () async {
      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.newSsss()).thenAnswer((_) async {});
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.recoveryKey).thenReturn('KEY');

      await handler.generateNewKey(mockBootstrap);
      handler.setKeyCopied();
      handler.setSaveToDevice(true);

      handler.reset();

      expect(handler.newRecoveryKey, isNull);
      expect(handler.generatingKey, isFalse);
      expect(handler.keyCopied, isFalse);
      expect(handler.recoveryKeyError, isNull);
      expect(handler.unlockedSsssKey, isNull);
    });

    test('consumeStoredRecoveryKey returns and clears key', () async {
      when(
        mockKeyBackup.getStoredRecoveryKey(),
      ).thenAnswer((_) async => 'stored-key');

      await handler.loadStoredKey();

      expect(handler.consumeStoredRecoveryKey(), 'stored-key');
      expect(handler.consumeStoredRecoveryKey(), isNull);
    });
  });
}
