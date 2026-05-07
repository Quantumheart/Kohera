import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/whats_new/widgets/release_notes_markdown.dart';

const _sample = '''
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

Widget _harness(Widget child, {ThemeMode mode = ThemeMode.light}) {
  return MaterialApp(
    theme: ThemeData.light(useMaterial3: true),
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

void main() {
  testWidgets('renders sample release body without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(const ReleaseNotesMarkdown(data: _sample)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kohera 1.4.0'), findsWidgets);
    expect(find.textContaining('Faster sync'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark theme without exceptions', (tester) async {
    await tester.pumpWidget(
      _harness(
        const ReleaseNotesMarkdown(data: _sample),
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
      _harness(
        ReleaseNotesMarkdown(
          data: _sample,
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
        .pumpWidget(_harness(const ReleaseNotesMarkdown(data: '')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
