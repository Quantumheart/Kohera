import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/pixel_sprite_avatar.dart';
import 'package:kohera/shared/widgets/pixelation_scope.dart';

/// Displays a room's avatar with a colored-initial fallback.
///
/// Resolves the mxc:// [avatarUrl] asynchronously via [avatarResolver] and
/// passes auth headers for authenticated media endpoints.
class RoomAvatarWidget extends StatefulWidget {
  const RoomAvatarWidget({
    required this.avatarUrl,
    required this.displayname,
    this.avatarResolver,
    this.size = 44,
    super.key,
  });

  /// The raw `mxc://` avatar URI as a string, or `null` if the room has no
  /// avatar.
  final String? avatarUrl;

  /// The room display name. Used for the initial fallback.
  final String displayname;

  /// Resolves [avatarUrl] to an HTTP thumbnail URL with auth headers.
  /// If `null`, only the fallback initial is shown.
  final AvatarResolver? avatarResolver;

  final double size;

  @override
  State<RoomAvatarWidget> createState() => _RoomAvatarWidgetState();
}

class _RoomAvatarWidgetState extends State<RoomAvatarWidget> {
  String? _resolvedUrl;
  Map<String, String>? _resolvedHeaders;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveThumbnail());
  }

  @override
  void didUpdateWidget(RoomAvatarWidget oldWidget) {
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
      debugPrint('[Kohera] Failed to resolve room avatar thumbnail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pixelate = PixelationScope.of(context);
    final pixelPx = (widget.size * 0.55).round().clamp(14, 48);
    final fallback =
        PixelSpriteAvatar(seed: widget.displayname, size: widget.size);

    return ClipRRect(
      borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _resolvedUrl != null
            ? CachedNetworkImage(
                imageUrl: _resolvedUrl!,
                httpHeaders: _resolvedHeaders,
                imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
                fit: BoxFit.cover,
                imageBuilder: pixelate
                    ? (context, imageProvider) => Image(
                          image: ResizeImage(
                            imageProvider,
                            width: pixelPx,
                            height: pixelPx,
                          ),
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.none,
                        )
                    : null,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}
