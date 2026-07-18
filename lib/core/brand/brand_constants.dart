import 'package:flutter/material.dart';

/// Single source of truth for Kohera brand identity.
///
/// Consumed by the in-app shell ([MaterialApp.title], notification channel name)
/// and by the native/web shell codegen ([scripts/generate_brand_shells.dart]).
/// Keep values in sync with `plans/brand_*.md` briefs.
class BrandConstants {
  BrandConstants._();

  /// Human-readable app name. Used for window titles, notifications, OS labels.
  static const String appName = 'Kohera';

  /// Brand tagline. Auth header + README hero + store listings.
  static const String tagline = 'Coherent threads, encrypted.';

  /// One-to-two sentence description for manifest, store listings, README.
  static const String description =
      'Kohera is a retro-pixel Matrix chat client — coherent threads for '
      'encrypted messaging, voice/video calls, and spaces. Built with Flutter, '
      'runs on desktop, mobile, and web.';

  /// Brand signature color: Flutter blue (the theme seed + web theme-color).
  static const Color brandColor = Color(0xFF1976D2);

  /// Windows AppUserModelID (reverse-DNS, keep lowercase).
  static const String appUserModelId = 'io.github.quantumheart.kohera';
}
