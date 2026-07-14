import 'package:kohera/features/chat/models/kohera_poll.dart';
import 'package:matrix/matrix.dart';

/// Converts an MSC3381 poll-start [Event] (+ [Timeline]) into a pre-computed
/// [KoheraPoll] for the chat message rendering widget tree.
///
/// This is the SDK conversion boundary for poll rendering. Display widgets
/// below consume [KoheraPoll] and never import `package:matrix/matrix.dart`.
class PollResolver {
  const PollResolver();

  KoheraPoll call(Event event, Timeline timeline,
      {required String myUserId, required bool canRedact}) {
    assert(event.type == PollEventContent.startType, 'PollResolver requires a poll-start event');

    final content = event.parsedPollEventContent.pollStartContent;
    final kind = content.kind == PollKind.disclosed
        ? KoheraPollKind.disclosed
        : KoheraPollKind.undisclosed;

    final ended = event.getPollHasBeenEnded(timeline);

    final answers = content.answers
        .map((a) => KoheraPollAnswer(id: a.id, label: a.mText))
        .toList(growable: false);

    final tallies = <String, int>{for (final a in answers) a.id: 0};
    var responseCount = 0;

    final responses = event.getPollResponses(timeline);
    final mySelections = Set<String>.from(responses[myUserId] ?? const {});

    final showTally = kind == KoheraPollKind.disclosed || ended;
    if (showTally) {
      responseCount = responses.length;
      for (final answerIds in responses.values) {
        for (final id in answerIds) {
          final current = tallies[id];
          if (current != null) tallies[id] = current + 1;
        }
      }
    }

    return KoheraPoll(
      question: content.question.mText,
      answers: answers,
      kind: kind,
      maxSelections: content.maxSelections,
      ended: ended,
      responseCount: responseCount,
      tallies: tallies,
      mySelections: mySelections,
      canEnd: event.senderId == myUserId || canRedact,
    );
  }
}
