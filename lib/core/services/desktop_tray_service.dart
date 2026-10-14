import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/brand/brand_constants.dart';
import 'package:kohera/core/services/desktop_shell.dart';
import 'package:kohera/core/services/preferences_service.dart';

class DesktopTrayService {
  DesktopTrayService({
    required PreferencesService preferences,
    DesktopShell? shell,
  })  : _prefs = preferences,
        _shell = shell;

  static const trayIconAsset = 'assets/tray/tray_icon.png';
  static const trayIconUnreadAsset = 'assets/tray/tray_icon_unread.png';
  static const trayTemplateAsset = 'assets/tray/tray_icon_template.png';
  static const trayTemplateUnreadAsset =
      'assets/tray/tray_icon_template_unread.png';

  static const menuLabels = TrayMenuLabels(
    open: 'Open ${BrandConstants.appName}',
    quit: 'Quit ${BrandConstants.appName}',
  );

  final PreferencesService _prefs;
  final DesktopShell? _shell;

  bool _initialized = false;
  bool _trayShown = false;
  bool _windowFocused = true;
  int _unreadCount = 0;
  Future<void> _pending = Future.value();

  bool get isSupported => _shell != null;

  bool get isTrayShown => _trayShown;

  // ── Lifecycle ───────────────────────────────────────────────

  Future<void> init() async {
    final shell = _shell;
    if (shell == null || _initialized) return;
    try {
      await shell.init(
        onCloseRequested: _onCloseRequested,
        onFocusChanged: _onFocusChanged,
      );
    } catch (e) {
      debugPrint('[Kohera] Desktop shell unavailable, tray disabled: $e');
      return;
    }
    _initialized = true;
    _prefs.addListener(_onPreferencesChanged);
    await _enqueue(_applyPreference);
    if (_unreadCount > 0) {
      await _enqueue(() => shell.setBadgeCount(_unreadCount));
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _prefs.removeListener(_onPreferencesChanged);
    await _enqueue(() async {
      if (_trayShown) await _shell!.removeTray();
      _trayShown = false;
      if (_unreadCount > 0) await _shell!.setBadgeCount(0);
    });
  }

  // ── Window ──────────────────────────────────────────────────

  Future<void> revealWindow() async {
    if (!_initialized) return;
    await _shell!.revealWindow();
    if (_unreadCount > 0) {
      await _enqueue(() => _shell.setBadgeCount(_unreadCount));
    }
  }

  Future<void> quit() async {
    if (!_initialized) return;
    debugPrint('[Kohera] Quitting from tray');
    _trayShown = false;
    await _shell!.quit();
  }

  void _onCloseRequested() {
    if (_trayShown) {
      debugPrint('[Kohera] Window close intercepted, hiding to tray');
      unawaited(_shell!.hideWindow());
    } else {
      unawaited(quit());
    }
  }

  // ── Attention ───────────────────────────────────────────────

  bool get isWindowFocused => _windowFocused;

  void requestAttention({required bool important}) {
    if (!_initialized || _windowFocused) return;
    debugPrint('[Kohera] Requesting window attention (important: $important)');
    unawaited(_enqueue(() => _shell!.requestAttention(important: important)));
  }

  void _onFocusChanged(bool focused) {
    if (focused == _windowFocused) return;
    _windowFocused = focused;
    if (focused) unawaited(_enqueue(_shell!.cancelAttention));
  }

  // ── Unread indicator ────────────────────────────────────────

  void setUnreadCount(int count) {
    if (count == _unreadCount) return;
    _unreadCount = count;
    if (!_initialized) return;
    unawaited(_enqueue(() async {
      await _shell!.setBadgeCount(count);
      if (_trayShown) await _shell.updateTray(_trayIconSpec);
    }));
  }

  @visibleForTesting
  TrayIconSpec get trayIconSpec => _trayIconSpec;

  TrayIconSpec get _trayIconSpec {
    final hasUnread = _unreadCount > 0;
    final template = _shell?.usesTemplateTrayIcons ?? false;
    final asset = switch ((template, hasUnread)) {
      (true, true) => trayTemplateUnreadAsset,
      (true, false) => trayTemplateAsset,
      (false, true) => trayIconUnreadAsset,
      (false, false) => trayIconAsset,
    };
    return TrayIconSpec(
      assetPath: asset,
      isTemplate: template,
      tooltip: hasUnread
          ? '${BrandConstants.appName} - $_unreadCount unread'
          : BrandConstants.appName,
    );
  }

  // ── Preference ──────────────────────────────────────────────

  bool get _trayWanted => _prefs.closeToTray && _shell!.supportsTray;

  void _onPreferencesChanged() {
    if (_trayWanted == _trayShown) return;
    unawaited(_enqueue(_applyPreference));
  }

  Future<void> _applyPreference() async {
    final enabled = _trayWanted;
    if (enabled == _trayShown) return;
    final shell = _shell!;
    if (enabled) {
      await shell.showTray(
        _trayIconSpec,
        labels: menuLabels,
        onOpen: () => unawaited(revealWindow()),
        onQuit: () => unawaited(quit()),
      );
      await shell.setInterceptClose(true);
    } else {
      await shell.setInterceptClose(false);
      await shell.removeTray();
    }
    _trayShown = enabled;
    debugPrint('[Kohera] Tray ${enabled ? "shown" : "removed"}');
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pending.then((_) => action()).catchError((Object e) {
      debugPrint('[Kohera] Tray update failed: $e');
    });
    _pending = next;
    return next;
  }
}
