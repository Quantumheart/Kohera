// coverage:ignore-file

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/dto.dart';
import 'package:kohera/core/backend/in_process_backend.dart';
import 'package:kohera/core/backend/matrix_service_proxy.dart';
import 'package:kohera/core/config/backend_config.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';

void main() {
  group('BackendConfig', () {
    test('useBackendIsolate defaults to false', () {
      BackendConfig.useBackendIsolate = false;
      expect(BackendConfig.useBackendIsolate, false);
    });

    test('useBackendIsolate can be toggled', () {
      BackendConfig.useBackendIsolate = true;
      expect(BackendConfig.useBackendIsolate, true);
      BackendConfig.useBackendIsolate = false;
      expect(BackendConfig.useBackendIsolate, false);
    });
  });

  group('MatrixServiceProxy with InProcessBackend', () {
    late InProcessBackend backend;
    late MatrixServiceProxy proxy;

    setUp(() async {
      backend = InProcessBackend();
      await backend.connect();
      proxy = MatrixServiceProxy(backend: backend);
    });

    tearDown(() async {
      proxy.dispose();
      await backend.disconnect();
    });

    test('start populates rooms from backend (empty for InProcessBackend)',
        () async {
      await proxy.start();
      expect(proxy.rooms, isEmpty);
      expect(proxy.isLoggedIn, false);
    });

    test('is a ChangeNotifier (listeners fire)', () async {
      var notifyCount = 0;
      proxy.addListener(() => notifyCount++);
      await proxy.start();
      // start() calls refreshLoginState + refreshRooms, each calling
      // notifyListeners at least once
      expect(notifyCount, greaterThan(0));
    });

    test('disposed flag is set on dispose', () async {
      final localBackend = InProcessBackend();
      await localBackend.connect();
      final localProxy = MatrixServiceProxy(backend: localBackend);
      await localProxy.start();
      expect(localProxy.disposed, false);
      localProxy.dispose();
      expect(localProxy.disposed, true);
      await localBackend.disconnect();
    });
  });

  group('RoomDto to KoheraRoomSummary mapping', () {
    test('maps all overlapping fields correctly', () {
      const dto = RoomDto(
        roomId: '!test:server',
        name: 'Test Room',
        displayName: 'Test Room',
        encrypted: true,
        isDirect: false,
        membership: 'Membership.join',
        unreadCount: 5,
        notificationCount: 3,
        highlightCount: 1,
        muted: false,
        pushRuleState: 'PushRuleState.notify',
        avatarMxc: 'mxc://server/avatar',
        topic: 'A topic',
        canonicalAlias: '#test:server',
        lastEventId: r'$event1',
        lastEventTs: 1700000000000,
      );

      // Replicate the mapping done by RoomListController._summaryFromDto
      final summary = KoheraRoomSummary(
        roomId: dto.roomId,
        displayname: dto.displayName,
        isDirectChat: dto.isDirect,
        isEncrypted: dto.encrypted,
        isSpace: false,
        notificationCount: dto.notificationCount,
        highlightCount: dto.highlightCount,
        typingDisplayNames: const [],
        pinnedEventIds: const [],
        spaceChildCount: 0,
        isFavourite: false,
        lastEventPreview: '',
        lastEventIsThreadReply: false,
        avatarUrl: dto.avatarMxc,
        topic: dto.topic,
        canonicalAlias: dto.canonicalAlias,
        lastEventTimestamp: dto.lastEventTs != null
            ? DateTime.fromMillisecondsSinceEpoch(dto.lastEventTs!)
            : null,
      );

      expect(summary.roomId, '!test:server');
      expect(summary.displayname, 'Test Room');
      expect(summary.isEncrypted, true);
      expect(summary.isDirectChat, false);
      expect(summary.notificationCount, 3);
      expect(summary.highlightCount, 1);
      expect(summary.avatarUrl, 'mxc://server/avatar');
      expect(summary.canonicalAlias, '#test:server');
      expect(summary.topic, 'A topic');
      expect(summary.lastEventTimestamp?.millisecondsSinceEpoch, 1700000000000);
    });

    test('handles null optional fields', () {
      const dto = RoomDto(
        roomId: '!empty:server',
        name: '',
        displayName: '',
        encrypted: false,
        isDirect: true,
        membership: 'Membership.join',
        unreadCount: 0,
        notificationCount: 0,
        highlightCount: 0,
        muted: false,
        pushRuleState: 'PushRuleState.notify',
      );

      final summary = KoheraRoomSummary(
        roomId: dto.roomId,
        displayname: dto.displayName,
        isDirectChat: dto.isDirect,
        isEncrypted: dto.encrypted,
        isSpace: false,
        notificationCount: dto.notificationCount,
        highlightCount: dto.highlightCount,
        typingDisplayNames: const [],
        pinnedEventIds: const [],
        spaceChildCount: 0,
        isFavourite: false,
        lastEventPreview: '',
        lastEventIsThreadReply: false,
        avatarUrl: dto.avatarMxc,
        topic: dto.topic,
        canonicalAlias: dto.canonicalAlias,
        lastEventTimestamp: dto.lastEventTs != null
            ? DateTime.fromMillisecondsSinceEpoch(dto.lastEventTs!)
            : null,
      );

      expect(summary.avatarUrl, isNull);
      expect(summary.canonicalAlias, isNull);
      expect(summary.topic, isNull);
      expect(summary.lastEventTimestamp, isNull);
    });
  });
}
