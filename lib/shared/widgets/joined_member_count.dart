import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Resolves an accurate joined-member count for [room] and rebuilds when it
/// becomes available.
///
/// The Matrix sync `summary` can report a stale or partial
/// `m.joined_member_count` — most visibly, Synapse partial-state joins report
/// `1` for large federated rooms. This widget shows the summary value
/// immediately, then refines it with the authoritative count from
/// `/joined_members`, caching the result per room for the session.
class JoinedMemberCount extends StatefulWidget {
  const JoinedMemberCount({
    required this.room,
    required this.builder,
    super.key,
  });

  final Room room;
  final Widget Function(BuildContext context, int count) builder;

  static final Map<String, int> _cache = {};
  static final Map<String, Future<void>> _inFlight = {};

  @override
  State<JoinedMemberCount> createState() => _JoinedMemberCountState();
}

class _JoinedMemberCountState extends State<JoinedMemberCount> {
  int get _summaryCount => widget.room.summary.mJoinedMemberCount ?? 0;

  int get _bestCount {
    final cached = JoinedMemberCount._cache[widget.room.id] ?? 0;
    return cached > _summaryCount ? cached : _summaryCount;
  }

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(JoinedMemberCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) _resolve();
  }

  void _resolve() {
    final room = widget.room;
    final id = room.id;
    if (JoinedMemberCount._cache.containsKey(id)) return;
    // Trust the summary when our local member list already accounts for it.
    if (room.participantListComplete) return;

    final pending = JoinedMemberCount._inFlight[id];
    if (pending != null) {
      unawaited(pending.whenComplete(_apply));
      return;
    }

    final future = room.client.getJoinedMembersByRoom(id).then((members) {
      if (members != null) JoinedMemberCount._cache[id] = members.length;
    }).catchError((Object e) {
      debugPrint('[Kohera] Failed to resolve member count for $id: $e');
    }).whenComplete(() => JoinedMemberCount._inFlight.remove(id));
    JoinedMemberCount._inFlight[id] = future;
    unawaited(future.whenComplete(_apply));
  }

  void _apply() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _bestCount);
}
