import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';

/// Wraps a [RoomAvatarWidget] with avatar editing controls.
///
/// SDK-free: display data comes from [summary] and [canEditAvatar]; avatar
/// mutations are delegated to [onSetAvatar] (the parent performs the SDK
/// `room.setAvatar` call). Tapping the avatar opens the image picker to
/// upload a new photo; a small "x" badge at the top-right removes the current
/// avatar. Only shows controls if [canEditAvatar] is true.
class AvatarEditOverlay extends StatefulWidget {
  const AvatarEditOverlay({
    required this.roomId,
    required this.summary,
    required this.canEditAvatar,
    required this.avatarResolver,
    required this.onSetAvatar,
    this.size = 72,
    super.key,
  });

  final String roomId;
  final KoheraRoomSummary summary;
  final bool canEditAvatar;
  final AvatarResolver? avatarResolver;

  /// Sets the room avatar. Pass bytes + filename to upload, or `null`/`null` to
  /// remove the avatar. The parent performs the SDK `room.setAvatar` call.
  final Future<void> Function(Uint8List? bytes, String? filename) onSetAvatar;

  final double size;

  @override
  State<AvatarEditOverlay> createState() => _AvatarEditOverlayState();
}

class _AvatarEditOverlayState extends State<AvatarEditOverlay> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.canEditAvatar) {
      return RoomAvatarWidget(
        avatarUrl: widget.summary.avatarUrl,
        displayname: widget.summary.displayname,
        avatarResolver: widget.avatarResolver,
        size: widget.size,
      );
    }

    final cs = Theme.of(context).colorScheme;
    final badgeSize = widget.size * 0.3;
    final badgeOffset = badgeSize * 0.25;

    // Pad all sides equally so the avatar stays centered when the badge
    // protrudes beyond the avatar bounds.
    return Padding(
      padding: EdgeInsets.all(badgeOffset),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          MouseRegion(
            cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _busy ? null : _uploadAvatar,
              child: RoomAvatarWidget(
                avatarUrl: widget.summary.avatarUrl,
                displayname: widget.summary.displayname,
                avatarResolver: widget.avatarResolver,
                size: widget.size,
              ),
            ),
          ),
          if (widget.summary.avatarUrl != null)
            Positioned(
              top: -badgeOffset,
              right: -badgeOffset,
              child: MouseRegion(
                cursor:
                    _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _busy ? null : _removeAvatar,
                  child: Container(
                    width: badgeSize,
                    height: badgeSize,
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: badgeSize * 0.55,
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

  Future<void> _uploadAvatar() async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
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
      await widget.onSetAvatar(bytes, picked.name);
      debugPrint('[Kohera] Room avatar uploaded: ${picked.name} (${bytes.length} bytes)');
      if (mounted) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Avatar updated')),
        );
      }
    } catch (e) {
      debugPrint('[Kohera] Avatar upload failed: $e');
      if (mounted) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Failed to update avatar')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAvatar() async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.onSetAvatar(null, null);
      debugPrint('[Kohera] Room avatar removed');
      if (mounted) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Avatar removed')),
        );
      }
    } catch (e) {
      debugPrint('[Kohera] Avatar removal failed: $e');
      if (mounted) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Failed to remove avatar')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
