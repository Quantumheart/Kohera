import 'package:flutter/foundation.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:kohera/features/calling/services/rtc_membership_service.dart'
    show callMemberEventType;
import 'package:matrix/matrix.dart';

// Ensures the homeserver notifies Kohera's VoIP pusher on inbound
// m.call.member state events for 1:1 rooms only. The room_member_count
// condition restricts pushes to two-member (direct) rooms so that joins to
// group calls never ring. Rule is written (or repaired) per-account on login
// and on sync reconnect so it works on any homeserver without admin config
// changes.

class CallPushRuleManager {
  CallPushRuleManager({required Client client}) : _client = client;

  final Client _client;

  Future<void> ensureRule() async {
    if (_client.userID == null) return;
    try {
      final rules = await _client.getPushRules();
      final existing = rules.override
          ?.where((r) => r.ruleId == kPushRuleCallMember)
          .firstOrNull;

      if (existing != null &&
          _actionsMatch(existing.actions) &&
          _conditionsMatch(existing.conditions)) {
        return;
      }

      await _client.setPushRule(
        PushRuleKind.override,
        kPushRuleCallMember,
        _desiredActions(),
        conditions: _desiredConditions(),
      );
      debugPrint('[Kohera] Installed $kPushRuleCallMember push rule');
    } catch (e) {
      debugPrint('[Kohera] Failed to ensure call push rule: $e');
    }
  }

  List<PushCondition> _desiredConditions() => [
        PushCondition(
          kind: 'event_match',
          key: 'type',
          pattern: callMemberEventType,
        ),
        PushCondition(kind: 'room_member_count', is_: '2'),
      ];

  List<Object?> _desiredActions() => [
        'notify',
        {'set_tweak': 'sound', 'value': 'ring'},
        {'set_tweak': 'highlight', 'value': false},
      ];

  bool _conditionsMatch(List<PushCondition>? conditions) {
    final desired = _desiredConditions();
    if (conditions == null || conditions.length != desired.length) return false;
    for (var i = 0; i < desired.length; i++) {
      final a = conditions[i];
      final b = desired[i];
      if (a.kind != b.kind ||
          a.key != b.key ||
          a.pattern != b.pattern ||
          a.is_ != b.is_) {
        return false;
      }
    }
    return true;
  }

  bool _actionsMatch(List<Object?> actions) {
    if (actions.length != 3) return false;
    if (actions[0] != 'notify') return false;

    final sound = actions[1];
    if (sound is! Map) return false;
    if (sound['set_tweak'] != 'sound' || sound['value'] != 'ring') return false;

    final highlight = actions[2];
    if (highlight is! Map) return false;
    if (highlight['set_tweak'] != 'highlight' ||
        highlight['value'] != false) {
      return false;
    }
    return true;
  }
}
