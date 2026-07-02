import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/presence_dot.dart';

/// Displays a user's Matrix avatar with a colored-initial fallback.
///
/// Resolves the mxc:// [avatarUrl] asynchronously via [avatarResolver] and
/// passes auth headers for authenticated media endpoints.
///
/// When [presence] and [userId] are both supplied, an opt-in status dot is
/// overlaid on the bottom-right. Unknown presence renders no dot.
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    required this.userId,
    required this.displayname,
    this.avatarUrl,
    this.avatarResolver,
    this.size = 44,
    this.presence,
    super.key,
  });

  /// The Matrix user ID (e.g. `@alice:example.com`). Used for the initial
  /// fallback and the presence dot.
  final String userId;

  /// The resolved display name. Currently unused for rendering (the initial
  /// is derived from [userId] to preserve existing behaviour) but stored for
  /// future tooltip/accessibility use.
  final String displayname;

  /// The raw `mxc://` avatar URI as a string, or `null` if the user has no
  /// avatar.
  final String? avatarUrl;

  /// Resolves [avatarUrl] to an HTTP thumbnail URL with auth headers.
  /// If `null`, only the fallback initial is shown.
  final AvatarResolver? avatarResolver;

  final double size;
  final PresenceService? presence;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  String? _resolvedUrl;
  Map<String, String>? _resolvedHeaders;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveThumbnail());
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _resolvedUrl = null;
      _resolvedHeaders = null;
      unawaited(_resolveThumbnail());
    }
  }

  Future<void> _resolveThumbnail() async {
    final resolver = widget.avatarResolver;
    if (resolver == null) return;
    try {
      final result = await resolver.resolve(
        widget.avatarUrl,
        size: widget.size,
      );
      if (mounted && result != null) {
        setState(() {
          _resolvedUrl = result.url;
          _resolvedHeaders = result.headers;
        });
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to resolve avatar thumbnail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = _userInitial(widget.userId);
    final bgColor = senderColor(widget.userId, cs, fallback: cs.primaryContainer);

    final avatar = ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _resolvedUrl != null
            ? CachedNetworkImage(
                imageUrl: _resolvedUrl!,
                httpHeaders: _resolvedHeaders,
                imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
                fit: BoxFit.cover,
                placeholder: (_, __) => _Fallback(
                  initial: initial,
                  bgColor: bgColor,
                  size: widget.size,
                ),
                errorWidget: (_, __, ___) => _Fallback(
                  initial: initial,
                  bgColor: bgColor,
                  size: widget.size,
                ),
              )
            : _Fallback(
                initial: initial,
                bgColor: bgColor,
                size: widget.size,
              ),
      ),
    );

    return PresenceOverlay(
      size: widget.size,
      presence: widget.presence,
      userId: widget.userId,
      child: avatar,
    );
  }

  static String _userInitial(String userId) {
    if (userId.isEmpty) return '?';
    if (userId.length > 1) return userId[1].toUpperCase();
    return userId[0].toUpperCase();
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.initial,
    required this.bgColor,
    required this.size,
  });

  final String initial;
  final Color bgColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: bgColor,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
