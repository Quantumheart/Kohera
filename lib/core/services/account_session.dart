import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/core/services/client_avatar_resolver.dart';
import 'package:kohera/core/services/client_media_resolver.dart';
import 'package:kohera/core/services/secure_storage.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/core/services/sub_services/auth_service.dart';
import 'package:kohera/core/services/sub_services/call_push_rule_manager.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/core/services/sub_services/global_push_rule_manager.dart';
import 'package:kohera/core/services/sub_services/outbox_connectivity.dart';
import 'package:kohera/core/services/sub_services/outbox_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/core/services/sub_services/sync_service.dart';
import 'package:kohera/core/services/sub_services/uia_service.dart';
import 'package:kohera/data/repositories/key_backup_repository.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/services/avatar_resolver.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/media_resolver.dart';
import 'package:matrix/matrix.dart';

/// Per-account composition root. Builds the sub-service graph in dependency
/// order and owns its disposal. One [AccountSession] exists per account;
/// [ClientManager] holds N of them and [MatrixService] coordinates one.
class AccountSession {
  final MatrixClientService _matrixClientService;
  final FlutterSecureStorage _flutterSecureStorage;

  MatrixClientService get matrixClientService => _matrixClientService;
  Client get client => _matrixClientService.client;
  String? get userID => _matrixClientService.client.userID;

  late final UiaService uia;
  late final ChatBackupService chatBackup;
  late final SelectionService selection;
  late final PresenceService presence;
  late final SpaceAccessService spaceAccess;
  late final SyncService sync;
  late final AuthService auth;
  late final OutboxService outbox;
  late final AvatarResolver avatarResolver;
  late final MediaResolver mediaResolver;
  late final StickerPackService stickerPacks;
  late final CallPushRuleManager callPushRuleManager;
  late final GlobalPushRuleManager globalPushRuleManager;

  late final MessageRepository messageRepository;
  late final KeyBackupRepository keyBackupRepository;

  final String clientName;

  bool _disposed = false;
  bool get disposed => _disposed;

  AccountSession({
    required MatrixClientService matrixClientService,
    FlutterSecureStorage? storage,
    this.clientName = 'default',
  }) : _matrixClientService = matrixClientService,
       _flutterSecureStorage =
           storage ??
           KoheraSecureStorage(
             iOptions: const IOSOptions(
               groupId: AppConstants.groupId,
               accessibility: KeychainAccessibility.first_unlock,
             ),
             webOptions: const WebOptions(
               dbName: AccountSessionConstants.dbName,
               publicKey: AccountSessionConstants.publicKey,
             ),
           ) {
    uia = UiaService(matrixClientService: _matrixClientService);
    chatBackup = ChatBackupService(
      matrixClientService: _matrixClientService,
      storage: _flutterSecureStorage,
    );
    selection = SelectionService(matrixClientService: matrixClientService);
    presence = PresenceService(matrixClientService: matrixClientService);
    spaceAccess = SpaceAccessService(matrixClientService: matrixClientService);
    sync = SyncService(
      matrixClientService: matrixClientService,
      onPostSyncBackup: () async {
        await chatBackup.tryAutoUnlockBackup();
      },
      shouldRetryBackup: () => chatBackup.chatBackupNeeded != false,
    );
    auth = AuthService(
      matrixClientService: matrixClientService,
      storage: _flutterSecureStorage,
      clientName: clientName,
      sync: sync,
      presence: presence,
      uia: uia,
      chatBackup: chatBackup,
    );
    callPushRuleManager = CallPushRuleManager(
      matrixClientService: matrixClientService,
    );
    globalPushRuleManager = GlobalPushRuleManager(
      matrixClientService: matrixClientService,
    );
    outbox = OutboxService(
      matrixClientService: _matrixClientService,
      clientName: clientName,
      connectivity: RealOutboxConnectivity(),
    );
    stickerPacks = StickerPackService(
      matrixClientService: _matrixClientService,
    );
    avatarResolver = ClientAvatarResolver(_matrixClientService);
    mediaResolver = ClientMediaResolver(_matrixClientService);
    messageRepository = MessageRepository(
      clientService: _matrixClientService,
      clientName: clientName,
    );
    keyBackupRepository = KeyBackupRepository(
      clientService: _matrixClientService,
      clientName: clientName,
      chatBackup: chatBackup,
      uia: uia,
    );
  }

  void dispose() {
    _disposed = true;
    messageRepository.dispose();
    keyBackupRepository.dispose();
    outbox.dispose();
    uia.dispose();
    selection.dispose();
    presence.dispose();
    chatBackup.dispose();
    sync.dispose();
    stickerPacks.dispose();
  }
}

class AccountSessionConstants {
  static const String dbName = 'KoheraEncryptedStorage';
  static const String publicKey = 'KoheraSecureStorage';
}

class AppConstants {
  static const String groupId = 'group.io.github.quantumheart.kohera';
}
