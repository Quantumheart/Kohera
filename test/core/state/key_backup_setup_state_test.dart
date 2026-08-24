import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/state/key_backup_setup_state.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'key_backup_setup_state_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<FlutterSecureStorage>(),
])
void main() {
  const userId = '@user:example.com';
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late KeyBackupSetupState state;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.userID).thenReturn(userId);
    state = KeyBackupSetupState(
      clientService: MatrixClientService(mockClient),
      storage: mockStorage,
    );
  });

  test('loadDismissalState reads both flags from storage', () async {
    when(mockStorage.read(key: 'e2ee_setup_skipped_$userId'))
        .thenAnswer((_) async => 'true');
    when(mockStorage.read(key: 'e2ee_banner_dismissed_$userId'))
        .thenAnswer((_) async => null);

    await state.loadDismissalState();

    expect(state.setupSkipped, isTrue);
    expect(state.bannerDismissed, isFalse);
  });

  test('markSetupSkipped sets flag immediately and persists', () async {
    await state.markSetupSkipped();

    expect(state.setupSkipped, isTrue);
    verify(
      mockStorage.write(key: 'e2ee_setup_skipped_$userId', value: 'true'),
    ).called(1);
  });

  test('dismissBanner sets flag immediately and persists', () async {
    await state.dismissBanner();

    expect(state.bannerDismissed, isTrue);
    verify(
      mockStorage.write(key: 'e2ee_banner_dismissed_$userId', value: 'true'),
    ).called(1);
  });

  test('resetBannerDismissed re-shows the banner', () async {
    await state.dismissBanner();
    expect(state.bannerDismissed, isTrue);

    state.resetBannerDismissed();

    expect(state.bannerDismissed, isFalse);
  });

  test('reset clears both dismissal flags', () async {
    await state.markSetupSkipped();
    await state.dismissBanner();

    state.reset();

    expect(state.setupSkipped, isFalse);
    expect(state.bannerDismissed, isFalse);
  });

  test('deleteDismissalState removes both keys', () async {
    await state.deleteDismissalState();

    verify(mockStorage.delete(key: 'e2ee_setup_skipped_$userId')).called(1);
    verify(mockStorage.delete(key: 'e2ee_banner_dismissed_$userId')).called(1);
  });
}
