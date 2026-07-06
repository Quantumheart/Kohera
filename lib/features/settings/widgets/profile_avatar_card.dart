import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/settings/services/profile_avatar_service.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:provider/provider.dart';

class ProfileAvatarCard extends StatefulWidget {
  const ProfileAvatarCard({super.key});

  @override
  State<ProfileAvatarCard> createState() => _ProfileAvatarCardState();
}

class _ProfileAvatarCardState extends State<ProfileAvatarCard> {
  bool _avatarUploading = false;
  Uri? _avatarUrl;
  String? _displayName;
  final _displayNameController = TextEditingController();
  bool _displayNameSaving = false;
  MatrixService? _profileService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<MatrixService>();
    if (!identical(service, _profileService)) {
      _profileService = service;
      _avatarUrl = null;
      _displayName = null;
      _displayNameController.text = '';
      unawaited(_fetchProfile());
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    try {
      final client = context.read<MatrixService>().client;
      final profile = await client.fetchOwnProfile();
      if (mounted) {
        setState(() {
          _avatarUrl = profile.avatarUrl;
          _displayName = profile.displayName;
          _displayNameController.text = profile.displayName ?? '';
        });
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to fetch profile: $e');
    }
  }

  Future<void> _saveDisplayName() async {
    final newName = _displayNameController.text.trim();
    if (newName == (_displayName ?? '')) return;

    final client = context.read<MatrixService>().client;
    setState(() => _displayNameSaving = true);
    try {
      await client.setProfileField(
        client.userID!, 'displayname', {'displayname': newName},
      );
      debugPrint('[Kohera] Display name updated to: $newName');
      await _fetchProfile();
    } catch (e) {
      debugPrint('[Kohera] Display name update failed: $e');
      if (mounted) {
        context.showSnack(
          'Failed to update display name: '
          '${MatrixService.friendlyAuthError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _displayNameSaving = false);
    }
  }

  Future<void> _uploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _avatarUploading = true);
    try {
      final client = context.read<MatrixService>().client;
      final bytes = await picked.readAsBytes();
      await const ProfileAvatarService().uploadAvatar(
        client,
        bytes,
        picked.name,
      );
      debugPrint('[Kohera] Avatar uploaded: ${picked.name} (${bytes.length} bytes)');
      await _fetchProfile();
    } catch (e) {
      debugPrint('[Kohera] Avatar upload failed: $e');
      if (mounted) {
        context.showSnack(
          'Failed to upload avatar: ${MatrixService.friendlyAuthError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  Future<void> _removeAvatar() async {
    final client = context.read<MatrixService>().client;
    setState(() => _avatarUploading = true);
    try {
      await client.setAvatar(null);
      debugPrint('[Kohera] Avatar removed');
      await _fetchProfile();
    } catch (e) {
      debugPrint('[Kohera] Avatar removal failed: $e');
      if (mounted) {
        context.showSnack(
          'Failed to remove avatar: ${MatrixService.friendlyAuthError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final client = matrix.client;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    UserAvatar(
                      avatarResolver: matrix.avatarResolver,
                      avatarUrl: _avatarUrl?.toString(),
                      userId: client.userID ?? '',
                      displayname: client.userID ?? 'Unknown',
                      size: 56,
                    ),
                    if (_avatarUploading)
                      const Positioned.fill(
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_displayName != null && _displayName!.isNotEmpty)
                        Text(
                          _displayName!,
                          style: tt.titleMedium,
                        ),
                      const SizedBox(height: 2),
                      Text(
                        client.userID ?? 'Unknown',
                        style: _displayName != null && _displayName!.isNotEmpty
                            ? tt.bodyMedium
                            : tt.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        client.homeserver.toString(),
                        style: tt.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _displayNameController,
                    enabled: !_displayNameSaving,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _saveDisplayName(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _displayNameSaving ? null : _saveDisplayName,
                  icon: _displayNameSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  tooltip: 'Save display name',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _avatarUploading ? null : _uploadAvatar,
                  icon: const Icon(Icons.photo_library_outlined,
                      size: 18,),
                  label: const Text('Upload avatar'),
                ),
                if (_avatarUrl != null)
                  OutlinedButton.icon(
                    onPressed: _avatarUploading ? null : _removeAvatar,
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: cs.error,),
                    label: Text('Remove',
                        style: TextStyle(color: cs.error),),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
