import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/calling/screens/call_pane.dart';
import 'package:kohera/features/chat/screens/chat_screen.dart';
import 'package:kohera/features/rooms/widgets/room_list.dart';
import 'package:kohera/features/spaces/widgets/space_rail.dart';
import 'package:kohera/shared/widgets/kohera_mark.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

class WideLayout extends StatefulWidget {
  const WideLayout({
    required this.width,
    required this.routerChild,
    required this.routeName,
    required this.roomId,
    super.key,
  });

  final double width;
  final Widget routerChild;
  final String? routeName;
  final String? roomId;

  @override
  State<WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends State<WideLayout> {
  double? _dragPanelWidth;

  static const double _extraWideBreakpoint = 1100;
  static const double _collapseThreshold = PreferencesService.collapseThreshold;

  @override
  Widget build(BuildContext context) {
    final showChat = widget.width >= _extraWideBreakpoint;
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          const SpaceRail(),

          if (showChat && _dragPanelWidth == null && prefs.panelWidth < _collapseThreshold) ...[
            SizedBox(
              width: 40,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Expand room list',
                  onPressed: () {
                    setState(() => _dragPanelWidth = null);
                    unawaited(prefs.setPanelWidth(PreferencesService.defaultPanelWidth));
                  },
                ),
              ),
            ),
            VerticalDivider(width: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
          ] else ...[
            SizedBox(
              width: showChat
                  ? (_dragPanelWidth ?? prefs.panelWidth).clamp(
                      _collapseThreshold,
                      PreferencesService.maxPanelWidth,
                    )
                  : 360,
              child: const RoomList(),
            ),

            if (showChat)
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragStart: (_) {
                    _dragPanelWidth = prefs.panelWidth;
                  },
                  onHorizontalDragUpdate: (details) {
                    final current = _dragPanelWidth ?? prefs.panelWidth;
                    setState(() {
                      _dragPanelWidth = (current + details.delta.dx)
                          .clamp(_collapseThreshold * 0.5, PreferencesService.maxPanelWidth);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    final w = _dragPanelWidth ?? prefs.panelWidth;
                    setState(() => _dragPanelWidth = null);
                    unawaited(prefs.setPanelWidth(w < _collapseThreshold ? 0 : w));
                  },
                  child: Container(
                    width: 5,
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              )
            else
              VerticalDivider(width: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
          ],

          Expanded(
            child: _buildContentPane(),
          ),
        ],
      ),
    );
  }

  Widget _buildContentPane() {
    final roomId = widget.roomId;
    final name = widget.routeName;

    if (name == Routes.settings ||
        name == Routes.settingsAppearance ||
        name == Routes.settingsNotifications ||
        name == Routes.settingsDevices ||
        name == Routes.settingsVoiceVideo ||
        name == Routes.settingsRecoveryKey ||
        name == Routes.settingsStickerPacks ||
        name == Routes.settingsIgnoredUsers ||
        name == Routes.settingsEmojiGgBrowse ||
        name == Routes.spaces ||
        name == Routes.spaceDetails ||
        name == Routes.inbox ||
        name == Routes.roomThread ||
        name == Routes.roomThreads ||
        name == Routes.whatsNew ||
        name == Routes.roomPermissions ||
        name == Routes.roomDetails) {
      return widget.routerChild;
    }

    if (name == Routes.call && roomId != null) {
      return const CallPane();
    }

    if (roomId == null) return _buildEmptyChat();

    return Row(
      children: [
        Expanded(
          child: ChatScreen(
            roomId: roomId,
            key: ValueKey(roomId),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyChat() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KoheraMark(
            size: 72,
            color: cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a conversation',
            style: tt.titleMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
// coverage:ignore-end
