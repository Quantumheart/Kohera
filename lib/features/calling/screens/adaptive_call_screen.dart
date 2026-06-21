import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/calling/screens/call_pane.dart';
import 'package:kohera/features/calling/screens/call_screen.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:provider/provider.dart';

/// Shows the embedded [CallPane] on wide layouts and the full-page
/// [CallScreen] on narrow ones.
class AdaptiveCallScreen extends StatelessWidget {
  const AdaptiveCallScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= HomeShell.wideBreakpoint;
    if (isWide) return const CallPane();
    final room = context.read<MatrixService>().client.getRoomById(roomId);
    return CallScreen(
      roomId: roomId,
      displayName: room?.getLocalizedDisplayname() ?? 'Call',
    );
  }
}
