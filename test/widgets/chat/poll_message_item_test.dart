import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/theme/kohera_theme.dart';
import 'package:kohera/features/chat/models/kohera_poll.dart';
import 'package:kohera/features/chat/widgets/poll_message_item.dart';
import 'package:provider/provider.dart';

KoheraPoll _poll({
  KoheraPollKind kind = KoheraPollKind.disclosed,
  int maxSelections = 1,
  bool ended = false,
  Set<String> mySelections = const {},
  Map<String, int> tallies = const {},
  int responseCount = 0,
}) {
  return KoheraPoll(
    question: 'Tea or coffee?',
    answers: const [
      KoheraPollAnswer(id: 'a1', label: 'Yes'),
      KoheraPollAnswer(id: 'a2', label: 'No'),
      KoheraPollAnswer(id: 'a3', label: 'Maybe'),
    ],
    kind: kind,
    maxSelections: maxSelections,
    ended: ended,
    responseCount: responseCount,
    tallies: tallies,
    mySelections: mySelections,
  );
}

Widget _harness(
  KoheraPoll poll, {
  void Function(List<String> answerIds)? onVote,
}) {
  return MaterialApp(
    theme: KoheraTheme.light(),
    home: Scaffold(
      body: ChangeNotifierProvider<PreferencesService>.value(
        value: PreferencesService(),
        child: PollMessageItem(
          poll: poll,
          isMe: false,
          isFirst: true,
          onVote: onVote,
        ),
      ),
    ),
  );
}

void main() {
  group('computeNextSelection', () {
    test('single-select replaces the prior choice', () {
      expect(
        computeNextSelection(
          current: {'a1'},
          answerId: 'a2',
          maxSelections: 1,
        ),
        ['a2'],
      );
    });

    test('single-select tapping the selected option retracts', () {
      expect(
        computeNextSelection(
          current: {'a1'},
          answerId: 'a1',
          maxSelections: 1,
        ),
        isEmpty,
      );
    });

    test('multi-select toggles an option on up to maxSelections', () {
      expect(
        computeNextSelection(
          current: {'a1'},
          answerId: 'a2',
          maxSelections: 2,
        ),
        ['a1', 'a2'],
      );
    });

    test('multi-select toggles an option off', () {
      expect(
        computeNextSelection(
          current: {'a1', 'a2'},
          answerId: 'a1',
          maxSelections: 2,
        ),
        ['a2'],
      );
    });

    test('multi-select ignores adds beyond maxSelections', () {
      final next = computeNextSelection(
        current: {'a1', 'a2'},
        answerId: 'a3',
        maxSelections: 2,
      );
      expect(next..sort(), ['a1', 'a2']);
    });
  });

  testWidgets('tapping an option fires onVote with the new selection',
      (tester) async {
    List<String>? voted;
    await tester.pumpWidget(_harness(
      _poll(),
      onVote: (ids) => voted = ids,
    ));

    await tester.tap(find.text('Yes'));
    await tester.pump();

    expect(voted, ['a1']);
  });

  testWidgets('tapping the selected option retracts the vote',
      (tester) async {
    List<String>? voted;
    await tester.pumpWidget(_harness(
      _poll(mySelections: const {'a1'}),
      onVote: (ids) => voted = ids,
    ));

    await tester.tap(find.text('Yes'));
    await tester.pump();

    expect(voted, isEmpty);
  });

  testWidgets('voting is disabled when the poll has ended', (tester) async {
    List<String>? voted;
    await tester.pumpWidget(_harness(
      _poll(ended: true),
      onVote: (ids) => voted = ids,
    ));

    await tester.tap(find.text('Yes'));
    await tester.pump();

    expect(voted, isNull);
  });

  testWidgets('selected option shows a check icon', (tester) async {
    await tester.pumpWidget(_harness(
      _poll(mySelections: const {'a2'}),
    ));

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
  });
}
