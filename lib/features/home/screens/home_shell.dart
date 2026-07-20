import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/calling/services/call_service.dart';
import 'package:kohera/features/calling/widgets/voice_banner.dart';
import 'package:kohera/features/e2ee/widgets/key_backup_banner.dart';
import 'package:kohera/features/home/widgets/narrow_layout.dart';
import 'package:kohera/features/home/widgets/wide_layout.dart';
import 'package:kohera/features/spaces/widgets/space_reparent_controller.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.routerChild, required this.routerState, super.key,
  });

  final Widget routerChild;
  final GoRouterState routerState;

  static const double wideBreakpoint = 720;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _syncScheduled = false;

  static const double _wideBreakpoint = HomeShell.wideBreakpoint;

  // ── Route → MatrixService sync ──────────────────────────────

  String? get _routeRoomId => widget.routerState.pathParameters[RouteParams.roomId];
  String? get _routeName => widget.routerState.topRoute?.name;

  void _syncRoomSelection() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final selection = context.read<SelectionService>();
      final roomId = _routeRoomId;
      if (selection.selectedRoomId != roomId) {
        selection.selectRoom(roomId);
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomeShell old) {
    super.didUpdateWidget(old);
    final oldRoomId = old.routerState.pathParameters[RouteParams.roomId];
    final newRoomId = _routeRoomId;

    if (oldRoomId != newRoomId) {
      _syncRoomSelection();
    }
  }

  @override
  void initState() {
    super.initState();
    _syncRoomSelection();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;

    final selection = context.read<SelectionService>();
    context.select<SelectionService, int>((s) => Object.hashAll(s.spaces.map((sp) => sp.id)));
    context.select<CallService, (KoheraCallState, String?)>(
      (s) => (s.callState, s.activeCallRoomId),
    );

    final child = isWide
        ? WideLayout(
            width: width,
            routerChild: widget.routerChild,
            routeName: _routeName,
            roomId: _routeRoomId,
          )
        : NarrowLayout(
            routerChild: widget.routerChild,
            routeName: _routeName,
            roomId: _routeRoomId,
          );

    return ChangeNotifierProvider<SpaceReparentController>(
      create: (_) => SpaceReparentController(),
      child: CallbackShortcuts(
        bindings: _buildKeyBindings(selection),
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              VoiceBanner(currentViewingRoomId: _routeRoomId),
              const KeyBackupBanner(),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildKeyBindings(SelectionService selection) {
    final spaces = selection.topLevelSpaces;
    final bindings = <ShortcutActivator, VoidCallback>{};

    bindings[const SingleActivator(LogicalKeyboardKey.digit0,
        control: true,)] = () => selection.clearSpaceSelection();

    final digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    for (var i = 0; i < digitKeys.length && i < spaces.length; i++) {
      final spaceId = spaces[i].id;
      bindings[SingleActivator(digitKeys[i], control: true)] =
          () => selection.selectSpace(spaceId);
      bindings[SingleActivator(digitKeys[i], control: true, shift: true)] =
          () => selection.toggleSpaceSelection(spaceId);
    }

    return bindings;
  }
}
// coverage:ignore-end
