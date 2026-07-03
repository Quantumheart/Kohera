import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/shared/widgets/avatar_edit_overlay.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';

KoheraRoomSummary _summary({String? avatarUrl}) => KoheraRoomSummary(
      roomId: '!room:example.com',
      displayname: 'Test Room',
      avatarUrl: avatarUrl,
      isDirectChat: false,
      isEncrypted: false,
      isSpace: false,
      notificationCount: 0,
      highlightCount: 0,
      typingDisplayNames: const [],
      pinnedEventIds: const [],
      spaceChildCount: 0,
      isFavourite: false,
      lastEventPreview: '',
      lastEventIsThreadReply: false,
    );

void main() {
  Widget buildTestWidget({
    required bool canEditAvatar,
    required Future<void> Function(Uint8List? bytes, String? filename)
        onSetAvatar,
    String? avatarUrl,
    double size = 72,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: AvatarEditOverlay(
          roomId: '!room:example.com',
          summary: _summary(avatarUrl: avatarUrl),
          canEditAvatar: canEditAvatar,
          avatarResolver: null,
          onSetAvatar: onSetAvatar,
          size: size,
        ),
      ),
    );
  }

  Future<void> noopSet(Uint8List? bytes, String? filename) async {}

  group('AvatarEditOverlay', () {
    testWidgets('renders plain RoomAvatarWidget when user lacks permission',
        (tester) async {
      await tester.pumpWidget(
        buildTestWidget(canEditAvatar: false, onSetAvatar: noopSet),
      );
      await tester.pump();

      expect(find.byType(RoomAvatarWidget), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('shows edit overlay when user has permission', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(canEditAvatar: true, onSetAvatar: noopSet),
      );
      await tester.pump();

      expect(find.byType(RoomAvatarWidget), findsOneWidget);
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('shows remove badge when avatar exists', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          canEditAvatar: true,
          avatarUrl: 'mxc://example.com/avatar',
          onSetAvatar: noopSet,
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('hides remove badge when no avatar', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(canEditAvatar: true, onSetAvatar: noopSet),
      );
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('calls onSetAvatar(null, null) on remove tap', (tester) async {
      Uint8List? capturedBytes;
      String? capturedFilename;
      await tester.pumpWidget(
        buildTestWidget(
          canEditAvatar: true,
          avatarUrl: 'mxc://example.com/avatar',
          onSetAvatar: (bytes, filename) async {
            capturedBytes = bytes;
            capturedFilename = filename;
          },
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(capturedBytes, isNull);
      expect(capturedFilename, isNull);
    });
  });
}
