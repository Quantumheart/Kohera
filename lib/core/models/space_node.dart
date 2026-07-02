import 'package:kohera/features/rooms/models/kohera_room_summary.dart';

/// A node in the space tree representing a joined space and its children.
class SpaceNode {
  final KoheraRoomSummary summary;
  final List<SpaceNode> subspaces;
  final List<String> directChildRoomIds;

  const SpaceNode({
    required this.summary,
    this.subspaces = const [],
    this.directChildRoomIds = const [],
  });
}
