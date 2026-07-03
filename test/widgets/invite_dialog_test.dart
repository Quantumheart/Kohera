import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/features/rooms/widgets/invite_dialog.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([MockSpec<MatrixService>()])
import 'invite_dialog_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;

  setUp(() {
    mockMatrix = MockMatrixService();
    when(mockMatrix.avatarResolver).thenReturn(const _NullAvatarResolver());
  });

  KoheraRoomSummary makeSummary({
    String displayname = 'Test Room',
    bool isSpace = false,
  }) =>
      KoheraRoomSummary(
        roomId: '!room:example.com',
        displayname: displayname,
        isDirectChat: false,
        isEncrypted: false,
        isSpace: isSpace,
        notificationCount: 0,
        highlightCount: 0,
        typingDisplayNames: const [],
        pinnedEventIds: const [],
        spaceChildCount: 0,
        isFavourite: false,
        lastEventPreview: '',
        lastEventIsThreadReply: false,
      );

  Widget buildTestWidget({
    required KoheraRoomSummary summary,
    required Future<void> Function() onAccept,
    required Future<void> Function() onDecline,
    String? inviterName = 'Alice',
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => InviteDialog.show(
                  context,
                  roomId: summary.roomId,
                  summary: summary,
                  inviterName: inviterName,
                  onAccept: onAccept,
                  onDecline: onDecline,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    required KoheraRoomSummary summary,
    required Future<void> Function() onAccept,
    required Future<void> Function() onDecline,
    String? inviterName = 'Alice',
  }) async {
    await tester.pumpWidget(
      buildTestWidget(
        summary: summary,
        inviterName: inviterName,
        onAccept: onAccept,
        onDecline: onDecline,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('InviteDialog', () {
    testWidgets('shows room name and inviter', (tester) async {
      await openDialog(
        tester,
        summary: makeSummary(),
        onAccept: () async {},
        onDecline: () async {},
      );

      expect(find.text('Room invite'), findsOneWidget);
      expect(find.text('Test Room'), findsOneWidget);
      expect(find.text('Invited by Alice'), findsOneWidget);
    });

    testWidgets('shows "Space invite" title for spaces', (tester) async {
      await openDialog(
        tester,
        summary: makeSummary(isSpace: true),
        onAccept: () async {},
        onDecline: () async {},
      );

      expect(find.text('Space invite'), findsOneWidget);
    });

    testWidgets('accept calls onAccept and closes dialog', (tester) async {
      var accepted = false;
      await openDialog(
        tester,
        summary: makeSummary(),
        onAccept: () async {
          accepted = true;
        },
        onDecline: () async {},
      );

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(accepted, isTrue);
      expect(find.text('Room invite'), findsNothing);
    });

    testWidgets('accept shows error on failure', (tester) async {
      await openDialog(
        tester,
        summary: makeSummary(),
        onAccept: () async => throw Exception('Server error'),
        onDecline: () async {},
      );

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(find.text('Room invite'), findsOneWidget);
      expect(find.textContaining('Server error'), findsOneWidget);
    });

    testWidgets('decline shows confirmation then calls onDecline',
        (tester) async {
      var declined = false;
      await openDialog(
        tester,
        summary: makeSummary(),
        onAccept: () async {},
        onDecline: () async {
          declined = true;
        },
      );

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      expect(find.text('Decline invite'), findsOneWidget);
      expect(find.text('Decline invite to Test Room?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await tester.pumpAndSettle();

      expect(declined, isTrue);
      expect(find.text('Room invite'), findsNothing);
    });

    testWidgets('decline cancellation keeps dialog open', (tester) async {
      var declined = false;
      await openDialog(
        tester,
        summary: makeSummary(),
        onAccept: () async {},
        onDecline: () async {
          declined = true;
        },
      );

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Room invite'), findsOneWidget);
      expect(declined, isFalse);
    });

    testWidgets('decline shows error on failure', (tester) async {
      await openDialog(
        tester,
        summary: makeSummary(),
        onAccept: () async {},
        onDecline: () async => throw Exception('Network error'),
      );

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await tester.pumpAndSettle();

      expect(find.text('Room invite'), findsOneWidget);
      expect(find.textContaining('Network error'), findsOneWidget);
    });

    testWidgets('buttons are disabled during accept', (tester) async {
      final completer = Completer<void>();
      await openDialog(
        tester,
        summary: makeSummary(),
        onAccept: () => completer.future,
        onDecline: () async {},
      );

      await tester.tap(find.text('Accept'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final declineButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Decline'),
      );
      expect(declineButton.onPressed, isNull);

      completer.complete();
      await tester.pumpAndSettle();
    });
  });
}

class _NullAvatarResolver implements AvatarResolver {
  const _NullAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(String? mxc, {required double size}) async =>
      null;
}
