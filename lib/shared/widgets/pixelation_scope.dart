import 'package:flutter/widgets.dart';

/// Inherited flag controlling whether rendered graphics (uploaded avatars and
/// emoji) are drawn as pixel art. Installed once near the app root from the
/// user preference.
///
/// Reads default to `true` when no ancestor is present (e.g. in widget tests),
/// so leaf widgets never depend on a provider being wired up.
class PixelationScope extends InheritedWidget {
  const PixelationScope({
    required this.enabled,
    required super.child,
    super.key,
  });

  final bool enabled;

  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PixelationScope>();
    return scope?.enabled ?? true;
  }

  @override
  bool updateShouldNotify(PixelationScope oldWidget) =>
      oldWidget.enabled != enabled;
}
