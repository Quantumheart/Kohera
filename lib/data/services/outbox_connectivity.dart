import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

abstract class OutboxConnectivity {
  Stream<bool> get onlineChanges;
  Future<bool> isOnline();
  Future<void> dispose();
}

class RealOutboxConnectivity implements OutboxConnectivity {
  RealOutboxConnectivity() : _connectivity = Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<bool> get onlineChanges =>
      _connectivity.onConnectivityChanged.map(_anyOnline);

  @override
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _anyOnline(results);
  }

  static bool _anyOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<void> dispose() async {}
}
