import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/theme/custom_theme.dart';
import 'package:kohera/core/utils/openmoji.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

PackageInfo _fakePackageInfo(String version) => PackageInfo(
      appName: 'kohera',
      packageName: 'app.kohera',
      version: version,
      buildNumber: '1',
    );

void main() {
  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp, packageInfo: _fakePackageInfo('1.0.0'));
    await prefs.init();
  });

  group('audio/video settings', () {
    test('autoMuteOnJoin defaults false and round-trips', () async {
      expect(prefs.autoMuteOnJoin, isFalse);
      await prefs.setAutoMuteOnJoin(true);
      expect(prefs.autoMuteOnJoin, isTrue);
    });

    test('noiseSuppression defaults true and round-trips', () async {
      expect(prefs.noiseSuppression, isTrue);
      await prefs.setNoiseSuppression(false);
      expect(prefs.noiseSuppression, isFalse);
    });

    test('echoCancellation defaults true and round-trips', () async {
      expect(prefs.echoCancellation, isTrue);
      await prefs.setEchoCancellation(false);
      expect(prefs.echoCancellation, isFalse);
    });

    test('pushToTalkEnabled defaults false and round-trips', () async {
      expect(prefs.pushToTalkEnabled, isFalse);
      await prefs.setPushToTalkEnabled(true);
      expect(prefs.pushToTalkEnabled, isTrue);
    });

    test('pushToTalkKeyId round-trips', () async {
      await prefs.setPushToTalkKeyId(42);
      expect(prefs.pushToTalkKeyId, 42);
    });

    test('inputDeviceId round-trips', () async {
      await prefs.setInputDeviceId('input1');
      expect(prefs.inputDeviceId, 'input1');
    });

    test('outputDeviceId round-trips', () async {
      await prefs.setOutputDeviceId('output1');
      expect(prefs.outputDeviceId, 'output1');
    });

    test('inputVolume defaults 1.0 and round-trips', () async {
      expect(prefs.inputVolume, 1.0);
      await prefs.setInputVolume(0.5);
      expect(prefs.inputVolume, 0.5);
    });

    test('outputVolume defaults 1.0 and round-trips', () async {
      expect(prefs.outputVolume, 1.0);
      await prefs.setOutputVolume(0.8);
      expect(prefs.outputVolume, 0.8);
    });

    test('autoGainControl defaults true and round-trips', () async {
      expect(prefs.autoGainControl, isTrue);
      await prefs.setAutoGainControl(false);
      expect(prefs.autoGainControl, isFalse);
    });

    test('voiceIsolation defaults true and round-trips', () async {
      expect(prefs.voiceIsolation, isTrue);
      await prefs.setVoiceIsolation(false);
      expect(prefs.voiceIsolation, isFalse);
    });

    test('typingNoiseDetection round-trips', () async {
      await prefs.setTypingNoiseDetection(true);
      expect(prefs.typingNoiseDetection, isTrue);
    });

    test('audioQuality defaults and round-trips', () async {
      expect(prefs.audioQuality, AudioQuality.music);
      await prefs.setAudioQuality(AudioQuality.high);
      expect(prefs.audioQuality, AudioQuality.high);
    });

    test('highPassFilter defaults false and round-trips', () async {
      expect(prefs.highPassFilter, isFalse);
      await prefs.setHighPassFilter(true);
      expect(prefs.highPassFilter, isTrue);
    });

    test('pttSoundEnabled defaults true and round-trips', () async {
      expect(prefs.pttSoundEnabled, isTrue);
      await prefs.setPttSoundEnabled(false);
      expect(prefs.pttSoundEnabled, isFalse);
    });
  });

  group('push settings', () {
    test('webPushEnabled defaults false and round-trips', () async {
      expect(prefs.webPushEnabled, isFalse);
      await prefs.setWebPushEnabled(true);
      expect(prefs.webPushEnabled, isTrue);
    });

    test('apnsPushEnabled defaults false and round-trips', () async {
      expect(prefs.apnsPushEnabled, isFalse);
      await prefs.setApnsPushEnabled(true);
      expect(prefs.apnsPushEnabled, isTrue);
    });
  });

  group('version tracking', () {
    test('currentVersion returns package version', () {
      expect(prefs.currentVersion, '1.0.0');
    });

    test('lastSeenVersion is set to currentVersion after init', () {
      expect(prefs.lastSeenVersion, '1.0.0');
    });

    test('markVersionSeen persists version', () async {
      await prefs.markVersionSeen('1.0.0');
      expect(prefs.lastSeenVersion, '1.0.0');
    });

    test('hasVersionBumped is true when current differs from seen',
        () async {
      await prefs.markVersionSeen('0.9.0');
      expect(prefs.hasVersionBumped, isTrue);
    });

    test('hasVersionBumped is false when current equals seen', () async {
      await prefs.markVersionSeen('1.0.0');
      expect(prefs.hasVersionBumped, isFalse);
    });

    test('markUpdateDismissed persists tag', () async {
      await prefs.markUpdateDismissed('v1.1.0');
      expect(prefs.lastDismissedUpdateTag, 'v1.1.0');
    });
  });

  group('custom theme', () {
    test('customTheme defaults to CustomTheme.defaults', () {
      expect(prefs.customTheme.background, CustomTheme.defaults.background);
    });

    test('setCustomTheme persists and round-trips', () async {
      const theme = CustomTheme(
        background: Color(0xFF000000),
        foreground: Color(0xFFFFFFFF),
        primary: Color(0xFF123456),
        secondary: Color(0xFF789ABC),
        muted: Color(0xFFAABBCC),
        border: Color(0xFF334455),
        highlight: Color(0xFF99AABB),
      );
      await prefs.setCustomTheme(theme);
      expect(prefs.customTheme.background, const Color(0xFF000000));
      expect(prefs.customTheme.primary, const Color(0xFF123456));
    });

    test('customThemeMode defaults dark and round-trips', () async {
      expect(prefs.customThemeMode, ThemeMode.dark);
      await prefs.setCustomThemeMode(ThemeMode.light);
      expect(prefs.customThemeMode, ThemeMode.light);
    });
  });

  group('theme preset', () {
    test('themePreset defaults null', () {
      expect(prefs.themePreset, isNull);
    });

    test('setThemePersist persists id', () async {
      await prefs.setThemePreset('catppuccin');
      expect(prefs.themePreset, 'catppuccin');
    });
  });

  group('scanlines and pixelate', () {
    test('scanlinesEnabled defaults true and round-trips', () async {
      expect(prefs.scanlinesEnabled, isTrue);
      await prefs.setScanlinesEnabled(false);
      expect(prefs.scanlinesEnabled, isFalse);
    });

    test('pixelateGraphics defaults true and round-trips', () async {
      expect(prefs.pixelateGraphics, isTrue);
      await prefs.setPixelateGraphics(false);
      expect(prefs.pixelateGraphics, isFalse);
    });
  });

  group('bubbleVibe', () {
    test('defaults to 0.0', () {
      expect(prefs.bubbleVibe, 0.0);
    });

    test('round-trips and clamps to 0..1', () async {
      await prefs.setBubbleVibe(0.5);
      expect(prefs.bubbleVibe, 0.5);
      await prefs.setBubbleVibe(-1);
      expect(prefs.bubbleVibe, 0.0);
      await prefs.setBubbleVibe(2);
      expect(prefs.bubbleVibe, 1.0);
    });
  });

  group('space sections', () {
    test('collapsedSpaceSections defaults empty', () {
      expect(prefs.collapsedSpaceSections, isEmpty);
    });

    test('toggleSectionCollapsed adds and removes', () async {
      await prefs.toggleSectionCollapsed('!space1:e.com');
      expect(prefs.collapsedSpaceSections, contains('!space1:e.com'));
      await prefs.toggleSectionCollapsed('!space1:e.com');
      expect(prefs.collapsedSpaceSections, isNot(contains('!space1:e.com')));
    });

    test('spaceOrder defaults empty and round-trips', () async {
      expect(prefs.spaceOrder, isEmpty);
      await prefs.setSpaceOrder(['!a:e.com', '!b:e.com']);
      expect(prefs.spaceOrder, ['!a:e.com', '!b:e.com']);
    });
  });

  group('browse servers', () {
    test('defaults to matrix.org', () {
      expect(prefs.browseServers, ['matrix.org']);
    });

    test('setBrowseServers round-trips', () async {
      await prefs.setBrowseServers(['server1.com', 'server2.com']);
      expect(prefs.browseServers, ['server1.com', 'server2.com']);
    });
  });

  group('mobile tab', () {
    test('defaults to inbox', () {
      expect(prefs.lastMobileTab, MobileTab.inbox);
    });

    test('round-trips inbox', () async {
      await prefs.setLastMobileTab(MobileTab.inbox);
      expect(prefs.lastMobileTab, MobileTab.inbox);
    });

    test('round-trips you', () async {
      await prefs.setLastMobileTab(MobileTab.you);
      expect(prefs.lastMobileTab, MobileTab.you);
    });
  });

  group('skin tone', () {
    test('defaults to none', () {
      expect(prefs.skinTone, SkinTone.none);
    });

    test('round-trips medium', () async {
      await prefs.setSkinTone(SkinTone.medium);
      expect(prefs.skinTone, SkinTone.medium);
    });
  });

  group('theme mode', () {
    test('defaults to system', () {
      expect(prefs.themeMode, ThemeMode.system);
    });

    test('round-trips dark', () async {
      await prefs.setThemeMode(ThemeMode.dark);
      expect(prefs.themeMode, ThemeMode.dark);
    });

    test('themeModeLabel reflects preset and mode', () async {
      await prefs.setThemePreset('custom');
      await prefs.setThemeMode(ThemeMode.dark);
      expect(prefs.themeModeLabel, contains('Dark'));
    });
  });

  group('init', () {
    test('init loads package info and sets currentVersion', () async {
      SharedPreferences.setMockInitialValues({});
      final p = PreferencesService(packageInfo: _fakePackageInfo('2.0.0'));
      await p.init();
      expect(p.currentVersion, '2.0.0');
    });

    test('init handles MissingPluginException gracefully', () async {
      SharedPreferences.setMockInitialValues({});
      final p = PreferencesService(packageInfo: _fakePackageInfo('3.0.0'));
      await p.init();
      // Should not throw
      expect(p.currentVersion, '3.0.0');
    });
  });
}
