import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/share_in/models/pending_share.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late ShareInStore store;
  late List<MapEntry<String, Object?>> calls;

  void setHandler(Future<Object?>? Function(MethodCall) handler) {
    TestWidgetsFlutterBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    channel = const MethodChannel('kohera/share');
    store = ShareInStore(channel: channel);
    calls = [];
  });

  tearDown(() {
    TestWidgetsFlutterBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ShareInStore.readRoomSnapshot', () {
    test('decodes native JSON array into RoomSnapshot list', () async {
      final raw = jsonEncode([
        {'roomId': '!a:srv', 'displayname': 'A', 'avatarMxc': 'mxc://a'},
        {'roomId': '!b:srv', 'displayname': 'B'},
      ]);
      setHandler((call) async => raw);

      final result = await store.readRoomSnapshot();

      expect(result, hasLength(2));
      expect(result[0].roomId, '!a:srv');
      expect(result[0].avatarMxc, 'mxc://a');
      expect(result[1].roomId, '!b:srv');
      expect(result[1].avatarMxc, isNull);
    });

    test('returns empty when native returns null', () async {
      setHandler((call) async => null);
      expect(await store.readRoomSnapshot(), isEmpty);
    });

    test('returns empty when native returns empty string', () async {
      setHandler((call) async => '');
      expect(await store.readRoomSnapshot(), isEmpty);
    });
  });

  group('ShareInStore.writeRoomSnapshot', () {
    test('encodes snapshots to JSON and invokes native', () async {
      setHandler((call) async {
        calls.add(MapEntry(call.method, call.arguments));
        return null;
      });

      await store.writeRoomSnapshot([
        const RoomSnapshot(roomId: '!a:srv', displayname: 'A'),
      ]);

      expect(calls.single.key, 'writeRoomSnapshot');
      final encoded = jsonDecode(calls.single.value! as String) as List;
      expect(encoded.single, {
        'roomId': '!a:srv',
        'displayname': 'A',
      });
    });
  });

  group('ShareInStore.readPendingShares', () {
    test('decodes native JSON array into PendingShare list', () async {
      final raw = jsonEncode([
        {
          'id': 'id1',
          'targetRoomId': '!a:srv',
          'accountId': 'default',
          'kind': 'text',
          'text': 'hi',
          'createdAt': 1700000000000,
        },
        {
          'id': 'id2',
          'targetRoomId': '!b:srv',
          'accountId': 'default',
          'kind': 'file',
          'filePath': '/x',
          'createdAt': 1,
        },
      ]);
      setHandler((call) async => raw);

      final result = await store.readPendingShares();

      expect(result, hasLength(2));
      expect(result[0].kind, PendingShareKind.text);
      expect(result[0].text, 'hi');
      expect(result[1].kind, PendingShareKind.file);
      expect(result[1].filePath, '/x');
    });

    test('returns empty when native returns null', () async {
      setHandler((call) async => null);
      expect(await store.readPendingShares(), isEmpty);
    });
  });

  group('ShareInStore.clear methods', () {
    test('clearPendingShare invokes with id argument', () async {
      setHandler((call) async {
        calls.add(MapEntry(call.method, call.arguments));
        return null;
      });

      await store.clearPendingShare('id1');

      expect(calls.single.key, 'clearPendingShare');
      expect(calls.single.value, 'id1');
    });

    test('clearAllPendingShares invokes with null argument', () async {
      setHandler((call) async {
        calls.add(MapEntry(call.method, call.arguments));
        return null;
      });

      await store.clearAllPendingShares();

      expect(calls.single.key, 'clearAllPendingShares');
      expect(calls.single.value, isNull);
    });
  });

  group('ShareInStore platform-missing degradation', () {
    test('read returns empty when no native handler registered', () async {
      // No mock handler set → MissingPluginException path.
      expect(await store.readRoomSnapshot(), isEmpty);
      expect(await store.readPendingShares(), isEmpty);
    });

    test('write does not throw when no native handler registered', () async {
      await store.writeRoomSnapshot(const []);
      await store.clearPendingShare('id');
      await store.clearAllPendingShares();
    });
  });
}
