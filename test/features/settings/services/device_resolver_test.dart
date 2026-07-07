import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/settings/services/device_resolver.dart';
import 'package:matrix/matrix.dart';
void main() {
  group('DeviceResolver', () {
    test('maps deviceId and displayName', () {
      final device = Device(
        deviceId: 'ABCD12',
        displayName: 'Kohera Android',
      );
      final kohera = const DeviceResolver()(device, isOwnDevice: true);

      expect(kohera.deviceId, 'ABCD12');
      expect(kohera.displayName, 'Kohera Android');
      expect(kohera.isOwnDevice, isTrue);
    });

    group('displayNameOrId', () {
      test('returns displayName when available', () {
        final device = Device(deviceId: 'ABCD12', displayName: 'My Phone');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).displayNameOrId,
          'My Phone',
        );
      });

      test('falls back to deviceId when displayName is null', () {
        final device = Device(deviceId: 'ABCD12');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).displayNameOrId,
          'ABCD12',
        );
      });
    });

    group('platformLabel', () {
      test('infers Android', () {
        final device = Device(deviceId: 'id', displayName: 'Kohera Android');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).platformLabel,
          'Android',
        );
      });

      test('infers iOS', () {
        final device = Device(deviceId: 'id', displayName: 'Element iOS');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).platformLabel,
          'iOS',
        );
      });

      test('returns null for an unrecognized name', () {
        final device = Device(deviceId: 'id', displayName: 'My Custom Client');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).platformLabel,
          isNull,
        );
      });
    });

    group('deviceIcon', () {
      test('returns phone icon for Android', () {
        final device = Device(deviceId: 'id', displayName: 'Kohera Android');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).deviceIcon,
          KIcons.phoneAndroidOutlined,
        );
      });

      test('returns web icon for Chrome', () {
        final device = Device(deviceId: 'id', displayName: 'Chrome on Windows');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).deviceIcon,
          KIcons.webOutlined,
        );
      });

      test('returns desktop icon for Linux', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'Element Desktop Linux',
        );
        expect(
          const DeviceResolver()(device, isOwnDevice: false).deviceIcon,
          KIcons.desktopMacOutlined,
        );
      });

      test('returns unknown icon for unrecognized name', () {
        final device = Device(deviceId: 'id', displayName: 'Mystery Box');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).deviceIcon,
          KIcons.devicesOtherOutlined,
        );
      });
    });

    group('lastSeenTs', () {
      test('returns DateTime from lastSeenTs', () {
        final ts = DateTime(2025, 6, 15, 10, 30).millisecondsSinceEpoch;
        final device = Device(deviceId: 'id', lastSeenTs: ts);
        expect(
          const DeviceResolver()(device, isOwnDevice: false).lastSeenTs,
          DateTime(2025, 6, 15, 10, 30),
        );
      });

      test('returns null when lastSeenTs is null', () {
        final device = Device(deviceId: 'id');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).lastSeenTs,
          isNull,
        );
      });
    });

    group('lastActiveString', () {
      test('returns "Unknown" when lastSeenTs is null', () {
        final device = Device(deviceId: 'id');
        expect(
          const DeviceResolver()(device, isOwnDevice: false).lastActiveString,
          'Unknown',
        );
      });

      test('returns "Active now" for recent activity', () {
        final ts = DateTime.now()
            .subtract(const Duration(minutes: 2))
            .millisecondsSinceEpoch;
        final device = Device(deviceId: 'id', lastSeenTs: ts);
        expect(
          const DeviceResolver()(device, isOwnDevice: false).lastActiveString,
          'Active now',
        );
      });
    });

    group('verification state (no deviceKeys)', () {
      final device = Device(deviceId: 'ABCD12', displayName: 'My Phone');

      test('isVerified is false when deviceKeys is null', () {
        expect(const DeviceResolver()(device, isOwnDevice: false).isVerified, isFalse);
      });

      test('isBlocked is false when deviceKeys is null', () {
        expect(const DeviceResolver()(device, isOwnDevice: false).isBlocked, isFalse);
      });

      test('keys is null when deviceKeys is null', () {
        expect(const DeviceResolver()(device, isOwnDevice: false).keys, isNull);
      });

      test('hasDeviceKeys is false when deviceKeys is null', () {
        expect(
          const DeviceResolver()(device, isOwnDevice: false).hasDeviceKeys,
          isFalse,
        );
      });
    });

    test('isOwnDevice is passed through', () {
      final device = Device(deviceId: 'id', displayName: 'Mine');
      expect(const DeviceResolver()(device, isOwnDevice: true).isOwnDevice, isTrue);
      expect(const DeviceResolver()(device, isOwnDevice: false).isOwnDevice, isFalse);
    });
  });
}
