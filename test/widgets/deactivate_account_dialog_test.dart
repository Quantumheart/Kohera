// Redundant default args are kept in verify() to assert exact forwarding.
// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/core/services/sub_services/uia_service.dart';
import 'package:kohera/features/settings/widgets/deactivate_account_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<ChatBackupService>(),
  MockSpec<ClientManager>(),
])
import 'deactivate_account_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;
  late MockChatBackupService mockChatBackup;
  late MockClientManager mockManager;
  late UiaService uiaService;

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    mockChatBackup = MockChatBackupService();
    mockManager = MockClientManager();
    uiaService = UiaService(client: mockClient);

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockMatrix.uia).thenReturn(uiaService);
    when(mockMatrix.chatBackup).thenReturn(mockChatBackup);
    when(mockClient.userID).thenReturn('@alice:example.com');
    when(mockChatBackup.chatBackupNeeded).thenReturn(false);

    when(mockClient.uiaRequestBackground<IdServerUnbindResult>(any))
        .thenAnswer((inv) {
      final cb = inv.positionalArguments[0]
          as Future<IdServerUnbindResult> Function(AuthenticationData?);
      return cb(null);
    });
    when(mockClient.deactivateAccount(
      auth: anyNamed('auth'),
      erase: anyNamed('erase'),
      idServer: anyNamed('idServer'),
    )).thenAnswer((_) async => IdServerUnbindResult.success);
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => DeactivateAccountDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      builder: (context, child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
          ChangeNotifierProvider<ClientManager>.value(value: mockManager),
        ],
        child: child,
      ),
    );
  }

  group('DeactivateAccountDialog', () {
    testWidgets('shows irreversible warning and erase option', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Deactivate account'), findsOneWidget);
      expect(find.textContaining('permanently deactivates'), findsOneWidget);
      expect(find.text('Erase my content'), findsOneWidget);
      expect(find.text('Unbind third-party identifiers'), findsOneWidget);
      expect(find.text('Deactivate'), findsOneWidget);
    });

    testWidgets('hides identity server field until unbind is checked',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Identity server'), findsNothing);

      await tester.tap(find.text('Unbind third-party identifiers'));
      await tester.pumpAndSettle();

      expect(find.text('Identity server'), findsOneWidget);
    });

    testWidgets('calls deactivate then removes service on confirm',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      verify(mockClient.deactivateAccount(
        auth: null,
        erase: false,
        idServer: null,
      )).called(1);
      verify(mockManager.removeService(mockMatrix)).called(1);
    });

    testWidgets('sends erase and idServer when selected', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Erase my content'));
      await tester.tap(find.text('Unbind third-party identifiers'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Identity server').first,
        'https://vector.im',
      );

      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      verify(mockClient.deactivateAccount(
        auth: null,
        erase: true,
        idServer: 'https://vector.im',
      )).called(1);
      verify(mockManager.removeService(mockMatrix)).called(1);
    });

    testWidgets('cancel does not deactivate', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(mockClient.deactivateAccount(
        auth: anyNamed('auth'),
        erase: anyNamed('erase'),
        idServer: anyNamed('idServer'),
      ));
      verifyNever(mockManager.removeService(mockMatrix));
    });

    testWidgets('surfaces MatrixException as in-dialog error', (tester) async {
      when(mockClient.deactivateAccount(
        auth: anyNamed('auth'),
        erase: anyNamed('erase'),
        idServer: anyNamed('idServer'),
      )).thenThrow(MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Wrong password',
      }));

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Wrong password'), findsOneWidget);
      verifyNever(mockManager.removeService(mockMatrix));
    });
  });
}
