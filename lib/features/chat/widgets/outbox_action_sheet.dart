import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

Future<void> showOutboxActionSheet(
  BuildContext context, {
  required Event event,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => OutboxActionSheet(event: event),
  );
}

class OutboxActionSheet extends StatelessWidget {
  const OutboxActionSheet({required this.event, super.key});

  final Event event;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('Retry sending'),
            onTap: () async {
              Navigator.of(context).pop();
              try {
                await event.sendAgain();
              } catch (e) {
                debugPrint('[Kohera] outbox sheet: retry failed: $e');
              }
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Discard message',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () async {
              Navigator.of(context).pop();
              try {
                await event.cancelSend();
              } catch (e) {
                debugPrint('[Kohera] outbox sheet: discard failed: $e');
              }
            },
          ),
        ],
      ),
    );
  }
}
