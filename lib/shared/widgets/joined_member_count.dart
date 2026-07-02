import 'dart:async';

import 'package:flutter/material.dart';

/// Resolves an accurate joined-member count for a room and rebuilds when it
/// becomes available.
///
/// The Matrix sync `summary` can report a stale or partial
/// `m.joined_member_count` — most visibly, Synapse partial-state joins report
/// `1` for large federated rooms. This widget shows the summary value
/// immediately, then refines it with the authoritative count from
/// `/joined_members`, caching the result per room for the session.
class JoinedMemberCount extends StatefulWidget {
  const JoinedMemberCount({
    required this.roomId,
    required this.summaryMemberCount,
    required this.participantListComplete,
    required this.resolveMemberCount,
    required this.builder,
    super.key,
  });

  final String roomId;
  final int summaryMemberCount;
  final bool participantListComplete;

  /// Async resolver that fetches the authoritative member count via
  /// `/joined_members`. Returns `null` on failure.
  final Future<int?> Function(String roomId) resolveMemberCount;

  final Widget Function(BuildContext context, int count) builder;

  static final Map<String, int> _cache = {};
  static final Map<String, Future<void>> _inFlight = {};

  @override
  State<JoinedMemberCount> createState() => _JoinedMemberCountState();
}

class _JoinedMemberCountState extends State<JoinedMemberCount> {
  int get _summaryCount => widget.summaryMemberCount;

  int get _bestCount {
    final cached = JoinedMemberCount._cache[widget.roomId] ?? 0;
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
    if (oldWidget.roomId != widget.roomId) _resolve();
  }

  void _resolve() {
    final id = widget.roomId;
    if (JoinedMemberCount._cache.containsKey(id)) return;
    if (widget.participantListComplete) return;

    final pending = JoinedMemberCount._inFlight[id];
    if (pending != null) {
      unawaited(pending.whenComplete(_apply));
      return;
    }

    final future = widget.resolveMemberCount(id).then((members) {
      if (members != null) JoinedMemberCount._cache[id] = members;
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
