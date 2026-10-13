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

abstract class DesktopShell {
  bool get usesTemplateTrayIcons;

  Future<void> init({required VoidCallback onCloseRequested});

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
