import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/models/server_auth_capabilities.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/auth/screens/homeserver_screen.dart';
import 'package:kohera/features/auth/screens/login_screen.dart';
import 'package:kohera/features/auth/screens/registration_screen.dart';
import 'package:kohera/features/calling/screens/call_pane.dart';
import 'package:kohera/features/calling/screens/call_screen.dart';
import 'package:kohera/features/chat/screens/chat_screen.dart';
import 'package:kohera/features/chat/screens/thread_list_screen.dart';
import 'package:kohera/features/chat/screens/thread_screen.dart';
import 'package:kohera/features/e2ee/screens/e2ee_setup_screen.dart';
import 'package:kohera/features/e2ee/screens/show_recovery_key_screen.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:kohera/features/home/widgets/inbox_screen.dart';
import 'package:kohera/features/rooms/screens/room_permissions_screen.dart';
import 'package:kohera/features/rooms/widgets/room_details_panel.dart';
import 'package:kohera/features/rooms/widgets/room_list.dart';
import 'package:kohera/features/settings/screens/appearance_screen.dart';
import 'package:kohera/features/settings/screens/devices_screen.dart';
import 'package:kohera/features/settings/screens/emoji_gg_browse_screen.dart';
import 'package:kohera/features/settings/screens/notification_settings_screen.dart';
import 'package:kohera/features/settings/screens/settings_screen.dart';
import 'package:kohera/features/settings/screens/sticker_packs_screen.dart';
import 'package:kohera/features/settings/screens/voice_video_settings_screen.dart';
import 'package:kohera/features/spaces/widgets/space_details_panel.dart';
import 'package:kohera/features/whats_new/screens/whats_new_screen.dart';
import 'package:provider/provider.dart';

/// Creates the app router with auth-aware redirects.
///
/// The router resolves the active [MatrixService] dynamically from
/// [manager] so that account switches don't require recreating the router
/// (which would reset the navigation stack and cause a visible flash).
GoRouter buildRouter(ClientManager manager) {
  final refreshListenable = _ActiveMatrixListenable(manager);
  final switchRedirector = AccountSwitchRedirector(manager.activeService);
  return GoRouter(
    refreshListenable: refreshListenable,
    initialLocation: RoutePaths.home,
    redirect: (context, state) {
      final matrixService = manager.activeService;
      final loggedIn = matrixService.isLoggedIn;
      final loc = state.matchedLocation;
      final onAuthRoute = loc.startsWith(RoutePaths.login) ||
          loc.startsWith(RoutePaths.register);
      final onSetupRoute = loc == RoutePaths.e2eeSetup;
      final onAddAccountRoute = loc.startsWith(RoutePaths.addAccount);

      final switchRedirect = switchRedirector.redirectFor(matrixService, loc);
      if (switchRedirect != null) return switchRedirect;

      // The add-account flow drives login against a pending service. If there
      // is none (genuine stray entry, or the moment after a successful commit
      // clears it), there is nothing to add — leave the flow before any
      // builder dereferences it.
      if (onAddAccountRoute && manager.pendingService == null) {
        return RoutePaths.home;
      }

      if (!loggedIn && !onAuthRoute) return RoutePaths.login;
      if (loggedIn && onAuthRoute && !onAddAccountRoute) return RoutePaths.home;

      if (loggedIn &&
          !onSetupRoute &&
          !onAuthRoute &&
          !onAddAccountRoute &&
          matrixService.chatBackup.chatBackupNeeded == true &&
          !matrixService.hasSkippedSetup) {
        return RoutePaths.e2eeSetup;
      }

      return null;
    },
    routes: [
      // ── Auth routes ──────────────────────────────────────────
      GoRoute(
        path: RoutePaths.login,
        name: Routes.login,
        builder: (context, state) => HomeserverScreen(key: ValueKey(state.uri)),
        routes: [
          GoRoute(
            path: ':homeserver',
            name: Routes.loginServer,
            builder: (context, state) => LoginScreen(
              homeserver: state.pathParameters['homeserver']!,
              capabilities: _capabilitiesFrom(state),
            ),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.register,
        name: Routes.register,
        builder: (context, state) =>
            RegistrationScreen(initialHomeserver: _homeserverFrom(context, state)),
      ),

      // ── Add-account login flow (outside the main app shell) ──
      //
      // A single shell owns the pending service for the whole flow: it
      // provides the shadowed [MatrixService] once and cancels the pending
      // service exactly when the flow is left (the shell is disposed). The
      // top-level redirect handles entry without a pending service, so the
      // shell never builds with a null one.
      ShellRoute(
        builder: (context, state, child) =>
            _AddAccountShell(manager: manager, child: child),
        routes: [
          GoRoute(
            path: RoutePaths.addAccount,
            name: Routes.addAccount,
            builder: (context, state) =>
                const HomeserverScreen(isAddAccount: true),
          ),
          GoRoute(
            path: RoutePaths.addAccountRegister,
            name: Routes.addAccountRegister,
            builder: (context, state) => RegistrationScreen(
              initialHomeserver: _homeserverFrom(context, state),
            ),
          ),
          GoRoute(
            path: RoutePaths.addAccountServer,
            name: Routes.addAccountServer,
            builder: (context, state) => LoginScreen(
              homeserver: state.pathParameters['homeserver']!,
              capabilities: _capabilitiesFrom(state),
              isAddAccount: true,
            ),
          ),
        ],
      ),

      // ── E2EE setup (full-page, outside shell) ────────────────
      GoRoute(
        path: RoutePaths.e2eeSetup,
        name: Routes.e2eeSetup,
        builder: (context, state) => const E2eeSetupScreen(),
      ),

      // ── Main app shell ───────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(routerChild: child, routerState: state),
        routes: [
          GoRoute(
            path: RoutePaths.home,
            name: Routes.home,
            builder: (context, state) => const RoomList(),
            routes: [
              GoRoute(
                path: 'rooms/:roomId',
                name: Routes.room,
                builder: (context, state) {
                  final roomId = state.pathParameters['roomId']!;
                  final eventId = state.extra as String?;
                  return ChatScreen(
                    roomId: roomId,
                    initialEventId: eventId,
                    key: ValueKey(
                      eventId != null ? '$roomId-$eventId' : roomId,
                    ),
                  );
                },
                routes: [
                  GoRoute(
                    path: 'details',
                    name: Routes.roomDetails,
                    builder: (context, state) {
                      final roomId = state.pathParameters['roomId']!;
                      return RoomDetailsPanel(
                        roomId: roomId,
                        isFullPage: true,
                        key: ValueKey('details-$roomId'),
                      );
                    },
                    routes: [
                      GoRoute(
                        path: 'permissions',
                        name: Routes.roomPermissions,
                        builder: (context, state) {
                          final roomId = state.pathParameters['roomId']!;
                          return RoomPermissionsScreen(
                            roomId: roomId,
                            key: ValueKey('permissions-$roomId'),
                          );
                        },
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'call',
                    name: Routes.call,
                    builder: (context, state) {
                      final roomId = state.pathParameters['roomId']!;
                      return _AdaptiveCallScreen(roomId: roomId);
                    },
                  ),
                  GoRoute(
                    path: 'thread/:eventId',
                    name: Routes.roomThread,
                    builder: (context, state) {
                      final roomId = state.pathParameters['roomId']!;
                      final eventId = state.pathParameters['eventId']!;
                      return ThreadScreen(
                        roomId: roomId,
                        threadRootEventId: eventId,
                        key: ValueKey('thread-$roomId-$eventId'),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'threads',
                    name: Routes.roomThreads,
                    builder: (context, state) {
                      final roomId = state.pathParameters['roomId']!;
                      return ThreadListScreen(
                        roomId: roomId,
                        key: ValueKey('threads-$roomId'),
                        onOpenThread: (eventId) =>
                            context.pushNamed(Routes.roomThread,
                                pathParameters: {
                                  'roomId': roomId,
                                  'eventId': eventId,
                                },),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'spaces',
                name: Routes.spaces,
                builder: (context, state) => const SizedBox.shrink(),
              ),
              GoRoute(
                path: 'spaces/:spaceId/details',
                name: Routes.spaceDetails,
                builder: (context, state) {
                  final spaceId = state.pathParameters['spaceId']!;
                  return SpaceDetailsPanel(
                    spaceId: spaceId,
                    isFullPage: true,
                    key: ValueKey('space-details-$spaceId'),
                  );
                },
              ),
              GoRoute(
                path: 'inbox',
                name: Routes.inbox,
                builder: (context, state) => const InboxScreen(),
              ),
              GoRoute(
                path: 'whats-new',
                name: Routes.whatsNew,
                builder: (context, state) => const WhatsNewScreen(),
              ),
              GoRoute(
                path: 'settings',
                name: Routes.settings,
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'appearance',
                    name: Routes.settingsAppearance,
                    builder: (context, state) =>
                        const AppearanceScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    name: Routes.settingsNotifications,
                    builder: (context, state) =>
                        const NotificationSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'devices',
                    name: Routes.settingsDevices,
                    builder: (context, state) => const DevicesScreen(),
                  ),
                  GoRoute(
                    path: 'voice-video',
                    name: Routes.settingsVoiceVideo,
                    builder: (context, state) =>
                        const VoiceVideoSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'recovery-key',
                    name: Routes.settingsRecoveryKey,
                    builder: (context, state) =>
                        const ShowRecoveryKeyScreen(),
                  ),
                  GoRoute(
                    path: 'sticker-packs',
                    name: Routes.settingsStickerPacks,
                    builder: (context, state) =>
                        const StickerPacksScreen(),
                  ),
                  GoRoute(
                    path: 'emoji-gg-browse',
                    name: Routes.settingsEmojiGgBrowse,
                    builder: (context, state) =>
                        const EmojiGgBrowseScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// A [Listenable] that forwards notifications from the currently active
/// [MatrixService] (and its [ChatBackupService]), re-binding automatically
/// when the active account changes. Lets the router use a stable
/// `refreshListenable` across account switches.
class _ActiveMatrixListenable extends ChangeNotifier {
  _ActiveMatrixListenable(this._manager) {
    _manager.addListener(_onManagerChanged);
    _attach(_manager.activeService);
  }

  final ClientManager _manager;
  MatrixService? _attached;

  void _onManagerChanged() {
    final next = _manager.activeService;
    if (!identical(next, _attached)) {
      _detach();
      _attach(next);
    }
    notifyListeners();
  }

  void _attach(MatrixService service) {
    service.addListener(notifyListeners);
    service.chatBackup.addListener(notifyListeners);
    _attached = service;
  }

  void _detach() {
    final prev = _attached;
    if (prev == null) return;
    prev.removeListener(notifyListeners);
    prev.chatBackup.removeListener(notifyListeners);
    _attached = null;
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _detach();
    super.dispose();
  }
}

/// Detects active-account switches and falls back to the room list when a
/// room route is still mounted.
///
/// Switching accounts swaps the per-account providers ([MatrixService] and
/// friends) for different instances while the keyed `ChatScreen` subtree is
/// still mounted and depends on them via `context.watch`. Reconciling the
/// keyed subtree onto the swapped providers deactivates an `InheritedElement`
/// before its dependent is released, tripping the framework's
/// `_dependents.isEmpty` assertion. Redirecting `/rooms/...` to `/` tears the
/// chat subtree down cleanly before the swap reconciles.
class AccountSwitchRedirector {
  AccountSwitchRedirector(this._active);

  MatrixService _active;

  String? redirectFor(MatrixService current, String location) {
    if (identical(current, _active)) return null;
    _active = current;
    return location.startsWith('/rooms/') ? '/' : null;
  }
}

/// Reads the homeserver for a registration route from the navigation extra,
/// falling back to the user's preferred default and then the app default.
String _homeserverFrom(BuildContext context, GoRouterState state) =>
    state.extra as String? ??
    context.read<PreferencesService>().defaultHomeserver ??
    AppConfig.instance.defaultHomeserver;

/// Reads the server capabilities for a login route from the navigation extra,
/// falling back to password-only auth before a .well-known lookup completes.
ServerAuthCapabilities _capabilitiesFrom(GoRouterState state) =>
    state.extra as ServerAuthCapabilities? ??
    const ServerAuthCapabilities(supportsPassword: true);

/// Owns the pending-service lifecycle for the entire add-account flow.
///
/// As a [ShellRoute] host this widget persists across the entry, server, and
/// register sub-routes and is disposed only when the flow is left, so it is
/// the single place that:
///   * provides the pending [MatrixService] to the shadowed subtree, and
///   * cancels the pending service on exit (a no-op once committed).
///
/// Intra-flow navigation (including Back) no longer tears down the pending
/// service, and the top-level redirect guarantees a pending service exists
/// before this builds.
class _AddAccountShell extends StatefulWidget {
  const _AddAccountShell({required this.manager, required this.child});

  final ClientManager manager;
  final Widget child;

  @override
  State<_AddAccountShell> createState() => _AddAccountShellState();
}

class _AddAccountShellState extends State<_AddAccountShell> {
  @override
  void dispose() {
    widget.manager.cancelPendingService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.manager.pendingService;
    if (pending == null) return const SizedBox.shrink();
    return ChangeNotifierProvider<MatrixService>.value(
      value: pending,
      child: widget.child,
    );
  }
}

class _AdaptiveCallScreen extends StatelessWidget {
  const _AdaptiveCallScreen({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final isWide =
        MediaQuery.sizeOf(context).width >= HomeShell.wideBreakpoint;
    if (isWide) return const CallPane();
    final room =
        context.read<MatrixService>().client.getRoomById(roomId);
    return CallScreen(
      roomId: roomId,
      displayName: room?.getLocalizedDisplayname() ?? 'Call',
    );
  }
}
