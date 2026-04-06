import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/e2ee/widgets/key_backup_banner.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([MockSpec<MatrixService>()])
import 'key_backup_banner_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;

  setUp(() {
    mockMatrix = MockMatrixService();
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: ChangeNotifierProvider<MatrixService>.value(
        value: mockMatrix,
        child: const Scaffold(body: KeyBackupBanner()),
      ),
    );
  }

  group('KeyBackupBanner', () {
    testWidgets('hidden when chatBackupNeeded is null', (tester) async {
      when(mockMatrix.chatBackupNeeded).thenReturn(null);
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Protect your messages'), findsNothing);
    });

    testWidgets('visible when chatBackupNeeded is true', (tester) async {
      when(mockMatrix.chatBackupNeeded).thenReturn(true);
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Protect your messages'), findsOneWidget);
      expect(
        find.text('Set up key backup to keep your encrypted messages safe'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Set up'), findsOneWidget);
    });

    testWidgets('hidden when chatBackupNeeded is false', (tester) async {
      when(mockMatrix.chatBackupNeeded).thenReturn(false);
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Protect your messages'), findsNothing);
    });

    testWidgets('disappears when backup status changes to enabled',
        (tester) async {
      final fake = _FakeMatrixService(chatBackupNeeded: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MatrixService>.value(
            value: fake,
            child: const Scaffold(body: KeyBackupBanner()),
          ),
        ),
      );

      expect(find.text('Protect your messages'), findsOneWidget);

      fake.chatBackupNeeded = false;
      await tester.pump();

      expect(find.text('Protect your messages'), findsNothing);
    });
  });
}

class _FakeMatrixService extends ChangeNotifier implements MatrixService {
  bool? _chatBackupNeeded;

  _FakeMatrixService({required bool? chatBackupNeeded})
      : _chatBackupNeeded = chatBackupNeeded;

  @override
  bool? get chatBackupNeeded => _chatBackupNeeded;
  set chatBackupNeeded(bool? value) {
    _chatBackupNeeded = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
