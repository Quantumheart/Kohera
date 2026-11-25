import 'package:kohera/data/models/kohera_event_types.dart';

/// A null-safe view over an MSC3381 poll-start event's content.
///
/// The SDK's `Event.parsedPollEventContent` throws
/// `type 'Null' is not a subtype of type 'String'` when a poll-start event is
/// missing the `org.matrix.msc1767.text` fallback (or an answer label), which
/// crashes the chat screen. This helper parses the same fields directly from
/// the raw event content with safe fallbacks, so a malformed poll degrades
/// gracefully instead of throwing.
class SafePollStart {
  const SafePollStart({
    required this.question,
    required this.answers,
    required this.maxSelections,
    required this.disclosed,
  });

  /// The poll question text (empty string when absent).
  final String question;

  /// Answer options in their original order. Answers without a usable `id`
  /// are dropped.
  final List<SafePollAnswer> answers;

  /// Maximum number of selections a voter may make (defaults to 1).
  final int maxSelections;

  /// Whether the poll tally is disclosed (public) while open.
  final bool disclosed;
}

/// One selectable answer option in a poll, parsed safely.
class SafePollAnswer {
  const SafePollAnswer({required this.id, required this.label});

  /// The stable answer id.
  final String id;

  /// A human-readable label, falling back to the `body` or the id.
  final String label;
}

const String _startKey = 'org.matrix.msc3381.poll.start';
const String _kindDisclosed = 'org.matrix.msc3381.poll.disclosed';
const String _textKey = 'org.matrix.msc1767.text';

/// Parses a poll-start event safely from its wire [type] and [content], or
/// returns `null` if it is not a poll-start event with usable start content.
///
/// Unlike the SDK's `Event.parsedPollEventContent`, this never throws on
/// missing text fields.
SafePollStart? safePollStartContent(
  String type,
  Map<String, Object?> content,
) {
  if (type != KoheraEventTypes.pollStart) return null;
  final startRaw = content[_startKey];
  if (startRaw is! Map) return null;
  final start = Map<String, Object?>.from(startRaw);

  final disclosed = start['kind'] == _kindDisclosed;

  final maxSelectionsRaw = start['max_selections'];
  final maxSelections = maxSelectionsRaw is int ? maxSelectionsRaw : 1;

  final questionMapRaw = start['question'];
  final questionMap =
      questionMapRaw is Map ? Map<String, Object?>.from(questionMapRaw) : null;
  final question = (questionMap?[_textKey] as String?) ??
      (questionMap?['body'] as String?) ??
      '';

  final answersRaw = start['answers'];
  final answers = <SafePollAnswer>[];
  if (answersRaw is List) {
    for (final entry in answersRaw) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || id.isEmpty) continue;
      final label =
          (entry[_textKey] as String?) ??
          (entry['body'] as String?) ??
          id;
      answers.add(SafePollAnswer(id: id, label: label));
    }
  }

  return SafePollStart(
    question: question,
    answers: answers,
    maxSelections: maxSelections,
    disclosed: disclosed,
  );
}

/// Returns a readable notification/preview body for a poll-start event,
/// or `null` when [type] is not the poll-start type.
///
/// Parses safely: a malformed poll (e.g. missing the `org.matrix.msc1767.text`
/// fallback) yields a generic body instead of throwing.
String? pollBodyFromContent(String type, Map<String, Object?> content) {
  if (type != KoheraEventTypes.pollStart) return null;
  final parsed = safePollStartContent(type, content);
  if (parsed == null) return '📊 Poll';
  final question = parsed.question;
  return question.isEmpty ? '📊 Poll' : '📊 Poll: $question';
}
