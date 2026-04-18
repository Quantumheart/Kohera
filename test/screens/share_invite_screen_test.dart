import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/settings/screens/share_invite_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.homeserver).thenReturn(Uri.parse('https://matrix.org'));
    matrixService = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
  });

  Widget buildApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
      ],
      child: const MaterialApp(home: ShareInviteScreen()),
    );
  }

  group('ShareInviteScreen', () {
    testWidgets('pre-fills homeserver from logged-in client', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(field.controller?.text, 'matrix.org');
    });

    testWidgets('outputs hidden until token entered', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Deep link'), findsNothing);
      expect(
        find.textContaining('Enter a homeserver and token'),
        findsOneWidget,
      );
    });

    testWidgets('entering token renders deep link + QR + HTML',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Registration token'),
        'abc123',
      );
      await tester.pumpAndSettle();

      expect(find.text('Deep link'), findsOneWidget);
      expect(find.text('QR code'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Landing-page HTML'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.text('Landing-page HTML'), findsOneWidget);
      expect(
        find.textContaining('kohera://register?server=matrix.org&token=abc123'),
        findsWidgets,
      );
    });

    testWidgets('copy button writes deep link to clipboard', (tester) async {
      String? copied;
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Registration token'),
        'abc123',
      );
      await tester.pumpAndSettle();

      final copyButton = find.widgetWithIcon(IconButton, Icons.copy).first;
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(copied, 'kohera://register?server=matrix.org&token=abc123');
      expect(find.text('Link copied to clipboard'), findsOneWidget);
    });

    testWidgets('URL-encodes special characters in token', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Registration token'),
        'abc xyz',
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('token=abc+xyz'),
        findsWidgets,
      );
    });
  });
}
