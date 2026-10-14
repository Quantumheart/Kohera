import 'package:flutter/foundation.dart';

@immutable
class TrayIconSpec {
  const TrayIconSpec({
    required this.assetPath,
    required this.isTemplate,
    required this.tooltip,
  });

  final String assetPath;
  final bool isTemplate;
  final String tooltip;

  @override
  bool operator ==(Object other) =>
      other is TrayIconSpec &&
      other.assetPath == assetPath &&
      other.isTemplate == isTemplate &&
      other.tooltip == tooltip;

  @override
  int get hashCode => Object.hash(assetPath, isTemplate, tooltip);
}

class TrayMenuLabels {
  const TrayMenuLabels({required this.open, required this.quit});

  final String open;
  final String quit;
}

String badgeLabelFor(int count, {required bool numericOnly}) {
  if (count <= 0) return '';
  if (count > 99 && !numericOnly) return '99+';
  return '$count';
}

abstract class DesktopShell {
  bool get supportsTray;

  bool get usesTemplateTrayIcons;

  Future<void> init({
    required VoidCallback onCloseRequested,
    required ValueChanged<bool> onFocusChanged,
  });

  Future<void> setBadgeCount(int count);

  Future<void> requestAttention({required bool important});

  Future<void> cancelAttention();

  Future<void> setInterceptClose(bool intercept);

  Future<void> revealWindow();

  Future<void> hideWindow();

  Future<void> quit();

  Future<void> showTray(
    TrayIconSpec spec, {
    required TrayMenuLabels labels,
    required VoidCallback onOpen,
    required VoidCallback onQuit,
  });

  Future<void> updateTray(TrayIconSpec spec);

  Future<void> removeTray();
}
