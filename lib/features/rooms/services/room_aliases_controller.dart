import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/models/kohera_room_aliases.dart';
import 'package:kohera/features/rooms/widgets/room_aliases_section.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

/// Conversion boundary for the room aliases feature.
///
/// Owns the SDK `Room` and translates alias state + alias management calls
/// into [KoheraRoomAliases] and callbacks for the SDK-free
/// [RoomAliasesSection]. Mirrors [JoinAccessController]: a self-contained
/// `StatefulWidget` that reads the room from `MatrixService`, listens to
/// sync for alias/canonical-alias state changes, and re-fetches local
/// aliases on demand.
class RoomAliasesController extends StatefulWidget {
  const RoomAliasesController({required this.roomId, super.key});

  final String roomId;

  @override
  State<RoomAliasesController> createState() => _RoomAliasesControllerState();
}

class _RoomAliasesControllerState extends State<RoomAliasesController> {
  KoheraRoomAliases? _data;
  bool _loading = true;
  StreamSubscription<SyncUpdate>? _syncSub;
  int _fetchGen = 0;

  Client get _client => context.read<MatrixService>().client;

  String? get _homeserverDomain {
    final userId = _client.userID;
    if (userId == null) return null;
    final colon = userId.lastIndexOf(':');
    if (colon <= 0) return null;
    return userId.substring(colon + 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSub ??= _client.onSync.stream.listen(_onSync);
    if (_data == null) unawaited(_reload());
  }

  @override
  void dispose() {
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  void _onSync(SyncUpdate update) {
    final stateEvents = update.rooms?.join?[widget.roomId]?.state ?? [];
    if (stateEvents.any((e) =>
        e.type == EventTypes.RoomCanonicalAlias || e.type == EventTypes.RoomAliases)) {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final gen = ++_fetchGen;
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final room = _client.getRoomById(widget.roomId);
      if (room == null) {
        if (mounted) {
          setState(() {
            _data = null;
            _loading = false;
          });
        }
        return;
      }
      final aliases = await _client.getLocalAliases(widget.roomId);
      if (gen != _fetchGen) return;
      final data = KoheraRoomAliases(
        roomId: widget.roomId,
        aliases: List.unmodifiable(aliases),
        canonicalAlias: room.canonicalAlias.isEmpty ? null : room.canonicalAlias,
        canEdit: room.canChangeStateEvent(EventTypes.RoomCanonicalAlias),
        homeserverDomain: _homeserverDomain,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Kohera] load aliases failed: $e');
      if (mounted && gen == _fetchGen) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _create(String localpart) async {
    final domain = _homeserverDomain;
    if (domain == null) throw StateError('No homeserver domain available');
    final alias = '#$localpart:$domain';
    await _client.setRoomAlias(alias, widget.roomId);
    await _reload();
  }

  Future<void> _delete(String alias) async {
    await _client.deleteRoomAlias(alias);
    final current = _data?.canonicalAlias;
    if (current == alias) {
      await _clearCanonical();
    }
    await _reload();
  }

  Future<void> _setCanonical(String alias) async {
    final room = _client.getRoomById(widget.roomId);
    if (room == null) return;
    await room.setCanonicalAlias(alias);
    await _reload();
  }

  Future<void> _clearCanonical() async {
    await _client.setRoomStateWithKey(
      widget.roomId,
      EventTypes.RoomCanonicalAlias,
      '',
      <String, Object?>{},
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading && _data == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_data == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Aliases unavailable', style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    return RoomAliasesSection(
      aliases: _data!,
      onCreate: _create,
      onDelete: _delete,
      onSetCanonical: _setCanonical,
      onClearCanonical: _clearCanonical,
    );
  }
}
