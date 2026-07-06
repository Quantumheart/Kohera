import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/call_push_rule_manager.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>()])
import 'call_push_rule_manager_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late CallPushRuleManager manager;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.userID).thenReturn('@alice:example.com');
    manager = CallPushRuleManager(client: mockClient);
  });

  PushRule makeDesiredRule() => PushRule(
        ruleId: 'io.kohera.call_member',
        default$: false,
        enabled: true,
        conditions: [
          PushCondition(
            kind: 'event_match',
            key: 'type',
            pattern: 'org.matrix.msc3401.call.member',
          ),
          PushCondition(kind: 'room_member_count', is$: '2'),
        ],
        actions: [
          'notify',
          {'set_tweak': 'sound', 'value': 'ring'},
          {'set_tweak': 'highlight', 'value': false},
        ],
      );

  test('writes rule restricted to 1:1 rooms when missing', () async {
    when(mockClient.getPushRules())
        .thenAnswer((_) async => PushRuleSet(override: []));
    when(
      mockClient.setPushRule(
        any,
        any,
        any,
        before: anyNamed('before'),
        after: anyNamed('after'),
        conditions: anyNamed('conditions'),
        pattern: anyNamed('pattern'),
      ),
    ).thenAnswer((_) async {});

    await manager.ensureRule();

    final captured = verify(
      mockClient.setPushRule(
        PushRuleKind.override,
        'io.kohera.call_member',
        any,
        conditions: captureAnyNamed('conditions'),
      ),
    ).captured;
    final conditions = captured.single as List<PushCondition>;
    expect(
      conditions.any(
        (c) => c.kind == 'event_match' &&
            c.key == 'type' &&
            c.pattern == 'org.matrix.msc3401.call.member',
      ),
      isTrue,
    );
    expect(
      conditions.any((c) => c.kind == 'room_member_count' && c.is$ == '2'),
      isTrue,
    );
  });

  test('no write when rule already present with matching actions', () async {
    when(mockClient.getPushRules())
        .thenAnswer((_) async => PushRuleSet(override: [makeDesiredRule()]));

    await manager.ensureRule();

    verifyNever(
      mockClient.setPushRule(
        any,
        any,
        any,
        before: anyNamed('before'),
        after: anyNamed('after'),
        conditions: anyNamed('conditions'),
        pattern: anyNamed('pattern'),
      ),
    );
  });

  test('rewrites rule when actions differ', () async {
    final stale = PushRule(
      ruleId: 'io.kohera.call_member',
      default$: false,
      enabled: true,
      actions: ['dont_notify'],
    );
    when(mockClient.getPushRules())
        .thenAnswer((_) async => PushRuleSet(override: [stale]));
    when(
      mockClient.setPushRule(
        any,
        any,
        any,
        before: anyNamed('before'),
        after: anyNamed('after'),
        conditions: anyNamed('conditions'),
        pattern: anyNamed('pattern'),
      ),
    ).thenAnswer((_) async {});

    await manager.ensureRule();

    verify(
      mockClient.setPushRule(
        PushRuleKind.override,
        'io.kohera.call_member',
        any,
        conditions: anyNamed('conditions'),
      ),
    ).called(1);
  });

  test('rewrites legacy rule that lacks the room_member_count condition',
      () async {
    final legacy = PushRule(
      ruleId: 'io.kohera.call_member',
      default$: false,
      enabled: true,
      conditions: [
        PushCondition(
          kind: 'event_match',
          key: 'type',
          pattern: 'org.matrix.msc3401.call.member',
        ),
      ],
      actions: [
        'notify',
        {'set_tweak': 'sound', 'value': 'ring'},
        {'set_tweak': 'highlight', 'value': false},
      ],
    );
    when(mockClient.getPushRules())
        .thenAnswer((_) async => PushRuleSet(override: [legacy]));
    when(
      mockClient.setPushRule(
        any,
        any,
        any,
        before: anyNamed('before'),
        after: anyNamed('after'),
        conditions: anyNamed('conditions'),
        pattern: anyNamed('pattern'),
      ),
    ).thenAnswer((_) async {});

    await manager.ensureRule();

    final captured = verify(
      mockClient.setPushRule(
        PushRuleKind.override,
        'io.kohera.call_member',
        any,
        conditions: captureAnyNamed('conditions'),
      ),
    ).captured;
    final conditions = captured.single as List<PushCondition>;
    expect(
      conditions.any((c) => c.kind == 'room_member_count' && c.is$ == '2'),
      isTrue,
    );
  });

  test('no-op when userID missing', () async {
    when(mockClient.userID).thenReturn(null);

    await manager.ensureRule();

    verifyNever(mockClient.getPushRules());
  });
}
