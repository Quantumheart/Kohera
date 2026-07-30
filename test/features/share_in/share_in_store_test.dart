import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late ShareInStore store;
  late List<MapEntry<String, Object?>> calls;

  void setHandler(Future<Object?>? Function(MethodCall) handler) {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    channel = const MethodChannel('kohera/share');
    store = ShareInStore(channel: channel);
    calls = [];
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
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

  group('ShareInStore.readIncomingShare', () {
    test('decodes native JSON into IncomingShare', () async {
      final raw = jsonEncode({
        'roomId': '!a:srv',
        'text': 'hi',
        'files': [
          {'filePath': '/x/p.png', 'name': 'p.png', 'mimeType': 'image/png'},
        ],
      });
      setHandler((call) async => raw);

      final result = await store.readIncomingShare();

      expect(result, isNotNull);
      expect(result!.roomId, '!a:srv');
      expect(result.text, 'hi');
      expect(result.files.single.filePath, '/x/p.png');
      expect(result.files.single.mimeType, 'image/png');
    });

    test('returns null when native returns null', () async {
      setHandler((call) async => null);
      expect(await store.readIncomingShare(), isNull);
    });

    test('returns null when native returns empty string', () async {
      setHandler((call) async => '');
      expect(await store.readIncomingShare(), isNull);
    });

    test('returns null on malformed JSON', () async {
      setHandler((call) async => '{not json');
      expect(await store.readIncomingShare(), isNull);
    });
  });

  group('ShareInStore.clearIncomingShare', () {
    test('invokes clearIncomingShare with null argument', () async {
      setHandler((call) async {
        calls.add(MapEntry(call.method, call.arguments));
        return null;
      });

      await store.clearIncomingShare();

      expect(calls.single.key, 'clearIncomingShare');
      expect(calls.single.value, isNull);
    });
  });

  group('ShareInStore.donateSendMessage', () {
    test('invokes donateSendMessage with JSON roomId/displayname/avatarPath', () async {
      setHandler((call) async {
        calls.add(MapEntry(call.method, call.arguments));
        return null;
      });

      await store.donateSendMessage(
        roomId: '!r:s',
        displayname: 'Devs',
        avatarPath: '/avatars/!r:s.png',
      );

      expect(calls.single.key, 'donateSendMessage');
      final decoded = jsonDecode(calls.single.value! as String) as Map<String, dynamic>;
      expect(decoded, {
        'roomId': '!r:s',
        'displayname': 'Devs',
        'avatarPath': '/avatars/!r:s.png',
      });
    });

    test('omits avatarPath when null', () async {
      setHandler((call) async {
        calls.add(MapEntry(call.method, call.arguments));
        return null;
      });

      await store.donateSendMessage(roomId: '!r:s', displayname: 'Devs');

      final decoded = jsonDecode(calls.single.value! as String) as Map<String, dynamic>;
      expect(decoded.containsKey('avatarPath'), isFalse);
    });
  });

  group('ShareInStore.activeAccountId', () {
    test('reads the id returned by native', () async {
      setHandler((call) async {
        if (call.method == 'readActiveAccountId') return 'default';
        return null;
      });
      expect(await store.readActiveAccountId(), 'default');
    });

    test('returns null when native returns null', () async {
      setHandler((call) async => null);
      expect(await store.readActiveAccountId(), isNull);
    });

    test('write invokes with id argument', () async {
      setHandler((call) async {
        calls.add(MapEntry(call.method, call.arguments));
        return null;
      });
      await store.writeActiveAccountId('work');
      expect(calls.single.key, 'writeActiveAccountId');
      expect(calls.single.value, 'work');
    });
  });

  group('ShareInStore platform-missing degradation', () {
    test('read returns empty/null when no native handler registered', () async {
      expect(await store.readRoomSnapshot(), isEmpty);
      expect(await store.readIncomingShare(), isNull);
    });

    test('write does not throw when no native handler registered', () async {
      await store.writeRoomSnapshot(const []);
      await store.clearIncomingShare();
    });
  });
}
