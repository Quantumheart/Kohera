import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';

/// Detects active-account switches and falls back to the room list when a
/// room route is still mounted.
///
/// Switching accounts swaps the per-account providers ([MatrixService] and
/// friends) for different instances while the keyed `ChatScreen` subtree is
/// still mounted and depends on them via `context.watch`. Reconciling the
/// keyed subtree onto the swapped providers deactivates an `InheritedElement`
/// before its dependent is released, tripping the framework's
/// `_dependents.isEmpty` assertion. Redirecting `/rooms/...` to `/` tears the
/// chat subtree down cleanly before the swap reconciles.
class AccountSwitchRedirector {
  AccountSwitchRedirector(this._active);

  MatrixService _active;

  String? redirectFor(MatrixService current, String location) {
    if (identical(current, _active)) return null;
    _active = current;
    return location.startsWith(RoutePaths.roomPrefix) ? RoutePaths.home : null;
  }
}
