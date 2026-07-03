import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kohera/core/models/kohera_push_rule_state.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_dialog.dart';
import 'package:kohera/features/rooms/models/kohera_device_key.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/features/rooms/models/kohera_room_permissions.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/features/rooms/services/room_member_list_resolver.dart';
import 'package:kohera/features/rooms/services/room_permissions_resolver.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog_params.dart';
import 'package:kohera/features/rooms/widgets/join_access_controller.dart';
import 'package:kohera/features/rooms/widgets/member_sheet_launcher.dart';
import 'package:kohera/features/rooms/widgets/shared_media_section.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:matrix/matrix.dart';

/// Owns the SDK `Room` for [RoomDetailsPanel] and exposes everything the
/// SDK-free panel needs: display models ([KoheraRoomSummary],
/// [KoheraRoomPermissions], [KoheraRoomMemberList]), action callbacks, device
/// verification, and the Room-typed child widgets ([JoinAccessController],
/// [SharedMediaSection], member sheet).
///
/// This is the conversion boundary for slice #708: it is the only place in
/// the room-details feature that imports `package:matrix/matrix.dart`.
class RoomDetailsController extends ChangeNotifier {
  RoomDetailsController({
    required this.roomId,
    required this.matrix,
    required this.selection,
  });

  final String roomId;
  final MatrixService matrix;
  final SelectionService selection;

  Room? _room;
  StreamSubscription<SyncUpdate>? _syncSub;
  Timer? _syncDebounce;
  KoheraRoomMemberList? _memberList;
  bool _loadingMembers = false;
  int? _lastMemberCount;
  int _memberLoadGen = 0;
  bool _disposed = false;

  bool get hasRoom => _room != null;

  KoheraRoomSummary? get summary =>
      _room == null ? null : selection.summaryFor(_room!);

  KoheraRoomPermissions? get permissions => _room == null
      ? null
      : const RoomPermissionsResolver()
          .convert(_room!, myUserId: matrix.client.userID ?? '');

  KoheraRoomMemberList? get memberList => _memberList;
  bool get loadingMembers => _loadingMembers;
  int? get summaryMemberCount => _room?.summary.mJoinedMemberCount;
  bool get participantListComplete => _room?.participantListComplete ?? false;

  bool get isFavourite => _room?.isFavourite ?? false;
  bool get isMuted => pushRuleState != KoheraPushRuleState.notify;
  bool get encrypted => _room?.encrypted ?? false;
  bool get isDirectChat => _room?.isDirectChat ?? false;
  String? get partnerId => _room?.directChatMatrixID;

  KoheraPushRuleState get pushRuleState =>
      _toKohera(_room?.pushRuleState ?? PushRuleState.notify);

  List<KoheraDeviceKey> get deviceKeys {
    final partner = _room?.directChatMatrixID;
    if (partner == null) return const [];
    final list = matrix.client.userDeviceKeys[partner];
    final devices = list?.deviceKeys.values.toList() ?? [];
    return devices
        .map(
          (dk) => KoheraDeviceKey(
            deviceId: dk.deviceId,
            displayName: dk.deviceDisplayName,
            verified: dk.verified,
            blocked: dk.blocked,
          ),
        )
        .toList();
  }

  AvatarResolver get avatarResolver => matrix.avatarResolver;
  PresenceService get presence => matrix.presence;

  // ── Lifecycle ───────────────────────────────────────────────

  void init() {
    _room = matrix.client.getRoomById(roomId);
    if (_room == null) {
      notifyListeners();
      return;
    }
    _lastMemberCount = _room!.summary.mJoinedMemberCount;
    unawaited(refreshDeviceKeys());
    unawaited(loadMembers());
    _syncSub = matrix.client.onSync.stream.listen((update) {
      final stateEvents = update.rooms?.join?[roomId]?.state ?? [];
      final hasPowerLevelChanges =
          stateEvents.any((e) => e.type == EventTypes.RoomPowerLevels);
      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(seconds: 2), () {
        if (_disposed) return;
        notifyListeners();
        if (hasPowerLevelChanges) {
          final room = matrix.client.getRoomById(roomId);
          if (room != null) unawaited(loadMembers());
        }
      });
    });
  }

  /// Called by the panel on `didUpdateWidget` to detect the room appearing or
  /// a member-count change requiring a member reload.
  void checkRoomChanged() {
    final room = matrix.client.getRoomById(roomId);
    if (room != null && _room == null) {
      _room = room;
      _lastMemberCount = room.summary.mJoinedMemberCount;
      notifyListeners();
      unawaited(loadMembers());
      return;
    }
    final count = room?.summary.mJoinedMemberCount;
    if (count != null && count != _lastMemberCount && !_loadingMembers) {
      unawaited(loadMembers());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _syncDebounce?.cancel();
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────

  Future<void> toggleMute() async {
    final room = _room!;
    final current = room.pushRuleState;
    await room.setPushRuleState(
      current == PushRuleState.notify
          ? PushRuleState.dontNotify
          : PushRuleState.notify,
    );
  }

  Future<void> toggleFavourite() async {
    final room = _room!;
    final target = !room.isFavourite;
    await room.setFavourite(target);
    await room.client.onSync.stream
        .firstWhere((_) => room.isFavourite == target)
        .timeout(
      const Duration(seconds: 5),
      onTimeout: () => SyncUpdate(nextBatch: ''),
    );
  }

  Future<void> setPushRule(KoheraPushRuleState state) async {
    await _room!.setPushRuleState(_fromKohera(state));
  }

  Future<void> invite(String mxid) async {
    await _room!.invite(mxid);
  }

  Future<void> setAvatar(Uint8List? bytes, String? filename) async {
    await _room!.setAvatar(
      bytes == null ? null : MatrixFile(bytes: bytes, name: filename ?? ''),
    );
  }

  Future<void> setName(String name) async {
    await _room!.setName(name);
  }

  Future<void> setDescription(String topic) async {
    await _room!.setDescription(topic);
  }

  Future<void> enableEncryption() async {
    await _room!.enableEncryption();
  }

  Future<void> leave() async {
    await _room!.leave();
    selection.selectRoom(null);
  }

  Future<int?> resolveMemberCount(String id) async {
    final r = matrix.client.getRoomById(id);
    if (r == null) return null;
    final members = await matrix.client.getJoinedMembersByRoom(id);
    return members?.length;
  }

  Future<void> loadMembers() async {
    final room = _room;
    if (room == null) return;
    final gen = ++_memberLoadGen;
    _loadingMembers = true;
    notifyListeners();
    try {
      final list = await const RoomMemberListResolver().resolve(room);
      if (_disposed || gen != _memberLoadGen) return;
      _memberList = list;
      _loadingMembers = false;
      _lastMemberCount = list.memberCount;
      notifyListeners();
    } catch (e) {
      debugPrint('[Kohera] Failed to load members: $e');
      if (!_disposed) {
        _loadingMembers = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshDeviceKeys() async {
    await matrix.client.updateUserDeviceKeys();
    if (!_disposed) notifyListeners();
  }

  Future<void> verifyDevice(BuildContext context, String? deviceId) async {
    final partner = _room?.directChatMatrixID;
    if (partner == null || deviceId == null) return;
    final dkList = matrix.client.userDeviceKeys[partner];
    final dk = dkList?.deviceKeys[deviceId];
    if (dk == null) return;
    final verification = await dk.startVerification();
    if (!context.mounted) return;
    await KeyVerificationDialog.show(context, verification: verification);
    await matrix.client.updateUserDeviceKeys();
    if (!_disposed) notifyListeners();
  }

  InviteUserDialogParams inviteDialogParams() => inviteUserDialogParams(_room!);

  Future<void> showMemberSheet(
    BuildContext context,
    KoheraRoomMember member,
  ) =>
      showRoomMemberSheet(context, room: _room!, member: member);

  Widget buildJoinAccessSection() => JoinAccessController(room: _room!);
  Widget buildSharedMediaSection() => SharedMediaSection(room: _room!);

  // ── Push rule mapping ──────────────────────────────────────

  static KoheraPushRuleState _toKohera(PushRuleState s) => switch (s) {
        PushRuleState.notify => KoheraPushRuleState.notify,
        PushRuleState.mentionsOnly => KoheraPushRuleState.mentionsOnly,
        PushRuleState.dontNotify => KoheraPushRuleState.dontNotify,
      };

  static PushRuleState _fromKohera(KoheraPushRuleState s) => switch (s) {
        KoheraPushRuleState.notify => PushRuleState.notify,
        KoheraPushRuleState.mentionsOnly => PushRuleState.mentionsOnly,
        KoheraPushRuleState.dontNotify => PushRuleState.dontNotify,
      };
}
