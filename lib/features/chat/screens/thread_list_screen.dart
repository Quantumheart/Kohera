import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/chat/services/thread_roots_service.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';
import 'package:kohera/features/chat/widgets/thread_list_tile.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
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
  List<ThreadSummary>? _summaries;
  StreamSubscription<dynamic>? _syncSub;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final summaries = await fetchThreadSummaries(
        client: matrix.client,
        room: room,
      );
      if (!mounted) return;
      setState(() {
        _summaries = summaries;
        _loading = false;
        _error = null;
      });
      _syncSub ??= matrix.client.onSync.stream.listen((_) {
        if (mounted) unawaited(_refresh());
      });
    } catch (e) {
      debugPrint('[Kohera] Thread roots fetch error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    unawaited(_syncSub?.cancel() ?? Future.value());
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

    final summaries = _summaries;
    final Widget body;
    if (_loading && summaries == null) {
      body = const Center(child: KoheraLoader());
    } else if (_error != null && (summaries == null || summaries.isEmpty)) {
      body = _buildError(context);
    } else if (summaries == null || summaries.isEmpty) {
      body = _buildEmpty(context);
    } else {
      body = ListView.separated(
        itemCount: summaries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final s = summaries[i];
          return ThreadListTile(
            summary: s,
            onTap: () => widget.onOpenThread(s.root.eventId),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: widget.onClose != null
            ? IconButton(
                icon: const Icon(KIcons.close),
                tooltip: 'Close threads',
                onPressed: widget.onClose,
              )
            : null,
        title: const Text('Threads'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: body,
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(KIcons.forumOutlined,
            size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4),),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'No threads yet',
            style: tt.titleMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Start one from any message → Reply in thread',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(KIcons.errorOutline, size: 48, color: cs.error),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Could not load threads',
            style: tt.titleMedium?.copyWith(color: cs.error),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _refresh,
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
