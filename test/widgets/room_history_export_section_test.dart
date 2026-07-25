import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/models/kohera_export_format.dart';
import 'package:kohera/features/rooms/models/kohera_room_export.dart';
import 'package:kohera/features/rooms/services/room_history_exporter.dart';
import 'package:kohera/features/rooms/widgets/room_history_export_section.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
])
import 'room_history_export_section_test.mocks.dart';

KoheraRoomExport _sample() => KoheraRoomExport(
      meta: const KoheraExportRoomMeta(
        roomId: '!room:example.com',
        displayname: 'Test Room',
        canonicalAlias: '#room:example.com',
        topic: 'topic',
      ),
      messages: [
        KoheraExportedMessage(
          eventId: r'$1:example.com',
          senderId: '@a:example.com',
          senderDisplayname: 'Alice',
          timestamp: DateTime.utc(2024),
          messageType: 'm.text',
          body: 'hi',
        ),
      ],
      options: const KoheraExportOptions(),
    );

class _FakeExporter extends RoomHistoryExporter {
  _FakeExporter(this.result) : super(matrix: _DummyMatrix());
  final KoheraRoomExport result;

  @override
  Future<KoheraRoomExport> export({
    required String roomId,
    required KoheraExportOptions options,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    onProgress?.call(result.messages.length, null);
    return KoheraRoomExport(
      meta: result.meta,
      messages: result.messages,
      options: options,
    );
  }
}

class _DummyMatrix implements MatrixService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;
  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.userID).thenReturn('@me:example.com');
    selectionService = SelectionService(client: mockClient);
    when(mockMatrix.selection).thenReturn(selectionService);
    when(mockMatrix.avatarResolver).thenReturn(const _NullAvatarResolver());
  });

  Widget buildTestWidget(RoomHistoryExportSection child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
          ChangeNotifierProvider<SelectionService>.value(value: selectionService),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  RoomHistoryExportSection section({
    required KoheraRoomExport result,
    String? savedPath,
  }) =>
      RoomHistoryExportSection(
        roomId: '!room:example.com',
        roomDisplayname: 'Test Room',
        exporter: _FakeExporter(result),
        onSaveFile: (_, _) async => savedPath,
        onWriteFile: (_, _) async {},
      );

  testWidgets('renders format chips and export button', (tester) async {
    await tester.pumpWidget(buildTestWidget(section(result: _sample())));
    await tester.pumpAndSettle();
    expect(find.text('EXPORT'), findsOneWidget);
    expect(find.text('JSON'), findsOneWidget);
    expect(find.text('HTML'), findsOneWidget);
    expect(find.text('Plaintext'), findsOneWidget);
    expect(find.text('Export history'), findsOneWidget);
  });

  testWidgets('default range label is All history', (tester) async {
    await tester.pumpWidget(buildTestWidget(section(result: _sample())));
    await tester.pumpAndSettle();
    expect(find.text('All history'), findsOneWidget);
  });

  testWidgets('toggling media switch updates state', (tester) async {
    await tester.pumpWidget(buildTestWidget(section(result: _sample())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Include media references'));
    await tester.pumpAndSettle();
    final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(sw.value, isTrue);
  });

  testWidgets('switching format updates selection', (tester) async {
    await tester.pumpWidget(buildTestWidget(section(result: _sample())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTML'));
    await tester.pumpAndSettle();
    final htmlChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('HTML'), matching: find.byType(ChoiceChip)),
    );
    expect(htmlChip.selected, isTrue);
  });

  testWidgets('export with saved path shows success', (tester) async {
    await tester.pumpWidget(
        buildTestWidget(section(result: _sample(), savedPath: '/tmp/out.json')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export history'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Exported 1 messages'), findsWidgets);
  });

  testWidgets('export without saved path shows no success', (tester) async {
    await tester.pumpWidget(
        buildTestWidget(section(result: _sample())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export history'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Exported 1 messages'), findsNothing);
  });
}

class _NullAvatarResolver implements AvatarResolver {
  const _NullAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(String? mxc,
      {required double size}) async => null;
}
