import 'package:flutter/foundation.dart';

/// Visibility of a poll's running tally.
enum KoheraPollKind { disclosed, undisclosed }

/// One selectable answer option in a poll.
@immutable
class KoheraPollAnswer {
  const KoheraPollAnswer({required this.id, required this.label});

  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraPollAnswer && id == other.id && label == other.label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// Kohera-owned domain model for a Matrix MSC3381 poll-start event.
///
/// Produced at the SDK boundary (`MessageTimelineController`) from
/// `Event.parsedPollEventContent` + `Event.getPollResponses`. Display widgets
/// (`PollMessageItem`) consume this type and never import
/// `package:matrix/matrix.dart`.
@immutable
class KoheraPoll {
  const KoheraPoll({
    required this.question,
    required this.answers,
    required this.kind,
    required this.maxSelections,
    required this.ended,
    required this.responseCount,
    required this.tallies,
    required this.mySelections,
  });

  final String question;

  /// Answer options in their original order.
  final List<KoheraPollAnswer> answers;

  final KoheraPollKind kind;

  /// Maximum number of selections a voter may make.
  final int maxSelections;

  /// Whether the poll has been ended by an authorised end event.
  final bool ended;

  /// Total number of valid, counted responses.
  final int responseCount;

  /// Per-answer tally: answer id → vote count. Empty (all zero) when the
  /// tally is hidden for an open undisclosed poll.
  final Map<String, int> tallies;

  /// Answer ids the current user has selected, derived from
  /// `Event.getPollResponses(timeline)[myUserId]`. Empty when the user has
  /// not voted (or retracted).
  final Set<String> mySelections;

  /// Whether the running tally should be rendered.
  ///
  /// Disclosed polls show counts while open and after they end. Undisclosed
  /// polls hide counts until [ended] becomes true.
  bool get showsTally =>
      kind == KoheraPollKind.disclosed || ended;
}
