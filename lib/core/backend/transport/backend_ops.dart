// coverage:ignore-file

/// Centralized op-name constants for [BackendCall]s and [BackendEvent]s.
///
/// Using these instead of inline string literals keeps the worker handler,
/// stub, and transport layer in sync with the contract in
/// `docs/backend-port-contract.md` and avoids typos.
abstract final class BackendOp {
  // ── Accounts ──────────────────────────────────────────────────
  static const accountsList = 'accounts.list';
  static const accountsLogin = 'accounts.login';
  static const accountsSso = 'accounts.sso';
  static const accountsRegister = 'accounts.register';
  static const accountsLogout = 'accounts.logout';
  static const accountsRestore = 'accounts.restore';
  static const subscribeAccountsLoginStateChanged =
      'subscribe.accounts.loginStateChanged';

  // ── Rooms list ────────────────────────────────────────────────
  static const roomsList = 'rooms.list';
  static const roomsCreate = 'rooms.create';
  static const subscribeRoomsListUpdates = 'subscribe.rooms.listUpdates';

  // ── Timeline ──────────────────────────────────────────────────
  static const timelineFetch = 'timeline.fetch';
  static const timelinePaginate = 'timeline.paginate';
  static const subscribeTimelineNewEvents = 'subscribe.timeline.newEvents';

  // ── Room management ───────────────────────────────────────────
  static const roomMgmtLeave = 'roomMgmt.leave';
  static const roomMgmtJoin = 'roomMgmt.join';
  static const roomMgmtInvite = 'roomMgmt.invite';
  static const roomMgmtKick = 'roomMgmt.kick';
  static const roomMgmtBan = 'roomMgmt.ban';
  static const roomMgmtUnban = 'roomMgmt.unban';
  static const roomMgmtSetName = 'roomMgmt.setName';
  static const roomMgmtSetTopic = 'roomMgmt.setTopic';
  static const roomMgmtSetAvatar = 'roomMgmt.setAvatar';

  // ── Room state ────────────────────────────────────────────────
  static const roomStateGet = 'roomState.get';
  static const roomStateSet = 'roomState.set';
  static const roomStateCanChange = 'roomState.canChange';
  static const roomStateGetPowerLevel = 'roomState.getPowerLevel';

  // ── Members & users ───────────────────────────────────────────
  static const membersGet = 'members.get';
  static const membersGetUser = 'members.getUser';
  static const membersSearch = 'members.search';

  // ── Messaging ─────────────────────────────────────────────────
  static const messageSend = 'message.send';
  static const messageSendText = 'message.sendText';
  static const messageReact = 'message.react';
  static const messageRedact = 'message.redact';
  static const messageReport = 'message.report';
  static const messageSendFile = 'message.sendFile';

  // ── Read state ────────────────────────────────────────────────
  static const readSetMarker = 'read.setMarker';
  static const readSetReceipt = 'read.setReceipt';
  static const readGetReceipts = 'read.getReceipts';

  // ── E2EE ──────────────────────────────────────────────────────
  static const e2eeEncryptionEnabled = 'e2ee.encryptionEnabled';
  static const e2eeDeviceKeys = 'e2ee.deviceKeys';
  static const e2eeVerifyDevice = 'e2ee.verifyDevice';
  static const e2eeStartVerification = 'e2ee.startVerification';
  static const e2eeCrossSigningEnabled = 'e2ee.crossSigning.enabled';
  static const e2eeCrossSigningIsCached = 'e2ee.crossSigning.isCached';
  static const e2eeCrossSigningSelfSign = 'e2ee.crossSigning.selfSign';
  static const e2eeBootstrap = 'e2ee.bootstrap';
  static const e2eeKeyBackupUnlock = 'e2ee.keyBackup.unlock';
  static const subscribeE2eeKeyVerificationRequest =
      'subscribe.e2ee.keyVerificationRequest';

  // ── Sync status ───────────────────────────────────────────────
  static const syncStatus = 'sync.status';

  // ── Media ──────────────────────────────────────────────────────
  static const mediaUpload = 'media.upload';
  static const mediaDownload = 'media.download';
  static const mediaMxcToHttp = 'media.mxcToHttp';
}

/// Centralized event-name constants for [BackendEvent]s pushed from the
/// worker to the UI.
abstract final class BackendEventName {
  static const roomsListUpdates = 'rooms.listUpdates';
  static const timelineNewEvents = 'timeline.newEvents';
  static const accountsLoginStateChanged = 'accounts.loginStateChanged';
  static const e2eeKeyVerificationRequest = 'e2ee.keyVerificationRequest';
  static const error = 'error';
}
