import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:kohera/features/share_in/models/room_snapshot.dart';
import 'package:kohera/features/share_in/services/avatar_cache_service.dart';
import 'package:kohera/shared/services/media_resolver.dart';

class _FakeMediaResolver implements MediaResolver {
  _FakeMediaResolver(this.resolved);
  final Map<String, MediaThumbnail> resolved;

  @override
  Future<MediaThumbnail?> resolve(
    String? mxc, {
    required double? width,
    required double? height,
  }) async =>
      mxc == null ? null : resolved[mxc];
}

const _pngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

http.Client _okClient(List<String> calls) => http_testing.MockClient(
      (request) async {
        calls.add(request.url.toString());
        return http.Response.bytes(_pngBytes, 200, headers: {
          'content-type': 'image/png',
        });
      },
    );

void main() {
  late Directory tmp;
  late List<String> calls;
  late _FakeMediaResolver resolver;
  late AvatarCacheService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('avatar_cache_test');
    calls = [];
    resolver = _FakeMediaResolver({
      'mxc://srv/a': const MediaThumbnail(url: 'https://srv/a'),
      'mxc://srv/a2': const MediaThumbnail(url: 'https://srv/a2'),
    });
    service = AvatarCacheService(
      mediaResolver: resolver,
      getAppGroupPath: () async => tmp.path,
      httpClient: _okClient(calls),
    );
  });

  tearDown(() async {
    await service.dispose();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('downloads and caches an avatar on first ensureFor', () async {
    await service.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a'),
    ]);

    expect(calls, hasLength(1));
    final paths = service.cachedPaths();
    expect(paths, contains('!a:s'));
    expect(File(paths['!a:s']!).existsSync(), isTrue);
  });

  test('cache hit: unchanged mxc does not re-download', () async {
    await service.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a'),
    ]);
    expect(calls, hasLength(1));

    await service.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a'),
    ]);
    expect(calls, hasLength(1), reason: 'unchanged avatar should skip download');
  });

  test('mxc change re-downloads and updates the cache', () async {
    await service.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a'),
    ]);
    final path = service.cachedPaths()['!a:s']!;
    expect(File(path).existsSync(), isTrue);

    await service.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a2'),
    ]);
    expect(calls, hasLength(2), reason: 'changed mxc should re-download');
    // Same image format -> same file path, bytes overwritten in place.
    expect(service.cachedPaths()['!a:s'], equals(path));
    expect(File(path).existsSync(), isTrue);

    // Index recorded the new mxc: a third ensure is a cache hit.
    final callsBefore = calls.length;
    await service.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a2'),
    ]);
    expect(calls.length, callsBefore);
  });

  test('room with null avatar is dropped from the cache', () async {
    await service.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a'),
    ]);
    expect(service.cachedPaths(), contains('!a:s'));

    await service.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A'),
    ]);
    expect(service.cachedPaths(), isNot(contains('!a:s')));
  });

  test('download error is tolerated and leaves no cached path', () async {
    final failing = http_testing.MockClient(
      (request) async => http.Response.bytes(const [], 500),
    );
    final failingService = AvatarCacheService(
      mediaResolver: resolver,
      getAppGroupPath: () async => tmp.path,
      httpClient: failing,
    );
    addTearDown(failingService.dispose);

    await failingService.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a'),
    ]);
    expect(failingService.cachedPaths(), isEmpty);
  });

  test('index persists across a fresh service instance', () async {
    await service.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a'),
    ]);

    final reloaded = AvatarCacheService(
      mediaResolver: resolver,
      getAppGroupPath: () async => tmp.path,
      httpClient: _okClient(calls),
    );
    addTearDown(reloaded.dispose);
    await reloaded.init();

    expect(reloaded.cachedPaths(), contains('!a:s'));
    // Re-ensure with the same mxc should be a cache hit (no new download).
    await reloaded.ensureFor([
      const RoomSnapshot(roomId: '!a:s', displayname: 'A', avatarMxc: 'mxc://srv/a'),
    ]);
    expect(calls, hasLength(1));
  });

  test('unresolved mxc (MediaResolver returns null) is skipped', () async {
    await service.ensureFor([
      const RoomSnapshot(roomId: '!x:s', displayname: 'X', avatarMxc: 'mxc://srv/unknown'),
    ]);
    expect(service.cachedPaths(), isNot(contains('!x:s')));
  });
}
