import 'package:flutter/foundation.dart';

/// User-entered poll configuration captured by [CreatePollDialog] before it
/// is sent via `Room.startPoll`.
///
/// Display widgets and the dialog never import `package:matrix/matrix.dart`;
/// the send boundary ([ChatMessageActions.sendPoll]) converts this draft into
/// SDK `PollAnswer`s with generated ids and calls `room.startPoll`.
@immutable
class KoheraPollDraft {
  const KoheraPollDraft({
    required this.question,
    required this.answers,
    required this.disclosed,
    required this.maxSelections,
  });

  final String question;

  /// Non-empty answer labels, in order. 2–20 entries (enforced by the dialog).
  final List<String> answers;

  /// `true` for a disclosed poll (live tallies), `false` for undisclosed.
  final bool disclosed;

  /// Maximum selections a voter may make. `1` = single-select.
  final int maxSelections;
}
