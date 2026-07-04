import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/settings/models/kohera_device.dart';

void main() {
  group('KoheraDevice', () {
    KoheraDevice build({
      String? displayName,
      Map<String, String>? keys,
      bool isVerified = false,
      bool isBlocked = false,
    }) =>
        KoheraDevice(
          deviceId: 'ABCD12',
          displayName: displayName,
          isOwnDevice: false,
          isVerified: isVerified,
          isBlocked: isBlocked,
          keys: keys,
          lastSeenTs: null,
          displayNameOrId: displayName ?? 'ABCD12',
          platformLabel: null,
          deviceIcon: Icons.devices_other_outlined,
          lastActiveString: 'Unknown',
        );

    test('stores all fields', () {
      final device = KoheraDevice(
        deviceId: 'XYZ',
        displayName: 'My Phone',
        isOwnDevice: true,
        isVerified: true,
        isBlocked: false,
        keys: const {'ed25519:XYZ': 'fp'},
        lastSeenTs: DateTime(2025),
        displayNameOrId: 'My Phone',
        platformLabel: 'Android',
        deviceIcon: Icons.phone_android_outlined,
        lastActiveString: 'Active now',
      );

      expect(device.deviceId, 'XYZ');
      expect(device.displayName, 'My Phone');
      expect(device.isOwnDevice, isTrue);
      expect(device.isVerified, isTrue);
      expect(device.isBlocked, isFalse);
      expect(device.keys, {'ed25519:XYZ': 'fp'});
      expect(device.lastSeenTs, DateTime(2025));
      expect(device.displayNameOrId, 'My Phone');
      expect(device.platformLabel, 'Android');
      expect(device.deviceIcon, Icons.phone_android_outlined);
      expect(device.lastActiveString, 'Active now');
    });

    test('displayName is nullable', () {
      expect(build().displayName, isNull);
    });

    group('hasDeviceKeys', () {
      test('is false when keys is null', () {
        expect(build().hasDeviceKeys, isFalse);
      });

      test('is true when keys is present', () {
        expect(
          build(keys: {'ed25519:ABC': 'fp'}).hasDeviceKeys,
          isTrue,
        );
      });
    });

    group('equality', () {
      test('is keyed on deviceId', () {
        final a = build();
        final b = KoheraDevice(
          deviceId: 'ABCD12',
          displayName: 'Completely Different Name',
          isOwnDevice: true,
          isVerified: true,
          isBlocked: true,
          keys: const {'k': 'v'},
          lastSeenTs: DateTime(2025, 6),
          displayNameOrId: 'Completely Different Name',
          platformLabel: 'iOS',
          deviceIcon: Icons.phone_iphone_outlined,
          lastActiveString: '1m ago',
        );

        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('differs for a different deviceId', () {
        final a = build();

        const other = KoheraDevice(
          deviceId: 'OTHER',
          displayName: null,
          isOwnDevice: false,
          isVerified: false,
          isBlocked: false,
          keys: null,
          lastSeenTs: null,
          displayNameOrId: 'OTHER',
          platformLabel: null,
          deviceIcon: Icons.devices_other_outlined,
          lastActiveString: 'Unknown',
        );

        expect(a, isNot(equals(other)));
      });
    });

    test('toString includes identifying fields', () {
      final device = build(displayName: 'My Phone', isVerified: true);
      final str = device.toString();
      expect(str, contains('ABCD12'));
      expect(str, contains('My Phone'));
      expect(str, contains('isVerified: true'));
    });
  });
}
