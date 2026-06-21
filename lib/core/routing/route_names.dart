/// Path-parameter keys used in route definitions and `pathParameters` maps.
///
/// Defined once so the `:key` in a route path stays in sync with every
/// `state.pathParameters['key']` read and `pathParameters: {'key': ...}` write.
abstract class RouteParams {
  static const roomId = 'roomId';
  static const homeserver = 'homeserver';
  static const eventId = 'eventId';
  static const spaceId = 'spaceId';
}

/// Absolute route paths for go_router navigation and redirect checks.
///
/// Use these instead of inline string literals so the path is defined once
/// and `context.go(...)` calls stay in sync with the route table.
abstract class RoutePaths {
  static const home = '/';
  static const roomPrefix = '/rooms/';
  static const login = '/login';
  static const register = '/register';
  static const e2eeSetup = '/e2ee-setup';
  static const settingsRecoveryKey = '/settings/recovery-key';

  // ── Add-account flow ──────────────────────────────────────────
  static const addAccount = '/add-account';
  static const addAccountRegister = '/add-account/register';
  static const addAccountServer = '/add-account/:${RouteParams.homeserver}';
}

/// Relative path segments for nested `GoRoute` definitions.
///
/// Nested sub-routes must use relative segments (a child `path` may not start
/// with `/`), so these complement the absolute [RoutePaths].
abstract class RouteSegments {
  static const loginServer = ':${RouteParams.homeserver}';
  static const room = 'rooms/:${RouteParams.roomId}';
  static const roomDetails = 'details';
  static const roomPermissions = 'permissions';
  static const call = 'call';
  static const roomThread = 'thread/:${RouteParams.eventId}';
  static const roomThreads = 'threads';
  static const spaces = 'spaces';
  static const spaceDetails = 'spaces/:${RouteParams.spaceId}/details';
  static const inbox = 'inbox';
  static const whatsNew = 'whats-new';
  static const settings = 'settings';
  static const settingsAppearance = 'appearance';
  static const settingsNotifications = 'notifications';
  static const settingsDevices = 'devices';
  static const settingsVoiceVideo = 'voice-video';
  static const settingsRecoveryKey = 'recovery-key';
  static const settingsStickerPacks = 'sticker-packs';
  static const settingsEmojiGgBrowse = 'emoji-gg-browse';
}

/// Named route constants for go_router navigation.
abstract class Routes {
  static const login = 'login';
  static const loginServer = 'login-server';
  static const register = 'register';
  static const home = 'home';
  static const room = 'room';
  static const roomDetails = 'room-details';
  static const roomThread = 'room-thread';
  static const roomThreads = 'room-threads';
  static const spaces = 'spaces';
  static const settings = 'settings';
  static const settingsAppearance = 'settings-appearance';
  static const settingsNotifications = 'settings-notifications';
  static const settingsDevices = 'settings-devices';
  static const settingsVoiceVideo = 'settings-voice-video';
  static const settingsRecoveryKey = 'settings-recovery-key';
  static const settingsStickerPacks = 'settings-sticker-packs';
  static const settingsEmojiGgBrowse = 'settings-emoji-gg-browse';
  static const inbox = 'inbox';
  static const spaceDetails = 'space-details';
  static const call = 'call';
  static const e2eeSetup = 'e2ee-setup';
  static const addAccount = 'add-account';
  static const addAccountServer = 'add-account-server';
  static const addAccountRegister = 'add-account-register';
  static const whatsNew = 'whats-new';
  static const roomPermissions = 'room-permissions';
}
