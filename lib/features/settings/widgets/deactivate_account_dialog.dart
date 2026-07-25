import 'package:flutter/material.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/settings/services/account_deactivation_service.dart';
import 'package:kohera/features/settings/widgets/uia_password_prompt_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

/// Permanently deactivate the signed-in Matrix account.
///
/// Irreversible. Requires UIA (password) confirmation handled by
/// [UiaService] via [MatrixService.uia.passwordPromptBuilder]. On success the
/// local [Client] is dropped through [ClientManager.removeService].
class DeactivateAccountDialog extends StatefulWidget {
  const DeactivateAccountDialog({super.key});

  /// Opens the dialog. Returns `true` if deactivation succeeded.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DeactivateAccountDialog(),
    );
    return result ?? false;
  }

  @override
  State<DeactivateAccountDialog> createState() =>
      _DeactivateAccountDialogState();
}

class _DeactivateAccountDialogState extends State<DeactivateAccountDialog> {
  bool _erase = false;
  bool _showIdServer = false;
  final _idServerController = TextEditingController();
  bool _busy = false;
  String? _error;

  late final MatrixService _matrix;
  late final ClientManager _manager;
  late final AccountDeactivationService _service;
  Future<String?> Function()? _previousPromptBuilder;

  @override
  void initState() {
    super.initState();
    _matrix = context.read<MatrixService>();
    _manager = context.read<ClientManager>();
    _service = AccountDeactivationService(matrix: _matrix);
    _previousPromptBuilder = _matrix.uia.passwordPromptBuilder;
    _matrix.uia.passwordPromptBuilder = _promptPassword;
  }

  @override
  void dispose() {
    _matrix.uia.passwordPromptBuilder = _previousPromptBuilder;
    _idServerController.dispose();
    super.dispose();
  }

  Future<String?> _promptPassword() async {
    if (!mounted) return null;
    return UiaPasswordPromptDialog.show(context);
  }

  Future<void> _confirm() async {
    final idServer = _idServerController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.deactivate(
        erase: _erase,
        idServer: _showIdServer && idServer.isNotEmpty ? idServer : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      await _manager.removeService(_matrix);
    } on MatrixException catch (e) {
      _setError(e.errorMessage);
    } catch (e) {
      _setError('Deactivation failed: $e');
    }
  }

  void _setError(String message) {
    debugPrint('[Kohera] Account deactivation failed: $message');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Deactivate account'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: cs.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This permanently deactivates your account and cannot '
                      'be undone. You will lose access to all your messages '
                      'and the username will not be available again.',
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Your password will be required to confirm.',
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _erase,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _erase = v ?? false),
                title: const Text('Erase my content'),
                subtitle: const Text(
                  'Ask the server to redact your messages and erase '
                  'non-event data. Servers are not required to comply.',
                ),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _showIdServer,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _showIdServer = v ?? false),
                title: const Text('Unbind third-party identifiers'),
                subtitle: const Text(
                  'Provide an identity server to unbind your 3PIDs from. '
                  'Leave off to let the homeserver use the originally bound '
                  'identity server.',
                ),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_showIdServer) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _idServerController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Identity server',
                    hintText: 'https://vector.im',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: cs.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
          ),
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Deactivate'),
        ),
      ],
    );
  }
}
