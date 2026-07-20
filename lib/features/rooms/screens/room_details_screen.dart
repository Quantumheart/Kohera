import 'package:flutter/material.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/widgets/room_details_panel.dart';
import 'package:provider/provider.dart';

/// Full-page host for [RoomDetailsPanel]. Owns the `Scaffold`/`AppBar` and
/// back navigation; the panel renders as bare content inside the body.
class RoomDetailsScreen extends StatelessWidget {
  const RoomDetailsScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final room = context.read<MatrixService>().client.getRoomById(roomId);
    final title = room?.getLocalizedDisplayname() ?? roomId;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(
            Routes.room,
            pathParameters: {RouteParams.roomId: roomId},
          ),
        ),
        title: Text(title),
      ),
      body: RoomDetailsPanel(
        roomId: roomId,
        onLeft: () {
          if (context.mounted) context.popOrGo(Routes.home);
        },
      ),
    );
  }
}