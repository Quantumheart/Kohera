import 'package:kohera/data/models/kohera_public_room.dart';
import 'package:matrix/matrix.dart';

/// Converts SDK public-directory payloads into domain models.
class PublicRoomResolver {
  const PublicRoomResolver();

  KoheraPublicRoom convert(PublishedRoomsChunk chunk) => KoheraPublicRoom(
        roomId: chunk.roomId,
        name: chunk.name,
        topic: chunk.topic,
        canonicalAlias: chunk.canonicalAlias,
        avatarUrl: chunk.avatarUrl,
        memberCount: chunk.numJoinedMembers,
        worldReadable: chunk.worldReadable,
        guestCanJoin: chunk.guestCanJoin,
        roomType: chunk.roomType,
      );

  KoheraPublicRoomsPage convertPage(QueryPublicRoomsResponse response) =>
      KoheraPublicRoomsPage(
        items: [for (final chunk in response.chunk) convert(chunk)],
        nextBatch: response.nextBatch,
        totalRoomCountEstimate: response.totalRoomCountEstimate,
      );

  PublicRoomQueryFilter toSdkFilter(KoheraPublicRoomFilter filter) =>
      PublicRoomQueryFilter(
        roomTypes: filter.roomTypes,
        genericSearchTerm: filter.genericSearchTerm,
      );
}
