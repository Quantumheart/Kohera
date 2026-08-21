import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/sub_services/call_push_rule_manager.dart';
import 'package:kohera/core/services/sub_services/global_push_rule_manager.dart';

class PushRuleRepository extends ChangeNotifier {
  PushRuleRepository({
    required CallPushRuleManager callPushRuleManager,
    required GlobalPushRuleManager globalPushRuleManager,
  })  : _callPushRuleManager = callPushRuleManager,
        _globalPushRuleManager = globalPushRuleManager;

  final CallPushRuleManager _callPushRuleManager;
  final GlobalPushRuleManager _globalPushRuleManager;
  bool _disposed = false;

  CallPushRuleManager get callPushRuleManager => _callPushRuleManager;
  GlobalPushRuleManager get globalPushRuleManager => _globalPushRuleManager;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
