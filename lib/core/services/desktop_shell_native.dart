import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/desktop_shell_shared.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

export 'package:kohera/core/services/desktop_shell_shared.dart';

DesktopShell? createDesktopShell() =>
    isNativeWindows || isNativeMacOS ? WindowManagerShell() : null;

// coverage:ignore-start
class WindowManagerShell with WindowListener implements DesktopShell {
  VoidCallback? _onCloseRequested;
  tray.TrayIcon? _trayIcon;
  tray.Image? _trayImage;
  tray.ListenerId? _trayListenerId;
  tray.Menu? _menu;
  final List<(tray.MenuItem, tray.ListenerId)> _menuItems = [];

  @override
  bool get usesTemplateTrayIcons => Platform.isMacOS;

  @override
  Future<void> init({required VoidCallback onCloseRequested}) async {
    _onCloseRequested = onCloseRequested;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
  }

  @override
  void onWindowClose() => _onCloseRequested?.call();

  @override
  Future<void> setInterceptClose(bool intercept) =>
      windowManager.setPreventClose(intercept);

  @override
  Future<void> revealWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hideWindow() => windowManager.hide();

  @override
  Future<void> quit() async {
    await removeTray();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  Future<void> showTray(
    TrayIconSpec spec, {
    required TrayMenuLabels labels,
    required VoidCallback onOpen,
    required VoidCallback onQuit,
  }) async {
    await removeTray();
    final icon = tray.TrayIcon.create();
    if (icon == null) {
      debugPrint('[Kohera] Tray icon could not be created');
      return;
    }
    _trayIcon = icon;
    _applySpec(spec);

    final menu = tray.Menu.create();
    if (menu != null) {
      _addMenuItem(menu, labels.open, onOpen);
      menu.addSeparator();
      _addMenuItem(menu, labels.quit, onQuit);
      icon.setContextMenu(menu);
      _menu = menu;
    }

    icon.setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);
    _trayListenerId = icon.addListener((event) {
      if (event is tray.TrayIconClickedEvent) onOpen();
    });
    icon.setVisible(true);
  }

  @override
  Future<void> updateTray(TrayIconSpec spec) async {
    if (_trayIcon == null) return;
    _applySpec(spec);
  }

  @override
  Future<void> removeTray() async {
    final icon = _trayIcon;
    if (icon == null) return;
    final listenerId = _trayListenerId;
    if (listenerId != null) icon.removeListener(listenerId);
    _trayListenerId = null;
    icon
      ..setContextMenu(null)
      ..setVisible(false);
    final menuItems = List.of(_menuItems);
    final menu = _menu;
    final image = _trayImage;
    _menuItems.clear();
    _menu = null;
    _trayImage = null;
    _trayIcon = null;
    Timer.run(() {
      for (final (item, id) in menuItems) {
        item
          ..removeListener(id)
          ..dispose();
      }
      menu?.dispose();
      image?.dispose();
      icon.dispose();
    });
  }

  void _applySpec(TrayIconSpec spec) {
    final icon = _trayIcon!;
    final image = tray.ImageAsset.fromAsset(spec.assetPath);
    if (image == null) {
      debugPrint('[Kohera] Tray icon asset not found: ${spec.assetPath}');
    } else {
      icon
        ..isIconTemplate = spec.isTemplate
        ..iconSize = const Size.square(16)
        ..icon = image;
      _trayImage?.dispose();
      _trayImage = image;
    }
    icon.setTooltip(spec.tooltip);
  }

  void _addMenuItem(tray.Menu menu, String label, VoidCallback onClick) {
    final item = tray.MenuItem.createWithLabelAndType(
      label,
      tray.MenuItemType.normal,
    );
    if (item == null) return;
    final id = item.addListener((event) {
      if (event is tray.MenuItemClickedEvent) onClick();
    });
    _menuItems.add((item, id));
    menu.addItem(item);
  }
}
// coverage:ignore-end
