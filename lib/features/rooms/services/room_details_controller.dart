import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/data/models/kohera_device_key.dart';
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/models/kohera_room_member.dart';
import 'package:kohera/data/models/kohera_room_permissions.dart';
import 'package:kohera/data/models/kohera_room_summary.dart';
import 'package:kohera/data/repositories/media_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:kohera/data/services/avatar_resolver.dart';
import 'package:kohera/features/e2ee/services/kohera_key_verification.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_dialog.dart';
import 'package:kohera/features/rooms/services/invite_user_dialog_params.dart';
import 'package:kohera/features/rooms/services/join_access_controller.dart';
import 'package:kohera/features/rooms/services/member_sheet_launcher.dart';
import 'package:kohera/features/rooms/services/shared_media_loader.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:kohera/features/rooms/widgets/shared_media_section.dart';
import 'package:matrix/encryption.dart';


/// Owns the room-details state for [RoomDetailsContent] and exposes
/// SDK-free domain models from repositories: [KoheraRoomSummary],
/// [KoheraRoomPermissions], [KoheraRoomMemberList], device keys, and
/// action callbacks.
///
/// This controller no longer imports `package:matrix/matrix.dart` — it
/// consumes domain models from [RoomRepository], [UserRepository], and
/// [MediaRepository]. The only SDK type it touches is [KeyVerification]
/// (from `package:matrix/encryption.dart`) for the E2EE verification
/// flow, obtained via [UserRepository.startDeviceVerification].
class RoomDetailsController extends ChangeNotifier {
  RoomDetailsController({
    required this.roomId,
    required this.roomRepo,
    required this.userRepo,
    required this.mediaRepo,
    required PresenceService presence,
    required SelectionService selection,
  })  : _presence = presence,
        _selection = selection;

  final String roomId;
  final RoomRepository roomRepo;
  final UserRepository userRepo;
  final MediaRepository mediaRepo;
  final PresenceService _presence;
  final SelectionService _selection;

  bool _hasRoom = false;
  StreamSubscription<void>? _syncSub;
  Timer? _syncDebounce;
  KoheraRoomMemberList? _memberList;
  bool _loadingMembers = false;
  int? _lastMemberCount;
  int _memberLoadGen = 0;
  bool _disposed = false;

  bool get hasRoom => _hasRoom;

  KoheraRoomSummary? get summary => roomRepo.summaryFor(roomId);

  KoheraRoomPermissions? get permissions => roomRepo.permissionsFor(roomId);

  KoheraRoomMemberList? get memberList => _memberList;
  bool get loadingMembers => _loadingMembers;
  int? get summaryMemberCount => roomRepo.getRoomSummaryMemberCount(roomId);
  bool get participantListComplete =>
      roomRepo.getRoomParticipantListComplete(roomId);

  /// Whether the current user has power to ban/unban in this room.
  bool get canBan => roomRepo.getRoomCanBan(roomId);

  bool get isFavourite => roomRepo.getRoomIsFavourite(roomId);
  bool get isMuted => pushRuleState != KoheraPushRuleState.notify;
  bool get encrypted => roomRepo.getRoomEncrypted(roomId);
  bool get isDirectChat => roomRepo.getRoomIsDirectChat(roomId);
  String? get partnerId => roomRepo.getRoomPartnerId(roomId);

  KoheraPushRuleState get pushRuleState =>
      roomRepo.getRoomPushRuleState(roomId);

  List<KoheraDeviceKey> get deviceKeys {
    final partner = roomRepo.getRoomPartnerId(roomId);
    if (partner == null) return const [];
    return userRepo.deviceKeysFor(partner);
  }

  AvatarResolver get avatarResolver => mediaRepo.avatarResolver;
  PresenceService get presence => _presence;

  // ── Lifecycle ───────────────────────────────────────────────

  void init() {
    _hasRoom = roomRepo.rawRoom(roomId) != null;
    if (!_hasRoom) {
      notifyListeners();
      return;
    }
    _lastMemberCount = roomRepo.getRoomSummaryMemberCount(roomId);
    unawaited(refreshDeviceKeys());
    unawaited(loadMembers());
    _syncSub = roomRepo.powerLevelChangesFor(roomId).listen((_) {
      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(seconds: 2), () {
        if (_disposed) return;
        notifyListeners();
        if (roomRepo.rawRoom(roomId) != null) {
          unawaited(loadMembers());
        }
      });
    });
  }

  /// Called by the panel on `didUpdateWidget` to detect the room appearing or
  /// a member-count change requiring a member reload.
  void checkRoomChanged() {
    final roomExists = roomRepo.rawRoom(roomId) != null;
    if (roomExists && !_hasRoom) {
      _hasRoom = true;
      _lastMemberCount = roomRepo.getRoomSummaryMemberCount(roomId);
      notifyListeners();
      unawaited(loadMembers());
      return;
    }
    final count = roomRepo.getRoomSummaryMemberCount(roomId);
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
    final current = pushRuleState;
    await roomRepo.setPushRuleState(
      roomId,
      current == KoheraPushRuleState.notify
          ? KoheraPushRuleState.dontNotify
          : KoheraPushRuleState.notify,
    );
  }

  Future<void> toggleFavourite() async {
    final target = !isFavourite;
    await roomRepo.setFavourite(roomId, target);
    await roomRepo.waitForFavourite(roomId, target);
  }

  Future<void> setPushRule(KoheraPushRuleState state) async {
    await roomRepo.setPushRuleState(roomId, state);
  }

  Future<void> invite(String mxid) async {
    await roomRepo.invite(roomId, mxid);
  }

  Future<void> setAvatar(Uint8List? bytes, String? filename) async {
    await roomRepo.setAvatar(roomId, bytes, filename);
  }

  Future<void> setName(String name) async {
    await roomRepo.setName(roomId, name);
  }

  Future<void> setDescription(String topic) async {
    await roomRepo.setDescription(roomId, topic);
  }

  Future<void> enableEncryption() async {
    await roomRepo.enableEncryption(roomId);
  }

  Future<void> leave() async {
    await roomRepo.leaveRoom(roomId);
    _selection.selectRoom(null);
  }

  Future<int?> resolveMemberCount(String id) async {
    return roomRepo.resolveMemberCount(id);
  }

  Future<void> loadMembers() async {
    if (!_hasRoom) return;
    final gen = ++_memberLoadGen;
    _loadingMembers = true;
    notifyListeners();
    try {
      final list = await roomRepo.memberListFor(roomId);
      if (_disposed || gen != _memberLoadGen) return;
      _memberList = list;
      _loadingMembers = false;
      _lastMemberCount = list?.memberCount;
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
    await userRepo.updateUserDeviceKeys();
    if (!_disposed) notifyListeners();
  }

  Future<void> verifyDevice(BuildContext context, String? deviceId) async {
    final partner = roomRepo.getRoomPartnerId(roomId);
    if (partner == null || deviceId == null) return;
    final verification = await userRepo.startDeviceVerification(
      partner,
      deviceId,
    );
    if (verification == null) return;
    if (!context.mounted) return;
    final kohera = KoheraKeyVerification(verification);
    try {
      await KeyVerificationDialog.show(context, verification: kohera);
    } finally {
      kohera.dispose();
    }
    await userRepo.updateUserDeviceKeys();
    if (!_disposed) notifyListeners();
  }

  InviteUserDialogParams inviteDialogParams() =>
      inviteUserDialogParams(roomId, roomRepo, userRepo);

  Future<void> showMemberSheet(
    BuildContext context,
    KoheraRoomMember member,
  ) =>
      showRoomMemberSheet(context, roomId: roomId, member: member);

  Future<void> unbanMember(
    BuildContext context,
    KoheraRoomMember member,
  ) async {
    await unbanRoomMember(context, roomRepo, roomId, member);
    unawaited(loadMembers());
  }

  Widget buildJoinAccessSection() => JoinAccessController(roomId: roomId);
  Widget buildSharedMediaSection() => SharedMediaSection(
        roomId: roomId,
        loader: sharedMediaLoaderForRoom(roomId, roomRepo),
        avatarResolver: mediaRepo.avatarResolver,
      );
}
