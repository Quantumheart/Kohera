import 'package:matrix/matrix.dart';

class MessageForwarder {
  const MessageForwarder._();

  /// Content to re-send when forwarding [source] to another room: a copy of the
  /// message content with relation metadata stripped, so the forwarded copy is
  /// a standalone message rather than a reply/edit/thread child of the original.
  static Map<String, dynamic> buildForwardContent(Event source) {
    return Map<String, dynamic>.from(source.content)
      ..remove('m.relates_to')
      ..remove('m.new_content');
  }

  /// Forwards [event] to [target]. When [timeline] is provided the latest
  /// edited version of the event is forwarded (via `getDisplayEvent`). Media and
  /// file messages are forwarded by reference — the original `mxc://` URI (and,
  /// for encrypted rooms, the embedded file key) travels in the content.
  static Future<void> forward({
    required Event event,
    required Room target,
    Timeline? timeline,
  }) async {
    final source = timeline != null ? event.getDisplayEvent(timeline) : event;
    await target.sendEvent(
      buildForwardContent(source),
      type: source.type,
    );
  }
}
