import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/core/services/client_avatar_resolver.dart';
import 'package:kohera/core/services/client_media_resolver.dart';
import 'package:kohera/core/services/secure_storage.dart';
import 'package:kohera/core/services/sub_services/auth_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';

import 'package:kohera/core/services/sub_services/sync_service.dart';
import 'package:kohera/core/services/sub_services/uia_service.dart';
import 'package:kohera/core/state/selection_controller.dart';
import 'package:kohera/data/repositories/key_backup_repository.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/repositories/outbox_repository.dart';
import 'package:kohera/data/repositories/push_rule_repository.dart';
import 'package:kohera/data/repositories/space_tree_repository.dart';
import 'package:kohera/data/repositories/sticker_pack_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
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
  late final SpaceTreeRepository spaceTree;
  late final SelectionController selectionController;
  late final PresenceService presence;
  late final SyncService sync;
  late final AuthService auth;
  late final AvatarResolver avatarResolver;
  late final MediaResolver mediaResolver;
  late final MessageRepository messageRepository;
  late final KeyBackupRepository keyBackupRepository;
  late final UserRepository userRepository;
  late final OutboxRepository outboxRepository;
  late final PushRuleRepository pushRuleRepository;
  late final StickerPackRepository stickerPackRepository;

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
    spaceTree = SpaceTreeRepository(clientService: matrixClientService);
    selectionController =
        SelectionController(clientService: matrixClientService);
    presence = PresenceService(matrixClientService: matrixClientService);
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
    userRepository = UserRepository(
      clientService: _matrixClientService,
      presenceOverride: presence,
    );
    outboxRepository = OutboxRepository(
      clientService: _matrixClientService,
      clientName: clientName,
    );
    pushRuleRepository = PushRuleRepository(
      clientService: _matrixClientService,
    );
    stickerPackRepository = StickerPackRepository(
      clientService: _matrixClientService,
    );
  }

  void dispose() {
    _disposed = true;
    messageRepository.dispose();
    keyBackupRepository.dispose();
    userRepository.dispose();
    outboxRepository.dispose();
    uia.dispose();
    spaceTree.dispose();
    selectionController.dispose();
    presence.dispose();
    chatBackup.dispose();
    sync.dispose();
    stickerPackRepository.dispose();
  }
}

class AccountSessionConstants {
  static const String dbName = 'KoheraEncryptedStorage';
  static const String publicKey = 'KoheraSecureStorage';
}

class AppConstants {
  static const String groupId = 'group.io.github.quantumheart.kohera';
}
