import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

typedef UrlLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});

/// Schemes safe to hand to the platform from untrusted content. Anything else
/// (`file:`, `javascript:`, `data:`, custom app schemes, ...) is rejected so a
/// crafted message link cannot open local resources or spoof its destination.
const Set<String> kAllowedUrlSchemes = {'http', 'https', 'mailto', 'matrix'};

/// Whether [uri] uses a scheme we are willing to launch.
bool isAllowedUrl(Uri uri) =>
    kAllowedUrlSchemes.contains(uri.scheme.toLowerCase());

/// Parses [rawUrl] and launches it externally, but only when it uses an allowed
/// scheme. Returns `true` when a launch was attempted, `false` when the URL was
/// null, unparseable, or blocked.
Future<bool> safeLaunchUrl(
  String? rawUrl, {
  UrlLauncher launcher = launchUrl,
}) async {
  if (rawUrl == null) return false;
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !isAllowedUrl(uri)) {
    debugPrint('[Kohera] Blocked launch of disallowed URL: $rawUrl');
    return false;
  }
  return launcher(uri, mode: LaunchMode.externalApplication);
}
