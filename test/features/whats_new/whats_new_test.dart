import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:kohera/features/whats_new/screens/whats_new_screen.dart';
import 'package:kohera/features/whats_new/widgets/release_notes_markdown.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:provider/provider.dart';

const _sampleMarkdown = '''
# Kohera 1.4.0

Some intro paragraph with **bold** and *italic*.

## Highlights

- Faster sync
- Bug fixes
- `inline code` works

```dart
final x = 42;
```

[Release page](https://github.com/Quantumheart/Kohera/releases/tag/v1.4.0)
''';

Widget _markdownHarness(Widget child, {ThemeMode mode = ThemeMode.light}) {
  return MaterialApp(
    theme: ThemeData.light(useMaterial3: true).copyWith(splashFactory: InkRipple.splashFactory),
    darkTheme: ThemeData.dark(useMaterial3: true),
    themeMode: mode,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
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

Widget _screenHarness(GitHubReleasesService service) =>
    Provider<GitHubReleasesService>.value(
      value: service,
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const WhatsNewScreen(),
      ),
    );

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

void main() {
  group('ReleaseNotesMarkdown', () {
    testWidgets('renders sample release body without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _markdownHarness(const ReleaseNotesMarkdown(data: _sampleMarkdown)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Kohera 1.4.0'), findsWidgets);
      expect(find.textContaining('Faster sync'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark theme without exceptions', (tester) async {
      await tester.pumpWidget(
        _markdownHarness(
          const ReleaseNotesMarkdown(data: _sampleMarkdown),
          mode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a link invokes the launcher with the parsed Uri',
        (tester) async {
      Uri? launched;
      await tester.pumpWidget(
        _markdownHarness(
          ReleaseNotesMarkdown(
            data: _sampleMarkdown,
            linkLauncher: (uri) async {
              launched = uri;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Release page'));
      await tester.pump();

      expect(launched, isNotNull);
      expect(launched!.host, 'github.com');
      expect(launched!.path, contains('Quantumheart/Kohera'));
    });

    testWidgets('empty markdown renders nothing and does not throw',
        (tester) async {
      await tester
          .pumpWidget(_markdownHarness(const ReleaseNotesMarkdown(data: '')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('WhatsNewScreen', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('kohera_whats_new_screen_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('shows spinner while loading', (tester) async {
      final completer = Completer<http.Response>();
      addTearDown(() {
        if (!completer.isCompleted) {
          completer.complete(http.Response('{}', 500));
        }
      });
      final svc = _service(
        cacheDir: tempDir,
        handler: (_) => completer.future,
      );

      await tester.pumpWidget(_screenHarness(svc));
      await tester.pump();

      expect(find.byType(KoheraLoader), findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);

      completer.complete(http.Response('{}', 500));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('shows cloud_off + Retry when offline and no cache',
        (tester) async {
      final svc = _service(
        cacheDir: tempDir,
        handler: (_) async => throw const SocketException('offline'),
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(_screenHarness(svc));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Offline fallback', () {
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
  });
}
