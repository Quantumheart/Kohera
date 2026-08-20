import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/resolvers/media_content_resolver.dart';
import 'package:kohera/features/chat/services/sdk_media_controller.dart';
import 'package:kohera/features/rooms/widgets/shared_media_section.dart';
import 'package:matrix/matrix.dart';

/// Creates a [SharedMediaLoader] that loads media from the room identified
/// by [roomId] via `room.searchEvents()`. This is the SDK boundary — the
/// returned function can be passed to [SharedMediaSection] which has no
/// matrix import.
SharedMediaLoader sharedMediaLoaderForRoom(
  String roomId,
  RoomRepository roomRepo,
) {
  return ({
    required String roomId,
    String? nextBatch,
  }) async {
    final room = roomRepo.rawRoom(roomId);
    if (room == null) return const SharedMediaPage(items: []);

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
        media: MediaContentResolver.resolve(event),
        controller: SdkMediaController(event, roomRepo.searchClient),
      );
    }).toList();

    return SharedMediaPage(items: items, nextBatch: result.nextBatch);
  };
}
