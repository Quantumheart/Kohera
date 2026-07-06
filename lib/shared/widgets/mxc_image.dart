import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/shared/services/media_resolver.dart';

class MxcImage extends StatefulWidget {
  const MxcImage({
    required this.mxcUrl,
    required this.mediaResolver,
    required this.fallbackText,
    required this.fallbackStyle,
    this.width,
    this.height,
    this.fit,
    super.key,
  });

  final String mxcUrl;
  final MediaResolver? mediaResolver;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final String fallbackText;
  final TextStyle? fallbackStyle;

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<MxcImage> {
  String? _resolvedUrl;
  Map<String, String>? _resolvedHeaders;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(MxcImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mxcUrl != widget.mxcUrl) {
      _resolvedUrl = null;
      _resolvedHeaders = null;
      _loading = true;
      unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final resolver = widget.mediaResolver;
    if (resolver == null) {
      if (mounted) {
        setState(() {
          _resolvedUrl = widget.mxcUrl.startsWith('http') ? widget.mxcUrl : null;
          _loading = false;
        });
      }
      return;
    }

    try {
      final result = await resolver.resolve(
        widget.mxcUrl,
        width: widget.width,
        height: widget.height,
      );
      if (mounted) {
        setState(() {
          _resolvedUrl = result?.url;
          _resolvedHeaders = result?.headers;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to resolve mxc image: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
      );
    }

    if (_resolvedUrl == null) {
      return Text(widget.fallbackText, style: widget.fallbackStyle);
    }

    return Image.network(
      _resolvedUrl!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      headers: _resolvedHeaders,
      errorBuilder: (_, _, _) => Text(widget.fallbackText, style: widget.fallbackStyle),
    );
  }
}
