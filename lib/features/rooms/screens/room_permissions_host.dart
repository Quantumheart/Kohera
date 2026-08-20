import 'package:flutter/material.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/rooms/screens/room_permissions_screen.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:kohera/features/rooms/services/room_permissions_sync_watcher.dart';
import 'package:provider/provider.dart';

/// Boundary widget that subscribes to sync updates, converts `Room` to
/// [KoheraRoomPermissions], and renders the SDK-free
/// [RoomPermissionsScreen] with action callbacks.
class RoomPermissionsHost extends StatefulWidget {
  const RoomPermissionsHost({required this.roomId, super.key});

  final String roomId;

  @override
  State<RoomPermissionsHost> createState() => _RoomPermissionsHostState();
}

class _RoomPermissionsHostState extends State<RoomPermissionsHost> {
  late RoomPermissionsSyncWatcher _watcher;

  @override
  void initState() {
    super.initState();
    _watcher = RoomPermissionsSyncWatcher(rooms: context.read<RoomRepository>());
    _watcher.watch(widget.roomId, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = context.read<RoomRepository>();
    final room = rooms.rawRoom(widget.roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permissions')),
        body: const Center(child: Text('Room not found')),
      );
    }

    final permissions = rooms.permissionsFor(widget.roomId)!;

    return RoomPermissionsScreen(
      permissions: permissions,
      onSetJoinRules: (rule) => PowerLevelService.setJoinRules(room, rule),
      onEnableEncryption: room.enableEncryption,
      onUpdatePowerLevel: (patch) =>
          PowerLevelService.update(rooms, room, patch),
      onApplyPowerLevelsContent: (content) => rooms.setRoomStateWithKey(
        room.id,
        'm.room.power_levels',
        '',
        content,
      ),
    );
  }
}
