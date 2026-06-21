import Flutter
import UIKit
import flutter_callkit_incoming
import AVFAudio
import CallKit
import PushKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CallkitIncomingAppDelegate, PKPushRegistryDelegate {
  private var apnsChannel: FlutterMethodChannel?
  private var pendingPushPayloads: [[AnyHashable: Any]] = []
  private var pendingNotificationActions: [(action: String, roomId: String, eventId: String?, replyText: String?)] = []
  private var channelReady = false
  private static let maxPendingPayloads = 20

  // ── PushKit / VoIP ──────────────────────────────────────────
  private var voipRegistry: PKPushRegistry?
  private var voipChannel: FlutterMethodChannel?
  private var pendingVoipPayloads: [[AnyHashable: Any]] = []
  private var voipChannelReady = false
  private var cachedVoipToken: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let replyAction = UNTextInputNotificationAction(
      identifier: "reply",
      title: "Reply",
      textInputButtonTitle: "Send",
      textInputPlaceholder: "Message..."
    )
    let markReadAction = UNNotificationAction(
      identifier: "mark_read",
      title: "Mark as Read"
    )
    let category = UNNotificationCategory(
      identifier: "MESSAGE",
      actions: [replyAction, markReadAction],
      intentIdentifiers: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
    UNUserNotificationCenter.current().delegate = self
    application.applicationIconBadgeNumber = 0

    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    application.applicationIconBadgeNumber = 0
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    guard let notification = userInfo["notification"] as? [String: Any],
          let roomId = notification["room_id"] as? String else {
      completionHandler()
      return
    }

    let eventId = notification["event_id"] as? String

    switch response.actionIdentifier {
    case "reply":
      let replyText = (response as? UNTextInputNotificationResponse)?.userText
      dispatchOrQueue(action: "reply", roomId: roomId, eventId: eventId, replyText: replyText)
    case "mark_read":
      dispatchOrQueue(action: "mark_read", roomId: roomId, eventId: eventId, replyText: nil)
    default:
      dispatchOrQueue(action: "tap", roomId: roomId, eventId: eventId, replyText: nil)
    }

    UIApplication.shared.applicationIconBadgeNumber = 0
    completionHandler()
  }

  private func dispatchOrQueue(action: String, roomId: String, eventId: String?, replyText: String?) {
    if channelReady {
      dispatchAction(action: action, roomId: roomId, eventId: eventId, replyText: replyText)
    } else {
      pendingNotificationActions.append((action: action, roomId: roomId, eventId: eventId, replyText: replyText))
    }
  }

  private func dispatchAction(action: String, roomId: String, eventId: String?, replyText: String?) {
    switch action {
    case "reply":
      apnsChannel?.invokeMethod("onNotificationReply", arguments: ["roomId": roomId, "text": replyText ?? ""])
    case "mark_read":
      apnsChannel?.invokeMethod("onNotificationMarkAsRead", arguments: ["roomId": roomId, "eventId": eventId ?? ""])
    default:
      apnsChannel?.invokeMethod("onNotificationTap", arguments: roomId)
    }
  }

  // ── APNs token callbacks ────────────────────────────────────

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsChannel?.invokeMethod("onToken", arguments: token)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    apnsChannel?.invokeMethod("onRegistrationError", arguments: error.localizedDescription)
  }

  // ── Background push receipt ─────────────────────────────────

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if channelReady {
      var completed = false
      apnsChannel?.invokeMethod("onRemoteMessage", arguments: userInfo) { _ in
        guard !completed else { return }
        completed = true
        completionHandler(.newData)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
        guard !completed else { return }
        completed = true
        completionHandler(.newData)
      }
    } else {
      if pendingPushPayloads.count < AppDelegate.maxPendingPayloads {
        pendingPushPayloads.append(userInfo)
      }
      completionHandler(.newData)
    }
  }

  private func flushPendingPayloads() {
    for payload in pendingPushPayloads {
      apnsChannel?.invokeMethod("onRemoteMessage", arguments: payload)
    }
    pendingPushPayloads.removeAll()

    for pending in pendingNotificationActions {
      dispatchAction(action: pending.action, roomId: pending.roomId, eventId: pending.eventId, replyText: pending.replyText)
    }
    pendingNotificationActions.removeAll()
  }

  private func flushPendingVoipPayloads() {
    for payload in pendingVoipPayloads {
      voipChannel?.invokeMethod("onVoipMessage", arguments: payload)
    }
    pendingVoipPayloads.removeAll()
  }

  // ── Flutter engine ──────────────────────────────────────────

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KoheraApnsPlugin") else { return }
    let messenger = registrar.messenger()

    apnsChannel = FlutterMethodChannel(name: "kohera/apns", binaryMessenger: messenger)
    apnsChannel?.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "requestToken":
        self?.channelReady = true
        self?.flushPendingPayloads()
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .badge, .sound]
        ) { granted, error in
          DispatchQueue.main.async {
            if granted {
              UIApplication.shared.registerForRemoteNotifications()
              result(nil)
            } else {
              result(FlutterError(
                code: "PERMISSION_DENIED",
                message: error?.localizedDescription ?? "Notification permission denied",
                details: nil
              ))
            }
          }
        }
      case "unregister":
        UIApplication.shared.unregisterForRemoteNotifications()
        result(nil)
      case "clearBadge":
        UIApplication.shared.applicationIconBadgeNumber = 0
        result(nil)
      case "setBadge":
        let count = (call.arguments as? [String: Any])?["count"] as? Int ?? 0
        UIApplication.shared.applicationIconBadgeNumber = count
        result(nil)
      case "getAppGroupPath":
        let path = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: "group.io.github.quantumheart.kohera"
        )?.path
        result(path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    voipChannel = FlutterMethodChannel(name: "kohera/voip", binaryMessenger: messenger)
    voipChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "requestVoipToken":
        self.voipChannelReady = true
        self.flushPendingVoipPayloads()
        if let cached = self.cachedVoipToken {
          self.voipChannel?.invokeMethod("onVoipToken", arguments: cached)
        }
        result(nil)
      case "unregisterVoip":
        self.voipRegistry?.desiredPushTypes = []
        self.cachedVoipToken = nil
        result(nil)
      case "getCachedVoipToken":
        result(self.cachedVoipToken)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // ── PushKit delegate ────────────────────────────────────────

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP else { return }
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    cachedVoipToken = token
    voipChannel?.invokeMethod("onVoipToken", arguments: token)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    cachedVoipToken = nil
    voipChannel?.invokeMethod("onVoipTokenInvalidated", arguments: nil)
  }

  // iOS 13+ contract: every VoIP push delivered to this delegate MUST report
  // an incoming call to CallKit before `completion()` returns, or PushKit's
  // `_terminateAppIfThereAreUnhandledVoIPPushes` kills the process with SIGABRT.
  // `classifyVoipPush` therefore has no "silently drop" outcome — a push we
  // intend to ignore still maps to `.reportAndEnd`, which reports a placeholder
  // call and immediately ends it to satisfy the contract.
  enum VoipPushOutcome: Equatable {
    case showIncomingCall(
      roomId: String,
      callerName: String,
      callerAvatarUrl: String?,
      isVideo: Bool
    )
    case reportAndEnd(handle: String, reason: String)
  }

  static func classifyVoipPush(_ dict: [AnyHashable: Any]) -> VoipPushOutcome {
    let notification = (dict["notification"] as? [AnyHashable: Any]) ?? dict

    guard let roomId = notification["room_id"] as? String else {
      return .reportAndEnd(handle: "Unknown", reason: "missing room_id")
    }

    let eventType = notification["event_type"] as? String
    guard eventType == "org.matrix.msc3401.call.member" else {
      return .reportAndEnd(handle: roomId, reason: "event_type=\(eventType ?? "nil")")
    }

    guard notification["call_id"] is String else {
      return .reportAndEnd(handle: roomId, reason: "missing call_id")
    }

    let senderDisplayName = (notification["sender_display_name"] as? String) ?? "Unknown"
    let callerAvatarUrl = notification["caller_avatar_url"] as? String
    let isVideoValue = notification["is_video"]
    let isVideo: Bool = {
      if let b = isVideoValue as? Bool { return b }
      if let s = isVideoValue as? String { return s == "true" || s == "1" }
      if let n = isVideoValue as? NSNumber { return n.boolValue }
      return false
    }()

    return .showIncomingCall(
      roomId: roomId,
      callerName: senderDisplayName,
      callerAvatarUrl: callerAvatarUrl,
      isVideo: isVideo
    )
  }

  // Native CallKit provider used to satisfy the PushKit contract for pushes we
  // cannot route through the Flutter plugin (malformed payloads, or the plugin
  // not being registered yet on a cold background launch).
  private lazy var placeholderCallProvider: CXProvider = {
    let configuration = CXProviderConfiguration(localizedName: "Kohera")
    configuration.supportsVideo = true
    configuration.supportedHandleTypes = [.generic]
    return CXProvider(configuration: configuration)
  }()

  private func reportAndEndPlaceholderCall(handle: String, completion: @escaping () -> Void) {
    let uuid = UUID()
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: handle)
    update.hasVideo = false
    placeholderCallProvider.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
      // The contract is satisfied the moment the call is reported. This push is
      // not actionable, so end the call immediately to avoid stale CallKit UI.
      self?.placeholderCallProvider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
      completion()
    }
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    // iOS terminates the process if `completion` isn't invoked, so guarantee
    // it fires on every code path via a one-shot guard.
    var completed = false
    let finish: () -> Void = {
      guard !completed else { return }
      completed = true
      completion()
    }

    guard type == .voIP else {
      finish()
      return
    }

    let dict = payload.dictionaryPayload

    let roomId: String
    let senderDisplayName: String
    let callerAvatarUrl: String?
    let isVideo: Bool

    switch AppDelegate.classifyVoipPush(dict) {
    case .reportAndEnd(let handle, let reason):
      NSLog("[Kohera] VoIP push not actionable (\(reason)); reporting + ending to satisfy PushKit contract")
      reportAndEndPlaceholderCall(handle: handle) { finish() }
      return
    case .showIncomingCall(let r, let name, let avatar, let video):
      roomId = r
      senderDisplayName = name
      callerAvatarUrl = avatar
      isVideo = video
    }

    let nativeCallId = UUID().uuidString

    // Strategy (a): rely on the flutter_callkit_incoming plugin being
    // registered as part of the implicit Flutter engine boot (happens during
    // super.application(... didFinishLaunching ...) before iOS can deliver a
    // push). If sharedInstance is still nil we cannot show the full Flutter
    // CallKit UI, but we must still report a call — fall back to the native
    // CXProvider so iOS does not kill the process for an unhandled VoIP push.
    guard let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance else {
      NSLog("[Kohera] PushKit: plugin not ready; reporting via native CXProvider fallback")
      reportAndEndPlaceholderCall(handle: roomId) { finish() }
      return
    }

    let data = flutter_callkit_incoming.Data(
      id: nativeCallId,
      nameCaller: senderDisplayName,
      handle: roomId,
      type: isVideo ? 1 : 0
    )
    data.appName = "Kohera"
    data.avatar = callerAvatarUrl ?? ""
    data.supportsVideo = true
    data.duration = 60000
    data.extra = [
      "roomId": roomId,
      "withVideo": isVideo ? "true" : "false",
    ]
    plugin.showCallkitIncoming(data, fromPushKit: true) {}

    var enriched: [AnyHashable: Any] = [:]
    for (k, v) in dict { enriched[k] = v }
    enriched["nativeCallId"] = nativeCallId
    enriched["callKitAlreadyShown"] = true

    // Defer PushKit `completion()` until Dart acks (or we hit the safety
    // timeout). This prevents iOS from suspending the process while the
    // Matrix oneShotSync is still writing to sqflite — which was the cause
    // of `0xdead10cc` watchdog kills on background launch.
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
      finish()
    }

    if voipChannelReady {
      voipChannel?.invokeMethod("onVoipMessage", arguments: enriched) { _ in
        finish()
      }
    } else if pendingVoipPayloads.count < AppDelegate.maxPendingPayloads {
      pendingVoipPayloads.append(enriched)
    }
  }

  // ── CallKit ─────────────────────────────────────────────────

  func onAccept(_ call: flutter_callkit_incoming.Call, _ action: CXAnswerCallAction) {
    action.fulfill()
  }

  func onDecline(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onEnd(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: flutter_callkit_incoming.Call) {}

  func didActivateAudioSession(_ audioSession: AVAudioSession) {}

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}
}
