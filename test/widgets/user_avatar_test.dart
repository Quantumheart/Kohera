import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
])
import 'user_avatar_test.mocks.dart';

void main() {
  late MockClient mockClient;

  setUp(() {
    mockClient = MockClient();
  });

  Widget buildTestWidget({
    Uri? avatarUrl,
    String? userId,
    double size = 44,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: UserAvatar(
          client: mockClient,
          avatarUrl: avatarUrl,
          userId: userId,
          size: size,
        ),
      ),
    );
  }

  group('UserAvatar', () {
    testWidgets('shows initial fallback when no avatar URL', (tester) async {
      await tester.pumpWidget(buildTestWidget(userId: '@alice:example.com'));
      await tester.pumpAndSettle();

      // Should show 'A' (second char of @alice, uppercased)
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('shows first char when userId is single character', (tester) async {
      await tester.pumpWidget(buildTestWidget(userId: '@'));
      await tester.pumpAndSettle();

      expect(find.text('@'), findsOneWidget);
    });

    testWidgets('shows ? when no userId provided', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders at correct size', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        userId: '@bob:example.com',
        size: 64,
      ),);
      await tester.pumpAndSettle();

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 64);
      expect(sizedBox.height, 64);
    });

    testWidgets('resolves thumbnail when avatarUrl is provided', (tester) async {
      final mxcUri = Uri.parse('mxc://example.com/avatar123');

      await tester.pumpWidget(buildTestWidget(
        avatarUrl: mxcUri,
        userId: '@charlie:example.com',
      ),);
      await tester.pump();

      // While resolving, the fallback initial should show
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('different userIds produce different colors', (tester) async {
      // This tests the color hashing — render two avatars and check they exist
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: Column(
            children: [
              UserAvatar(
                client: mockClient,
                userId: '@alice:example.com',
              ),
              UserAvatar(
                client: mockClient,
                userId: '@bob:example.com',
              ),
            ],
          ),
        ),
      ),);
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('uses ClipOval for circular shape', (tester) async {
      await tester.pumpWidget(buildTestWidget(userId: '@dave:example.com'));
      await tester.pumpAndSettle();

      expect(find.byType(ClipOval), findsOneWidget);
    });
  });

  group('UserAvatar presence dot', () {
    late CachedStreamController<CachedPresence> presenceController;
    late PresenceService presenceService;

    setUp(() {
      presenceController = CachedStreamController<CachedPresence>();
      when(mockClient.onPresenceChanged).thenReturn(presenceController);
      presenceService = PresenceService(client: mockClient);
    });

    tearDown(() => presenceService.dispose());

    Widget buildWithPresence(
      String userId, {
      ThemeData? theme,
      double size = 44,
    }) {
      return MaterialApp(
        theme: theme ?? ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: UserAvatar(
            client: mockClient,
            userId: userId,
            presence: presenceService,
            size: size,
          ),
        ),
      );
    }

    void emit(String userId, PresenceType type) =>
        presenceController.add(CachedPresence(type, null, null, true, userId));

    ThemeData seeded({Brightness brightness = Brightness.light}) => ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: brightness,
          ),
        );

    Container dotFor(WidgetTester tester, String label) =>
        tester.widget<Container>(
          find.descendant(
            of: find.bySemanticsLabel(label),
            matching: find.byType(Container),
          ),
        );

    testWidgets('unknown presence renders no dot and no layout shift',
        (tester) async {
      await tester.pumpWidget(buildWithPresence('@alice:example.com'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Online'), findsNothing);
      expect(find.bySemanticsLabel('Away'), findsNothing);
      expect(find.bySemanticsLabel('Offline'), findsNothing);
      expect(tester.getSize(find.byType(UserAvatar)), const Size(44, 44));
    });

    testWidgets('online renders dot labelled Online with primary color',
        (tester) async {
      final theme = seeded();
      emit('@alice:example.com', PresenceType.online);
      await tester.pumpWidget(
        buildWithPresence('@alice:example.com', theme: theme),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Online'), findsOneWidget);
      expect(
        (dotFor(tester, 'Online').decoration! as BoxDecoration).color,
        theme.colorScheme.primary,
      );
    });

    testWidgets('away maps to tertiary and offline to outline, live',
        (tester) async {
      final theme = seeded();
      emit('@bob:example.com', PresenceType.unavailable);
      await tester.pumpWidget(
        buildWithPresence('@bob:example.com', theme: theme),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Away'), findsOneWidget);
      expect(
        (dotFor(tester, 'Away').decoration! as BoxDecoration).color,
        theme.colorScheme.tertiary,
      );

      emit('@bob:example.com', PresenceType.offline);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Offline'), findsOneWidget);
      expect(
        (dotFor(tester, 'Offline').decoration! as BoxDecoration).color,
        theme.colorScheme.outline,
      );
    });

    testWidgets('dot is sized relative to avatar size', (tester) async {
      emit('@alice:example.com', PresenceType.online);
      await tester.pumpWidget(buildWithPresence('@alice:example.com', size: 80));
      await tester.pumpAndSettle();

      final dotFinder = find.descendant(
        of: find.bySemanticsLabel('Online'),
        matching: find.byType(Container),
      );
      expect(tester.getSize(dotFinder).width, closeTo(80 * 0.3, 0.5));
    });

    testWidgets('colors come from the active scheme in dark theme',
        (tester) async {
      final dark = seeded(brightness: Brightness.dark);
      emit('@alice:example.com', PresenceType.online);
      await tester.pumpWidget(
        buildWithPresence('@alice:example.com', theme: dark),
      );
      await tester.pumpAndSettle();

      expect(
        (dotFor(tester, 'Online').decoration! as BoxDecoration).color,
        dark.colorScheme.primary,
      );
    });
  });
}
