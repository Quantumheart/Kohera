import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/state/key_backup_setup_state.dart';
import 'package:kohera/data/repositories/key_backup_repository.dart';
import 'package:kohera/features/e2ee/widgets/key_backup_banner.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<KeyBackupRepository>(),
  MockSpec<KeyBackupSetupState>(),
])
import 'key_backup_banner_test.mocks.dart';

void main() {
  late MockKeyBackupRepository mockKeyBackup;
  late MockKeyBackupSetupState mockSetup;

  setUp(() {
    mockKeyBackup = MockKeyBackupRepository();
    mockSetup = MockKeyBackupSetupState();
    when(mockSetup.bannerDismissed).thenReturn(false);
  });

  Widget buildTestWidget({
    required KeyBackupRepository repo,
    required KeyBackupSetupState setup,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyBackupRepository>.value(value: repo),
          ChangeNotifierProvider<KeyBackupSetupState>.value(value: setup),
        ],
        child: const Scaffold(body: KeyBackupBanner()),
      ),
    );
  }

  group('KeyBackupBanner', () {
    testWidgets('hidden when chatBackupNeeded is null', (tester) async {
      when(mockKeyBackup.chatBackupNeeded).thenReturn(null);
      await tester.pumpWidget(
        buildTestWidget(repo: mockKeyBackup, setup: mockSetup),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);
    });

    testWidgets('visible when chatBackupNeeded is true', (tester) async {
      when(mockKeyBackup.chatBackupNeeded).thenReturn(true);
      await tester.pumpWidget(
        buildTestWidget(repo: mockKeyBackup, setup: mockSetup),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsOneWidget);
      expect(
        find.text(
          'Without key backup, you may lose message history '
          'and some features will not work',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Set up'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byIcon(Icons.shield_outlined),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });

    testWidgets('hidden when chatBackupNeeded is false', (tester) async {
      when(mockKeyBackup.chatBackupNeeded).thenReturn(false);
      await tester.pumpWidget(
        buildTestWidget(repo: mockKeyBackup, setup: mockSetup),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);
    });

    testWidgets('disappears when backup status changes to enabled',
        (tester) async {
      final fake = _FakeKeyBackup(chatBackupNeeded: true);
      await tester.pumpWidget(
        buildTestWidget(repo: fake, setup: _FakeSetupState()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsOneWidget);

      fake.chatBackupNeeded = false;
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);
    });

    testWidgets('hidden when needed but already dismissed', (tester) async {
      when(mockKeyBackup.chatBackupNeeded).thenReturn(true);
      when(mockSetup.bannerDismissed).thenReturn(true);
      await tester.pumpWidget(
        buildTestWidget(repo: mockKeyBackup, setup: mockSetup),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);
    });

    testWidgets('dismiss button hides the banner', (tester) async {
      final fakeSetup = _FakeSetupState();
      await tester.pumpWidget(
        buildTestWidget(
          repo: _FakeKeyBackup(chatBackupNeeded: true),
          setup: fakeSetup,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);
      expect(fakeSetup.bannerDismissed, isTrue);
    });

    testWidgets('appears when backup status changes to needed',
        (tester) async {
      final fake = _FakeKeyBackup(chatBackupNeeded: false);
      await tester.pumpWidget(
        buildTestWidget(repo: fake, setup: _FakeSetupState()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);

      fake.chatBackupNeeded = true;
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsOneWidget);
    });

    testWidgets('content wrapped in SafeArea to avoid status-bar overlap',
        (tester) async {
      when(mockKeyBackup.chatBackupNeeded).thenReturn(true);
      await tester.pumpWidget(
        buildTestWidget(repo: mockKeyBackup, setup: mockSetup),
      );
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.byIcon(Icons.shield_outlined),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
    });
  });
}

class _FakeKeyBackup extends ChangeNotifier implements KeyBackupRepository {
  _FakeKeyBackup({required bool? chatBackupNeeded})
      : _chatBackupNeeded = chatBackupNeeded;

  bool? _chatBackupNeeded;

  @override
  bool? get chatBackupNeeded => _chatBackupNeeded;
  set chatBackupNeeded(bool? value) {
    _chatBackupNeeded = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSetupState extends ChangeNotifier implements KeyBackupSetupState {
  _FakeSetupState({bool bannerDismissed = false})
      : _bannerDismissed = bannerDismissed;

  bool _bannerDismissed;

  @override
  bool get bannerDismissed => _bannerDismissed;

  @override
  Future<void> dismissBanner() async {
    _bannerDismissed = true;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
