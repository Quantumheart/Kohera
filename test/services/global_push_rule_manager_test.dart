import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/global_push_rule_manager.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>()])
import 'global_push_rule_manager_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late GlobalPushRuleManager manager;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.userID).thenReturn('@alice:example.com');
    when(mockClient.setPushRuleEnabled(any, any, any)).thenAnswer((_) async {});
    manager = GlobalPushRuleManager(client: mockClient);
  });

  test('all enables message + encrypted underride rules and disables master',
      () async {
    await manager.syncNotificationLevel(NotificationLevel.all);

    verify(
      mockClient.setPushRuleEnabled(
        PushRuleKind.override,
        '.m.rule.master',
        false,
      ),
    ).called(1);
    verify(
      mockClient.setPushRuleEnabled(
        PushRuleKind.underride,
        '.m.rule.message',
        true,
      ),
    ).called(1);
    verify(
      mockClient.setPushRuleEnabled(
        PushRuleKind.underride,
        '.m.rule.encrypted',
        true,
      ),
    ).called(1);
  });

  test('mentionsOnly disables message + encrypted underride rules', () async {
    await manager.syncNotificationLevel(NotificationLevel.mentionsOnly);

    verify(
      mockClient.setPushRuleEnabled(
        PushRuleKind.override,
        '.m.rule.master',
        false,
      ),
    ).called(1);
    verify(
      mockClient.setPushRuleEnabled(
        PushRuleKind.underride,
        '.m.rule.message',
        false,
      ),
    ).called(1);
    verify(
      mockClient.setPushRuleEnabled(
        PushRuleKind.underride,
        '.m.rule.encrypted',
        false,
      ),
    ).called(1);
  });

  test('off enables the master suppress-all rule', () async {
    await manager.syncNotificationLevel(NotificationLevel.off);

    verify(
      mockClient.setPushRuleEnabled(
        PushRuleKind.override,
        '.m.rule.master',
        true,
      ),
    ).called(1);
    verifyNever(
      mockClient.setPushRuleEnabled(
        PushRuleKind.underride,
        any,
        any,
      ),
    );
  });

  test('no-op when userID missing', () async {
    when(mockClient.userID).thenReturn(null);

    await manager.syncNotificationLevel(NotificationLevel.mentionsOnly);

    verifyNever(mockClient.setPushRuleEnabled(any, any, any));
  });

  test('swallows homeserver errors without throwing', () async {
    when(mockClient.setPushRuleEnabled(any, any, any))
        .thenThrow(Exception('network down'));

    await manager.syncNotificationLevel(NotificationLevel.all);
  });
}
