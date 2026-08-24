import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/repositories/key_backup_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/features/e2ee/screens/e2ee_setup_screen.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks/matrix_service_mock.mocks.dart';
import 'bootstrap_controller_test.mocks.dart';
@GenerateNiceMocks([MockSpec<KeyBackupRepository>()])
import 'e2ee_setup_screen_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrixService;
  late MockKeyBackupRepository mockKeyBackup;
  late MockClient mockClient;
  late MockUiaInteractionController mockUia;

  setUp(() {
    mockMatrixService = MockMatrixService();
    mockKeyBackup = MockKeyBackupRepository();
    mockClient = MockClient();
    mockUia = MockUiaInteractionController();

    when(mockMatrixService.matrixClientService).thenReturn(MatrixClientService(mockClient));
    when(mockMatrixService.keyBackupRepository).thenReturn(mockKeyBackup);
    when(mockMatrixService.uia).thenReturn(mockUia);
    when(mockMatrixService.hasSkippedSetup).thenReturn(false);

    when(mockKeyBackup.chatBackupEnabled).thenReturn(false);
    when(mockKeyBackup.chatBackupNeeded).thenReturn(true);

    when(mockClient.encryption).thenReturn(null);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
          ChangeNotifierProvider<KeyBackupRepository>.value(
            value: mockKeyBackup,
          ),
        ],
        child: const MaterialApp(
          home: E2eeSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'fresh-login path auto-starts bootstrap with no explainer Next or skip button',
    (tester) async {
      await pumpScreen(tester);

      expect(find.text('Next'), findsNothing);
      expect(find.text('Skip for now'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets('saved-confirmation dialog is not present in the widget tree', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Have you saved your recovery key?'), findsNothing);
    expect(find.text("I've saved it"), findsNothing);
  });

  testWidgets('management path renders when backup already enabled', (
    tester,
  ) async {
    when(mockKeyBackup.chatBackupEnabled).thenReturn(true);
    when(mockKeyBackup.chatBackupNeeded).thenReturn(false);

    await pumpScreen(tester);

    expect(find.text('Chat backup'), findsOneWidget);
    expect(find.text('Show recovery key'), findsOneWidget);
  });
}
