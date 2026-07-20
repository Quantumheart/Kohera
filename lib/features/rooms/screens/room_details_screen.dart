import 'package:flutter/material.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/services/room_details_controller.dart';
import 'package:kohera/features/rooms/widgets/room_details_content.dart';
import 'package:provider/provider.dart';

/// Full-page host for room details. Owns the [RoomDetailsController]
/// (the SDK conversion boundary) and provides the `Scaffold`/`AppBar` with
/// back navigation; the body is the shared [RoomDetailsContent].
class RoomDetailsScreen extends StatefulWidget {
  const RoomDetailsScreen({required this.roomId, super.key});

  final String roomId;

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
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
  void didUpdateWidget(covariant RoomDetailsScreen oldWidget) {
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
    final title = _controller.summary?.displayname ?? widget.roomId;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.popOrGo(
            Routes.room,
            pathParameters: {RouteParams.roomId: widget.roomId},
          ),
        ),
        title: Text(title),
      ),
      body: RoomDetailsContent(
        controller: _controller,
        onLeft: () {
          if (context.mounted) context.popOrGo(Routes.home);
        },
      ),
    );
  }
}
