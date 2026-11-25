import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/rooms/widgets/shared_media_section.dart';

/// Creates a [SharedMediaLoader] that loads media from the room identified
/// by [roomId] via [RoomRepository.searchSharedMedia]. The returned
/// function can be passed to [SharedMediaSection], which has no matrix
/// import.
SharedMediaLoader sharedMediaLoaderForRoom(
  String roomId,
  RoomRepository roomRepo,
) {
  return ({
    required String roomId,
    String? nextBatch,
  }) async {
    final result = await roomRepo.searchSharedMedia(
      roomId,
      nextBatch: nextBatch,
    );

    final items = [
      for (final item in result.items)
        SharedMediaItem(media: item.media, controller: item.controller),
    ];

    return SharedMediaPage(items: items, nextBatch: result.nextBatch);
  };
}
