import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/desktop_shell_shared.dart';
import 'package:kohera/core/services/desktop_tray_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeShell implements DesktopShell {
  _FakeShell({
    this.usesTemplateTrayIcons = false,
    this.supportsTray = true,
    this.failInit = false,
  });

  final bool failInit;

  @override
  final bool supportsTray;

  @override
  final bool usesTemplateTrayIcons;

  final List<String> calls = [];
  VoidCallback? onCloseRequested;
  ValueChanged<bool>? onFocusChanged;
  VoidCallback? onOpen;
  VoidCallback? onQuit;
  TrayIconSpec? shownSpec;
  TrayMenuLabels? labels;
  bool interceptClose = false;

  @override
  Future<void> init({
    required VoidCallback onCloseRequested,
    required ValueChanged<bool> onFocusChanged,
  }) async {
    calls.add('init');
    if (failInit) throw StateError('no window manager');
    this.onCloseRequested = onCloseRequested;
    this.onFocusChanged = onFocusChanged;
  }

  @override
  Future<void> setBadgeCount(int count) async => calls.add('badge:$count');

  @override
  Future<void> requestAttention({required bool important}) async =>
      calls.add('attention:$important');

  @override
  Future<void> cancelAttention() async => calls.add('cancelAttention');

  @override
  Future<void> setInterceptClose(bool intercept) async {
    calls.add('intercept:$intercept');
    interceptClose = intercept;
  }

  @override
  Future<void> revealWindow() async => calls.add('reveal');

  @override
  Future<void> hideWindow() async => calls.add('hide');

  @override
  Future<void> quit() async => calls.add('quit');

  @override
  Future<void> showTray(
    TrayIconSpec spec, {
    required TrayMenuLabels labels,
    required VoidCallback onOpen,
    required VoidCallback onQuit,
  }) async {
    calls.add('showTray');
    shownSpec = spec;
    this.labels = labels;
    this.onOpen = onOpen;
    this.onQuit = onQuit;
  }

  @override
  Future<void> updateTray(TrayIconSpec spec) async {
    calls.add('updateTray');
    shownSpec = spec;
  }

  @override
  Future<void> removeTray() async {
    calls.add('removeTray');
    shownSpec = null;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late PreferencesService prefs;
  late _FakeShell shell;
  late DesktopTrayService service;

  Future<void> createService({
    bool closeToTray = false,
    bool template = false,
    bool supportsTray = true,
  }) async {
    SharedPreferences.setMockInitialValues({'close_to_tray': closeToTray});
    prefs = PreferencesService(prefs: await SharedPreferences.getInstance());
    shell = _FakeShell(
      usesTemplateTrayIcons: template,
      supportsTray: supportsTray,
    );
    service = DesktopTrayService(preferences: prefs, shell: shell);
  }

  group('without a shell', () {
    test('is unsupported and every call is a no-op', () async {
      SharedPreferences.setMockInitialValues({'close_to_tray': true});
      prefs = PreferencesService(prefs: await SharedPreferences.getInstance());
      final service = DesktopTrayService(preferences: prefs);

      await service.init();
      service.setUnreadCount(3);
      await service.revealWindow();
      await service.quit();
      await service.dispose();

      expect(service.isSupported, isFalse);
      expect(service.isTrayShown, isFalse);
    });
  });

  group('init', () {
    test('leaves close behaviour alone when the setting is off', () async {
      await createService();

      await service.init();

      expect(shell.calls, ['init']);
      expect(service.isTrayShown, isFalse);
      expect(shell.interceptClose, isFalse);
    });

    test('shows the tray and intercepts close when the setting is on',
        () async {
      await createService(closeToTray: true);

      await service.init();

      expect(shell.calls, ['init', 'showTray', 'intercept:true']);
      expect(service.isTrayShown, isTrue);
      expect(shell.labels?.open, 'Open Kohera');
      expect(shell.labels?.quit, 'Quit Kohera');
    });

    test('a failing shell disables the tray without throwing', () async {
      SharedPreferences.setMockInitialValues({'close_to_tray': true});
      prefs = PreferencesService(prefs: await SharedPreferences.getInstance());
      shell = _FakeShell(failInit: true);
      service = DesktopTrayService(preferences: prefs, shell: shell);

      await service.init();
      await prefs.setCloseToTray(false);
      await prefs.setCloseToTray(true);
      await _settle();
      await service.revealWindow();
      await service.quit();

      expect(shell.calls, ['init']);
      expect(service.isTrayShown, isFalse);
    });

    test('only initialises once', () async {
      await createService(closeToTray: true);

      await service.init();
      await service.init();

      expect(shell.calls.where((c) => c == 'init'), hasLength(1));
      expect(shell.calls.where((c) => c == 'showTray'), hasLength(1));
    });
  });

  group('toggling the setting', () {
    test('enabling shows the tray and intercepts close', () async {
      await createService();
      await service.init();

      await prefs.setCloseToTray(true);
      await _settle();

      expect(shell.calls, ['init', 'showTray', 'intercept:true']);
      expect(service.isTrayShown, isTrue);
    });

    test('disabling releases close before removing the tray', () async {
      await createService(closeToTray: true);
      await service.init();
      shell.calls.clear();

      await prefs.setCloseToTray(false);
      await _settle();

      expect(shell.calls, ['intercept:false', 'removeTray']);
      expect(service.isTrayShown, isFalse);
    });

    test('unrelated preference changes do not touch the tray', () async {
      await createService(closeToTray: true);
      await service.init();
      shell.calls.clear();

      await prefs.setReadReceipts(false);
      await _settle();

      expect(shell.calls, isEmpty);
    });

    test('rapid toggles end in the latest state', () async {
      await createService();
      await service.init();

      await prefs.setCloseToTray(true);
      await prefs.setCloseToTray(false);
      await prefs.setCloseToTray(true);
      await _settle();
      await _settle();

      expect(service.isTrayShown, isTrue);
      expect(shell.interceptClose, isTrue);
    });
  });

  group('window close', () {
    test('hides the window while the tray is shown', () async {
      await createService(closeToTray: true);
      await service.init();
      shell.calls.clear();

      shell.onCloseRequested!();
      await _settle();

      expect(shell.calls, ['hide']);
    });

    test('quits when the tray is not shown', () async {
      await createService();
      await service.init();
      shell.calls.clear();

      shell.onCloseRequested!();
      await _settle();

      expect(shell.calls, ['quit']);
    });
  });

  group('tray menu', () {
    test('open reveals the window', () async {
      await createService(closeToTray: true);
      await service.init();
      shell.calls.clear();

      shell.onOpen!();
      await _settle();

      expect(shell.calls, ['reveal']);
    });

    test('quit exits the app', () async {
      await createService(closeToTray: true);
      await service.init();
      shell.calls.clear();

      shell.onQuit!();
      await _settle();

      expect(shell.calls, ['quit']);
      expect(service.isTrayShown, isFalse);
    });
  });

  group('unread indicator', () {
    test('uses the plain icon with no unread messages', () async {
      await createService(closeToTray: true);
      await service.init();

      expect(
        shell.shownSpec,
        const TrayIconSpec(
          assetPath: DesktopTrayService.trayIconAsset,
          isTemplate: false,
          tooltip: 'Kohera',
        ),
      );
    });

    test('switches to the unread icon and count tooltip', () async {
      await createService(closeToTray: true);
      await service.init();

      service.setUnreadCount(4);
      await _settle();

      expect(
        shell.shownSpec,
        const TrayIconSpec(
          assetPath: DesktopTrayService.trayIconUnreadAsset,
          isTemplate: false,
          tooltip: 'Kohera - 4 unread',
        ),
      );
    });

    test('returns to the plain icon when everything is read', () async {
      await createService(closeToTray: true);
      await service.init();
      service.setUnreadCount(2);
      await _settle();

      service.setUnreadCount(0);
      await _settle();

      expect(shell.shownSpec?.assetPath, DesktopTrayService.trayIconAsset);
      expect(shell.shownSpec?.tooltip, 'Kohera');
    });

    test('does not update the tray when the count is unchanged', () async {
      await createService(closeToTray: true);
      await service.init();
      service.setUnreadCount(2);
      await _settle();
      shell.calls.clear();

      service.setUnreadCount(2);
      await _settle();

      expect(shell.calls, isEmpty);
    });

    test('remembers the count while the tray is hidden', () async {
      await createService();
      await service.init();

      service.setUnreadCount(5);
      await _settle();
      expect(shell.calls, ['init', 'badge:5']);

      await prefs.setCloseToTray(true);
      await _settle();

      expect(shell.shownSpec?.assetPath, DesktopTrayService.trayIconUnreadAsset);
    });

    test('uses template icons where the shell asks for them', () async {
      await createService(closeToTray: true, template: true);
      await service.init();

      expect(shell.shownSpec?.assetPath, DesktopTrayService.trayTemplateAsset);
      expect(shell.shownSpec?.isTemplate, isTrue);

      service.setUnreadCount(1);
      await _settle();

      expect(
        shell.shownSpec?.assetPath,
        DesktopTrayService.trayTemplateUnreadAsset,
      );
    });
  });

  group('dispose', () {
    test('removes the tray and stops following the setting', () async {
      await createService(closeToTray: true);
      await service.init();
      shell.calls.clear();

      await service.dispose();
      await prefs.setCloseToTray(false);
      await _settle();

      expect(shell.calls, ['removeTray']);
    });
  });

  group('tray support', () {
    test('never shows a tray where the shell has none', () async {
      await createService(closeToTray: true, supportsTray: false);
      await service.init();

      await prefs.setCloseToTray(false);
      await prefs.setCloseToTray(true);
      await _settle();

      expect(service.isTrayShown, isFalse);
      expect(shell.calls, ['init']);
    });

    test('closing the window quits where the shell has no tray', () async {
      await createService(closeToTray: true, supportsTray: false);
      await service.init();
      shell.calls.clear();

      shell.onCloseRequested!();
      await _settle();

      expect(shell.calls, ['quit']);
    });
  });

  group('badge', () {
    test('follows the unread count without the tray', () async {
      await createService();
      await service.init();

      service
        ..setUnreadCount(3)
        ..setUnreadCount(0);
      await _settle();

      expect(shell.calls, ['init', 'badge:3', 'badge:0']);
    });

    test('is applied at init when a count arrived earlier', () async {
      await createService();

      service.setUnreadCount(7);
      await service.init();

      expect(shell.calls, ['init', 'badge:7']);
    });

    test('is cleared on dispose', () async {
      await createService();
      await service.init();
      service.setUnreadCount(2);
      await _settle();
      shell.calls.clear();

      await service.dispose();

      expect(shell.calls, ['badge:0']);
    });

    test('updates the badge and the tray together', () async {
      await createService(closeToTray: true);
      await service.init();
      shell.calls.clear();

      service.setUnreadCount(4);
      await _settle();

      expect(shell.calls, ['badge:4', 'updateTray']);
    });
  });

  group('attention', () {
    test('is not requested while the window is focused', () async {
      await createService();
      await service.init();
      shell.calls.clear();

      service.requestAttention(important: true);
      await _settle();

      expect(service.isWindowFocused, isTrue);
      expect(shell.calls, isEmpty);
    });

    test('is requested while the window is unfocused', () async {
      await createService();
      await service.init();
      shell.onFocusChanged!(false);
      shell.calls.clear();

      service
        ..requestAttention(important: false)
        ..requestAttention(important: true);
      await _settle();

      expect(shell.calls, ['attention:false', 'attention:true']);
    });

    test('is cancelled when the window regains focus', () async {
      await createService();
      await service.init();
      shell.onFocusChanged!(false);
      service.requestAttention(important: true);
      await _settle();
      shell.calls.clear();

      shell.onFocusChanged!(true);
      await _settle();

      expect(service.isWindowFocused, isTrue);
      expect(shell.calls, ['cancelAttention']);
    });

    test('repeated focus events do not cancel again', () async {
      await createService();
      await service.init();
      shell.calls.clear();

      shell.onFocusChanged!(true);
      await _settle();

      expect(shell.calls, isEmpty);
    });

    test('is ignored before init', () async {
      await createService();

      service.requestAttention(important: true);
      await _settle();

      expect(shell.calls, isEmpty);
    });
  });

  group('badgeLabelFor', () {
    test('is empty with no unread messages', () {
      expect(badgeLabelFor(0, numericOnly: false), '');
      expect(badgeLabelFor(-1, numericOnly: true), '');
    });

    test('shows the count', () {
      expect(badgeLabelFor(5, numericOnly: false), '5');
      expect(badgeLabelFor(99, numericOnly: false), '99');
    });

    test('caps large counts unless the platform needs a number', () {
      expect(badgeLabelFor(100, numericOnly: false), '99+');
      expect(badgeLabelFor(100, numericOnly: true), '100');
    });
  });
}
