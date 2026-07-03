import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/models/kohera_read_receipt.dart';
import 'package:kohera/features/chat/services/read_receipt_resolver.dart';
import 'package:kohera/features/chat/widgets/read_receipts.dart';
import 'package:kohera/shared/models/kohera_user_summary_mapper.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<User>(),
  MockSpec<Client>(),
])
import 'read_receipts_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

class _NullAvatarResolver implements AvatarResolver {
  const _NullAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(String? mxcUrl, {required double size}) async => null;
}

MockUser _makeUser(String id, String? displayName, {Uri? avatarUrl}) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  when(user.calcDisplayname()).thenReturn(displayName ?? id);
  when(user.avatarUrl).thenReturn(avatarUrl);
  return user;
}

KoheraReadReceipt _receipt(MockUser user, DateTime time) =>
    KoheraReadReceipt(user: toKoheraUserSummary(user), time: time);

MockRoom _makeRoom({
  required Map<String, LatestReceiptStateData> globalOtherUsers,
  required Map<String, MockUser> userMap,
  Map<String, LatestReceiptStateData>? mainThreadOtherUsers,
  Map<String, Map<String, LatestReceiptStateData>>? byThreadOtherUsers,
}) {
  final room = MockRoom();

  final global = LatestReceiptStateForTimeline(
    ownPrivate: null,
    ownPublic: null,
    latestOwnReceipt: null,
    otherUsers: globalOtherUsers,
  );

  LatestReceiptStateForTimeline? mainThread;
  if (mainThreadOtherUsers != null) {
    mainThread = LatestReceiptStateForTimeline(
      ownPrivate: null,
      ownPublic: null,
      latestOwnReceipt: null,
      otherUsers: mainThreadOtherUsers,
    );
  }

  final byThread = <String, LatestReceiptStateForTimeline>{};
  if (byThreadOtherUsers != null) {
    for (final entry in byThreadOtherUsers.entries) {
      byThread[entry.key] = LatestReceiptStateForTimeline(
        ownPrivate: null,
        ownPublic: null,
        latestOwnReceipt: null,
        otherUsers: entry.value,
      );
    }
  }

  when(room.receiptState).thenReturn(
    LatestReceiptState(
      global: global,
      mainThread: mainThread,
      byThread: byThread,
    ),
  );

  for (final entry in userMap.entries) {
    when(room.unsafeGetUserFromMemoryOrFallback(entry.key)).thenReturn(entry.value);
  }

  return room;
}

Widget _wrapRow(List<KoheraReadReceipt> receipts, {bool isMe = true}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: Scaffold(
      body: ReadReceiptsRow(
        receipts: receipts,
        avatarResolver: const _NullAvatarResolver(),
        isMe: isMe,
      ),
    ),
  );
}

// ── Tests ────────────────────────────────────────────────────

void main() {
  group('buildReceiptMap', () {
    test('maps receipts by eventId and excludes own user', () {
      final alice = _makeUser('@alice:example.com', 'Alice');
      final bob = _makeUser('@bob:example.com', 'Bob');

      final room = _makeRoom(
        globalOtherUsers: {
          '@alice:example.com': LatestReceiptStateData(r'$evt1', 1000),
          '@bob:example.com': LatestReceiptStateData(r'$evt1', 2000),
          '@me:example.com': LatestReceiptStateData(r'$evt2', 3000),
        },
        userMap: {
          '@alice:example.com': alice,
          '@bob:example.com': bob,
          '@me:example.com': _makeUser('@me:example.com', 'Me'),
        },
      );

      final map = buildReceiptMap(room, '@me:example.com');

      expect(map.containsKey(r'$evt1'), isTrue);
      expect(map[r'$evt1']!.length, 2);
      expect(
        map[r'$evt1']!.map((r) => r.user.userId),
        containsAll(['@alice:example.com', '@bob:example.com']),
      );

      // Own user should not appear
      expect(
        map.values.expand((l) => l).any((r) => r.user.userId == '@me:example.com'),
        isFalse,
      );
    });

    test('includes mainThread receipts without duplicating users', () {
      final alice = _makeUser('@alice:example.com', 'Alice');

      final room = _makeRoom(
        globalOtherUsers: {
          '@alice:example.com': LatestReceiptStateData(r'$evt1', 1000),
        },
        mainThreadOtherUsers: {
          '@alice:example.com': LatestReceiptStateData(r'$evt2', 2000),
        },
        userMap: {
          '@alice:example.com': alice,
        },
      );

      final map = buildReceiptMap(room, '@me:example.com');

      // Alice should only appear once (from global, since it's processed first)
      final allReceipts = map.values.expand((l) => l).toList();
      expect(
        allReceipts.where((r) => r.user.userId == '@alice:example.com').length,
        1,
      );
    });

    test('threadRootId scopes receipts to byThread only', () {
      final alice = _makeUser('@alice:example.com', 'Alice');
      final bob = _makeUser('@bob:example.com', 'Bob');

      final room = _makeRoom(
        globalOtherUsers: {
          '@alice:example.com': LatestReceiptStateData(r'$global1', 1000),
        },
        mainThreadOtherUsers: {
          '@alice:example.com': LatestReceiptStateData(r'$main1', 1500),
        },
        byThreadOtherUsers: {
          r'$root': {
            '@bob:example.com': LatestReceiptStateData(r'$thread1', 2000),
          },
        },
        userMap: {
          '@alice:example.com': alice,
          '@bob:example.com': bob,
        },
      );

      final map = buildReceiptMap(
        room,
        '@me:example.com',
        threadRootId: r'$root',
      );

      expect(map.containsKey(r'$thread1'), isTrue);
      expect(map[r'$thread1']!.single.user.userId, '@bob:example.com');
      expect(map.containsKey(r'$global1'), isFalse);
      expect(map.containsKey(r'$main1'), isFalse);
    });

    test('threadRootId with no matching thread returns empty', () {
      final room = _makeRoom(
        globalOtherUsers: {
          '@alice:example.com': LatestReceiptStateData(r'$evt1', 1000),
        },
        userMap: {
          '@alice:example.com': _makeUser('@alice:example.com', 'Alice'),
        },
      );

      final map = buildReceiptMap(
        room,
        '@me:example.com',
        threadRootId: r'$missing',
      );

      expect(map, isEmpty);
    });

    test('returns empty map for room with no receipts', () {
      final room = _makeRoom(
        globalOtherUsers: {},
        userMap: {},
      );

      final map = buildReceiptMap(room, '@me:example.com');
      expect(map, isEmpty);
    });
  });

  group('ReadReceiptsRow', () {
    testWidgets('renders SizedBox.shrink for empty receipts', (tester) async {
      await tester.pumpWidget(_wrapRow([]));

      // Should find a SizedBox with zero dimensions (shrink)
      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 0);
      expect(sizedBox.height, 0);
    });

    testWidgets('renders correct number of avatars for 2 receipts', (tester) async {
      final receipts = [
        _receipt(
          _makeUser('@alice:example.com', 'Alice'),
          DateTime(2024, 1, 1, 12),
        ),
        _receipt(
          _makeUser('@bob:example.com', 'Bob'),
          DateTime(2024, 1, 1, 12, 5),
        ),
      ];

      await tester.pumpWidget(_wrapRow(receipts));
      await tester.pump();

      expect(find.byType(UserAvatar), findsNWidgets(2));
      // Should not show overflow badge
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('shows +N badge when more than 3 receipts', (tester) async {
      final receipts = List.generate(
        5,
        (i) => _receipt(
          _makeUser('@user$i:example.com', 'User $i'),
          DateTime(2024, 1, 1, 12, i),
        ),
      );

      await tester.pumpWidget(_wrapRow(receipts));
      await tester.pump();

      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('tap opens readers bottom sheet', (tester) async {
      final receipts = [
        _receipt(
          _makeUser('@alice:example.com', 'Alice'),
          DateTime(2024, 1, 1, 14, 30),
        ),
      ];

      await tester.pumpWidget(_wrapRow(receipts));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Bottom sheet should show "Read by 1"
      expect(find.text('Read by 1'), findsOneWidget);
      // Should show the user's name
      expect(find.text('Alice'), findsOneWidget);
      // Should show the time (locale-aware: US English default)
      expect(find.text('2:30 PM'), findsOneWidget);
    });

    testWidgets('bottom sheet shows multiple readers', (tester) async {
      final receipts = [
        _receipt(
          _makeUser('@alice:example.com', 'Alice'),
          DateTime(2024, 1, 1, 14, 30),
        ),
        _receipt(
          _makeUser('@bob:example.com', 'Bob'),
          DateTime(2024, 1, 1, 15, 45),
        ),
      ];

      await tester.pumpWidget(_wrapRow(receipts));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.text('Read by 2'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('hidden when readReceipts preference is disabled', (tester) async {
      SharedPreferences.setMockInitialValues({'read_receipts': false});
      final sp = await SharedPreferences.getInstance();
      final prefs = PreferencesService(prefs: sp);

      final receipts = [
        _receipt(
          _makeUser('@alice:example.com', 'Alice'),
          DateTime(2024, 1, 1, 14, 30),
        ),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesService>.value(
          value: prefs,
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final show = context.watch<PreferencesService>().readReceipts;
                  if (!show) return const SizedBox.shrink();
                  return ReadReceiptsRow(
                    receipts: receipts,
                    avatarResolver: const _NullAvatarResolver(),
                    isMe: true,
                  );
                },
              ),
            ),
          ),
        ),
      );

      // ReadReceiptsRow should not be rendered
      expect(find.byType(ReadReceiptsRow), findsNothing);
      expect(find.byType(UserAvatar), findsNothing);
    });

    testWidgets('falls back to user ID when displayName is null', (tester) async {
      final receipts = [
        _receipt(
          _makeUser('@anon:example.com', null),
          DateTime(2024, 1, 1, 10),
        ),
      ];

      await tester.pumpWidget(_wrapRow(receipts));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.text('@anon:example.com'), findsOneWidget);
    });
  });
}
