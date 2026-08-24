import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/data/services/call_push_rule_manager.dart';
import 'package:kohera/data/services/global_push_rule_manager.dart';
import 'package:kohera/data/services/matrix_client_service.dart';

/// Manages server-side push rules for an account: the VoIP call-member
/// override rule and the global notification-level defaults. Owns the two
/// stateless push-rule managers; [AccountSession] builds one per account and
/// exposes it via `session.pushRuleRepository`.
class PushRuleRepository {
  PushRuleRepository({
    required MatrixClientService clientService,
    CallPushRuleManager? callOverride,
    GlobalPushRuleManager? globalOverride,
  })  : _call = callOverride ??
            CallPushRuleManager(matrixClientService: clientService),
        _global = globalOverride ??
            GlobalPushRuleManager(matrixClientService: clientService);

  final CallPushRuleManager _call;
  final GlobalPushRuleManager _global;

  /// Installs or repairs the VoIP call-member push rule (per-account on login).
  Future<void> ensureCallRule() => _call.ensureRule();

  /// Syncs the global notification level to the server's default push rules.
  Future<void> syncNotificationLevel(NotificationLevel level) =>
      _global.syncNotificationLevel(level);
}
