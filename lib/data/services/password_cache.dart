import 'dart:async';

/// Briefly caches the user's login password so User-Interactive Auth (UIA)
/// challenges can auto-complete without re-prompting. Set on login, cleared
/// on logout, and self-expires after a short window. Pure session state — no
/// SDK, no UI.
class PasswordCache {
  String? _cachedPassword;
  Timer? _expiryTimer;

  /// The cached password, or null when none is held.
  String? get cachedPassword => _cachedPassword;

  void setCachedPassword(String password) {
    _cachedPassword = password;
    _expiryTimer?.cancel();
    _expiryTimer = Timer(const Duration(seconds: 30), () {
      _cachedPassword = null;
      _expiryTimer = null;
    });
  }

  void clearCachedPassword() {
    _cachedPassword = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  void dispose() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }
}
