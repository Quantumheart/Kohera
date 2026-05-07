import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:kohera/features/whats_new/screens/whats_new_screen.dart';
import 'package:provider/provider.dart';

GitHubReleasesService _service({
  required Directory cacheDir,
  required Future<http.Response> Function(http.Request) handler,
}) {
  return GitHubReleasesService(
    client: MockClient(handler),
    cacheDirProvider: () async => cacheDir,
  );
}

Widget _harness(GitHubReleasesService service) =>
    Provider<GitHubReleasesService>.value(
      value: service,
      child: const MaterialApp(home: WhatsNewScreen()),
    );

void main() {
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

    await tester.pumpWidget(_harness(svc));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
      await tester.pumpWidget(_harness(svc));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
