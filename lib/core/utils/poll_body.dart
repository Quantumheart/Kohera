import 'package:matrix/matrix.dart';

/// Returns a readable notification/preview body for a poll-start event,
/// or `null` when [event] is not a poll-start event.
String? pollStartBody(Event event) {
  if (event.type != PollEventContent.startType) return null;
  final question = event.parsedPollEventContent.pollStartContent.question.mText;
  return question.isEmpty ? '📊 Poll' : '📊 Poll: $question';
}
