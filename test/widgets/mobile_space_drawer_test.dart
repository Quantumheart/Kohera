import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/home/widgets/mobile_space_drawer.dart';
import 'package:matrix/matrix.dart' show Client, SyncUpdate;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
])
import 'mobile_space_drawer_test.mocks.dart';

class _FakeMatrixService extends ChangeNotifier implements MatrixService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  late MockClient mockClient;
  late _FakeMatrixService fakeMatrix;
  late SelectionService selection;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync)
        .thenReturn(CachedStreamController<SyncUpdate>());
    fakeMatrix = _FakeMatrixService();
    selection = SelectionService(client: mockClient);
  });

  tearDown(() {
    fakeMatrix.dispose();
    selection.dispose();
  });

  Widget buildTestWidget() {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          name: Routes.home,
          builder: (_, __) => Scaffold(
            drawer: const MobileSpaceDrawer(),
            body: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          ),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: fakeMatrix),
        ChangeNotifierProvider<SelectionService>.value(value: selection),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  group('MobileSpaceDrawer', () {
    testWidgets('renders Home and action tiles with no spaces',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Create space'), findsOneWidget);
      expect(find.text('Join space'), findsOneWidget);
    });

    testWidgets('Home tile tap clears space selection', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(selection.selectedSpaceIds, isEmpty);
    });
  });
}
