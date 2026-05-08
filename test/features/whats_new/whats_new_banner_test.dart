import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/whats_new/widgets/whats_new_banner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sampleBody = r'''
{
  "tag_name": "v1.4.0",
  "name": "Kohera 1.4.0",
  "body": "## What's new\n- Faster sync",
  "published_at": "2026-05-01T12:00:00Z",
  "html_url": "https://github.com/Quantumheart/Kohera/releases/tag/v1.4.0"
}
''';

PackageInfo _pkg(String version) => PackageInfo(
      appName: 'kohera',
      packageName: 'app.kohera',
      version: version,
      buildNumber: '1',
    );

Future<PreferencesService> _prefsWith({
  required String current,
  String? lastSeen,
}) async {
  SharedPreferences.setMockInitialValues({
    if (lastSeen != null) 'last_seen_version': lastSeen,
  });
  final sp = await SharedPreferences.getInstance();
  final svc = PreferencesService(prefs: sp, packageInfo: _pkg(current));
  await svc.init();
  return svc;
}

GitHubReleasesService _releasesService({
  required Directory cacheDir,
  Future<http.Response> Function(http.Request)? handler,
}) {
  return GitHubReleasesService(
    client: MockClient(
      handler ?? (request) async => http.Response(_sampleBody, 200),
    ),
    cacheDirProvider: () async => cacheDir,
  );
}

Widget _harness({
  required PreferencesService prefs,
  required GitHubReleasesService releases,
  GoRouter? router,
}) {
  final theRouter = router ??
      GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
              body: Column(
                children: [WhatsNewBanner(), Expanded(child: SizedBox())],
              ),
            ),
            routes: [
              GoRoute(
                path: 'whats-new',
                name: 'whats-new',
                builder: (_, __) =>
                    const Scaffold(body: Text('detail-page-stub')),
              ),
            ],
          ),
        ],
      );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PreferencesService>.value(value: prefs),
      Provider<GitHubReleasesService>.value(value: releases),
    ],
    child: MaterialApp.router(routerConfig: theRouter),
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kohera_banner_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('hidden when there is no version bump', (tester) async {
    final prefs = await _prefsWith(current: '1.4.0'); // fresh install path
    final releases = _releasesService(cacheDir: tempDir);

    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(prefs: prefs, releases: releases));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byType(WhatsNewBanner), findsOneWidget);
    expect(find.textContaining("What's new in"), findsNothing);
  });

  testWidgets('shows after version bump and notes load', (tester) async {
    final prefs = await _prefsWith(lastSeen: '1.0.0', current: '1.4.0');
    final releases = _releasesService(cacheDir: tempDir);

    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(prefs: prefs, releases: releases));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text("What's new in v1.4.0"), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('dismiss marks version seen and hides the banner',
      (tester) async {
    final prefs = await _prefsWith(lastSeen: '1.0.0', current: '1.4.0');
    final releases = _releasesService(cacheDir: tempDir);

    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(prefs: prefs, releases: releases));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text("What's new in v1.4.0"), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(prefs.lastSeenVersion, '1.4.0');
    expect(prefs.hasVersionBumped, isFalse);
    expect(find.text("What's new in v1.4.0"), findsNothing);
  });

  testWidgets('View navigates to the whats-new route', (tester) async {
    final prefs = await _prefsWith(lastSeen: '1.0.0', current: '1.4.0');
    final releases = _releasesService(cacheDir: tempDir);

    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(prefs: prefs, releases: releases));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.text('detail-page-stub'), findsOneWidget);
  });

  testWidgets('shows update-available when latest tag is newer than installed',
      (tester) async {
    final prefs = await _prefsWith(current: '1.0.0');
    final releases = _releasesService(cacheDir: tempDir);

    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(prefs: prefs, releases: releases));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('Update available'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('Open launches the GitHub release URL externally',
      (tester) async {
    final prefs = await _prefsWith(current: '1.0.0');
    final releases = _releasesService(cacheDir: tempDir);
    final launched = <Uri>[];

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: Column(
              children: [
                WhatsNewBanner(
                  linkLauncher: (uri) async {
                    launched.add(uri);
                    return true;
                  },
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ],
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _harness(prefs: prefs, releases: releases, router: router),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      launched.single.toString(),
      'https://github.com/Quantumheart/Kohera/releases/tag/v1.4.0',
    );
  });

  testWidgets('dismissing update-available persists tag and hides banner',
      (tester) async {
    final prefs = await _prefsWith(current: '1.0.0');
    final releases = _releasesService(cacheDir: tempDir);

    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(prefs: prefs, releases: releases));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('Update available'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(prefs.lastDismissedUpdateTag, 'v1.4.0');
    expect(find.textContaining('Update available'), findsNothing);
  });

  testWidgets('stays hidden when release notes fail to load', (tester) async {
    final prefs = await _prefsWith(lastSeen: '1.0.0', current: '1.4.0');
    final releases = _releasesService(
      cacheDir: tempDir,
      handler: (request) async => http.Response('boom', 500),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(prefs: prefs, releases: releases));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining("What's new in"), findsNothing);
  });
}
