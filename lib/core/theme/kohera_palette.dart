import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// A [ThemeExtension] that defines pixel-specific color and style tokens.
///
/// This extension provides the color and style tokens needed for the pixel
/// aesthetic that are not covered by Material's [ColorScheme].
class KoheraPalette extends ThemeExtension<KoheraPalette> {
  const KoheraPalette({
    required this.borderStrong,
    required this.borderWidth,
    required this.shadowHard,
    required this.shadowOffset,
    required this.radius,
    required this.online,
    required this.idle,
    required this.unread,
    required this.onUnread,
    required this.mention,
    required this.link,
    required this.ownBubble,
    required this.onOwnBubble,
    required this.otherBubble,
    required this.onOtherBubble,
    required this.success,
    required this.warning,
    required this.danger,
    required this.scanline,
    required this.dither,
    required this.accentRamp,
  });

  /// The strong border color used for the 2px hard outline on every surface.
  final Color borderStrong;

  /// The outline thickness.
  final double borderWidth;

  /// Solid offset drop-shadow color (no blur).
  final Color shadowHard;

  /// Shadow displacement in pixels.
  final double shadowOffset;

  /// Corner radius - 0 for sharp corners, can be swappable for "soft-pixel" mode.
  final double radius;

  /// Presence dot color for online users.
  final Color online;

  /// Presence dot color for idle users.
  final Color idle;

  /// Unread badge fill color.
  final Color unread;

  /// Unread badge text color.
  final Color onUnread;

  /// Highlight color for @-mentions / keywords.
  final Color mention;

  /// Hyperlinks and own-message accent color.
  final Color link;

  /// Your sent messages bubble color.
  final Color ownBubble;

  /// Text color on your sent messages bubble.
  final Color onOwnBubble;

  /// Received messages bubble color.
  final Color otherBubble;

  /// Text color on received messages bubble.
  final Color onOtherBubble;

  /// Semantic success color, independent of accent.
  final Color success;

  /// Semantic warning color, independent of accent.
  final Color warning;

  /// Semantic danger color, independent of accent.
  final Color danger;

  /// Overlay tint for scanlines (0 opacity disables).
  final Color scanline;

  /// Panel dither texture tint.
  final Color dither;

  /// Seeds for multi-color wordmark & procedural avatars.
  final List<Color> accentRamp;

  /// The active [KoheraPalette] for [context], falling back to one derived
  /// from the [ColorScheme] when the theme declares no extension (e.g. widget
  /// tests using a bare [ThemeData]).
  factory KoheraPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<KoheraPalette>() ??
        KoheraPalette.fromColorScheme(theme.colorScheme, theme.brightness);
  }

  /// Creates a PICO-8 inspired palette.
  factory KoheraPalette.pico8(Brightness brightness) {
    // PICO-8 color palette (https://www.lexaloffle.com/pico-8.php)
    const pico8Colors = [
      Color(0xFF000000), // 0: black
      Color(0xFF1D2B53), // 1: dark-blue
      Color(0xFF7E2553), // 2: dark-purple
      Color(0xFF008751), // 3: dark-green
      Color(0xFFAB5236), // 4: brown
      Color(0xFF5F574F), // 5: dark-gray
      Color(0xFFC2C3C7), // 6: light-gray
      Color(0xFFFFF1E8), // 7: white
      Color(0xFFFF004D), // 8: red
      Color(0xFFFFA300), // 9: orange
      Color(0xFFFFEC27), // 10: yellow
      Color(0xFF00E436), // 11: green
      Color(0xFF29ADFF), // 12: blue
      Color(0xFF83769C), // 13: lavender
      Color(0xFFFF77A8), // 14: pink
      Color(0xFFFFCCAA), // 15: light-peach
    ];

    // For dark mode, we use the standard PICO-8 colors as specified in the spec
    // For light mode, we adjust some colors for better contrast
    if (brightness == Brightness.dark) {
      return KoheraPalette(
        borderStrong: pico8Colors[0], // #000000 black
        borderWidth: 2,
        shadowHard: pico8Colors[2], // #7E2553 dark-purple
        shadowOffset: 3,
        radius: 0,
        online: pico8Colors[11], // #00E436 green
        idle: pico8Colors[11], // #00E436 green (same as online per spec)
        unread: pico8Colors[14], // #FF77A8 pink
        onUnread: pico8Colors[0], // #000000 black
        mention: pico8Colors[10], // #FFEC27 yellow
        link: pico8Colors[12], // #29ADFF blue
        ownBubble: const Color(0xFF0B2B3F), // custom dark blue (spec)
        onOwnBubble: pico8Colors[7], // #FFF1E8 white
        otherBubble: const Color(0xFF0E1638), // custom dark navy (spec)
        onOtherBubble: pico8Colors[7], // #FFF1E8 white
        success: pico8Colors[11], // #00E436 green (11)
        warning: pico8Colors[9], // #FFA300 orange (9)
        danger: pico8Colors[8], // #FF004D red (8)
        scanline: pico8Colors[0].withValues(alpha: 0.18), // #000000 @ .18
        dither: pico8Colors[1], // #1D2B53 dark-blue
        accentRamp: [
          pico8Colors[14], // 14: pink
          pico8Colors[9], // 9: orange
          pico8Colors[10], // 10: yellow
          pico8Colors[11], // 11: green
          pico8Colors[12], // 12: blue
          pico8Colors[13], // 13: lavender
        ],
      );
    } else {
      // Light mode — designed counterpart for light background
      return KoheraPalette(
        borderStrong: pico8Colors[0], // #000000 black
        borderWidth: 2,
        shadowHard: pico8Colors[2], // #7E2553 dark-purple
        shadowOffset: 3,
        radius: 0,
        online: pico8Colors[3], // #008751 dark-green (darker for light bg)
        idle: pico8Colors[3], // #008751 dark-green (same as online per spec)
        unread: pico8Colors[8], // #FF004D red (darker for light bg)
        onUnread: pico8Colors[7], // #FFF1E8 white
        mention: pico8Colors[10], // #FFEC27 yellow
        link: pico8Colors[1], // #1D2B53 dark-blue (darker for light bg)
        ownBubble: pico8Colors[12], // #29ADFF blue (bright for own messages)
        onOwnBubble: pico8Colors[0], // #000000 black
        otherBubble: pico8Colors[6], // #C2C3C7 light-gray
        onOtherBubble: pico8Colors[0], // #000000 black
        success: pico8Colors[3], // #008751 dark-green
        warning: pico8Colors[9], // #FFA300 orange (9)
        danger: pico8Colors[8], // #FF004D red (8)
        scanline: pico8Colors[0].withValues(alpha: 0.18), // #000000 @ .18
        dither: pico8Colors[15], // #FFCCAA light-peach
        accentRamp: [
          pico8Colors[14], // 14: pink
          pico8Colors[9], // 9: orange
          pico8Colors[10], // 10: yellow
          pico8Colors[11], // 11: green
          pico8Colors[12], // 12: blue
          pico8Colors[13], // 13: lavender
        ],
      );
    }
  }

  /// Derives a [KoheraPalette] from a Material [ColorScheme].
  ///
  /// Used for non-pixel color presets and dynamic (wallpaper) color so their
  /// pixel tokens match their own palette instead of inheriting PICO-8's.
  factory KoheraPalette.fromColorScheme(ColorScheme cs, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return KoheraPalette(
      borderStrong: isDark ? const Color(0xFF000000) : const Color(0xFF1B1B1B),
      borderWidth: 2,
      shadowHard:
          Color.alphaBlend(cs.shadow.withValues(alpha: 0.55), cs.surface),
      shadowOffset: 3,
      radius: 0,
      online: const Color(0xFF3BA55D),
      idle: const Color(0xFFE0A72C),
      unread: cs.primary,
      onUnread: cs.onPrimary,
      mention: cs.tertiary,
      link: cs.primary,
      ownBubble: cs.primaryContainer,
      onOwnBubble: cs.onPrimaryContainer,
      otherBubble: cs.surfaceContainerHigh,
      onOtherBubble: cs.onSurface,
      success: const Color(0xFF3BA55D),
      warning: const Color(0xFFE0A72C),
      danger: cs.error,
      scanline: const Color(0xFF000000).withValues(alpha: 0.18),
      dither: cs.surfaceContainerHighest,
      accentRamp: [
        cs.primary,
        cs.secondary,
        cs.tertiary,
        cs.error,
        cs.primaryContainer,
        cs.secondaryContainer,
      ],
    );
  }

  /// Creates a Game Boy DMG inspired palette.
  factory KoheraPalette.gameboy(Brightness brightness) {
    // Game Boy DMG color palette
    const gameboyColors = [
      Color(0xFF0F380F), // darkest green
      Color(0xFF306230), // dark green
      Color(0xFF8BAC0F), // light green
      Color(0xFF9BBC0F), // lightest green
    ];

    if (brightness == Brightness.dark) {
      return KoheraPalette(
        borderStrong: gameboyColors[0], // darkest green
        borderWidth: 2,
        shadowHard: gameboyColors[0], // darkest green
        shadowOffset: 3,
        radius: 0,
        online: gameboyColors[2], // light green
        idle: gameboyColors[3], // lightest green
        unread: gameboyColors[2], // light green
        onUnread: gameboyColors[0], // darkest green
        mention: gameboyColors[3], // lightest green
        link: gameboyColors[2], // light green
        ownBubble: gameboyColors[2], // light green (dark text)
        onOwnBubble: gameboyColors[0], // darkest green
        otherBubble: gameboyColors[1], // dark green — distinct from darkest surface
        onOtherBubble: gameboyColors[3], // lightest green
        success: gameboyColors[2], // light green
        warning: gameboyColors[3], // lightest green
        danger: gameboyColors[0], // darkest green
        scanline: gameboyColors[0].withValues(alpha: 0.18), // darkest green with 18% opacity
        dither: gameboyColors[1], // dark green
        accentRamp: [
          gameboyColors[3], // lightest green
          gameboyColors[2], // light green
          gameboyColors[1], // dark green
          gameboyColors[0], // darkest green
        ],
      );
    } else {
      return KoheraPalette(
        borderStrong: gameboyColors[0], // darkest green
        borderWidth: 2,
        shadowHard: gameboyColors[0], // darkest green
        shadowOffset: 3,
        radius: 0,
        online: gameboyColors[2], // light green
        idle: gameboyColors[3], // lightest green
        unread: gameboyColors[2], // light green
        onUnread: gameboyColors[3], // lightest green
        mention: gameboyColors[3], // lightest green
        link: gameboyColors[2], // light green
        ownBubble: gameboyColors[1], // dark green — distinct from lightest surface
        onOwnBubble: gameboyColors[3], // lightest green
        otherBubble: gameboyColors[2], // light green (dark text)
        onOtherBubble: gameboyColors[0], // darkest green
        success: gameboyColors[2], // light green
        warning: gameboyColors[3], // lightest green
        danger: gameboyColors[0], // darkest green
        scanline: gameboyColors[0].withValues(alpha: 0.18), // darkest green with 18% opacity
        dither: gameboyColors[1], // dark green
        accentRamp: [
          gameboyColors[0], // darkest green
          gameboyColors[1], // dark green
          gameboyColors[2], // light green
          gameboyColors[3], // lightest green
        ],
      );
    }
  }

  /// Creates a "Paper" palette — ink on warm paper (light-native), with a
  /// designed dark "night paper" counterpart.
  factory KoheraPalette.paper(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const KoheraPalette(
        borderStrong: Color(0xFF0E0D0B),
        borderWidth: 2,
        shadowHard: Color(0xFF000000),
        shadowOffset: 3,
        radius: 0,
        online: Color(0xFF7FB069),
        idle: Color(0xFFD9A441),
        unread: Color(0xFFC46A5B),
        onUnread: Color(0xFF15130F),
        mention: Color(0xFFD9A441),
        link: Color(0xFF7FA6C9),
        ownBubble: Color(0xFF2A2822),
        onOwnBubble: Color(0xFFEDE6D2),
        otherBubble: Color(0xFF1C1A15),
        onOtherBubble: Color(0xFFEDE6D2),
        success: Color(0xFF7FB069),
        warning: Color(0xFFD9A441),
        danger: Color(0xFFC46A5B),
        scanline: Color(0x2E000000), // black @ ~18%
        dither: Color(0xFF2A2822),
        accentRamp: [
          Color(0xFFC46A5B),
          Color(0xFF7FA6C9),
          Color(0xFFD9A441),
          Color(0xFF7FB069),
          Color(0xFF9C8BB0),
          Color(0xFFB58B6A),
        ],
      );
    }
    return const KoheraPalette(
      borderStrong: Color(0xFF2B2620),
      borderWidth: 2,
      shadowHard: Color(0xFFBEB5A0), // warm gray
      shadowOffset: 3,
      radius: 0,
      online: Color(0xFF4E7A3A),
      idle: Color(0xFFB07D1F),
      unread: Color(0xFFB0453A),
      onUnread: Color(0xFFFBF7EC),
      mention: Color(0xFFC9A227),
      link: Color(0xFF3A6EA5),
      ownBubble: Color(0xFFE8E0CC),
      onOwnBubble: Color(0xFF2B2620),
      otherBubble: Color(0xFFFBF7EC),
      onOtherBubble: Color(0xFF2B2620),
      success: Color(0xFF4E7A3A),
      warning: Color(0xFFB07D1F),
      danger: Color(0xFFB0453A),
      scanline: Color(0x1A000000), // black @ ~10% (lighter for paper)
      dither: Color(0xFFDED5C0),
      accentRamp: [
        Color(0xFFB0453A),
        Color(0xFF3A6EA5),
        Color(0xFFC9A227),
        Color(0xFF4E7A3A),
        Color(0xFF6D5D8A),
        Color(0xFF8A6D4A),
      ],
    );
  }

  /// Creates a SNES-inspired palette — 16-bit soft-beveled pixel theme
  /// (snes.css inspired, revised spec). Grey #e5e5e5 light surface (snes.css
  /// default canvas), aged-yellow #fcf4d9 as an elevated accent + dark
  /// onSurface text, phantom purple #9b5de5 primary, dusk #2c3e50 text/border,
  /// 9-color snes.css accent ramp. radius 4 (soft-pixel), shadowOffset 6
  /// (wide grid), translucent shadowHard rgba(#000,0.2).
  factory KoheraPalette.snes(Brightness brightness) {
    const phantomPurple = Color(0xFF9b5de5);
    const oceanBlue = Color(0xFF4eb6d9);
    const sunshineYellow = Color(0xFFf2c019);
    const natureGreen = Color(0xFF4bb244);
    const plumberRed = Color(0xFFf22561);
    const rose = Color(0xFFf784b2);
    const galaxyBlue = Color(0xFF5a7d9a);
    const lavaOrange = Color(0xFFff6f00);

    const dusk = Color(0xFF2c3e50);
    const agedYellow = Color(0xFFfcf4d9);
    const secondaryPurple = Color(0xFFf0e4ff);
    const turquoise = Color(0xFF40e0d0);

    if (brightness == Brightness.dark) {
      return const KoheraPalette(
        borderStrong: dusk,
        borderWidth: 2,
        shadowHard: Color(0x33000000),
        shadowOffset: 6,
        radius: 4,
        online: natureGreen,
        idle: sunshineYellow,
        unread: plumberRed,
        onUnread: Color(0xFFFFFFFF),
        mention: sunshineYellow,
        link: oceanBlue,
        ownBubble: phantomPurple,
        onOwnBubble: Color(0xFFFFFFFF),
        otherBubble: Color(0xFF384a5c),
        onOtherBubble: agedYellow,
        success: natureGreen,
        warning: sunshineYellow,
        danger: plumberRed,
        scanline: Color(0x2E000000),
        dither: Color(0xFFf0e4ff),
        accentRamp: [
          plumberRed,
          natureGreen,
          sunshineYellow,
          oceanBlue,
          turquoise,
          phantomPurple,
          rose,
          galaxyBlue,
          lavaOrange,
        ],
      );
    }
    return const KoheraPalette(
      borderStrong: dusk,
      borderWidth: 2,
      shadowHard: Color(0x33000000),
      shadowOffset: 6,
      radius: 4,
      online: Color(0xFF2f7d2a),
      idle: Color(0xFFb8900f),
      unread: Color(0xFFc41a4d),
      onUnread: Color(0xFFFFFFFF),
      mention: Color(0xFFb8900f),
      link: Color(0xFF2a6d8a),
      ownBubble: Color(0xFF7b3dc4),             // deeper phantom purple — light-mode contrast + brightness adaptation
      onOwnBubble: Color(0xFFFFFFFF),
      otherBubble: secondaryPurple,
      onOtherBubble: dusk,
      success: Color(0xFF2f7d2a),
      warning: Color(0xFFb8900f),
      danger: Color(0xFFc41a4d),
      scanline: Color(0x1A000000),
      dither: Color(0xFFdcdcdc),
      accentRamp: [
        plumberRed,
        natureGreen,
        sunshineYellow,
        oceanBlue,
        turquoise,
        phantomPurple,
        rose,
        galaxyBlue,
        lavaOrange,
      ],
    );
  }

  @override
  KoheraPalette copyWith({
    Color? borderStrong,
    double? borderWidth,
    Color? shadowHard,
    double? shadowOffset,
    double? radius,
    Color? online,
    Color? idle,
    Color? unread,
    Color? onUnread,
    Color? mention,
    Color? link,
    Color? ownBubble,
    Color? onOwnBubble,
    Color? otherBubble,
    Color? onOtherBubble,
    Color? success,
    Color? warning,
    Color? danger,
    Color? scanline,
    Color? dither,
    List<Color>? accentRamp,
  }) {
    return KoheraPalette(
      borderStrong: borderStrong ?? this.borderStrong,
      borderWidth: borderWidth ?? this.borderWidth,
      shadowHard: shadowHard ?? this.shadowHard,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      radius: radius ?? this.radius,
      online: online ?? this.online,
      idle: idle ?? this.idle,
      unread: unread ?? this.unread,
      onUnread: onUnread ?? this.onUnread,
      mention: mention ?? this.mention,
      link: link ?? this.link,
      ownBubble: ownBubble ?? this.ownBubble,
      onOwnBubble: onOwnBubble ?? this.onOwnBubble,
      otherBubble: otherBubble ?? this.otherBubble,
      onOtherBubble: onOtherBubble ?? this.onOtherBubble,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      scanline: scanline ?? this.scanline,
      dither: dither ?? this.dither,
      accentRamp: accentRamp ?? this.accentRamp,
    );
  }

  @override
  KoheraPalette lerp(ThemeExtension<KoheraPalette>? other, double t) {
    if (other is! KoheraPalette) {
      return this;
    }

    return KoheraPalette(
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t)!,
      shadowHard: Color.lerp(shadowHard, other.shadowHard, t)!,
      shadowOffset: lerpDouble(shadowOffset, other.shadowOffset, t)!,
      radius: lerpDouble(radius, other.radius, t)!,
      online: Color.lerp(online, other.online, t)!,
      idle: Color.lerp(idle, other.idle, t)!,
      unread: Color.lerp(unread, other.unread, t)!,
      onUnread: Color.lerp(onUnread, other.onUnread, t)!,
      mention: Color.lerp(mention, other.mention, t)!,
      link: Color.lerp(link, other.link, t)!,
      ownBubble: Color.lerp(ownBubble, other.ownBubble, t)!,
      onOwnBubble: Color.lerp(onOwnBubble, other.onOwnBubble, t)!,
      otherBubble: Color.lerp(otherBubble, other.otherBubble, t)!,
      onOtherBubble: Color.lerp(onOtherBubble, other.onOtherBubble, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      scanline: Color.lerp(scanline, other.scanline, t)!,
      dither: Color.lerp(dither, other.dither, t)!,
      accentRamp: _lerpColorList(accentRamp, other.accentRamp, t),
    );
  }

  /// Linear interpolation between two color lists.
  static List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    if (a.length != b.length) {
      // If lengths don't match, return the list that's closer to t
      return t < 0.5 ? a : b;
    }

    final result = <Color>[];
    for (var i = 0; i < a.length; i++) {
      result.add(Color.lerp(a[i], b[i], t)!);
    }
    return result;
  }
}

/// Creates a [BoxDecoration] with the pixel aesthetic using tokens from [KoheraPalette].
///
/// This helper function provides a consistent way to apply the pixel styling
/// throughout the app.
BoxDecoration pixelBox(BuildContext context, {Color? fill}) {
  final palette = KoheraPalette.of(context);
  return BoxDecoration(
    color: fill ?? Theme.of(context).colorScheme.surface,
    border: Border.all(color: palette.borderStrong, width: palette.borderWidth),
    borderRadius: BorderRadius.circular(palette.radius),
    boxShadow: [
      BoxShadow(
        color: palette.shadowHard,
        offset: Offset(palette.shadowOffset, palette.shadowOffset),
      ),
    ],
  );
}
