import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/kohera_state_event_text.dart';
import 'package:provider/provider.dart';

class StateEventTile extends StatelessWidget {
  const StateEventTile({required this.item, super.key});

  final KoheraStateEventText item;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.text,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMessageTime(item.timestamp),
            style: tt.bodySmall?.copyWith(
              fontSize: 11,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );

    if (item.isTombstone) {
      content = InkWell(
        onTap: () => _onTombstoneTap(context),
        borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Flexible(child: content)],
      ),
    );
  }

  Future<void> _onTombstoneTap(BuildContext context) async {
    final replacement = item.replacementRoomId;
    if (replacement == null || replacement.isEmpty) return;

    final matrix = context.read<MatrixService>();
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    try {
      final existing = matrix.client.getRoomById(replacement);
      if (existing == null) {
        await matrix.client.joinRoom(replacement);
      }
      router.goNamed(Routes.room, pathParameters: {RouteParams.roomId: replacement});
    } catch (e) {
      debugPrint('[Kohera] Failed to open replacement room: $e');
      scaffold.showSnackBar(
        const SnackBar(content: Text('Could not open the upgraded room')),
      );
    }
  }
}
