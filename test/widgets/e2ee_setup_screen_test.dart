import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/features/e2ee/screens/e2ee_setup_screen.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'bootstrap_controller_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrixService;
  late MockChatBackupService mockChatBackup;
  late MockClient mockClient;
  late MockUiaService mockUia;

  setUp(() {
    mockMatrixService = MockMatrixService();
    mockChatBackup = MockChatBackupService();
    mockClient = MockClient();
    mockUia = MockUiaService();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockMatrixService.chatBackup).thenReturn(mockChatBackup);
    when(mockMatrixService.uia).thenReturn(mockUia);
    when(mockMatrixService.hasSkippedSetup).thenReturn(false);

    when(mockChatBackup.chatBackupEnabled).thenReturn(false);
    when(mockChatBackup.chatBackupNeeded).thenReturn(true);
    when(mockChatBackup.setupSkipped).thenReturn(false);

    when(mockClient.encryption).thenReturn(null);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
          ChangeNotifierProvider<ChatBackupService>.value(
            value: mockChatBackup,
          ),
        ],
        child: const MaterialApp(
          home: E2eeSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('fresh-login path auto-starts bootstrap with no explainer Next or skip button',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Next'), findsNothing);
    expect(find.text('Skip for now'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('saved-confirmation dialog is not present in the widget tree',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Have you saved your recovery key?'), findsNothing);
    expect(find.text("I've saved it"), findsNothing);
  });

  testWidgets('management path renders when backup already enabled',
      (tester) async {
    when(mockChatBackup.chatBackupEnabled).thenReturn(true);
    when(mockChatBackup.chatBackupNeeded).thenReturn(false);

    await pumpScreen(tester);

    expect(find.text('Chat backup'), findsOneWidget);
    expect(find.text('Show recovery key'), findsOneWidget);
  });
}
