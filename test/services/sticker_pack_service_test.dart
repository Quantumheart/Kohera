import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:kohera/core/models/openmoji_pack.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/core/services/openmoji_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import 'sticker_pack_service_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

const _kUserEmotesType = 'im.ponies.user_emotes';
const _kRoomEmotesType = 'im.ponies.room_emotes';
const _kSubscriptionsType = 'kohera.sticker_pack_subscriptions';

BasicEvent _accountDataEvent(String type, Map<String, Object?> content) =>
    BasicEvent(type: type, content: content);

StrippedStateEvent _stateEvent(Map<String, Object?> content) =>
    StrippedStateEvent(
      type: _kRoomEmotesType,
      senderId: '@bot:example.com',
      stateKey: '',
      content: content,
    );

Map<String, Object?> _packContent({
  String displayName = 'Test Pack',
  Map<String, Object?>? images,
}) =>
    {
      'pack': {'display_name': displayName},
      'images': images ??
          {
            'wave': {'url': 'mxc://example.com/wave'},
          },
    };

Map<String, Object?> _stickerOnlyContent() => {
      'pack': {
        'display_name': 'Sticker Pack',
        'usage': ['sticker'],
      },
      'images': {
        'blob': {'url': 'mxc://example.com/blob'},
      },
    };

Map<String, Object?> _emojiOnlyContent() => {
      'pack': {
        'display_name': 'Emoji Pack',
        'usage': ['emoticon'],
      },
      'images': {
        'partyblob': {'url': 'mxc://example.com/partyblob'},
      },
    };

void main() {
  late MockClient mockClient;
  late CachedStreamController<SyncUpdate> syncCtl;
  late StickerPackService service;

  setUp(() {
    mockClient = MockClient();
    syncCtl = CachedStreamController<SyncUpdate>();
    when(mockClient.onSync).thenReturn(syncCtl);
    when(mockClient.accountData).thenReturn({});
    when(mockClient.rooms).thenReturn([]);
    service = StickerPackService(client: mockClient);
  });

  tearDown(() => service.dispose());

  // ── StickerPack.fromContent ──────────────────────────────────

  group('StickerPack.fromContent', () {
    test('returns null for empty images', () {
      final pack = StickerPack.fromContent(
        id: 'test',
        content: {'pack': {}, 'images': {}},
      );
      expect(pack, isNull);
    });

    test('parses sticker-only pack', () {
      final pack = StickerPack.fromContent(
        id: 'test',
        content: _stickerOnlyContent(),
      )!;
      expect(pack.stickers, hasLength(1));
      expect(pack.emoji, isEmpty);
      expect(pack.stickers.first.shortcode, 'blob');
    });

    test('parses emoji-only pack', () {
      final pack = StickerPack.fromContent(
        id: 'test',
        content: _emojiOnlyContent(),
      )!;
      expect(pack.emoji, hasLength(1));
      expect(pack.stickers, isEmpty);
      expect(pack.emoji.first.shortcode, 'partyblob');
    });

    test('defaults to both sticker and emoji when usage absent', () {
      final pack = StickerPack.fromContent(
        id: 'test',
        content: _packContent(),
      )!;
      expect(pack.stickers, hasLength(1));
      expect(pack.emoji, hasLength(1));
    });

    test('per-image usage overrides pack default', () {
      final pack = StickerPack.fromContent(
        id: 'test',
        content: {
          'pack': {'usage': ['sticker', 'emoticon']},
          'images': {
            'only_sticker': {
              'url': 'mxc://example.com/s',
              'usage': ['sticker'],
            },
            'only_emoji': {
              'url': 'mxc://example.com/e',
              'usage': ['emoticon'],
            },
          },
        },
      )!;
      expect(pack.stickers.map((i) => i.shortcode), contains('only_sticker'));
      expect(pack.stickers.map((i) => i.shortcode), isNot(contains('only_emoji')));
      expect(pack.emoji.map((i) => i.shortcode), contains('only_emoji'));
      expect(pack.emoji.map((i) => i.shortcode), isNot(contains('only_sticker')));
    });

    test('strips invalid avatar URL', () {
      final pack = StickerPack.fromContent(
        id: 'test',
        content: {
          'pack': {'display_name': 'No Avatar'},
          'images': {
            'x': {'url': 'mxc://example.com/x'},
          },
        },
      )!;
      expect(pack.avatarUrl, isNull);
    });

    test('keeps valid mxc avatar URL', () {
      const avatarUrl = 'mxc://example.com/avatar123';
      final pack = StickerPack.fromContent(
        id: 'test',
        content: {
          'pack': {
            'display_name': 'Has Avatar',
            'avatar_url': avatarUrl,
          },
          'images': {
            'x': {'url': 'mxc://example.com/x'},
          },
        },
      )!;
      expect(pack.avatarUrl?.toString(), avatarUrl);
    });
  });

  // ── accountPacks ────────────────────────────────────────────

  group('accountPacks', () {
    test('returns empty list when no account data', () {
      expect(service.accountPacks, isEmpty);
    });

    test('returns user emotes pack when present', () {
      when(mockClient.accountData).thenReturn({
        _kUserEmotesType: _accountDataEvent(_kUserEmotesType, _packContent()),
      });
      expect(service.accountPacks, hasLength(1));
      expect(service.accountPacks.first.id, _kUserEmotesType);
    });

    test('includes subscribed room packs', () {
      const roomId = '!stickers:example.com';
      final mockRoom = MockRoom();
      when(mockRoom.id).thenReturn(roomId);
      when(mockRoom.getState(_kRoomEmotesType)).thenReturn(
        _stateEvent(_packContent(displayName: 'Room Pack')),
      );
      when(mockClient.getRoomById(roomId)).thenReturn(mockRoom);
      when(mockClient.accountData).thenReturn({
        _kSubscriptionsType: _accountDataEvent(
          _kSubscriptionsType,
          {'room_ids': [roomId]},
        ),
      });

      final packs = service.accountPacks;
      expect(packs, hasLength(1));
      expect(packs.first.id, roomId);
    });

    test('skips subscribed room when getRoomById returns null', () {
      when(mockClient.accountData).thenReturn({
        _kSubscriptionsType: _accountDataEvent(
          _kSubscriptionsType,
          {'room_ids': ['!gone:example.com']},
        ),
      });
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.accountPacks, isEmpty);
    });
  });

  // ── packsForRoom ────────────────────────────────────────────

  group('packsForRoom', () {
    late MockRoom mockRoom;

    setUp(() {
      mockRoom = MockRoom();
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.spaceParents).thenReturn([]);
      when(mockRoom.getState(_kRoomEmotesType)).thenReturn(null);
    });

    test('includes room pack when present', () {
      when(mockRoom.getState(_kRoomEmotesType)).thenReturn(
        _stateEvent(_packContent(displayName: 'Room Pack')),
      );
      final packs = service.packsForRoom(mockRoom);
      expect(packs, hasLength(1));
      expect(packs.first.id, '!room:example.com');
    });

    test('deduplicates room pack already in account subscriptions', () {
      const roomId = '!room:example.com';
      when(mockClient.accountData).thenReturn({
        _kSubscriptionsType: _accountDataEvent(
          _kSubscriptionsType,
          {'room_ids': [roomId]},
        ),
      });
      when(mockClient.getRoomById(roomId)).thenReturn(mockRoom);
      when(mockRoom.getState(_kRoomEmotesType)).thenReturn(
        _stateEvent(_packContent()),
      );

      final packs = service.packsForRoom(mockRoom);
      final ids = packs.map((p) => p.id).toList();
      expect(ids.where((id) => id == roomId).length, 1);
    });

    test('includes space packs from parent spaces', () {
      final mockSpace = MockRoom();
      const spaceId = '!space:example.com';
      when(mockSpace.id).thenReturn(spaceId);
      when(mockSpace.getState(_kRoomEmotesType)).thenReturn(
        _stateEvent(_packContent(displayName: 'Space Pack')),
      );

      final spaceParent = SpaceParent.fromState(
        StrippedStateEvent(
          type: EventTypes.SpaceParent,
          senderId: '@bot:example.com',
          stateKey: spaceId,
          content: {'via': ['example.com']},
        ),
      );
      when(mockRoom.spaceParents).thenReturn([spaceParent]);
      when(mockClient.getRoomById(spaceId)).thenReturn(mockSpace);

      final packs = service.packsForRoom(mockRoom);
      expect(packs.map((p) => p.id), contains(spaceId));
    });
  });

  // ── availableRoomPacks ──────────────────────────────────────

  group('availableRoomPacks', () {
    test('returns room packs not already subscribed', () {
      final mockRoom = MockRoom();
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.getState(_kRoomEmotesType)).thenReturn(
        _stateEvent(_packContent()),
      );
      when(mockClient.rooms).thenReturn([mockRoom]);
      expect(service.availableRoomPacks(), hasLength(1));
    });

    test('excludes rooms already subscribed', () {
      const roomId = '!room:example.com';
      final mockRoom = MockRoom();
      when(mockRoom.id).thenReturn(roomId);
      when(mockRoom.getState(_kRoomEmotesType)).thenReturn(
        _stateEvent(_packContent()),
      );
      when(mockClient.rooms).thenReturn([mockRoom]);
      when(mockClient.accountData).thenReturn({
        _kSubscriptionsType: _accountDataEvent(
          _kSubscriptionsType,
          {'room_ids': [roomId]},
        ),
      });
      expect(service.availableRoomPacks(), isEmpty);
    });
  });

  // ── subscription management ─────────────────────────────────

  group('subscribeToRoomPack', () {
    test('writes new room id to account data', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockClient.accountData).thenReturn({});

      await service.subscribeToRoomPack('!room:example.com');

      verify(
        mockClient.setAccountData(
          '@user:example.com',
          _kSubscriptionsType,
          {'room_ids': ['!room:example.com']},
        ),
      ).called(1);
    });

    test('does not write if already subscribed', () async {
      const roomId = '!room:example.com';
      when(mockClient.accountData).thenReturn({
        _kSubscriptionsType: _accountDataEvent(
          _kSubscriptionsType,
          {'room_ids': [roomId]},
        ),
      });

      await service.subscribeToRoomPack(roomId);
      verifyNever(mockClient.setAccountData(any, any, any));
    });
  });

  group('unsubscribeFromRoomPack', () {
    test('removes room id from subscriptions', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockClient.accountData).thenReturn({
        _kSubscriptionsType: _accountDataEvent(
          _kSubscriptionsType,
          {
            'room_ids': ['!a:example.com', '!b:example.com'],
          },
        ),
      });

      await service.unsubscribeFromRoomPack('!a:example.com');

      verify(
        mockClient.setAccountData(
          '@user:example.com',
          _kSubscriptionsType,
          {'room_ids': ['!b:example.com']},
        ),
      ).called(1);
    });
  });

  group('reorderSubscriptions', () {
    test('writes ordered ids to account data', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      final ordered = ['!b:example.com', '!a:example.com'];

      await service.reorderSubscriptions(ordered);

      verify(
        mockClient.setAccountData(
          '@user:example.com',
          _kSubscriptionsType,
          {'room_ids': ordered},
        ),
      ).called(1);
    });
  });

  // ── OpenMoji default packs ──────────────────────────────────

  group('importOpenMojiPack', () {
    const testPack = OpenMojiPack(
      id: 'smileys',
      name: 'OpenMoji Smileys',
      description: 'd',
      emojis: [
        OpenMojiEmoji(
          hexcode: '1F600',
          shortcode: 'grinning',
          annotation: 'grinning face',
        ),
        OpenMojiEmoji(
          hexcode: '1F602',
          shortcode: 'joy',
          annotation: 'face with tears of joy',
        ),
      ],
    );

    OpenMojiService fakeService() => OpenMojiService(
          client: http_testing.MockClient(
            (_) async => http.Response.bytes([1, 2, 3], 200),
          ),
          catalog: const [testPack],
        );

    setUp(() {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(
        mockClient.uploadContent(
          any,
          filename: anyNamed('filename'),
          contentType: anyNamed('contentType'),
        ),
      ).thenAnswer((_) async => Uri.parse('mxc://example.com/abc'));
    });

    test('uploads each emoji and reports progress', () async {
      final oms = fakeService();
      addTearDown(oms.dispose);

      final events =
          await service.importOpenMojiPack(testPack, oms).toList();

      expect(events, hasLength(2));
      expect(events.last.isComplete, isTrue);
      verify(
        mockClient.uploadContent(
          any,
          filename: anyNamed('filename'),
          contentType: anyNamed('contentType'),
        ),
      ).called(2);
    });

    test('writes an emoticon pack to imported account data', () async {
      final oms = fakeService();
      addTearDown(oms.dispose);

      await service.importOpenMojiPack(testPack, oms).drain<void>();

      final captured = verify(
        mockClient.setAccountData(
          '@user:example.com',
          'kohera.imported_packs',
          captureAny,
        ),
      ).captured.single as Map<String, Object?>;

      final packs = (captured['packs'] as List).cast<Map<String, Object?>>();
      expect(packs, hasLength(1));
      final stored = packs.single;
      expect(stored['id'], 'openmoji_smileys');
      expect(stored['source'], 'openmoji');
      expect(stored['source_slug'], 'smileys');
      expect(stored['usage'], 'emoticon');
      final images = stored['images'] as Map<String, Object?>;
      expect(images.keys, containsAll(['grinning', 'joy']));
    });

    test('does not write account data when all downloads fail', () async {
      final oms = OpenMojiService(
        client: http_testing.MockClient(
          (_) async => http.Response('nope', 404),
        ),
        catalog: const [testPack],
      );
      addTearDown(oms.dispose);

      await service.importOpenMojiPack(testPack, oms).drain<void>();

      verifyNever(mockClient.setAccountData(any, any, any));
    });
  });

  group('importedOpenMojiSlugs', () {
    test('returns only slugs from openmoji-sourced packs', () {
      when(mockClient.accountData).thenReturn({
        'kohera.imported_packs': _accountDataEvent('kohera.imported_packs', {
          'packs': [
            {
              'id': 'openmoji_smileys',
              'source': 'openmoji',
              'source_slug': 'smileys',
            },
            {
              'id': 'emojigg_42',
              'source': 'emojigg',
              'source_slug': 'cool-pack',
            },
          ],
        }),
      });

      expect(service.importedOpenMojiSlugs, {'smileys'});
      expect(service.importedEmojiGgSlugs, {'cool-pack'});
    });
  });

  group('importedPacks usage', () {
    Map<String, Object?> importedContent({String? usage}) => {
          'packs': [
            {
              'id': 'openmoji_smileys',
              'display_name': 'OpenMoji Smileys',
              'source': 'openmoji',
              'source_slug': 'smileys',
              if (usage != null) 'usage': usage,
              'images': {
                'grinning': {
                  'url': 'mxc://example.com/grinning',
                  'body': 'grinning face',
                },
              },
            },
          ],
        };

    test('emoticon usage registers images as emoji', () {
      when(mockClient.accountData).thenReturn({
        'kohera.imported_packs': _accountDataEvent(
          'kohera.imported_packs',
          importedContent(usage: 'emoticon'),
        ),
      });

      final pack = service.importedPacks.single;
      expect(pack.emoji, hasLength(1));
      expect(pack.stickers, isEmpty);
      expect(pack.emoji.first.shortcode, 'grinning');
    });

    test('absent usage defaults to sticker for backward compatibility', () {
      when(mockClient.accountData).thenReturn({
        'kohera.imported_packs': _accountDataEvent(
          'kohera.imported_packs',
          importedContent(),
        ),
      });

      final pack = service.importedPacks.single;
      expect(pack.stickers, hasLength(1));
      expect(pack.emoji, isEmpty);
    });
  });

  // ── reactivity ──────────────────────────────────────────────

  group('notifyListeners', () {
    test('fires when user emotes account data arrives in sync', () async {
      var notified = false;
      service.addListener(() => notified = true);

      syncCtl.add(
        SyncUpdate(
          nextBatch: '1',
          accountData: [
            _accountDataEvent(_kUserEmotesType, _packContent()),
          ],
        ),
      );

      await Future<void>(() {});
      expect(notified, isTrue);
    });

    test('fires when subscriptions account data arrives in sync', () async {
      var notified = false;
      service.addListener(() => notified = true);

      syncCtl.add(
        SyncUpdate(
          nextBatch: '1',
          accountData: [
            _accountDataEvent(_kSubscriptionsType, {'room_ids': []}),
          ],
        ),
      );

      await Future<void>(() {});
      expect(notified, isTrue);
    });

    test('does not fire for unrelated account data in sync', () {
      var notified = false;
      service.addListener(() => notified = true);

      syncCtl.add(
        SyncUpdate(
          nextBatch: '1',
          accountData: [_accountDataEvent('m.push_rules', {})],
        ),
      );

      expect(notified, isFalse);
    });

    test('does not fire when sync has no account data', () {
      var notified = false;
      service.addListener(() => notified = true);

      syncCtl.add(SyncUpdate(nextBatch: '1'));

      expect(notified, isFalse);
    });
  });
}
