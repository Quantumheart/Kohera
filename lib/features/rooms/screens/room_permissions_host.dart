import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/models/kohera_room_permissions.dart';
import 'package:kohera/features/rooms/screens/room_permissions_screen.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:kohera/features/rooms/services/room_permissions_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

/// Boundary widget that subscribes to sync updates, converts `Room` to
/// [KoheraRoomPermissions], and renders the SDK-free
/// [RoomPermissionsScreen] with action callbacks.
///
/// This is the only permissions-related widget that imports
/// `package:matrix/matrix.dart`.
class RoomPermissionsHost extends StatefulWidget {
  const RoomPermissionsHost({required this.roomId, super.key});

  final String roomId;

  @override
  State<RoomPermissionsHost> createState() => _RoomPermissionsHostState();
}

class _RoomPermissionsHostState extends State<RoomPermissionsHost> {
  StreamSubscription<SyncUpdate>? _syncSub;
  Timer? _debounce;

  static const Set<String> _watchedTypes = {
    EventTypes.RoomPowerLevels,
    EventTypes.RoomJoinRules,
    EventTypes.Encryption,
  };

  @override
  void initState() {
    super.initState();
    final client = context.read<MatrixService>().client;
    _syncSub = client.onSync.stream.listen(_onSync);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  void _onSync(SyncUpdate update) {
    final stateEvents =
        update.rooms?.join?[widget.roomId]?.state ?? [];
    if (!stateEvents.any((e) => _watchedTypes.contains(e.type))) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = context.read<MatrixService>().client;
    final room = client.getRoomById(widget.roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permissions')),
        body: const Center(child: Text('Room not found')),
      );
    }

    final permissions = const RoomPermissionsResolver().convert(
      room,
      myUserId: client.userID ?? '',
    );

    return RoomPermissionsScreen(
      permissions: permissions,
      onSetJoinRules: (rule) => room.setJoinRules(_toSdkJoinRules(rule)),
      onEnableEncryption: room.enableEncryption,
      onUpdatePowerLevel: (patch) => PowerLevelService.update(room, patch),
      onApplyPowerLevelsContent: (content) => room.client.setRoomStateWithKey(
        room.id,
        EventTypes.RoomPowerLevels,
        '',
        content,
      ),
    );
  }

  JoinRules _toSdkJoinRules(KoheraJoinRule rule) => switch (rule) {
        KoheraJoinRule.public => JoinRules.public,
        KoheraJoinRule.invite => JoinRules.invite,
        KoheraJoinRule.knock => JoinRules.knock,
        KoheraJoinRule.restricted => JoinRules.restricted,
      };
}
