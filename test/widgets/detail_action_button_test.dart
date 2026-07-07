import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/shared/widgets/detail_action_button.dart';
void main() {
  group('DetailActionButton', () {
    testWidgets('invokes onTap when enabled', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailActionButton(
              icon: KIcons.add,
              label: 'Add',
              onTap: () => tapped++,
            ),
          ),
        ),
      );

      expect(find.text('Add'), findsOneWidget);
      await tester.tap(find.byType(DetailActionButton));
      expect(tapped, 1);
    });

    testWidgets('is inert when onTap is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DetailActionButton(icon: KIcons.add, label: 'Add'),
          ),
        ),
      );

      // Tapping a disabled button must not throw and shows the label.
      await tester.tap(find.byType(DetailActionButton));
      expect(find.text('Add'), findsOneWidget);
    });
  });
}
