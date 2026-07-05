import 'package:kohera/features/chat/services/media_content_resolver.dart';
import 'package:kohera/features/chat/services/sdk_media_controller.dart';
import 'package:kohera/features/rooms/widgets/shared_media_section.dart';
import 'package:matrix/matrix.dart';

/// Creates a [SharedMediaLoader] that loads media from [room] via
/// `room.searchEvents()`. This is the SDK boundary — the returned function
/// can be passed to [SharedMediaSection] which has no matrix import.
SharedMediaLoader sharedMediaLoaderForRoom(Room room) {
  return ({
    required String roomId,
    String? nextBatch,
  }) async {
    final result = await room.searchEvents(
      searchFunc: (event) {
        final mt = event.messageType;
        return mt == MessageTypes.Image ||
            mt == MessageTypes.Video ||
            mt == MessageTypes.File ||
            mt == MessageTypes.Audio;
      },
      nextBatch: nextBatch,
      limit: 20,
    );

    final items = result.events.map((event) {
      return SharedMediaItem(
        media: const MediaContentResolver()(event),
        controller: SdkMediaController(event),
      );
    }).toList();

    return SharedMediaPage(items: items, nextBatch: result.nextBatch);
  };
}
