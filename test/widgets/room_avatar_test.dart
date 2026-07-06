import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/pixel_sprite_avatar.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';

class _NullAvatarResolver implements AvatarResolver {
  const _NullAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(String? mxcUrl, {required double size}) async => null;
}

void main() {
  const avatarResolver = _NullAvatarResolver();

  Widget buildTestWidget({
    String? avatarUrl,
    String displayname = 'General',
    double size = 44,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: RoomAvatarWidget(
          avatarUrl: avatarUrl,
          displayname: displayname,
          avatarResolver: avatarResolver,
          size: size,
        ),
      ),
    );
  }

  group('RoomAvatarWidget', () {
    testWidgets('shows pixel sprite fallback when no avatar', (tester) async {
      await tester.pumpWidget(buildTestWidget(displayname: 'Random'));
      await tester.pump();

      expect(find.byType(PixelSpriteAvatar), findsOneWidget);
    });

    testWidgets('shows pixel sprite fallback for empty display name',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(displayname: ''));
      await tester.pump();

      expect(find.byType(PixelSpriteAvatar), findsOneWidget);
    });

    testWidgets('renders at correct size', (tester) async {
      await tester.pumpWidget(buildTestWidget(size: 64));
      await tester.pump();

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 64);
      expect(sizedBox.height, 64);
    });

    testWidgets('uses ClipRRect for rounded shape', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(ClipRRect), findsOneWidget);
    });
  });
}
