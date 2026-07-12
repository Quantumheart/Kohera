import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/features/e2ee/services/bootstrap_controller.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_actions_bar.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_custody_gate.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_done_banner.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_error_section.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_explainer.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_key_card.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_management_panel.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_status_line.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_unlock_section.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_verify_section.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:provider/provider.dart';

class E2eeSetupScreen extends StatefulWidget {
  const E2eeSetupScreen({super.key});

  @override
  State<E2eeSetupScreen> createState() => _E2eeSetupScreenState();
}

class _E2eeSetupScreenState extends State<E2eeSetupScreen> {
  late MatrixService _matrixService;
  BootstrapController? _controller;
  final _recoveryKeyController = TextEditingController();
  bool _uiaPromptShowing = false;
  bool _autoStarted = false;
  bool _showManagement = false;
  Timer? _doneTimer;

  @override
  void initState() {
    super.initState();
    _matrixService = context.read<MatrixService>();
    _matrixService.uia.passwordPromptBuilder = _showPasswordPrompt;

    if (_matrixService.chatBackup.chatBackupEnabled) {
      _showManagement = true;
    }
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    _matrixService.uia.passwordPromptBuilder = null;
    _cleanupController();
    _recoveryKeyController.dispose();
    super.dispose();
  }

  // ── Controller lifecycle ──────────────────────────────────────

  void _startBootstrap({bool wipeExisting = false}) {
    _cleanupController();
    _showManagement = false;
    _controller = BootstrapController(
      matrixService: _matrixService,
      wipeExisting: wipeExisting,
    );
    _controller!.addListener(_onControllerChanged);
    if (mounted) setState(() {});
    unawaited(_controller!.startBootstrap());
  }

  void _cleanupController() {
    if (_controller != null) {
      if (_controller!.keyCopied) {
        unawaited(Clipboard.setData(const ClipboardData(text: '')));
      }
      _controller!.removeListener(_onControllerChanged);
      _controller!.dispose();
      _controller = null;
    }
  }

  void _onControllerChanged() {
    final storedKey = _controller?.consumeStoredRecoveryKey();
    if (storedKey != null) {
      _recoveryKeyController.text = storedKey;
    }
    _scheduleDoneDismissal();
    if (mounted) setState(() {});
  }

  void _scheduleDoneDismissal() {
    final phase = _controller?.phase;
    if (phase == SetupPhase.done) {
      if (_doneTimer != null) return;
      _doneTimer = Timer(const Duration(seconds: 2), () {
        _doneTimer = null;
        if (mounted && _controller?.phase == SetupPhase.done) {
          unawaited(_finishSetup());
        }
      });
    } else {
      _doneTimer?.cancel();
      _doneTimer = null;
    }
  }

  // ── UIA prompt ────────────────────────────────────────────────

  /// Shows a password dialog for UIA authentication.
  /// Called by [UiaService] when a password-stage request arrives.
  Future<String?> _showPasswordPrompt() async {
    if (!mounted || _uiaPromptShowing) return null;
    _uiaPromptShowing = true;
    var passwordValue = '';
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Authentication required'),
        content: TextField(
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => passwordValue = value,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, passwordValue),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    _uiaPromptShowing = false;
    return password != null && password.isNotEmpty ? password : null;
  }

  // ── Confirmations ─────────────────────────────────────────────

  Future<void> _confirmSkip() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Skip chat backup setup?',
      message:
          'Without key backup:\n'
          '• Message history is lost\n'
          "• Cross-device verification won't work\n"
          '• Some features may not work\n\n'
          'You can set this up later in Settings > Chat backup.',
      confirmLabel: 'Skip anyway',
      cancelLabel: 'Go back',
      barrierDismissible: false,
    );
    if (confirmed) _skip();
  }

  Future<void> _confirmCreateNewKey() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Create new backup?',
      message:
          'This will create a new recovery key. If you had a previous '
          'backup, that encrypted message history may be lost.',
      confirmLabel: 'Create new backup',
      cancelLabel: 'Go back',
    );
    if (confirmed) {
      _recoveryKeyController.clear();
      _controller?.restartWithWipe();
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmDisable() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Disable backup?',
      message:
          'Your recovery key and server-side backup will be deleted. '
          'You will lose access to your encrypted message history on '
          'other devices.',
      confirmLabel: 'Disable backup',
      cancelLabel: 'Go back',
      destructive: true,
    );
    if (confirmed) {
      await _matrixService.chatBackup.disableChatBackup();
      _matrixService.skipSetup();
      if (mounted) context.go(RoutePaths.home);
    }
  }

  // ── Finish / Skip ─────────────────────────────────────────────

  Future<void> _finishSetup() async {
    _doneTimer?.cancel();
    _doneTimer = null;
    final shouldClearClipboard = _controller?.keyCopied ?? false;
    _matrixService.skipSetup();
    if (mounted) context.go(RoutePaths.home);
    if (shouldClearClipboard) {
      unawaited(Clipboard.setData(const ClipboardData(text: '')));
    }
  }

  void _skip() {
    _matrixService.skipSetup();
    context.go(RoutePaths.home);
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final backupNeeded = context.select<ChatBackupService, bool?>(
      (s) => s.chatBackupNeeded,
    );

    if (backupNeeded == null) {
      return const Scaffold(
        body: Center(child: KoheraLoader()),
      );
    }

    if (backupNeeded && _controller == null && !_autoStarted) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startBootstrap();
      });
    }

    if (!backupNeeded &&
        !_showManagement &&
        _controller == null &&
        !_autoStarted) {
      _showManagement = true;
    }

    final isBlocking = !_matrixService.hasSkippedSetup && backupNeeded;

    return PopScope(
      canPop: !isBlocking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isBlocking) unawaited(_confirmSkip());
      },
      child: Scaffold(
        appBar: isBlocking
            ? null
            : AppBar(
                leading: BackButton(
                  onPressed: _showManagement
                      ? () => context.go(RoutePaths.home)
                      : () => unawaited(_finishSetup()),
                ),
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Expanded(child: _buildBody()),
                    const SizedBox(height: 16),
                    _buildActionsBar(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_showManagement) {
      return SingleChildScrollView(
        child: E2eeSetupManagementPanel(
          onShowRecoveryKey: () => context.go(RoutePaths.settingsRecoveryKey),
          onCreateNewKey: () => _startBootstrap(wipeExisting: true),
          onDisable: _confirmDisable,
        ),
      );
    }

    final controller = _controller;
    final sections = <Widget>[
      const SizedBox(height: 24),
      const E2eeSetupExplainer(),
      const SizedBox(height: 24),
    ];

    if (controller == null) {
      sections.add(const E2eeSetupStatusLine(message: 'Preparing...'));
    } else {
      switch (controller.phase) {
        case SetupPhase.loading:
          sections.add(E2eeSetupStatusLine(message: controller.loadingMessage));
        case SetupPhase.savingKey:
          if (controller.generatingKey) {
            sections.add(
              E2eeSetupStatusLine(message: controller.loadingMessage),
            );
          } else {
            sections.add(
              E2eeSetupKeyCard(
                recoveryKey: controller.newRecoveryKey,
                copied: controller.keyCopied,
                onCopy: controller.setKeyCopied,
              ),
            );
            sections.add(const SizedBox(height: 8));
            sections.add(
              E2eeSetupCustodyGate(
                saveToDevice: controller.saveToDevice,
                onChanged: controller.setSaveToDevice,
              ),
            );
          }
        case SetupPhase.unlock:
          sections.add(
            E2eeSetupUnlockSection(
              recoveryKeyController: _recoveryKeyController,
              recoveryKeyError: controller.recoveryKeyError,
              saveToDevice: controller.saveToDevice,
              onSaveToDeviceChanged: controller.setSaveToDevice,
              onVerify: controller.startVerification,
              onCreateNewKey: _confirmCreateNewKey,
              enabled: !controller.unlocking,
            ),
          );
        case SetupPhase.verification:
          sections.add(
            E2eeSetupVerifySection(
              verification: controller.koheraVerification,
              onDone: controller.onVerificationDone,
              onCancel: controller.onVerificationCancel,
            ),
          );
        case SetupPhase.done:
          sections.add(const E2eeSetupDoneBanner());
        case SetupPhase.error:
          sections.add(E2eeSetupErrorSection(message: controller.error));
      }
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections,
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────

  Widget _buildActionsBar() {
    if (_showManagement) return const E2eeSetupActionsBar();

    final controller = _controller;
    if (controller == null) {
      return E2eeSetupActionsBar(
        secondaryLabel: 'Skip for now',
        onSecondary: _confirmSkip,
      );
    }

    return switch (controller.phase) {
      SetupPhase.loading ||
      SetupPhase.verification ||
      SetupPhase.done => const E2eeSetupActionsBar(),
      SetupPhase.savingKey =>
        controller.generatingKey
            ? E2eeSetupActionsBar(
                secondaryLabel: 'Skip for now',
                onSecondary: _confirmSkip,
              )
            : E2eeSetupActionsBar(
                secondaryLabel: 'Skip for now',
                onSecondary: _confirmSkip,
                primaryLabel: 'Next',
                onPrimary: controller.confirmNewSsss,
                primaryEnabled: controller.canConfirmNewKey,
              ),
      SetupPhase.unlock => E2eeSetupActionsBar(
        secondaryLabel: 'Skip for now',
        onSecondary: _confirmSkip,
        secondaryEnabled: !controller.unlocking,
        primaryLabel: 'Unlock',
        onPrimary: () =>
            controller.unlockExistingSsss(_recoveryKeyController.text.trim()),
        primaryEnabled: !controller.unlocking,
        primaryBusy: controller.unlocking,
      ),
      SetupPhase.error => E2eeSetupActionsBar(
        secondaryLabel: 'Close',
        onSecondary: () => context.go(RoutePaths.home),
        primaryLabel: 'Retry',
        onPrimary: controller.retry,
      ),
    };
  }
}
