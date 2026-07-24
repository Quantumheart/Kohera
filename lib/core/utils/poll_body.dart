import 'package:kohera/core/utils/poll_content.dart';
import 'package:matrix/matrix.dart';

/// Returns a readable notification/preview body for a poll-start event,
/// or `null` when [event] is not a poll-start event.
///
/// Parses safely: a malformed poll (e.g. missing the `org.matrix.msc1767.text`
/// fallback) yields a generic body instead of throwing.
String? pollStartBody(Event event) {
  if (event.type != PollEventContent.startType) return null;
  final parsed = safePollStart(event);
  if (parsed == null) return '📊 Poll';
  final question = parsed.question;
  return question.isEmpty ? '📊 Poll' : '📊 Poll: $question';
}
