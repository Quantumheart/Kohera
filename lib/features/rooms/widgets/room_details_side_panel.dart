import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/services/room_details_controller.dart';
import 'package:kohera/features/rooms/widgets/room_details_content.dart';
import 'package:provider/provider.dart';

/// Wide-layout side panel for room details. Owns the
/// [RoomDetailsController] and hosts the shared [RoomDetailsContent]
/// without a `Scaffold` (the side panel's chrome is provided by the layout).
class RoomDetailsSidePanel extends StatefulWidget {
  const RoomDetailsSidePanel({required this.roomId, super.key});

  final String roomId;

  @override
  State<RoomDetailsSidePanel> createState() => _RoomDetailsSidePanelState();
}

class _RoomDetailsSidePanelState extends State<RoomDetailsSidePanel> {
  late RoomDetailsController _controller;
  bool _created = false;

  // ── Lifecycle ───────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_created) {
      _created = true;
      _controller = RoomDetailsController(
        roomId: widget.roomId,
        matrix: context.read<MatrixService>(),
        selection: context.read<SelectionService>(),
      )..addListener(_onChanged);
      _controller.init();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant RoomDetailsSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.checkRoomChanged();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RoomDetailsContent(controller: _controller);
  }
}
