import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/features/calling/services/call_controller.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/calling/services/call_service.dart';
import 'package:lattice/features/calling/widgets/call_control_bar.dart';
import 'package:lattice/features/calling/widgets/pip_self_view.dart';
import 'package:lattice/features/calling/widgets/video_grid.dart';
import 'package:provider/provider.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({required this.roomId, required this.displayName, super.key});

  final String roomId;
  final String displayName;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _popTimer;

  void _onControllerChanged() {
    if (!mounted) return;
    final callService = context.read<CallService>();
    final controller = callService.activeCall;
    if (controller == null || controller.state == CallState.ended) {
      _popTimer ??= Timer(const Duration(seconds: 2), () {
        if (mounted) unawaited(CallNavigator.endCall(context));
      });
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final callService = context.read<CallService>();
    callService.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _popTimer?.cancel();
    context.read<CallService>().removeListener(_onControllerChanged);
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final controller = callService.activeCall;
    final tt = Theme.of(context).textTheme;

    return PopScope(
      canPop: controller == null ||
          (controller.state != CallState.connected &&
              controller.state != CallState.reconnecting),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.displayName),
        ),
        body: controller == null
            ? _buildEnded(tt, null)
            : switch (controller.state) {
                CallState.joining => _buildJoining(tt),
                CallState.connected => _buildConnected(tt, controller),
                CallState.reconnecting => _buildReconnecting(tt),
                CallState.ended => _buildEnded(tt, controller),
              },
      ),
    );
  }

  // ── State views ───────────────────────────────────────────────

  Widget _buildJoining(TextTheme tt) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('Connecting...', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text(widget.displayName, style: tt.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildConnected(TextTheme tt, CallController controller) {
    final remoteParticipants = controller.participants
        .where((p) => !p.isLocal)
        .toList();
    final localParticipant = controller.participants
        .where((p) => p.isLocal)
        .firstOrNull;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: VideoGrid(participants: remoteParticipants),
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
        ),
        if (localParticipant != null)
          PipSelfView(participant: localParticipant),
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

  Widget _buildEnded(TextTheme tt, CallController? controller) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.call_end, size: 48),
          const SizedBox(height: 16),
          Text('Call ended', style: tt.titleMedium),
          if (controller?.error != null) ...[
            const SizedBox(height: 8),
            Text(
              controller!.error!,
              style: tt.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
