import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';

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
    final cs = Theme.of(context).colorScheme;
    final name = widget.displayname;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '#';
    final bgColor = senderColor(name, cs, fallback: cs.primaryContainer);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * 0.28),
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
                  textColor: Colors.white,
                  size: widget.size,
                ),
                errorWidget: (_, __, ___) => _Fallback(
                  initial: initial,
                  bgColor: bgColor,
                  textColor: Colors.white,
                  size: widget.size,
                ),
              )
            : _Fallback(
                initial: initial,
                bgColor: bgColor,
                textColor: Colors.white,
                size: widget.size,
              ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.initial,
    required this.bgColor,
    required this.textColor,
    required this.size,
  });

  final String initial;
  final Color bgColor;
  final Color textColor;
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
          color: textColor,
        ),
      ),
    );
  }
}
