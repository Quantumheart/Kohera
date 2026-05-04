import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:image_picker/image_picker.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:matrix/matrix.dart';

enum _Step { basics, settings, children }

class SpaceWizard extends StatefulWidget {
  const SpaceWizard({
    required this.matrixService,
    this.parentSpace,
    super.key,
  });

  final MatrixService matrixService;
  final Room? parentSpace;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
    Room? parentSpace,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SpaceWizard(
        matrixService: matrixService,
        parentSpace: parentSpace,
      ),
    );
  }

  @override
  State<SpaceWizard> createState() => _SpaceWizardState();
}

class _SpaceWizardState extends State<SpaceWizard> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();

  _Step _step = _Step.basics;
  MatrixFile? _avatarFile;
  bool _isPublic = false;
  late bool _enableFederation;
  bool _loading = false;
  String? _nameError;
  String? _networkError;

  bool get _isSubspace => widget.parentSpace != null;

  @override
  void initState() {
    super.initState();
    _enableFederation = _isSubspace;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  // ── Step navigation ─────────────────────────────────────────────

  void _next() {
    if (_step == _Step.basics) {
      if (_nameController.text.trim().isEmpty) {
        setState(() => _nameError = 'Name is required');
        return;
      }
      setState(() => _step = _Step.settings);
    } else if (_step == _Step.settings) {
      setState(() => _step = _Step.children);
    }
  }

  void _back() {
    if (_step == _Step.settings) {
      setState(() => _step = _Step.basics);
    } else if (_step == _Step.children) {
      setState(() => _step = _Step.settings);
    }
  }

  // ── Avatar picker ───────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _avatarFile = MatrixFile(bytes: bytes, name: picked.name);
      });
    } catch (e) {
      debugPrint('[Kohera] Space wizard avatar pick failed: $e');
    }
  }

  void _clearAvatar() {
    setState(() => _avatarFile = null);
  }

  // ── Submit ──────────────────────────────────────────────────────

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _step = _Step.basics;
        _nameError = 'Name is required';
      });
      return;
    }

    setState(() {
      _loading = true;
      _networkError = null;
    });

    final scaffold = ScaffoldMessenger.of(context);
    final selection = widget.matrixService.selection;

    try {
      final client = widget.matrixService.client;
      final topic = _topicController.text.trim();

      final roomId = await client.createRoom(
        name: name,
        topic: topic.isNotEmpty ? topic : null,
        creationContent: {
          'type': 'm.space',
          if (!_enableFederation) 'm.federate': false,
        },
        visibility: _isPublic ? Visibility.public : Visibility.private,
        powerLevelContentOverride: {'events_default': 100},
      );

      await client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));

      var avatarFailed = false;
      if (_avatarFile != null) {
        final room = client.getRoomById(roomId);
        if (room != null) {
          try {
            await room.setAvatar(_avatarFile);
          } catch (e) {
            debugPrint('[Kohera] Space avatar upload failed: $e');
            avatarFailed = true;
          }
        }
      }

      var childLinkFailed = false;
      if (_isSubspace) {
        try {
          await widget.parentSpace!.setSpaceChild(roomId);
          widget.matrixService.selection.invalidateSpaceTree();
        } catch (e) {
          debugPrint('[Kohera] Space wizard setSpaceChild failed: $e');
          childLinkFailed = true;
        }
      } else {
        selection.selectSpace(roomId);
      }

      debugPrint('[Kohera] Space created: $roomId (subspace=$_isSubspace)');

      if (!mounted) return;
      Navigator.pop(context);

      if (avatarFailed) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Avatar upload failed')),
        );
      }
      if (childLinkFailed) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Failed to add to parent space')),
        );
      }
    } on TimeoutException {
      debugPrint('[Kohera] Space wizard timed out');
      if (!mounted) return;
      setState(() => _networkError =
          'Timed out waiting for the server. The space may still be created.',);
    } catch (e) {
      debugPrint('[Kohera] Space wizard failed: $e');
      if (!mounted) return;
      setState(() => _networkError = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────

  String get _title => _isSubspace
      ? 'Create subspace in "${widget.parentSpace!.getLocalizedDisplayname()}"'
      : 'Create Space';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= HomeShell.wideBreakpoint;

    return PopScope(
      canPop: !_loading,
      child: isWide ? _buildWide(context) : _buildNarrow(context),
    );
  }

  Widget _buildWide(BuildContext context) {
    return AlertDialog(
      title: Text(
        _title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      content: SizedBox(
        width: 520,
        height: 520,
        child: _buildBody(context),
      ),
      actions: _buildActions(context),
    );
  }

  Widget _buildNarrow(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: _loading ? null : () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(child: _buildBody(context)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _buildActions(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _StepDots(current: _step.index, total: 3),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: switch (_step) {
              _Step.basics => _buildBasics(context),
              _Step.settings => _buildSettings(context),
              _Step.children => _buildChildren(context),
            },
          ),
        ),
        if (_networkError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _networkError!,
              style: TextStyle(color: cs.error, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildBasics(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _AvatarPicker(
          file: _avatarFile,
          onPick: _loading ? null : _pickAvatar,
          onClear: _loading ? null : _clearAvatar,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameController,
          autofocus: true,
          enabled: !_loading,
          decoration: InputDecoration(
            labelText: 'Name',
            border: const OutlineInputBorder(),
            errorText: _nameError,
          ),
          onChanged: (_) => setState(() {
            if (_nameError != null && _nameController.text.trim().isNotEmpty) {
              _nameError = null;
            }
          }),
          onSubmitted: (_) => _next(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _topicController,
          enabled: !_loading,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Topic (optional)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildSettings(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Public space'),
          subtitle: Text(
            'Anyone with the address can join.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          value: _isPublic,
          onChanged:
              _loading ? null : (v) => setState(() => _isPublic = v),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text('Allow federation'),
          subtitle: Text(
            'Cannot be changed later.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          value: _enableFederation,
          onChanged: _loading
              ? null
              : (v) => setState(() => _enableFederation = v),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildChildren(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_special_outlined, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Add rooms & subspaces',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Coming in the next release. After creating this space, '
                'you can add existing rooms and subspaces from the room list.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final canNext = _step != _Step.basics ||
        _nameController.text.trim().isNotEmpty;

    Widget spinner() => const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );

    return switch (_step) {
      _Step.basics => [
          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _loading || !canNext ? null : _next,
            child: const Text('Next'),
          ),
        ],
      _Step.settings => [
          TextButton(
            onPressed: _loading ? null : _back,
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: _loading ? null : _next,
            child: const Text('Next'),
          ),
        ],
      _Step.children => [
          TextButton(
            onPressed: _loading ? null : _back,
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: _loading ? null : _create,
            child: _loading ? spinner() : const Text('Create'),
          ),
        ],
    };
  }
}

// ── Avatar picker ───────────────────────────────────────────────

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.file,
    required this.onPick,
    required this.onClear,
  });

  final MatrixFile? file;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFile = file != null;

    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          GestureDetector(
            onTap: onPick,
            child: ClipOval(
              child: hasFile
                  ? Image.memory(
                      file!.bytes,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 96,
                      height: 96,
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 36,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          if (hasFile)
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: cs.errorContainer,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: cs.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Step dots ───────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final isActive = i <= current;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? cs.primary : cs.outlineVariant,
            ),
          ),
        );
      }),
    );
  }
}
