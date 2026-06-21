import 'package:flutter/material.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:provider/provider.dart';

/// Owns the pending-service lifecycle for the entire add-account flow.
///
/// As a [ShellRoute] host this widget persists across the entry, server, and
/// register sub-routes and is disposed only when the flow is left, so it is
/// the single place that:
///   * provides the pending [MatrixService] to the shadowed subtree, and
///   * cancels the pending service on exit (a no-op once committed).
///
/// Intra-flow navigation (including Back) no longer tears down the pending
/// service, and the top-level redirect guarantees a pending service exists
/// before this builds.
class AddAccountShell extends StatefulWidget {
  const AddAccountShell({
    required this.manager,
    required this.routerChild,
    super.key,
  });

  final ClientManager manager;
  final Widget routerChild;

  @override
  State<AddAccountShell> createState() => _AddAccountShellState();
}

class _AddAccountShellState extends State<AddAccountShell> {
  @override
  void dispose() {
    widget.manager.cancelPendingService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.manager.pendingService;
    if (pending == null) return const SizedBox.shrink();
    return ChangeNotifierProvider<MatrixService>.value(
      value: pending,
      child: widget.routerChild,
    );
  }
}
