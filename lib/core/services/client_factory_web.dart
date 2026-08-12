import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/client_factory_shared.dart';
import 'package:matrix/matrix.dart';

// coverage:ignore-start
Future<Client> createDefaultClient(
  String clientName, {
  Future<void> Function(Client)? onSoftLogout,
}) async {
  MatrixSdkDatabase database;
  try {
    database = await MatrixSdkDatabase.init('kohera_$clientName');
  } catch (e, s) {
    debugPrint('[Kohera] MatrixSdkDatabase.init failed for $clientName: $e');
    debugPrint('[Kohera] Stack trace: $s');
    rethrow;
  }
  return buildClient(
    clientName,
    database,
    NativeImplementationsWebWorker(
      Uri.parse('native_executor.js'),
      timeout: const Duration(minutes: 1),
    ),
    onSoftLogout,
  );
}
// coverage:ignore-end
