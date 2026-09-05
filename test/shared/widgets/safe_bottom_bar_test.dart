import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/widgets/safe_bottom_bar.dart';

void main() {
  Widget harness({
    required double bottomInset,
    Widget? child,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          padding: EdgeInsets.only(bottom: bottomInset),
          size: const Size(400, 600),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  testWidgets('clears content above bottom inset', (tester) async {
    const key = Key('content');
    await tester.pumpWidget(harness(
      bottomInset: 48,
      child: const SafeBottomBar(
        child: SizedBox(key: key, height: 40),
      ),
    ));

    final contentBottom = tester.getRect(find.byKey(key)).bottom;
    expect(contentBottom, lessThan(600 - 48 + 1));
  });

  testWidgets('fills color behind inset strip', (tester) async {
    const fill = Color(0xFF112233);
    await tester.pumpWidget(harness(
      bottomInset: 48,
      child: const SafeBottomBar(
        color: fill,
        child: SizedBox(height: 20),
      ),
    ));

    final bar = tester.getRect(find.byType(SafeBottomBar));
    expect(bar.bottom, 600);
    final colored = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(SafeBottomBar),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(colored.color, fill);
  });

  testWidgets('applies content padding separately from inset', (tester) async {
    const key = Key('content');
    await tester.pumpWidget(harness(
      bottomInset: 48,
      child: const SafeBottomBar(
        padding: EdgeInsets.only(bottom: 10),
        child: SizedBox(key: key, height: 30),
      ),
    ));

    final contentBottom = tester.getRect(find.byKey(key)).bottom;
    expect(contentBottom, closeTo(600 - 48 - 10, 0.1));
  });

  testWidgets('is idempotent under nested SafeArea', (tester) async {
    const key = Key('content');
    await tester.pumpWidget(harness(
      bottomInset: 48,
      child: const SafeBottomBar(
        child: SafeBottomBar(
          child: SizedBox(key: key, height: 20),
        ),
      ),
    ));

    final contentBottom = tester.getRect(find.byKey(key)).bottom;
    expect(contentBottom, closeTo(600 - 48, 0.1));
  });

  testWidgets('zero inset renders content at bottom', (tester) async {
    const key = Key('content');
    await tester.pumpWidget(harness(
      bottomInset: 0,
      child: const SafeBottomBar(
        child: SizedBox(key: key, height: 20),
      ),
    ));

    final contentBottom = tester.getRect(find.byKey(key)).bottom;
    expect(contentBottom, 600);
  });
}
