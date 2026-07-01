import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:kohera/features/home/widgets/inbox/invitations_view.dart';
import 'package:kohera/features/home/widgets/inbox/load_more_button.dart';
import 'package:kohera/features/home/widgets/inbox/notification_group_tile.dart';
import 'package:kohera/features/home/widgets/mobile_space_drawer.dart';
import 'package:kohera/features/notifications/enum/inbox_filter.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:provider/provider.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final InboxController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<InboxController>();
    if (_controller.grouped.isEmpty && !_controller.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_controller.fetch());
      });
    }
    _controller.startPolling();
  }

  @override
  void dispose() {
    _controller.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InboxController>();
    final selection = context.watch<SelectionService>();
    final inviteCount =
        selection.invitedRooms.length + selection.invitedSpaces.length;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isNarrow =
        MediaQuery.sizeOf(context).width < HomeShell.wideBreakpoint;

    return Scaffold(
      drawer: isNarrow ? const MobileSpaceDrawer() : null,
      appBar: AppBar(
        leading: isNarrow
            ? Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Spaces',
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              )
            : null,
        title: const Text(InboxText.title),
      ),
      body: Column(
        children: [
          // ── Filter segmented button ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<InboxFilter>(
              showSelectedIcon: false,
              selected: {controller.filter},
              onSelectionChanged: (selected) =>
                  controller.setFilter(selected.first),
              segments: [
                const ButtonSegment(
                  value: InboxFilter.all,
                  label: Text(InboxText.filterAll),
                ),
                const ButtonSegment(
                  value: InboxFilter.mentions,
                  label: Text(InboxText.filterMentions),
                ),
                const ButtonSegment(
                  value: InboxFilter.threads,
                  label: Text(InboxText.filterThreads),
                ),
                ButtonSegment(
                  value: InboxFilter.invitations,
                  label: Text(
                    inviteCount > 0
                        ? InboxText.invitationsWithCount(inviteCount)
                        : InboxText.filterInvitations,
                  ),
                ),
              ],
            ),
          ),

          // ── Content ──
          Expanded(
            child: controller.filter == InboxFilter.invitations
                ? InvitationsView(cs: cs, tt: tt)
                : controller.isLoading && controller.grouped.isEmpty
                    ? const Center(child: KoheraLoader())
                    : controller.error != null && controller.grouped.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline,
                                    size: 48,
                                    color: cs.error.withValues(alpha: 0.6),),
                                const SizedBox(height: 12),
                                Text(
                                  InboxText.failedToLoad,
                                  style: tt.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.tonal(
                                  onPressed: controller.fetch,
                                  child: const Text(InboxText.retry),
                                ),
                              ],
                            ),
                          )
                        : controller.grouped.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.notifications_none_rounded,
                                        size: 56,
                                        color: cs.onSurfaceVariant
                                            .withValues(alpha: 0.3),),
                                    const SizedBox(height: 16),
                                    Text(
                                      InboxText.noNotifications,
                                      style: tt.titleMedium?.copyWith(
                                        color: cs.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: controller.refresh,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4,),
                                  itemCount: controller.grouped.length +
                                      (controller.hasMore ? 1 : 0),
                                  itemBuilder: (context, i) {
                                    if (i == controller.grouped.length) {
                                      return LoadMoreButton(
                                        isLoading: controller.isLoading,
                                        onPressed: controller.loadMore,
                                      );
                                    }
                                    return NotificationGroupTile(
                                      group: controller.grouped[i],
                                      controller: controller,
                                    );
                                  },
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}
