import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:matrix/matrix.dart';

/// Syncs the global [NotificationLevel] to the homeserver's account-wide
/// Matrix push rules so that APNs/UnifiedPush pushes are filtered
/// **server-side**, not only by the local [shouldNotifyForEvent] filter.
///
/// The local filter never runs on the iOS APNs path (the native notification
/// extension renders the push straight from the APNs payload), so without
/// server-side rules every message generates a push regardless of the
/// "mentions only" setting. This manager fixes that by toggling the standard
/// default push rules, mirroring the per-account approach of
/// [CallPushRuleManager].
///
/// Mapping:
///
///  - [NotificationLevel.all] — enable the default `.m.rule.message` and
///    `.m.rule.encrypted` underride rules (push for every message); disable
///    `.m.rule.master`.
///  - [NotificationLevel.mentionsOnly] — disable those underride rules so only
///    the default mention override rules (`.m.rule.contains_user_name`,
///    `.m.rule.contains_display_name`, `.m.rule.atroomnotification`) generate
///    pushes; disable `.m.rule.master`.
///  - [NotificationLevel.off] — enable `.m.rule.master` to suppress all
///    pushes.
///
/// Per-room push rules always take precedence over these global defaults, so
/// individually muted rooms stay muted.
class GlobalPushRuleManager {
  GlobalPushRuleManager({required Client client}) : _client = client;

  final Client _client;

  /// Default underride rule that notifies on any `m.room.message`.
  static const _messageRule = '.m.rule.message';

  /// Default underride rule that notifies on any `m.room.encrypted`.
  static const _encryptedRule = '.m.rule.encrypted';

  /// Override rule that, when enabled, suppresses all notifications.
  static const _masterRule = '.m.rule.master';

  /// Push the given [level] to the homeserver's account-wide push rules.
  ///
  /// No-op when not logged in. Errors are logged and swallowed so a transient
  /// homeserver failure never prevents the local preference from being saved.
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

  /// Reconcile server push rules with the persisted notification level.
  ///
  /// Called on login and session restore so the homeserver state matches the
  /// local preference even after a re-install or a homeserver rule reset,
  /// mirroring [CallPushRuleManager.ensureRule].
  Future<void> ensureSync(NotificationLevel level) =>
      syncNotificationLevel(level);

  Future<void> _setEnabled(
    PushRuleKind kind,
    String ruleId,
    bool enabled,
  ) =>
      _client.setPushRuleEnabled(kind, ruleId, enabled);
}
