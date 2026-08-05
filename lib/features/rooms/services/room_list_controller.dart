import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/services/room_list_builder.dart';
import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';

/// Business logic for the room list screen.
///
/// Owns search query state, FAB open/close state, message search delegation,
/// and exposes computed list items, context-menu eligibility, app-bar title,
/// and space-empty state.
class RoomListController extends ChangeNotifier {
  RoomListController({
    required MatrixService matrixService,
    required SelectionService selectionService,
    required PreferencesService preferencesService,
    required SpaceRoomsController spaceRoomsController,
    RoomListSearchController? messageSearchController,
  }) : _matrix = matrixService,
       _selection = selectionService,
       _prefs = preferencesService,
       _spaceRooms = spaceRoomsController,
       _messageSearch =
           messageSearchController ??
           RoomListSearchController(
             getClient: () => matrixService.client,
           ) {
    _messageSearch.addListener(notifyListeners);
  }

  final MatrixService _matrix;
  final SelectionService _selection;
  final PreferencesService _prefs;
  final SpaceRoomsController _spaceRooms;
  final RoomListSearchController _messageSearch;

  String _query = '';
  bool _searchOpen = false;
  bool _fabOpen = false;

  String get query => _query;
  bool get isSearchOpen => _searchOpen;
  bool get isFabOpen => _fabOpen;
  RoomListSearchController get messageSearch => _messageSearch;

  List<ListItem> get items {
    final baseItems = buildSectionItems(
      _selection,
      _prefs,
      _query,
      spaceRoomsController: _spaceRooms,
    );

    if (_query.trim().length < RoomListSearchController.minQueryLength) {
      return baseItems;
    }

    baseItems.add(
      MessageSearchHeaderItem(
        resultCount: _messageSearch.totalCount,
        isLoading: _messageSearch.isLoading,
        error: _messageSearch.error,
      ),
    );
    for (final result in _messageSearch.results) {
      baseItems.add(MessageSearchResultItem(result: result));
    }
    if (_messageSearch.nextBatch != null && !_messageSearch.isLoading) {
      baseItems.add(LoadMoreMessagesItem(isLoading: false));
    }

    return baseItems;
  }

  bool get hasRoomItems => items.any(
    (i) => i is RoomItem || i is InviteItem || i is HeaderItem,
  );

  bool get hasMessageResults => _messageSearch.results.isNotEmpty;

  bool get isMessageSearchActive => _messageSearch.isLoading;

  bool get isEmpty =>
      !hasRoomItems && !hasMessageResults && !isMessageSearchActive;

  bool get selectedSpaceCanManage => _selection.selectedSpaceIds.any((id) {
    final space = _matrix.client.getRoomById(id);
    return space != null && space.canChangeStateEvent('m.space.child');
  });

  Set<String> get manageableSpaceIds => {
    for (final s in _selection.spaces)
      if (s.canChangeStateEvent('m.space.child')) s.id,
  };

  String appBarTitle() {
    final ids = _selection.selectedSpaceIds;
    if (ids.isEmpty) return 'Chats';
    if (ids.length == 1) {
      return _matrix.client.getRoomById(ids.first)?.getLocalizedDisplayname() ??
          'Space';
    }
    return '${ids.length} spaces';
  }

  String? spaceWithNoJoinedRooms() {
    if (_selection.selectedSpaceIds.length != 1) return null;
    if (_query.isNotEmpty) return null;

    final spaceId = _selection.selectedSpaceIds.first;
    final space = _matrix.client.getRoomById(spaceId);
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

  void setQuery(String value, {Set<String>? scopeRoomIds}) {
    _query = value;
    _messageSearch.onQueryChanged(value, scopeRoomIds: scopeRoomIds);
    notifyListeners();
  }

  void clearQuery() {
    _query = '';
    _messageSearch.clear();
    notifyListeners();
  }

  void openSearch() {
    _searchOpen = true;
    notifyListeners();
  }

  void closeSearch() {
    if (!_searchOpen) return;
    _searchOpen = false;
    _query = '';
    _messageSearch.clear();
    notifyListeners();
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

  Set<String>? selectedSpaceRoomIds() => spaceRoomIds(_selection);

  void maybeFetchSpaceHierarchy() {
    for (final spaceId in _selection.selectedSpaceIds) {
      if (!_spaceRooms.isCached(spaceId)) {
        unawaited(_spaceRooms.fetchSpaceRooms(spaceId));
      }
    }
  }

  @override
  void dispose() {
    _messageSearch.removeListener(notifyListeners);
    _messageSearch.dispose();
    super.dispose();
  }
}
