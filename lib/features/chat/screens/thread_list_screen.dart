import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';
import 'package:kohera/features/chat/widgets/thread_list_tile.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class ThreadListScreen extends StatefulWidget {
  const ThreadListScreen({
    required this.roomId,
    required this.onOpenThread,
    super.key,
    this.onClose,
  });

  final String roomId;
  final void Function(String rootEventId) onOpenThread;
  final VoidCallback? onClose;

  @override
  State<ThreadListScreen> createState() => _ThreadListScreenState();
}

class _ThreadListScreenState extends State<ThreadListScreen> {
  Timeline? _timeline;
  StreamSubscription<dynamic>? _syncSub;
  bool _backfilling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (!mounted) return;
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;
    final timeline = await room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) {
      timeline.cancelSubscriptions();
      return;
    }
    setState(() => _timeline = timeline);
    _syncSub = matrix.client.onSync.stream.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_backfillUntilThreadsFound(timeline, room, matrix));
  }

  Future<void> _backfillUntilThreadsFound(
    Timeline timeline,
    Room room,
    MatrixService matrix,
  ) async {
    if (_backfilling) return;
    _backfilling = true;
    try {
      const maxRounds = 10;
      var rounds = 0;
      while (mounted && rounds < maxRounds && timeline.canRequestHistory) {
        final summaries = deriveThreadSummaries(
          timeline: timeline,
          room: room,
          myUserId: matrix.client.userID ?? '',
        );
        if (summaries.isNotEmpty) break;
        rounds++;
        await timeline.requestHistory();
      }
    } catch (e) {
      debugPrint('[Kohera] Thread list backfill error: $e');
    } finally {
      _backfilling = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    unawaited(_syncSub?.cancel() ?? Future.value());
    _timeline?.cancelSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    final tt = Theme.of(context).textTheme;

    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Threads')),
        body: Center(child: Text('Room not found', style: tt.bodyLarge)),
      );
    }

    final timeline = _timeline;
    if (timeline == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Threads')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final summaries = deriveThreadSummaries(
      timeline: timeline,
      room: room,
      myUserId: matrix.client.userID ?? '',
    );

    return Scaffold(
      appBar: AppBar(
        leading: widget.onClose != null
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              )
            : null,
        title: const Text('Threads'),
      ),
      body: summaries.isEmpty
          ? (_backfilling
              ? const Center(child: CircularProgressIndicator())
              : _buildEmpty(context))
          : ListView.separated(
              itemCount: summaries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = summaries[i];
                return ThreadListTile(
                  summary: s,
                  onTap: () => widget.onOpenThread(s.root.eventId),
                );
              },
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined,
              size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4),),
          const SizedBox(height: 12),
          Text(
            'No threads yet',
            style: tt.titleMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Start one from any message → Reply in thread',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
