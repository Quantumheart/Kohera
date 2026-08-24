import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/password_cache.dart';
import 'package:matrix/matrix.dart';

/// Shows a password prompt dialog and returns the entered password,
/// or `null` if the user cancelled.
typedef PasswordPromptBuilder = Future<String?> Function();

/// Mediates the Matrix User-Interactive Authentication (UIA) flow between the
/// SDK and the UI: it listens for UIA challenges, auto-completes them from the
/// [PasswordCache] when possible, otherwise drives a password prompt (or
/// forwards to the UI stream). Presentation/interaction state — it owns the
/// prompt callback that widgets set.
class UiaInteractionController {
  UiaInteractionController({
    required MatrixClientService matrixClientService,
    required PasswordCache passwordCache,
  })  : _matrixClientService = matrixClientService,
        _passwordCache = passwordCache;

  final MatrixClientService _matrixClientService;
  final PasswordCache _passwordCache;

  final _uiaController = StreamController<UiaRequest<dynamic>>.broadcast();
  Stream<UiaRequest<dynamic>> get onUiaRequest => _uiaController.stream;

  StreamSubscription<UiaRequest<dynamic>>? _uiaSub;

  /// Callback that shows a password prompt dialog and returns the entered
  /// password, or `null` if the user cancelled.
  ///
  /// When set, password-stage UIA requests are handled internally by
  /// calling this callback — the stream consumer never sees them.
  PasswordPromptBuilder? passwordPromptBuilder;

  void listenForUia() {
    unawaited(_uiaSub?.cancel());
    _uiaSub = _matrixClientService.client.onUiaRequest.stream.listen(_handleUiaRequest);
  }

  Future<void> _handleUiaRequest(UiaRequest<dynamic> uiaRequest) async {
    if (uiaRequest.state != UiaRequestState.waitForUser ||
        uiaRequest.nextStages.isEmpty) {
      return;
    }

    final stage = uiaRequest.nextStages.first;
    debugPrint('[Kohera] UIA request: stage=$stage');

    switch (stage) {
      case AuthenticationTypes.password:
        final password = _passwordCache.cachedPassword;
        final userId = _matrixClientService.client.userID;
        if (password != null && userId != null) {
          debugPrint('[Kohera] UIA: completing with cached password');
          return uiaRequest.completeStage(
            AuthenticationPassword(
              session: uiaRequest.session,
              password: password,
              identifier: AuthenticationUserIdentifier(user: userId),
            ),
          );
        }
        if (passwordPromptBuilder != null) {
          debugPrint('[Kohera] UIA: prompting for password via callback');
          final entered = await passwordPromptBuilder!();
          if (entered != null && entered.isNotEmpty && userId != null) {
            _passwordCache.setCachedPassword(entered);
            return uiaRequest.completeStage(
              AuthenticationPassword(
                session: uiaRequest.session,
                password: entered,
                identifier: AuthenticationUserIdentifier(user: userId),
              ),
            );
          }
          uiaRequest.cancel();
          return;
        }
        debugPrint('[Kohera] UIA: no cached password, forwarding to UI');
        _uiaController.add(uiaRequest);
      case AuthenticationTypes.dummy:
        return uiaRequest.completeStage(
          AuthenticationData(
            type: AuthenticationTypes.dummy,
            session: uiaRequest.session,
          ),
        );
      default:
        debugPrint('[Kohera] UIA: unsupported stage $stage, cancelling');
        uiaRequest.cancel();
    }
  }

  void completeUiaWithPassword(UiaRequest<dynamic> request, String password) {
    final userId = _matrixClientService.client.userID;
    if (userId == null) return;
    _passwordCache.setCachedPassword(password);
    unawaited(
      request.completeStage(
        AuthenticationPassword(
          session: request.session,
          password: password,
          identifier: AuthenticationUserIdentifier(user: userId),
        ),
      ),
    );
  }

  void cancelUiaSub() {
    unawaited(_uiaSub?.cancel());
  }

  void dispose() {
    unawaited(_uiaController.close());
    cancelUiaSub();
  }
}
