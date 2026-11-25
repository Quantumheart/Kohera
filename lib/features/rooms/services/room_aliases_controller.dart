import 'dart:async';

import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/rooms/models/kohera_room_aliases.dart';
import 'package:kohera/features/rooms/widgets/room_aliases_section.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Conversion boundary for the room aliases feature.
///
/// Reads alias state through [RoomRepository] and translates alias
/// management calls into [KoheraRoomAliases] and callbacks for the SDK-free
/// [RoomAliasesSection]. Mirrors [JoinAccessController]: a self-contained
/// `StatefulWidget` that listens to sync for alias/canonical-alias state
/// changes and re-fetches local aliases on demand.
class RoomAliasesController extends StatefulWidget {
  const RoomAliasesController({required this.roomId, super.key});

  final String roomId;

  @override
  State<RoomAliasesController> createState() => _RoomAliasesControllerState();
}

class _RoomAliasesControllerState extends State<RoomAliasesController> {
  KoheraRoomAliases? _data;
  bool _loading = true;
  StreamSubscription<void>? _syncSub;
  int _fetchGen = 0;

  RoomRepository get _rooms => context.read<RoomRepository>();

  String? get _homeserverDomain {
    final userId = _rooms.userId;
    if (userId == null) return null;
    final colon = userId.lastIndexOf(':');
    if (colon <= 0) return null;
    return userId.substring(colon + 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSub ??= _rooms
        .aliasChangesFor(widget.roomId)
        .listen((_) => unawaited(_reload()));
    if (_data == null) unawaited(_reload());
  }

  @override
  void dispose() {
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  Future<void> _reload() async {
    final gen = ++_fetchGen;
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      if (_rooms.summaryFor(widget.roomId) == null) {
        if (mounted) {
          setState(() {
            _data = null;
            _loading = false;
          });
        }
        return;
      }
      final aliases = await _rooms.getLocalAliases(widget.roomId);
      if (gen != _fetchGen) return;
      final data = KoheraRoomAliases(
        roomId: widget.roomId,
        aliases: List.unmodifiable(aliases),
        canonicalAlias: _rooms.canonicalAlias(widget.roomId),
        canEdit: _rooms.canChangeCanonicalAlias(widget.roomId),
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
    await _rooms.setRoomAlias(alias, widget.roomId);
    await _reload();
  }

  Future<void> _delete(String alias) async {
    await _rooms.deleteRoomAlias(alias);
    final current = _data?.canonicalAlias;
    if (current == alias) {
      await _clearCanonical();
    }
    await _reload();
  }

  Future<void> _setCanonical(String alias) async {
    await _rooms.setCanonicalAlias(widget.roomId, alias);
    await _reload();
  }

  Future<void> _clearCanonical() async {
    await _rooms.clearCanonicalAlias(widget.roomId);
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
