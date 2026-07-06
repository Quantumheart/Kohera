import 'package:flutter/material.dart';
import 'package:kohera/features/calling/services/call_navigator.dart';
import 'package:kohera/features/calling/services/call_service.dart';

// coverage:ignore-start

class JoinCallBanner extends StatelessWidget {
  const JoinCallBanner({
    required this.roomId,
    required this.callService,
    super.key,
  });

  final String roomId;
  final CallService callService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final callIds = callService.activeCallIdsForRoom(roomId);
    final participantCount = callIds.isNotEmpty
        ? callService.callParticipantCount(roomId, callIds.first)
        : 0;

    return Material(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.call_rounded, size: 18, color: cs.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Call in progress${participantCount > 0 ? ' \u2014 $participantCount participant${participantCount == 1 ? '' : 's'}' : ''}',
                style: TextStyle(color: cs.onPrimaryContainer),
              ),
            ),
            FilledButton.tonal(
              onPressed: () => CallNavigator.startCall(context, roomId: roomId),
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}
// coverage:ignore-end
