import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/outbox_service.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/message_bubble_outbox_status.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'message_bubble_outbox_status_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<Client>(),
  MockSpec<Room>(),
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

Event _event({
  required EventStatus status,
  String? txid,
  String eventId = r'$evt',
}) {
  final ev = MockEvent();
  when(ev.status).thenReturn(status);
  when(ev.transactionId).thenReturn(txid);
  when(ev.eventId).thenReturn(eventId);
  when(ev.originServerTs).thenReturn(DateTime.now());
  return ev;
}

Widget _harness({
  required OutboxService outbox,
  required Event event,
}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: ChangeNotifierProvider<OutboxService>.value(
      value: outbox,
      child: Scaffold(
        body: Center(
          child: MessageBubbleOutboxStatus(
            event: event,
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
    final event = _event(status: EventStatus.synced);
    await tester.pumpWidget(_harness(outbox: outbox, event: event));
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });

  testWidgets('sending event with no outbox entry shows schedule', (tester) async {
    final outbox = _StubOutbox({}, client);
    final event = _event(status: EventStatus.sending, txid: 'tx');
    await tester.pumpWidget(_harness(outbox: outbox, event: event));
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
  });

  testWidgets('retrying entry shows schedule with tooltip', (tester) async {
    final outbox = _StubOutbox(
      {'tx': _entry(txid: 'tx', attempts: 2)},
      client,
    );
    final event = _event(status: EventStatus.error, txid: 'tx');
    await tester.pumpWidget(_harness(outbox: outbox, event: event));
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byTooltip, isNotNull);
  });

  testWidgets('final-failed entry shows error_outline indicator', (tester) async {
    final outbox = _StubOutbox(
      {'tx': _entry(txid: 'tx', attempts: 8, failed: true)},
      client,
    );
    final event = _event(status: EventStatus.error, txid: 'tx');
    await tester.pumpWidget(_harness(outbox: outbox, event: event));
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  test('debugPhaseFor classification matrix', () {
    Event ev(EventStatus s) {
      final e = MockEvent();
      when(e.status).thenReturn(s);
      return e;
    }

    expect(debugPhaseFor(null, ev(EventStatus.synced)), 'sent');
    expect(debugPhaseFor(null, ev(EventStatus.sent)), 'sent');
    expect(debugPhaseFor(null, ev(EventStatus.sending)), 'sending');
    expect(debugPhaseFor(null, ev(EventStatus.error)), 'sending');
    expect(
      debugPhaseFor(_entry(txid: 'x'), ev(EventStatus.error)),
      'sending',
    );
    expect(
      debugPhaseFor(_entry(txid: 'x', attempts: 1), ev(EventStatus.error)),
      'retrying',
    );
    expect(
      debugPhaseFor(
        _entry(txid: 'x', attempts: 8, failed: true),
        ev(EventStatus.error),
      ),
      'failed',
    );
  });
}
