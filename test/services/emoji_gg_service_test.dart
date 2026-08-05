import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kohera/core/services/emoji_gg_service.dart';
import 'package:path/path.dart' as p;

const _channel = MethodChannel('plugins.flutter.io/path_provider');

const _samplePacksBody = '''
[
  {"id": 1, "name": "Pack A", "slug": "pack-a", "description": "desc", "amount": 2, "emojis": "1001-alpha.png,1002-beta.png", "category": "gaming"},
  {"id": 2, "name": "Pack B", "slug": "pack-b", "description": "", "amount": 0, "emojis": "", "category": null}
]
''';

void main() {
  late Directory tempDir;
  late int callCount;
// (client removed — unused)

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('emoji_gg_test_');
    callCount = 0;

    // Mock path_provider to return our temp dir.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  EmojiGgService makeService({
    required MockClientHandler handler,
    Duration? cacheTtl,
    Duration? requestTimeout,
  }) {
    return EmojiGgService(
      client: MockClient(handler),
      cacheTtl: cacheTtl ?? const Duration(hours: 24),
      requestTimeout: requestTimeout ?? const Duration(seconds: 15),
    );
  }

  group('EmojiGgService.fetchPacks', () {
    test('fetches packs from network on first call', () async {
      final svc = makeService(
        handler: (request) async {
          callCount++;
          return http.Response(_samplePacksBody, 200);
        },
      );

      final packs = await svc.fetchPacks();

      expect(callCount, 1);
      expect(packs.length, 1); // Pack B has amount 0 → filtered out
      expect(packs.first.id, 1);
      expect(packs.first.name, 'Pack A');
      expect(packs.first.emojiSlugs, ['1001-alpha', '1002-beta']);
      svc.dispose();
    });

    test('uses memory cache on second call without network', () async {
      final svc = makeService(
        handler: (request) async {
          callCount++;
          return http.Response(_samplePacksBody, 200);
        },
      );

      await svc.fetchPacks();
      final packs = await svc.fetchPacks();

      expect(callCount, 1); // Only one network call
      expect(packs.length, 1);
      svc.dispose();
    });

    test('forceRefresh bypasses memory cache', () async {
      final svc = makeService(
        handler: (request) async {
          callCount++;
          return http.Response(_samplePacksBody, 200);
        },
      );

      await svc.fetchPacks();
      await svc.fetchPacks(forceRefresh: true);

      expect(callCount, 2);
      svc.dispose();
    });

    test('returns empty list on non-200 status', () async {
      final svc = makeService(
        handler: (request) async => http.Response('Server error', 500),
      );

      final packs = await svc.fetchPacks();

      expect(packs, isEmpty);
      svc.dispose();
    });

    test('returns empty list on network error', () async {
      final svc = makeService(
        handler: (request) async => throw Exception('Network down'),
      );

      final packs = await svc.fetchPacks();

      expect(packs, isEmpty);
      svc.dispose();
    });

    test('returns empty list after dispose', () async {
      final svc = makeService(
        handler: (request) async => http.Response(_samplePacksBody, 200),
      );

      svc.dispose();
      final packs = await svc.fetchPacks();

      expect(packs, isEmpty);
    });

    test('deduplicates concurrent in-flight requests', () async {
      final svc = makeService(
        handler: (request) async {
          callCount++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(_samplePacksBody, 200);
        },
      );

      final futures = await Future.wait([
        svc.fetchPacks(),
        svc.fetchPacks(),
        svc.fetchPacks(),
      ]);

      expect(callCount, 1);
      expect(futures.every((p) => p.length == 1), isTrue);
      svc.dispose();
    });

    test('parses packs with empty emojis field', () async {
      final svc = makeService(
        handler: (request) async {
          callCount++;
          return http.Response(
            '[{"id": 5, "name": "Empty", "slug": "e", "description": "", "emojis": "", "amount": 0}]',
            200,
          );
        },
      );

      final packs = await svc.fetchPacks();

      // amount 0 → filtered out by the .where((pack) => pack.amount > 0)
      expect(packs, isEmpty);
      svc.dispose();
    });
  });

  group('EmojiGgService.downloadImage', () {
    test('returns body bytes on 200', () async {
      final svc = makeService(
        handler: (request) async {
          return http.Response.bytes(
            [0x89, 0x50, 0x4E, 0x47],
            200,
          );
        },
      );

      final bytes = await svc.downloadImage('https://emoji.gg/img/123.png');

      expect(bytes, [0x89, 0x50, 0x4E, 0x47]);
      svc.dispose();
    });

    test('throws on non-200 status', () async {
      final svc = makeService(
        handler: (request) async => http.Response('Not found', 404),
      );

      expect(
        () => svc.downloadImage('https://emoji.gg/img/missing.png'),
        throwsException,
      );
      svc.dispose();
    });
  });

  group('EmojiGgService disk cache', () {
    // The service fires _writeDiskCache via unawaited(), so we must wait
    // for the cache file to materialise before disposing / asserting.
    Future<void> waitForCacheFile() async {
      final file = File(p.join(tempDir.path, 'emojigg_packs_cache.json'));
      for (var i = 0; i < 50; i++) {
        if (file.existsSync()) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('persists to disk and reads from disk on next service instance',
        () async {
      // First instance: fetches from network and writes disk cache.
      final svc1 = makeService(
        handler: (request) async {
          callCount++;
          return http.Response(_samplePacksBody, 200);
        },
      );
      await svc1.fetchPacks();
      await waitForCacheFile();
      svc1.dispose();

      // Second instance: should read from disk cache without network.
      final svc2 = makeService(
        handler: (request) async {
          callCount++;
          return http.Response('[]', 200);
        },
      );
      final packs = await svc2.fetchPacks();

      // callCount is still 1 — disk cache was used, no extra network call.
      expect(callCount, 1);
      expect(packs.length, 1);
      expect(packs.first.id, 1);
      svc2.dispose();
    });

    test('ignores stale disk cache and refetches', () async {
      // First instance writes cache.
      final svc1 = makeService(
        handler: (request) async {
          callCount++;
          return http.Response(_samplePacksBody, 200);
        },
        cacheTtl: const Duration(milliseconds: 1),
      );
      await svc1.fetchPacks();
      await waitForCacheFile();
      svc1.dispose();

      // Wait for cache to become stale.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Second instance with same short TTL should refetch.
      final svc2 = makeService(
        handler: (request) async {
          callCount++;
          return http.Response(
            '[{"id": 99, "name": "Fresh", "slug": "f", "description": "", "emojis": "x", "amount": 1}]',
            200,
          );
        },
        cacheTtl: const Duration(milliseconds: 1),
      );
      final packs = await svc2.fetchPacks();

      expect(callCount, 2); // Refetched from network
      expect(packs.first.id, 99);
      svc2.dispose();
    });
  });
}
