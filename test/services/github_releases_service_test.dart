import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:path/path.dart' as p;

const _sampleBody = r'''
{
  "tag_name": "v1.4.0",
  "name": "Kohera 1.4.0",
  "body": "## What's new\n- Faster sync\n- Bug fixes",
  "published_at": "2026-05-01T12:00:00Z",
  "html_url": "https://github.com/Quantumheart/Kohera/releases/tag/v1.4.0"
}
''';

GitHubReleasesService _service({
  required Directory cacheDir,
  required MockClientHandler handler,
  Duration? cacheTtl,
}) {
  return GitHubReleasesService(
    client: MockClient(handler),
    cacheDirProvider: () async => cacheDir,
    cacheTtl: cacheTtl ?? const Duration(hours: 6),
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kohera_releases_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('first call hits network and persists to cache', () async {
    var calls = 0;
    final svc = _service(
      cacheDir: tempDir,
      handler: (request) async {
        calls++;
        return http.Response(
          _sampleBody,
          200,
          headers: {'etag': 'W/"abc123"'},
        );
      },
    );

    final notes = await svc.fetchLatest();
    expect(calls, 1);
    expect(notes, isNotNull);
    expect(notes!.tagName, 'v1.4.0');
    expect(notes.name, 'Kohera 1.4.0');
    expect(notes.body, contains('Faster sync'));
    expect(notes.htmlUrl, contains('Quantumheart/Kohera'));
    expect(notes.etag, 'W/"abc123"');

    final cacheFile = File(p.join(tempDir.path, 'whats_new_cache.json'));
    expect(cacheFile.existsSync(), isTrue);
  });

  test('second call within TTL returns cached value without hitting network',
      () async {
    var calls = 0;
    final svc = _service(
      cacheDir: tempDir,
      handler: (request) async {
        calls++;
        return http.Response(_sampleBody, 200);
      },
    );

    await svc.fetchLatest();
    await svc.fetchLatest();
    await svc.fetchLatest();

    expect(calls, 1);
  });

  test('expired cache triggers revalidation with If-None-Match header',
      () async {
    var calls = 0;
    String? sentIfNoneMatch;
    final svc = _service(
      cacheDir: tempDir,
      cacheTtl: Duration.zero,
      handler: (request) async {
        calls++;
        sentIfNoneMatch = request.headers['If-None-Match'];
        if (calls == 1) {
          return http.Response(
            _sampleBody,
            200,
            headers: {'etag': 'W/"abc123"'},
          );
        }
        return http.Response('', 304);
      },
    );

    final first = await svc.fetchLatest();
    final second = await svc.fetchLatest();

    expect(calls, 2);
    expect(sentIfNoneMatch, 'W/"abc123"');
    expect(second, isNotNull);
    expect(second!.tagName, first!.tagName);
    expect(second.body, first.body);
    expect(second.fetchedAt.isAfter(first.fetchedAt), isTrue);
  });

  test('forceRefresh bypasses fresh cache', () async {
    var calls = 0;
    final svc = _service(
      cacheDir: tempDir,
      handler: (request) async {
        calls++;
        return http.Response(_sampleBody, 200);
      },
    );

    await svc.fetchLatest();
    await svc.fetchLatest(forceRefresh: true);
    expect(calls, 2);
  });

  test('network error returns cached value if present', () async {
    var calls = 0;
    final svc = _service(
      cacheDir: tempDir,
      cacheTtl: Duration.zero,
      handler: (request) async {
        calls++;
        if (calls == 1) {
          return http.Response(_sampleBody, 200);
        }
        throw const SocketException('offline');
      },
    );

    final first = await svc.fetchLatest();
    final second = await svc.fetchLatest();

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(second!.tagName, 'v1.4.0');
  });

  test('non-200, non-304 response returns cached value', () async {
    var calls = 0;
    final svc = _service(
      cacheDir: tempDir,
      cacheTtl: Duration.zero,
      handler: (request) async {
        calls++;
        if (calls == 1) {
          return http.Response(_sampleBody, 200);
        }
        return http.Response('rate limited', 403);
      },
    );

    await svc.fetchLatest();
    final second = await svc.fetchLatest();
    expect(second, isNotNull);
    expect(second!.tagName, 'v1.4.0');
  });

  test('getCached reads disk without hitting network', () async {
    var calls = 0;
    final svc = _service(
      cacheDir: tempDir,
      handler: (request) async {
        calls++;
        return http.Response(_sampleBody, 200);
      },
    );
    await svc.fetchLatest();

    final fresh = _service(
      cacheDir: tempDir,
      handler: (request) async {
        calls++;
        return http.Response('should not be called', 500);
      },
    );

    final cached = await fresh.getCached();
    expect(cached, isNotNull);
    expect(cached!.tagName, 'v1.4.0');
    expect(calls, 1);
  });

  test('concurrent fetchLatest calls coalesce to a single request', () async {
    var calls = 0;
    final svc = _service(
      cacheDir: tempDir,
      handler: (request) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(_sampleBody, 200);
      },
    );

    final results = await Future.wait([
      svc.fetchLatest(),
      svc.fetchLatest(),
      svc.fetchLatest(),
    ]);

    expect(calls, 1);
    expect(results.every((r) => r != null), isTrue);
  });

  test('malformed cache file does not throw', () async {
    final cacheFile = File(p.join(tempDir.path, 'whats_new_cache.json'))
      ..writeAsStringSync('{not json');

    final svc = _service(
      cacheDir: tempDir,
      handler: (request) async => http.Response(_sampleBody, 200),
    );

    final cached = await svc.getCached();
    expect(cached, isNull);

    final notes = await svc.fetchLatest();
    expect(notes, isNotNull);
    expect(cacheFile.existsSync(), isTrue);
  });
}
