import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_dialog.dart';
import 'package:kohera/features/settings/models/kohera_device.dart';
import 'package:kohera/features/settings/services/device_management_service.dart';
import 'package:kohera/features/settings/widgets/device_list_item.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:kohera/shared/widgets/section_header.dart';
import 'package:provider/provider.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<KoheraDevice>? _devices;
  bool _loading = true;
  String? _error;

  late DeviceManagementService _deviceService;
  late MatrixService _matrix;

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _matrix = context.read<MatrixService>();
    _deviceService = DeviceManagementService(matrix: _matrix);
    _matrix.uia.passwordPromptBuilder = _showPasswordPrompt;
    unawaited(_loadDevices());
  }

  @override
  void dispose() {
    _matrix.uia.passwordPromptBuilder = null;
    super.dispose();
  }

  // ── Load Devices ───────────────────────────────────────────

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await _deviceService.loadDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Kohera] Failed to load devices: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load devices';
        _loading = false;
      });
    }
  }

  // ── UIA Password Prompt ────────────────────────────────────

  /// Shows a password dialog for UIA authentication.
  /// Called by [UiaService] when a password-stage request arrives.
  Future<String?> _showPasswordPrompt() async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final passwordController = TextEditingController();
        return AlertDialog(
          title: const Text('Authentication required'),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(ctx, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, passwordController.text),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  // ── Rename Device ──────────────────────────────────────────

  Future<void> _renameDevice(KoheraDevice device) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: device.displayName);
        return AlertDialog(
          title: const Text('Rename device'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Device name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(ctx, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    if (newName == null || newName.isEmpty) return;

    try {
      if (!mounted) return;
      await _deviceService.renameDevice(device.deviceId, newName);
      await _loadDevices();
    } catch (e) {
      debugPrint('[Kohera] Failed to rename device: $e');
      if (!mounted) return;
      context.showSnack('Failed to rename device');
    }
  }

  // ── Remove Device ──────────────────────────────────────────

  Future<void> _removeDevice(KoheraDevice device) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Remove device?',
      message: 'Remove "${device.displayNameOrId}"? '
          'This will sign out that device.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      if (!mounted) return;
      await _deviceService.removeDevice(device.deviceId);
      await _loadDevices();
    } catch (e) {
      debugPrint('[Kohera] Failed to remove device: $e');
      if (!mounted) return;
      context.showSnack('Failed to remove device');
    }
  }

  // ── Remove All Other Devices ───────────────────────────────

  Future<void> _removeAllOtherDevices() async {
    final currentDeviceId = _deviceService.currentDeviceId;
    final otherIds = _devices
            ?.where((d) => d.deviceId != currentDeviceId)
            .map((d) => d.deviceId)
            .toList() ??
        [];
    if (otherIds.isEmpty) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Remove all other devices?',
      message: 'This will sign out ${otherIds.length} other '
          '${otherIds.length == 1 ? 'device' : 'devices'}.',
      confirmLabel: 'Remove all',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await _deviceService.removeAllOtherDevices(otherIds);
      await _loadDevices();
    } catch (e) {
      debugPrint('[Kohera] Failed to remove devices: $e');
      if (!mounted) return;
      context.showSnack('Failed to remove devices');
    }
  }

  // ── Verify Device ──────────────────────────────────────────

  Future<void> _verifyDevice(KoheraDevice device) async {
    try {
      final kohera = await _deviceService.verifyDevice(device.deviceId);
      if (kohera == null) {
        if (!mounted) return;
        context.showSnack('No encryption keys found for device');
        return;
      }
      if (!mounted) return;
      try {
        await KeyVerificationDialog.show(context, verification: kohera);
      } finally {
        kohera.dispose();
      }
      await _loadDevices();
    } catch (e) {
      debugPrint('[Kohera] Failed to start verification: $e');
      if (!mounted) return;
      context.showSnack('Failed to start verification');
    }
  }

  // ── Block / Unblock Device ─────────────────────────────────

  Future<void> _toggleBlockDevice(KoheraDevice device) async {
    try {
      await _deviceService.toggleBlockDevice(device.deviceId);
      await _loadDevices();
    } catch (e) {
      debugPrint('[Kohera] Failed to toggle block: $e');
      if (!mounted) return;
      context.showSnack('Failed to update device');
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(Routes.settings),
        ),
        title: const Text('Devices'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: KoheraLoader());
    }
    if (_error != null) {
      return _buildError();
    }
    if (_devices == null || _devices!.isEmpty) {
      return const Center(child: Text('No devices found'));
    }

    final matrix = context.read<MatrixService>();
    final currentDeviceId = _deviceService.currentDeviceId;
    final thisDevice =
        _devices!.where((d) => d.deviceId == currentDeviceId).toList();
    final otherDevices =
        _devices!.where((d) => d.deviceId != currentDeviceId).toList()
          ..sort((a, b) {
            final aTs = a.lastSeenTs;
            final bTs = b.lastSeenTs;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _loadDevices,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Chat backup warning
          if (matrix.chatBackup.chatBackupNeeded == true) ...[
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Chat backup is not set up. Device verification '
                        'may not work correctly without it.',
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── This Device ──
          if (thisDevice.isNotEmpty) ...[
            const SectionHeader(label: 'THIS DEVICE'),
            Card(
              child: DeviceListItem(
                device: thisDevice.first,
                isCurrentDevice: true,
                onRename: () => _renameDevice(thisDevice.first),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Other Devices ──
          const SectionHeader(label: 'OTHER DEVICES'),
          if (otherDevices.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No other devices found',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else ...[
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < otherDevices.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    DeviceListItem(
                      device: otherDevices[i],
                      isCurrentDevice: false,
                      onRename: () => _renameDevice(otherDevices[i]),
                      onVerify: () => _verifyDevice(otherDevices[i]),
                      onToggleBlock: () => _toggleBlockDevice(otherDevices[i]),
                      onRemove: () => _removeDevice(otherDevices[i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _removeAllOtherDevices,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Remove all other devices'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildError() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: cs.error),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: cs.error)),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _loadDevices,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
