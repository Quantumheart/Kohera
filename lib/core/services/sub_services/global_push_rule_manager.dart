import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:matrix/matrix.dart';

// Mirrors CallPushRuleManager: the global NotificationLevel was previously a
// local-only filter, so the homeserver kept pushing every message. APNs pushes
// are triggered server-side by push rules, and on iOS the local filter
// (shouldNotifyForEvent) never runs — the notification extension renders the
// APNs payload directly — so toggling the standard default rules here makes
// "mentions only" actually suppress non-mention pushes server-side. Per-room
// push rules take precedence over these global defaults.
class GlobalPushRuleManager {
  GlobalPushRuleManager({required Client client}) : _client = client;

  final Client _client;

  static const _messageRule = '.m.rule.message';
  static const _encryptedRule = '.m.rule.encrypted';
  static const _masterRule = '.m.rule.master';

  Future<void> syncNotificationLevel(NotificationLevel level) async {
    if (_client.userID == null) return;
    try {
      switch (level) {
        case NotificationLevel.all:
          await _setEnabled(PushRuleKind.override, _masterRule, false);
          await _setEnabled(PushRuleKind.underride, _messageRule, true);
          await _setEnabled(PushRuleKind.underride, _encryptedRule, true);
        case NotificationLevel.mentionsOnly:
          await _setEnabled(PushRuleKind.override, _masterRule, false);
          await _setEnabled(PushRuleKind.underride, _messageRule, false);
          await _setEnabled(PushRuleKind.underride, _encryptedRule, false);
        case NotificationLevel.off:
          await _setEnabled(PushRuleKind.override, _masterRule, true);
      }
      debugPrint(
        '[Kohera] Synced global notification level "${level.label}" '
        'to server push rules',
      );
    } catch (e) {
      debugPrint(
        '[Kohera] Failed to sync global push rules for '
        '"${level.label}": $e',
      );
    }
  }

  Future<void> _setEnabled(PushRuleKind kind, String ruleId, bool enabled) =>
      _client.setPushRuleEnabled(kind, ruleId, enabled);
}
