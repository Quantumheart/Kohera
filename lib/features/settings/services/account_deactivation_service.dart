import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';

/// Wraps Matrix account deactivation behind UIA.
///
/// Deactivation is permanent and irreversible. After success the homeserver
/// invalidates all access tokens and unbinds the user's third-party
/// identifiers; the caller is responsible for dropping the local [Client]
/// (see [ClientManager.removeService]).
class AccountDeactivationService {
  AccountDeactivationService({required this.matrix});

  final MatrixService matrix;

  /// Permanently deactivates the signed-in account.
  ///
  /// [erase] requests the homeserver to redact the account's events and erase
  /// non-event data where possible. [idServer], when provided, is the identity
  /// server to unbind all 3PIDs from; when omitted the homeserver uses the
  /// identity server originally used to bind each identifier.
  Future<IdServerUnbindResult> deactivate({
    bool erase = false,
    String? idServer,
  }) async {
    final client = matrix.client;
    return client.uiaRequestBackground<IdServerUnbindResult>(
      (auth) => client.deactivateAccount(
        auth: auth,
        erase: erase,
        idServer: idServer,
      ),
    );
  }
}
