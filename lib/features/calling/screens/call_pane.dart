import 'package:flutter/material.dart';
import 'package:lattice/features/calling/services/call_controller.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/calling/services/call_service.dart';
import 'package:lattice/features/calling/widgets/call_control_bar.dart';
import 'package:lattice/features/calling/widgets/video_grid.dart';
import 'package:provider/provider.dart';

class CallPane extends StatelessWidget {
  const CallPane({super.key});

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final controller = callService.activeCall;
    final displayName = callService.activeDisplayName ?? 'Call';

    if (controller == null) {
      return const Center(child: Text('No active call'));
    }

    final tt = Theme.of(context).textTheme;

    return switch (controller.state) {
      CallState.joining => _buildJoining(tt, displayName),
      CallState.connected => _buildConnected(tt, controller),
      CallState.reconnecting => _buildReconnecting(tt),
      CallState.ended => _buildEnded(context, tt, controller),
    };
  }

  // ── State views ───────────────────────────────────────────────

  Widget _buildJoining(TextTheme tt, String displayName) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('Connecting...', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text(displayName, style: tt.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildConnected(TextTheme tt, CallController controller) {
    return Column(
      children: [
        Expanded(
          child: VideoGrid(participants: controller.participants),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _formatElapsed(controller.elapsed),
            style: tt.titleMedium,
          ),
        ),
        CallControlBar(controller: controller),
      ],
    );
  }

  Widget _buildReconnecting(TextTheme tt) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 48),
          const SizedBox(height: 16),
          Text('Reconnecting...', style: tt.titleMedium),
        ],
      ),
    );
  }

  Widget _buildEnded(BuildContext context, TextTheme tt, CallController controller) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.call_end, size: 48),
          const SizedBox(height: 16),
          Text('Call ended', style: tt.titleMedium),
          if (controller.error != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.error!,
              style: tt.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => CallNavigator.endCall(context),
            child: const Text('Return'),
          ),
        ],
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}
