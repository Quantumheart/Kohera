import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/state/selection_controller.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/space_tree_repository.dart';
import 'package:kohera/features/rooms/services/room_list_builder.dart';
import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:kohera/features/rooms/services/room_list_snapshot.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';

/// Business logic for the room list screen.
///
/// Architecture: a **sync-driven computation pipeline** that listens to its
/// dependencies, debounces their notifications, and produces a single
/// immutable [RoomListSnapshot] containing everything the view needs.
///
/// The view watches only the snapshot via `context.select`, so rebuilds are
/// triggered by a pre-computed value rather than five independent
/// `ChangeNotifier`s each firing on every sync.
class RoomListController extends ChangeNotifier {
  RoomListController({
    required RoomRepository roomRepository,
    required SpaceTreeRepository selectionService,
    required SelectionController selectionController,
    required PreferencesService preferencesService,
    required SpaceRoomsController spaceRoomsController,
    required MessageRepository messageRepository,
    RoomListSearchController? messageSearchController,
  }) : _rooms = roomRepository,
       _selection = selectionService,
       _selectionState = selectionController,
       _prefs = preferencesService,
       _spaceRooms = spaceRoomsController,
       _messageSearch =
           messageSearchController ??
           RoomListSearchController(
             getClient: () => roomRepository.searchClient,
             searchIndex: messageRepository.searchDatabase,
             ensureRoomIndexed: messageRepository.ensureRoomIndexed,
           ) {
    // Listen to every dependency — any change schedules a debounced recompute.
    _selection.addListener(_scheduleRecompute);
    _selectionState.addListener(_scheduleRecompute);
    _prefs.addListener(_scheduleRecompute);
    _spaceRooms.addListener(_scheduleRecompute);
    _messageSearch.addListener(_scheduleRecompute);

    // Compute the initial snapshot synchronously so the first build is correct.
    _recompute();
  }

  final RoomRepository _rooms;
  final SpaceTreeRepository _selection;
  final SelectionController _selectionState;
  final PreferencesService _prefs;
  final SpaceRoomsController _spaceRooms;
  final RoomListSearchController _messageSearch;

  // ── Snapshot ─────────────────────────────────────────────────

  RoomListSnapshot _snapshot = RoomListSnapshot.empty;

  /// The current pre-computed snapshot. O(1) — safe to call from `build()`.
  RoomListSnapshot get snapshot => _snapshot;

  // ── Immediate UI state (not debounced) ───────────────────────
  // These drive animations and need to feel instant. They trigger an
  // immediate notify without waiting for the debounce window.

  String _query = '';
  bool _searchOpen = false;
  bool _fabOpen = false;

  String get query => _query;
  bool get isSearchOpen => _searchOpen;
  bool get isFabOpen => _fabOpen;
  RoomListSearchController get messageSearch => _messageSearch;

  // ── Debounced recompute pipeline ─────────────────────────────

  Timer? _recomputeTimer;

  /// Debounce window. Sync updates often arrive in bursts (several syncs
  /// within 100-200ms). Batching them into a single recompute prevents
  /// redundant O(rooms × spaces) iterations and rebuild storms.
  static const _debounceDuration = Duration(milliseconds: 80);

  void _scheduleRecompute() {
    // If this was triggered by user action (query/search/fab change) we
    // already called _recompute() immediately in the setter. Sync-driven
    // notifications arrive here and are debounced.
    if (_recomputeTimer?.isActive ?? false) return;
    _recomputeTimer = Timer(_debounceDuration, _recompute);
  }

  void _recompute() {
    _recomputeTimer?.cancel();
    _recomputeTimer = null;

    final items = buildSectionItems(
      _selection,
      _selectionState,
      _prefs,
      _query,
      spaceRoomsController: _spaceRooms,
    );

    // Append message-search results if the query is long enough.
    final hasQuery = _query.trim().length >= RoomListSearchController.minQueryLength;
    if (hasQuery) {
      items.add(
        MessageSearchHeaderItem(
          resultCount: _messageSearch.totalCount,
          isLoading: _messageSearch.isLoading,
          error: _messageSearch.error,
        ),
      );
      for (final result in _messageSearch.results) {
        items.add(MessageSearchResultItem(result: result));
      }
      if (_messageSearch.nextBatch != null && !_messageSearch.isLoading) {
        items.add(LoadMoreMessagesItem(isLoading: false));
      }
    }

    final hasRoomItems = items.any(
      (i) => i is RoomItem || i is InviteItem || i is HeaderItem,
    );

    final manageableSpaceIds = {
      for (final s in _selection.spaces)
        if (s.canChangeStateEvent('m.space.child')) s.id,
    };

    final selectedSpaceCanManage = _selectionState.selectedSpaceIds.any((id) {
      final space = _rooms.rawRoom(id);
      return space != null && space.canChangeStateEvent('m.space.child');
    });

    _snapshot = RoomListSnapshot(
      items: List.unmodifiable(items),
      manageableSpaceIds: manageableSpaceIds,
      selectedSpaceCanManage: selectedSpaceCanManage,
      spaceWithNoJoinedRooms: _computeSpaceWithNoJoinedRooms(),
      appBarTitle: _computeAppBarTitle(),
      isEmpty: !hasRoomItems &&
          _messageSearch.results.isEmpty &&
          !_messageSearch.isLoading,
      hasMessageResults: _messageSearch.results.isNotEmpty,
      isMessageSearchActive: _messageSearch.isLoading,
      messageSearch: _messageSearch,
    );

    notifyListeners();
  }

  String? _computeSpaceWithNoJoinedRooms() {
    if (_selectionState.selectedSpaceIds.length != 1) return null;
    if (_query.isNotEmpty) return null;

    final spaceId = _selectionState.selectedSpaceIds.first;
    final space = _rooms.rawRoom(spaceId);
    if (space == null || !space.isSpace) return null;

    final joinedRooms = _selection.roomsForSpace(spaceId);
    if (joinedRooms.isNotEmpty) return null;

    final state = _spaceRooms.getRoomState(spaceId);
    if (!_spaceRooms.isCached(spaceId)) return spaceId;
    if (state.loading || state.error != null || state.previewForbidden) {
      return spaceId;
    }
    if (state.unjoinedRooms.isEmpty && state.subspaces.isEmpty) return null;
    return spaceId;
  }

  String _computeAppBarTitle() {
    final ids = _selectionState.selectedSpaceIds;
    if (ids.isEmpty) return 'Chats';
    if (ids.length == 1) {
      return _rooms.rawRoom(ids.first)?.getLocalizedDisplayname() ?? 'Space';
    }
    return '${ids.length} spaces';
  }

  // ── User actions (immediate recompute + notify) ──────────────

  void setQuery(String value, {Set<String>? scopeRoomIds}) {
    _query = value;
    _messageSearch.onQueryChanged(value, scopeRoomIds: scopeRoomIds);
    _recompute(); // immediate — user typing should feel responsive
  }

  void clearQuery() {
    _query = '';
    _messageSearch.clear();
    _recompute();
  }

  void openSearch() {
    _searchOpen = true;
    notifyListeners(); // UI-only change, no snapshot recompute needed
  }

  void closeSearch() {
    if (!_searchOpen) return;
    _searchOpen = false;
    _query = '';
    _messageSearch.clear();
    _recompute();
  }

  void toggleSearch() {
    if (_searchOpen) {
      closeSearch();
    } else {
      openSearch();
    }
  }

  void openFab() {
    _fabOpen = true;
    notifyListeners();
  }

  void closeFab() {
    if (!_fabOpen) return;
    _fabOpen = false;
    notifyListeners();
  }

  void toggleFab() {
    if (_fabOpen) {
      closeFab();
    } else {
      openFab();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  Set<String>? selectedSpaceRoomIds() => spaceRoomIds(_selection, _selectionState);

  void maybeFetchSpaceHierarchy() {
    for (final spaceId in _selectionState.selectedSpaceIds) {
      if (!_spaceRooms.isCached(spaceId)) {
        unawaited(_spaceRooms.fetchSpaceRooms(spaceId));
      }
    }
  }

  @override
  void dispose() {
    _recomputeTimer?.cancel();
    _selection.removeListener(_scheduleRecompute);
    _selectionState.removeListener(_scheduleRecompute);
    _prefs.removeListener(_scheduleRecompute);
    _spaceRooms.removeListener(_scheduleRecompute);
    _messageSearch.removeListener(_scheduleRecompute);
    _messageSearch.dispose();
    super.dispose();
  }
}
