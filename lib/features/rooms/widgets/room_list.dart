import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:kohera/features/home/widgets/mobile_space_drawer.dart';
import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:kohera/features/rooms/widgets/invite_tile.dart';
import 'package:kohera/features/rooms/widgets/message_search_tiles.dart';
import 'package:kohera/features/rooms/widgets/new_dm_dialog.dart';
import 'package:kohera/features/rooms/widgets/new_room_dialog.dart';
import 'package:kohera/features/rooms/widgets/room_list_builder.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:kohera/features/rooms/widgets/room_section_header.dart';
import 'package:kohera/features/rooms/widgets/room_tile.dart';
import 'package:kohera/features/spaces/models/space_rooms_model.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';
import 'package:kohera/features/spaces/widgets/space_action_dialog.dart';
import 'package:kohera/features/whats_new/widgets/whats_new_banner.dart';
import 'package:kohera/shared/widgets/speed_dial_item.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class RoomList extends StatefulWidget {
  const RoomList({super.key});

  @override
  State<RoomList> createState() => _RoomListState();
}

class _RoomListState extends State<RoomList>
    with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'roomlist-search');
  String _query = '';
  bool _searchOpen = false;
  late final AnimationController _searchAnimCtrl;
  late final Animation<double> _searchAnimation;
  late final AnimationController _fabAnimCtrl;
  late final Animation<double> _fabAnimation;
  bool _fabOpen = false;
  late final RoomListSearchController _messageSearch;

  @override
  void initState() {
    super.initState();
    _messageSearch = RoomListSearchController(
      getClient: () => context.read<MatrixService>().client,
    );
    _messageSearch.addListener(_onMessageSearchChanged);
    _searchAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _searchAnimation = CurvedAnimation(
      parent: _searchAnimCtrl,
      curve: Curves.easeOut,
    );
    _fabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimCtrl,
      curve: Curves.easeOut,
    );
  }

  void _onMessageSearchChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _messageSearch.removeListener(_onMessageSearchChanged);
    _messageSearch.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchAnimCtrl.dispose();
    _fabAnimCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      unawaited(_searchAnimCtrl.forward());
      _searchFocus.requestFocus();
    } else {
      unawaited(_searchAnimCtrl.reverse());
      _searchCtrl.clear();
      _query = '';
      _messageSearch.clear();
    }
  }

  void _closeSearch() {
    if (_searchOpen) {
      setState(() {
        _searchOpen = false;
        _searchCtrl.clear();
        _query = '';
      });
      _searchFocus.unfocus();
      unawaited(_searchAnimCtrl.reverse());
      _messageSearch.clear();
    }
  }

  void _toggleFab() {
    setState(() => _fabOpen = !_fabOpen);
    if (_fabOpen) {
      unawaited(_fabAnimCtrl.forward());
    } else {
      unawaited(_fabAnimCtrl.reverse());
    }
  }

  void _closeFab() {
    if (_fabOpen) {
      setState(() => _fabOpen = false);
      unawaited(_fabAnimCtrl.reverse());
    }
  }

  String _appBarTitle(SelectionService selection, MatrixService matrix) {
    final ids = selection.selectedSpaceIds;
    if (ids.isEmpty) return 'Chats';
    if (ids.length == 1) {
      return matrix.client
              .getRoomById(ids.first)
              ?.getLocalizedDisplayname() ??
          'Space';
    }
    return '${ids.length} spaces';
  }

  /// Returns the selected [Room] if it is a space with zero joined rooms
  /// and the hierarchy has (or is fetching) unjoined children.
  /// Returns `null` otherwise, falling back to the default empty state.
  Room? _spaceWithNoJoinedRooms(
    SelectionService selection,
    MatrixService matrix,
    SpaceRoomsController spaceRoomsController,
  ) {
    // Only applies when exactly one space is selected and no search is active.
    if (selection.selectedSpaceIds.length != 1) return null;
    if (_query.isNotEmpty) return null;

    final spaceId = selection.selectedSpaceIds.first;
    final space = matrix.client.getRoomById(spaceId);
    if (space == null || !space.isSpace) return null;

    // Must have zero joined rooms in this space.
    final joinedRooms = selection.roomsForSpace(spaceId);
    if (joinedRooms.isNotEmpty) return null;

    // Check the hierarchy state — loading / error / forbidden also show the
    // empty state (with appropriate messaging) so the user doesn't see a
    // blank pane.  If the hierarchy is loaded and has no children, fall back
    // to the default empty treatment.
    final state = spaceRoomsController.getRoomState(spaceId);
    if (!spaceRoomsController.isCached(spaceId)) return space;
    if (state.loading || state.error != null || state.previewForbidden) {
      return space;
    }
    if (state.unjoinedRooms.isEmpty && state.subspaces.isEmpty) return null;
    return space;
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionService>();
    final matrix = context.read<MatrixService>();
    final prefs = context.watch<PreferencesService>();
    final spaceRoomsController = context.watch<SpaceRoomsController>();
    final cs = Theme.of(context).colorScheme;

    final items = buildSectionItems(selection, prefs, _query,
        spaceRoomsController: spaceRoomsController,);

    // Trigger hierarchy fetch for selected spaces not yet cached.
    for (final spaceId in selection.selectedSpaceIds) {
      if (!spaceRoomsController.isCached(spaceId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(spaceRoomsController.fetchSpaceRooms(spaceId));
          }
        });
      }
    }

    // Pre-compute context menu eligibility data once for all tiles.
    final selectedSpaceCanManage = selection.selectedSpaceIds.any((id) {
      final space = matrix.client.getRoomById(id);
      return space != null && space.canChangeStateEvent('m.space.child');
    });
    final manageableSpaceIds = <String>{
      for (final s in selection.spaces)
        if (s.canChangeStateEvent('m.space.child')) s.id,
    };

    // Append message search items when query is long enough
    if (_query.trim().length >= RoomListSearchController.minQueryLength) {
      items.add(MessageSearchHeaderItem(
        resultCount: _messageSearch.totalCount,
        isLoading: _messageSearch.isLoading,
        error: _messageSearch.error,
      ),);
      for (final result in _messageSearch.results) {
        items.add(MessageSearchResultItem(result: result));
      }
      if (_messageSearch.nextBatch != null && !_messageSearch.isLoading) {
        items.add(LoadMoreMessagesItem(isLoading: false));
      }
    }

    // Determine if the list is truly empty (no rooms AND no message results)
    final hasRoomItems = items.any((i) =>
        i is RoomItem || i is InviteItem || i is HeaderItem,);
    final hasMessageResults = _messageSearch.results.isNotEmpty;
    final isMessageSearchActive = _messageSearch.isLoading;
    final isEmpty = !hasRoomItems && !hasMessageResults && !isMessageSearchActive;
    final isNarrow =
        MediaQuery.sizeOf(context).width < HomeShell.wideBreakpoint;

    // Check if we should show the centered empty state for a space with
    // zero joined rooms (issue #681).  This takes priority over the normal
    // list rendering so the user sees a clear CTA instead of a header with
    // an inline unjoined group.
    final spaceEmpty = _spaceWithNoJoinedRooms(
      selection,
      matrix,
      spaceRoomsController,
    );

    return PopScope(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        drawer: isNarrow ? const MobileSpaceDrawer() : null,
        appBar: AppBar(
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _searchOpen
                ? SizeTransition(
                    sizeFactor: _searchAnimation,
                    axis: Axis.horizontal,
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      key: const ValueKey('search'),
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onChanged: (v) {
                        setState(() => _query = v);
                        _messageSearch.onQueryChanged(v,
                            scopeRoomIds: spaceRoomIds(selection),);
                      },
                      decoration: InputDecoration(
                        hintText: 'Search\u2026',
                        border: InputBorder.none,
                        isDense: true,
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                  _messageSearch.clear();
                                },
                              )
                            : null,
                      ),
                    ),
                  )
                : Text(
                    _appBarTitle(selection, matrix),
                    key: const ValueKey('title'),
                  ),
          ),
          leading: _searchOpen
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _closeSearch,
                )
              : (isNarrow
                  ? Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu),
                        tooltip: 'Spaces',
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    )
                  : null),
          actions: _searchOpen
              ? null
              : [
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search',
                    onPressed: _toggleSearch,
                  ),
                ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
              const WhatsNewBanner(),
              // ── Sectioned room list ──
              Expanded(
                child: spaceEmpty != null
                    ? _SpaceEmptyState(
                        space: spaceEmpty,
                        controller: spaceRoomsController,
                        matrixService: matrix,
                      )
                    : isEmpty && items.isEmpty
                        ? Center(
                            child: Text(
                              _query.isNotEmpty
                                  ? 'No results for "$_query"'
                                  : 'No rooms yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: cs.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                          )
                        : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4,),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return switch (item) {
                            InviteItem() =>
                              InviteTile(room: item.room),
                            HeaderItem() => RoomSectionHeader(
                                item: item,
                                prefs: prefs,
                                selection: selection,
                                matrixService: matrix,
                              ),
                            RoomItem() => Padding(
                                padding: EdgeInsets.only(
                                    left: item.depth * 16.0,),
                                child: Builder(builder: (_) {
                                  final memberships = selection.spaceMemberships(item.room.id);
                                  return RoomTile(
                                    room: item.room,
                                    isSelected: selection.selectedRoomId == item.room.id,
                                    memberships: memberships,
                                    hasContextMenu: selectedSpaceCanManage ||
                                        manageableSpaceIds.isNotEmpty,
                                    parentSpaceId: item.parentSpaceId,
                                    sectionRooms: item.sectionRooms,
                                  );
                                },),
                              ),
                            MessageSearchHeaderItem() =>
                              MessageSearchHeader(item: item),
                            MessageSearchResultItem() =>
                              MessageSearchResultTile(
                                result: item.result,
                                query: _query,
                              ),
                            LoadMoreMessagesItem() =>
                              LoadMoreButton(
                                isLoading: item.isLoading,
                                onPressed: () => _messageSearch.performSearch(
                                    loadMore: true,),
                              ),
                            UnjoinedRoomGroupHeaderItem() =>
                              _UnjoinedGroupHeader(item: item,
                                  matrixService: matrix,),
                            UnjoinedRoomItem() => Padding(
                                padding: EdgeInsets.only(
                                    left: item.depth * 16.0,),
                                child: _UnjoinedRoomTile(
                                  metadata: item.metadata,
                                  parentSpaceId: item.parentSpaceId,
                                  controller: spaceRoomsController,
                                ),),
                            SubspaceOpenItem() => Padding(
                                padding: EdgeInsets.only(
                                    left: item.depth * 16.0,),
                                child: _SubspaceOpenTile(
                                  metadata: item.metadata,
                                  parentSpaceId: item.parentSpaceId,
                                  matrixService: matrix,
                                ),),
                            UnjoinedRoomLoadingItem() => Padding(
                                padding: EdgeInsets.only(
                                    left: item.depth * 16.0 + 10,),
                                child: const SizedBox(
                                  height: 32,
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),),
                            UnjoinedRoomErrorItem() => Padding(
                                padding: EdgeInsets.only(
                                    left: item.depth * 16.0,),
                                child: _UnjoinedErrorTile(item: item,
                                    controller: spaceRoomsController,),),
                            UnjoinedRoomForbiddenItem() => Padding(
                                padding: EdgeInsets.only(
                                    left: item.depth * 16.0 + 10,),
                                child: const _UnjoinedForbiddenTile(),),
                          };
                        },
                      ),
              ),
            ],
          ),

          // ── Scrim overlay to dismiss speed dial ──
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeFab,
                child: const ColoredBox(
                  color: Colors.black26,
                ),
              ),
            ),

          // ── FAB + speed dial ──
          Positioned(
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ── Mini-FABs (speed dial) ──
                SizeTransition(
                  sizeFactor: _fabAnimation,
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SpeedDialItem(
                          label: 'New Room',
                          icon: Icons.group_add_rounded,
                          onTap: () {
                            _closeFab();
                            unawaited(NewRoomDialog.show(context, matrixService: matrix));
                          },
                        ),
                        const SizedBox(height: 8),
                        SpeedDialItem(
                          label: 'New Direct Message',
                          icon: Icons.chat_bubble_outline_rounded,
                          onTap: () {
                            _closeFab();
                            unawaited(NewDirectMessageDialog.show(
                                context,
                                matrixService: matrix,
                            ),);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Main FAB ──
                FloatingActionButton(
                  heroTag: 'compose',
                  onPressed: _toggleFab,
                  child: AnimatedRotation(
                    turns: _fabOpen ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.edit_rounded),
                  ),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}

// ── Unjoined group header ────────────────────────────────

class _UnjoinedGroupHeader extends StatelessWidget {
  const _UnjoinedGroupHeader({required this.item, required this.matrixService});

  final UnjoinedRoomGroupHeaderItem item;
  final MatrixService matrixService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final space = matrixService.client.getRoomById(item.spaceId);

    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10, top: 8, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'MORE ROOMS TO JOIN'
              .toUpperCase(),
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              if (space == null) return;
              unawaited(SpaceDiscoveryDialog.showSpaceRooms(
                context,
                matrixService: matrixService,
                roomId: space.id,
                name: space.getLocalizedDisplayname(),
                avatar: space.avatar,
                canonicalAlias: space.canonicalAlias,
              ),);
            },
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Browse all'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Unjoined room tile ─────────────────────────────────────

class _UnjoinedRoomTile extends StatefulWidget {
  const _UnjoinedRoomTile({
    required this.metadata,
    required this.parentSpaceId,
    required this.controller,
  });

  final SpaceRoomMetadata metadata;
  final String parentSpaceId;
  final SpaceRoomsController controller;

  @override
  State<_UnjoinedRoomTile> createState() => _UnjoinedRoomTileState();
}

class _UnjoinedRoomTileState extends State<_UnjoinedRoomTile> {
  bool _isJoining = false;
  bool _joinError = false;

  Future<void> _join() async {
    setState(() {
      _isJoining = true;
      _joinError = false;
    });
    final result = await widget.controller.join(
      roomId: widget.metadata.roomId,
      parentSpaceId: widget.parentSpaceId,
    );
    if (!mounted) return;
    setState(() {
      _isJoining = false;
      _joinError = result == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = widget.metadata.name ?? widget.metadata.roomId;

    return ListTile(
      leading: Opacity(
        opacity: 0.5,
        child: CircleAvatar(
          radius: 20,
          backgroundColor: cs.surfaceContainerHighest,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '#',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium?.copyWith(color: cs.onSurface),
      ),
      subtitle: Text(
        '${widget.metadata.memberCount} members',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: _isJoining
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _joinError
              ? TextButton(
                  onPressed: _join,
                  child: const Text('Retry'),
                )
              : FilledButton.tonal(
                  onPressed: _join,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Join'),
                ),
    );
  }
}

// ── Subspace "Open" tile ───────────────────────────────────

class _SubspaceOpenTile extends StatelessWidget {
  const _SubspaceOpenTile({
    required this.metadata,
    required this.parentSpaceId,
    required this.matrixService,
  });

  final SpaceRoomMetadata metadata;
  final String parentSpaceId;
  final MatrixService matrixService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = metadata.name ?? metadata.roomId;

    return ListTile(
      leading: Opacity(
        opacity: 0.5,
        child: CircleAvatar(
          radius: 20,
          backgroundColor: cs.surfaceContainerHighest,
          child: Icon(Icons.workspaces_outlined, color: cs.onSurfaceVariant),
        ),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium?.copyWith(color: cs.onSurface),
      ),
      subtitle: Text(
        'Subspace · ${metadata.memberCount} members',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: OutlinedButton(
        onPressed: () {
          unawaited(SpaceDiscoveryDialog.showSpaceRooms(
            context,
            matrixService: matrixService,
            roomId: metadata.roomId,
            name: name,
            avatar: metadata.avatar,
          ),);
        },
        child: const Text('Open'),
      ),
    );
  }
}

// ── Unjoined error tile ──────────────────────────────────────

class _UnjoinedErrorTile extends StatelessWidget {
  const _UnjoinedErrorTile({required this.item, required this.controller});

  final UnjoinedRoomErrorItem item;
  final SpaceRoomsController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not load rooms',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          TextButton(
            onPressed: () {
              unawaited(controller.fetchSpaceRooms(item.spaceId));
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Unjoined forbidden tile ──────────────────────────────────

class _UnjoinedForbiddenTile extends StatelessWidget {
  const _UnjoinedForbiddenTile();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This space hides its room list',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state for a space with zero joined rooms ─────────────────────────

class _SpaceEmptyState extends StatelessWidget {
  const _SpaceEmptyState({
    required this.space,
    required this.controller,
    required this.matrixService,
  });

  final Room space;
  final SpaceRoomsController controller;
  final MatrixService matrixService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = controller.getRoomState(space.id);

    // ── Loading ──
    if (!controller.isCached(space.id) || state.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading rooms…',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // ── Error ──
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: cs.error),
              const SizedBox(height: 16),
              Text('Could not load rooms', style: tt.titleMedium),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  unawaited(controller.fetchSpaceRooms(space.id));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // ── Forbidden ──
    if (state.previewForbidden) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                "You're in the ${space.getLocalizedDisplayname()} space",
                style: tt.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'This space hides its room list. '
                'Join rooms to start seeing messages.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  unawaited(SpaceDiscoveryDialog.showSpaceRooms(
                    context,
                    matrixService: matrixService,
                    roomId: space.id,
                    name: space.getLocalizedDisplayname(),
                    avatar: space.avatar,
                    canonicalAlias: space.canonicalAlias,
                  ),);
                },
                child: const Text('Browse rooms'),
              ),
            ],
          ),
        ),
      );
    }

    // ── Success: unjoined children available ──
    final totalRooms = state.unjoinedRooms.length + state.subspaces.length;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Space avatar
              CircleAvatar(
                radius: 40,
                backgroundColor: cs.surfaceContainerHighest,
                child: Icon(Icons.workspaces_outlined,
                    size: 40, color: cs.onSurfaceVariant,),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                "You're in the ${space.getLocalizedDisplayname()} space",
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                'Join rooms to start seeing messages',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Browse rooms button
              FilledButton(
                onPressed: () {
                  unawaited(SpaceDiscoveryDialog.showSpaceRooms(
                    context,
                    matrixService: matrixService,
                    roomId: space.id,
                    name: space.getLocalizedDisplayname(),
                    avatar: space.avatar,
                    canonicalAlias: space.canonicalAlias,
                  ),);
                },
                child: Text('Browse $totalRooms rooms'),
              ),
              const SizedBox(height: 24),

              // Inline join list
              Text(
                'or join directly',
                style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),

              // Unjoined room tiles
              for (final metadata in state.unjoinedRooms.take(5))
                _UnjoinedRoomTile(
                  metadata: metadata,
                  parentSpaceId: space.id,
                  controller: controller,
                ),

              // Subspace tiles
              for (final metadata in state.subspaces.take(3))
                _SubspaceOpenTile(
                  metadata: metadata,
                  parentSpaceId: space.id,
                  matrixService: matrixService,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
