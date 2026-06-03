import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late CachedStreamController<CachedPresence> presenceController;
  late PresenceService service;

  setUp(() {
    mockClient = MockClient();
    presenceController = CachedStreamController<CachedPresence>();
    when(mockClient.onPresenceChanged).thenReturn(presenceController);
    service = PresenceService(client: mockClient);
  });

  tearDown(() => service.dispose());

  group('consuming', () {
    test('presence is unknown (null) by default', () {
      expect(service.presenceFor('@alice:example.com'), isNull);
    });

    test('reflects a presence update from sync and notifies', () async {
      var notified = 0;
      service.addListener(() => notified++);

      final cached =
          CachedPresence(PresenceType.online, null, 'busy', true, '@alice:example.com');
      presenceController.add(cached);
      await Future<void>.delayed(Duration.zero);

      final result = service.presenceFor('@alice:example.com');
      expect(result, same(cached));
      expect(result?.presence, PresenceType.online);
      expect(result?.statusMsg, 'busy');
      expect(notified, 1);
    });

    test('still unknown for users with no presence event', () async {
      presenceController.add(
        CachedPresence(PresenceType.online, null, null, true, '@alice:example.com'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.presenceFor('@bob:example.com'), isNull);
    });
  });

  group('publishing', () {
    test('setOnline/setAway/setOffline drive syncPresence', () {
      service.setOnline();
      verify(mockClient.syncPresence = PresenceType.online).called(1);

      service.setAway();
      verify(mockClient.syncPresence = PresenceType.unavailable).called(1);

      service.setOffline();
      verify(mockClient.syncPresence = PresenceType.offline).called(1);
    });

    test('publishing disabled is a no-op until re-enabled', () {
      service.setPublishingEnabled(false);
      clearInteractions(mockClient);

      service.setOnline();
      verifyNever(mockClient.syncPresence = PresenceType.online);

      service.setPublishingEnabled(true);
      verify(mockClient.syncPresence = PresenceType.online).called(1);
    });

    test('disabling publishing advertises offline', () {
      service.setOnline();
      clearInteractions(mockClient);

      service.setPublishingEnabled(false);
      verify(mockClient.syncPresence = PresenceType.offline).called(1);
    });
  });
}
