import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/data/services/matrix_client_service.dart';

/// Tracks whether the user skipped E2EE key-backup setup or dismissed the setup
/// banner, persisted per-account in secure storage. Onboarding/UI state — the
/// key-backup domain itself lives in [KeyBackupRepository].
class KeyBackupSetupState extends ChangeNotifier {
  KeyBackupSetupState({
    required MatrixClientService clientService,
    required FlutterSecureStorage storage,
  })  : _clientService = clientService,
        _storage = storage;

  final MatrixClientService _clientService;
  final FlutterSecureStorage _storage;

  bool _setupSkipped = false;
  bool get setupSkipped => _setupSkipped;

  bool _bannerDismissed = false;
  bool get bannerDismissed => _bannerDismissed;

  Future<void> loadDismissalState() async {
    final userId = _clientService.client.userID;
    if (userId == null) return;
    final results = await Future.wait([
      _storage.read(key: 'e2ee_setup_skipped_$userId'),
      _storage.read(key: 'e2ee_banner_dismissed_$userId'),
    ]);
    _setupSkipped = results[0] == 'true';
    _bannerDismissed = results[1] == 'true';
    notifyListeners();
  }

  Future<void> markSetupSkipped() async {
    _setupSkipped = true;
    notifyListeners();
    final userId = _clientService.client.userID;
    if (userId == null) return;
    await _storage.write(key: 'e2ee_setup_skipped_$userId', value: 'true');
  }

  Future<void> dismissBanner() async {
    _bannerDismissed = true;
    notifyListeners();
    final userId = _clientService.client.userID;
    if (userId == null) return;
    await _storage.write(key: 'e2ee_banner_dismissed_$userId', value: 'true');
  }

  /// Re-shows the banner after the user disables backup.
  void resetBannerDismissed() {
    _bannerDismissed = false;
    notifyListeners();
  }

  void reset() {
    _setupSkipped = false;
    _bannerDismissed = false;
    notifyListeners();
  }

  Future<void> deleteDismissalState() async {
    final userId = _clientService.client.userID;
    if (userId == null) return;
    await Future.wait([
      _storage.delete(key: 'e2ee_setup_skipped_$userId'),
      _storage.delete(key: 'e2ee_banner_dismissed_$userId'),
    ]);
  }
}
