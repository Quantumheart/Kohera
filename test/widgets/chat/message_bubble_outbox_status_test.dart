import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/outbox_service.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/message_bubble_outbox_status.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'message_bubble_outbox_status_test.mocks.dart';
@GenerateNiceMocks([
  MockSpec<Client>(),
])
class _StubOutbox extends OutboxService {
  _StubOutbox(this._entries, MockClient client)
      : super(client: client, clientName: 'test');

  final Map<String, OutboxEntryView> _entries;

  @override
  Map<String, OutboxEntryView> get entries => _entries;

  @override
  Future<void> start() async {}
}

OutboxEntryView _entry({
  required String txid,
  int attempts = 0,
  bool failed = false,
}) =>
    OutboxEntryView(
      txid: txid,
      roomId: '!r:s',
      attempts: attempts,
      nextRetryAt: DateTime.now().add(const Duration(seconds: 4)),
      finalFailed: failed,
    );

Widget _harness({
  required OutboxService outbox,
  required KoheraMessageStatus status,
  String? txid,
  String eventId = r'$evt',
}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: ChangeNotifierProvider<OutboxService>.value(
      value: outbox,
      child: Scaffold(
        body: Center(
          child: MessageBubbleOutboxStatus(
            eventId: eventId,
            transactionId: txid,
            status: status,
            metrics: DensityMetrics.of(MessageDensity.defaultDensity),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockClient client;

  setUp(() {
    client = MockClient();
    when(client.rooms).thenReturn([]);
  });

  testWidgets('synced event shows done_all icon', (tester) async {
    final outbox = _StubOutbox({}, client);
    await tester.pumpWidget(
      _harness(
        outbox: outbox,
        status: KoheraMessageStatus.sent,
      ),
    );
    expect(find.byIcon(KIcons.doneAllRounded), findsOneWidget);
  });

  testWidgets('sending event with no outbox entry shows schedule',
      (tester) async {
    final outbox = _StubOutbox({}, client);
    await tester.pumpWidget(
      _harness(
        outbox: outbox,
        status: KoheraMessageStatus.sending,
        txid: 'tx',
      ),
    );
    expect(find.byIcon(KIcons.scheduleRounded), findsOneWidget);
  });

  testWidgets('retrying entry shows schedule with tooltip', (tester) async {
    final outbox = _StubOutbox(
      {'tx': _entry(txid: 'tx', attempts: 2)},
      client,
    );
    await tester.pumpWidget(
      _harness(
        outbox: outbox,
        status: KoheraMessageStatus.error,
        txid: 'tx',
      ),
    );
    expect(find.byIcon(KIcons.scheduleRounded), findsOneWidget);
    expect(find.byTooltip, isNotNull);
  });

  testWidgets('final-failed entry shows error_outline indicator',
      (tester) async {
    final outbox = _StubOutbox(
      {'tx': _entry(txid: 'tx', attempts: 8, failed: true)},
      client,
    );
    await tester.pumpWidget(
      _harness(
        outbox: outbox,
        status: KoheraMessageStatus.error,
        txid: 'tx',
      ),
    );
    expect(find.byIcon(KIcons.errorOutlineRounded), findsOneWidget);
  });

  test('debugPhaseFor classification matrix', () {
    expect(
      debugPhaseFor(null, KoheraMessageStatus.sent, r'$evt', null),
      'sent',
    );
    expect(
      debugPhaseFor(null, KoheraMessageStatus.sending, r'$evt', null),
      'sending',
    );
    expect(
      debugPhaseFor(null, KoheraMessageStatus.error, r'$evt', null),
      'sending',
    );
    expect(
      debugPhaseFor(
        _entry(txid: 'x'),
        KoheraMessageStatus.error,
        r'$evt',
        null,
      ),
      'sending',
    );
    expect(
      debugPhaseFor(
        _entry(txid: 'x', attempts: 1),
        KoheraMessageStatus.error,
        r'$evt',
        null,
      ),
      'retrying',
    );
    expect(
      debugPhaseFor(
        _entry(txid: 'x', attempts: 8, failed: true),
        KoheraMessageStatus.error,
        r'$evt',
        null,
      ),
      'failed',
    );
  });
}
