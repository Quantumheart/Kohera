import 'package:flutter/material.dart';

/// Sanctioned owner of the bottom system-inset for docked bottom UI
/// (compose bar, FAB clusters, space rail, action sheets).
///
/// Contract:
/// - Consumes [MediaQuery.padding]'s bottom inset so descendants never
///   double-apply it. [SafeArea] is idempotent: a nested [SafeBottomBar]
///   inside an ancestor that already consumed the inset contributes zero.
/// - When [decoration] or [color] is supplied, the fill extends behind the
///   inset strip (Android gesture pill, iOS home indicator, PWA browser
///   chrome) so the docked surface reads as one piece instead of leaving a
///   transparent gap above the system bar.
/// - [padding] is content spacing only; the system inset is handled separately
///   so the two never race or double-count.
/// - Single source of truth: [MediaQuery.padding.bottom], which `main.dart`
///   seeds from `webSafeAreaInsets()` on PWA. One inlet, every platform.
///
/// Prefer this over raw `MediaQuery.paddingOf(context).bottom` reads, which
/// fight [Scaffold.resizeToAvoidBottomInset] and desync during system-UI
/// transitions (e.g. Android app-switch reasserting the navigation bar).
class SafeBottomBar extends StatelessWidget {
  const SafeBottomBar({
    this.decoration,
    this.color,
    this.padding = EdgeInsets.zero,
    this.child,
    super.key,
  });

  final BoxDecoration? decoration;
  final Color? color;
  final EdgeInsets padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final inner = SafeArea(
      top: false,
      child: Padding(padding: padding, child: child),
    );
    if (decoration != null) {
      return DecoratedBox(decoration: decoration!, child: inner);
    }
    if (color != null) {
      return ColoredBox(color: color!, child: inner);
    }
    return inner;
  }
}
