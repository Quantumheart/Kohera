import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kohera/core/services/github_releases_service.dart';

ReleaseNotes _sampleCached(DateTime now) => ReleaseNotes(
      tagName: 'v1.4.0',
      name: 'Kohera 1.4.0',
      body: "## What's new\n- Faster sync",
      publishedAt: DateTime.utc(2026, 5, 1, 12),
      htmlUrl: 'https://github.com/Quantumheart/Kohera/releases/tag/v1.4.0',
      fetchedAt: now.subtract(const Duration(days: 1)),
    );

Future<void> _writeCache(Directory dir, ReleaseNotes notes) async {
  final file = File('${dir.path}/whats_new_cache.json');
  await file.writeAsString(jsonEncode(notes.toCacheJson()));
}

GitHubReleasesService _service({
  required Directory cacheDir,
  required Future<http.Response> Function(http.Request) handler,
}) {
  return GitHubReleasesService(
    client: MockClient(handler),
    cacheDirProvider: () async => cacheDir,
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kohera_offline_fallback_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('fetchLatest returns cached notes on network failure', () async {
    final cached = _sampleCached(DateTime.now());
    await _writeCache(tempDir, cached);
    final svc = _service(
      cacheDir: tempDir,
      handler: (_) async => throw const SocketException('offline'),
    );

    final result = await svc.fetchLatest(forceRefresh: true);

    expect(result, isNotNull);
    expect(result!.tagName, cached.tagName);
    expect(result.body, cached.body);
  });

  test('fetchLatest returns null when offline and no cache', () async {
    final svc = _service(
      cacheDir: tempDir,
      handler: (_) async => throw const SocketException('offline'),
    );

    final result = await svc.fetchLatest(forceRefresh: true);

    expect(result, isNull);
  });

  test('cache round-trip preserves all fields', () async {
    final original = _sampleCached(DateTime.now());
    await _writeCache(tempDir, original);
    final svc = _service(
      cacheDir: tempDir,
      handler: (_) async => http.Response('{}', 500),
    );

    final cached = await svc.getCached();

    expect(cached, isNotNull);
    expect(cached!.tagName, original.tagName);
    expect(cached.name, original.name);
    expect(cached.body, original.body);
    expect(cached.htmlUrl, original.htmlUrl);
    expect(
      cached.publishedAt.toIso8601String(),
      original.publishedAt.toIso8601String(),
    );
  });
}
