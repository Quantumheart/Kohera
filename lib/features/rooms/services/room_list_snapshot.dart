import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';

/// Immutable, pre-computed snapshot of everything the room list view needs to
/// render.
///
/// Produced by [RoomListController] on data-change (debounced) and consumed by
/// the view via `context.select`.  Moving all heavy computation here — off the
/// build cycle — means the view's `build()` does O(1) reads instead of
/// re-iterating every room/space on every sync.
class RoomListSnapshot {
  const RoomListSnapshot({
    this.items = const [],
    this.manageableSpaceIds = const {},
    this.selectedSpaceCanManage = false,
    this.spaceWithNoJoinedRooms,
    this.appBarTitle = 'Chats',
    this.isEmpty = true,
    this.isInitialLoading = false,
    this.hasMessageResults = false,
    this.isMessageSearchActive = false,
    this.messageSearch,
  });

  /// The flat, ordered list of rooms, headers, invites, and search results.
  final List<ListItem> items;

  /// Space IDs the user can manage (for context-menu visibility).
  final Set<String> manageableSpaceIds;

  /// Whether the currently-selected space can be managed.
  final bool selectedSpaceCanManage;

  /// The ID of a selected space that has zero joined rooms, or `null`.
  final String? spaceWithNoJoinedRooms;

  /// Title text for the app bar.
  final String appBarTitle;

  /// True when the list has no room items and no message results.
  final bool isEmpty;

  /// True when [isEmpty] but the first sync or cache hydration has not
  /// finished yet — the view should show a loader, not an empty state.
  final bool isInitialLoading;

  /// True when message search has results.
  final bool hasMessageResults;

  /// True when a message search is in flight.
  final bool isMessageSearchActive;

  /// The message search controller (for "load more" in the list).
  final RoomListSearchController? messageSearch;

  /// Sentinel for the initial empty state before the first compute.
  static const empty = RoomListSnapshot();
}
