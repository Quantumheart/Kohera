import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/brand/brand_constants.dart';
import 'package:kohera/core/routing/active_matrix_listenable.dart';
import 'package:kohera/core/routing/app_router.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/deep_link_service.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/core/services/sub_services/outbox_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/web_shell_sync.dart';
import 'package:kohera/core/theme/kohera_theme.dart';
import 'package:kohera/core/theme/theme_presets.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/core/utils/vodozemac_init.dart';
import 'package:kohera/data/repositories/auth_repository.dart';
import 'package:kohera/data/repositories/key_backup_repository.dart';
import 'package:kohera/data/repositories/media_repository.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/repositories/message_search_repository.dart';
import 'package:kohera/data/repositories/outbox_repository.dart';
import 'package:kohera/data/repositories/push_rule_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/space_repository.dart';
import 'package:kohera/data/repositories/sticker_pack_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:kohera/features/auth/services/sso_web_init.dart';
import 'package:kohera/features/calling/services/call_service.dart';
import 'package:kohera/features/calling/services/push_to_talk_service.dart';
import 'package:kohera/features/calling/services/ringtone_service.dart';
import 'package:kohera/features/calling/widgets/incoming_call_overlay.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:kohera/features/chat/services/opengraph_service.dart';
import 'package:kohera/features/e2ee/widgets/verification_request_listener.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';
import 'package:kohera/features/notifications/widgets/notification_lifecycle_observer.dart';
import 'package:kohera/features/share_in/services/avatar_cache_service.dart';
import 'package:kohera/features/share_in/services/room_snapshot_service.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';
import 'package:kohera/features/share_in/services/share_intake_controller.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:kohera/shared/widgets/pixelation_scope.dart';
import 'package:kohera/shared/widgets/scanline_overlay.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KoheraApp());
}

class KoheraApp extends StatefulWidget {
  const KoheraApp({super.key});

  @override
  State<KoheraApp> createState() => _KoheraAppState();
}

class _KoheraAppState extends State<KoheraApp> {
  ClientManager? _clientManager;
  PreferencesService? _preferencesService;
  GoRouter? _router;
  Object? _initError;
  MatrixService? _displayedService;
  ThemeData? _splashLight;
  ThemeData? _splashDark;
  final _ringtoneService = RingtoneService();
  RoomSnapshotService? _roomSnapshotService;
  AvatarCacheService? _avatarCacheService;
ShareIntakeController? _shareIntake;
  DeepLinkService? _deepLinkService;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<String?> _getAppGroupPath() async {
    try {
      return await const MethodChannel('kohera/apns')
          .invokeMethod<String>('getAppGroupPath');
    } on PlatformException catch (e) {
      debugPrint('[Kohera] App Group path lookup failed: $e');
      return null;
    }
  }

  void _bindShareIn(MatrixService service) {
    _roomSnapshotService?.dispose();
    _shareIntake?.dispose();
    unawaited(_avatarCacheService?.dispose());
    _avatarCacheService = AvatarCacheService(
      mediaResolver: service.mediaResolver,
      getAppGroupPath: _getAppGroupPath,
    );
    _roomSnapshotService = RoomSnapshotService(
      client: service.client,
      sink: ShareInStore(),
      avatarCache: _avatarCacheService,
    )..start();
    unawaited(ShareInStore().writeActiveAccountId(service.clientName));
  }

  Future<void> _init() async {
    // Keep the branded splash up long enough for its growth animation to play.
    final minSplash = Future<void>.delayed(const Duration(seconds: 3));
    try {
      if (isNativeDesktop) MediaKit.ensureInitialized();

      final prefs = PreferencesService();
      await prefs.init();
      if (!mounted) return;
      _applySplashTheme(prefs);

      await Future.wait([initVodozemac(), AppConfig.load()]);

      final clientManager = ClientManager();
      await clientManager.init();

      final pendingSso = await checkPendingSsoLogin();
      if (pendingSso != null) {
        await clientManager.activeService.completeSsoLogin(
          homeserver: pendingSso.homeserver,
          loginToken: pendingSso.loginToken,
        );
      }

      await minSplash;
      if (!mounted) return;
      clientManager.addListener(_onActiveServiceChanged);
      final refreshListenable = ActiveMatrixListenable(clientManager);
      setState(() {
        _clientManager = clientManager;
        _preferencesService = prefs;
        _displayedService = clientManager.activeService;
        _router = buildRouter(
          clientManager,
          refreshListenable: refreshListenable,
        );
      });
      _bindShareIn(clientManager.activeService);
      _shareIntake = ShareIntakeController(
        clientManager: clientManager,
        router: _router!,
      )..start();
      // Start deep-link listener now that the router exists. The shared
      // refreshListenable lets queued links replay once login / E2EE setup
      // completes instead of being dropped by the router redirect.
      _deepLinkService = DeepLinkService(
        router: _router!,
        clientManager: clientManager,
        refreshListenable: refreshListenable,
      )..init();
      unawaited(_deepLinkService!.processInitialLink());
    } catch (e) {
      debugPrint('[Kohera] Initialization failed: $e');
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  void _applySplashTheme(PreferencesService prefs) {
    final isCustom = prefs.themePreset == 'custom';
    final preset = isCustom ? null : getPreset(prefs.themePreset);
    final customScheme = isCustom ? prefs.customTheme : null;
    setState(() {
      _splashLight = customScheme != null
          ? KoheraTheme.light(
              dynamic: customScheme.toColorScheme(Brightness.light),
              palette: customScheme.toKoheraPalette(Brightness.light),
            )
          : KoheraTheme.light(preset: preset);
      _splashDark = customScheme != null
          ? KoheraTheme.dark(
              dynamic: customScheme.toColorScheme(Brightness.dark),
              palette: customScheme.toKoheraPalette(Brightness.dark),
            )
          : KoheraTheme.dark(preset: preset);
    });
  }

  void _onActiveServiceChanged() {
    final manager = _clientManager;
    if (manager == null) return;
    if (identical(manager.activeService, _displayedService)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _clientManager?.activeService;
      if (current == null || identical(current, _displayedService)) return;
      _bindShareIn(current);
      setState(() => _displayedService = current);
    });
  }

  @override
  void dispose() {
    _clientManager?.removeListener(_onActiveServiceChanged);
    _router?.dispose();
    _deepLinkService?.dispose();
    _roomSnapshotService?.dispose();
    unawaited(_avatarCacheService?.dispose());
    unawaited(_ringtoneService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clientManager = _clientManager;
    if (clientManager == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _splashLight ??
            ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: BrandConstants.brandColor,
              ),
            ),
        darkTheme: _splashDark ??
            ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: BrandConstants.brandColor,
                brightness: Brightness.dark,
              ),
            ),
        home: Scaffold(
          body: Center(
            child: _initError != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to start Kohera',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _initError.toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                      if (_initError.toString().toLowerCase().contains('indexeddb') ||
                          _initError.toString().toLowerCase().contains('database'))
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text(
                            'This may be caused by your browser blocking\nIndexedDB (e.g. Private Browsing).',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          setState(() => _initError = null);
                          unawaited(_init());
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  )
                // Loader defaults to colorScheme.primary; the splash theme is
                // seeded by the brand color so it renders brand-blue before the
                // Kohera theme (prefs) is loaded.
                : const KoheraLoader(size: 96),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClientManager>.value(
          value: clientManager,
        ),
        ChangeNotifierProvider<PreferencesService>.value(
          value: _preferencesService!,
        ),
        ChangeNotifierProvider(create: (_) => MediaPlaybackService()),
        Provider(
          create: (_) => GitHubReleasesService(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return Consumer2<ClientManager, PreferencesService>(
            builder: (context, manager, prefs, _) {
              final matrix = _displayedService ?? manager.activeService;
              final router = _router!;

              return MultiProvider(
                providers: [
                  ChangeNotifierProvider<MatrixService>.value(
                    value: matrix,
                  ),
                  Provider<OpenGraphService>(
                    create: (ctx) => OpenGraphService(
                      matrixClient: ctx.read<MatrixService>().client,
                    ),
                    dispose: (_, service) => service.dispose(),
                  ),
                  ChangeNotifierProvider<SelectionService>.value(
                    value: matrix.selection,
                  ),
                  Provider<SpaceDiscoveryDataSource>(
                    create: (cxt) =>
                        LiveSpaceDiscoveryDataSource(matrix.client),
                  ),
                  ChangeNotifierProvider<SpaceRoomsController>(
                    create: (ctx) {
                      final controller = SpaceRoomsController(
                        dataSource: ctx.read<SpaceDiscoveryDataSource>(),
                        client: matrix.client,
                      );
                      controller.listenToSync();
                      return controller;
                    },
                  ),
                  ChangeNotifierProvider<ChatBackupService>.value(
                    value: matrix.chatBackup,
                  ),
                  ChangeNotifierProvider<OutboxService>.value(
                    value: matrix.outbox,
                  ),
                  ChangeNotifierProvider<StickerPackService>.value(
                    value: matrix.stickerPacks,
                  ),
                  ChangeNotifierProxyProvider<MatrixService, InboxController>(
                    create: (ctx) => InboxController(
                      client: ctx.read<MatrixService>().client,
                    ),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return InboxController(client: matrix.client);
                      }
                      previous.updateClient(matrix.client);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, CallService>(
                    create: (ctx) {
                      final cs = CallService(
                        client: ctx.read<MatrixService>().client,
                        ringtoneService: _ringtoneService,
                      )..preferencesService = prefs;
                      if (ctx.read<MatrixService>().isLoggedIn) cs.init();
                      return cs;
                    },
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        final cs = CallService(
                          client: matrix.client,
                          ringtoneService: _ringtoneService,
                        )..preferencesService = prefs;
                        if (matrix.isLoggedIn) cs.init();
                        return cs;
                      }
                      previous
                        ..updateClient(matrix.client)
                        ..preferencesService = prefs;
                      if (matrix.isLoggedIn) {
                        previous.init();
                      }
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, RoomRepository>(
                    create: (ctx) =>
                        RoomRepository(matrix: ctx.read<MatrixService>()),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return RoomRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, UserRepository>(
                    create: (ctx) =>
                        UserRepository(matrix: ctx.read<MatrixService>()),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return UserRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, MessageRepository>(
                    create: (ctx) =>
                        MessageRepository(matrix: ctx.read<MatrixService>()),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return MessageRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, AuthRepository>(
                    create: (ctx) =>
                        AuthRepository(matrix: ctx.read<MatrixService>()),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return AuthRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, KeyBackupRepository>(
                    create: (ctx) =>
                        KeyBackupRepository(matrix: ctx.read<MatrixService>()),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return KeyBackupRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, MediaRepository>(
                    create: (ctx) =>
                        MediaRepository(matrix: ctx.read<MatrixService>()),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return MediaRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, SpaceRepository>(
                    create: (ctx) =>
                        SpaceRepository(matrix: ctx.read<MatrixService>()),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return SpaceRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, OutboxRepository>(
                    create: (ctx) =>
                        OutboxRepository(matrix: ctx.read<MatrixService>()),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return OutboxRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, PushRuleRepository>(
                    create: (ctx) =>
                        PushRuleRepository(matrix: ctx.read<MatrixService>()),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return PushRuleRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, StickerPackRepository>(
                    create: (ctx) => StickerPackRepository(
                      matrix: ctx.read<MatrixService>(),
                    ),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return StickerPackRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                  ChangeNotifierProxyProvider<MatrixService, MessageSearchRepository>(
                    create: (ctx) => MessageSearchRepository(
                      matrix: ctx.read<MatrixService>(),
                    ),
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        return MessageSearchRepository(matrix: matrix);
                      }
                      previous.updateMatrixService(matrix);
                      return previous;
                    },
                  ),
                ],
                child: ChangeNotifierProvider(
                  create: (ctx) => PushToTalkService(
                    callService: ctx.read<CallService>(),
                    prefs: prefs,
                    ringtoneService: _ringtoneService,
                  ),
                  child: Builder(
                    builder: (context) {
                      final callService = context.read<CallService>();
                      final isCustom = prefs.themePreset == 'custom';
                      final preset =
                          isCustom ? null : getPreset(prefs.themePreset);
                      final customScheme = isCustom ? prefs.customTheme : null;

                      final theme = customScheme != null
                          ? KoheraTheme.light(
                              dynamic: customScheme.toColorScheme(
                                Brightness.light,
                              ),
                              palette: customScheme.toKoheraPalette(
                                Brightness.light,
                              ),
                            )
                          : KoheraTheme.light(
                              dynamic: lightDynamic,
                              preset: preset,
                            );
                      final darkTheme = customScheme != null
                          ? KoheraTheme.dark(
                              dynamic: customScheme.toColorScheme(
                                Brightness.dark,
                              ),
                              palette: customScheme.toKoheraPalette(
                                Brightness.dark,
                              ),
                            )
                          : KoheraTheme.dark(
                              dynamic: darkDynamic,
                              preset: preset,
                            );

                      final themeMode = isCustom
                          ? prefs.customThemeMode
                          : (preset?.forcedMode ?? prefs.themeMode);

                      return NotificationLifecycleObserver(
                        matrixService: matrix,
                        preferencesService: prefs,
                        callService: callService,
                        router: router,
                        child: MaterialApp.router(
                          title: BrandConstants.appName,
                          debugShowCheckedModeBanner: false,
                          theme: theme,
                          darkTheme: darkTheme,
                          themeMode: themeMode,
                          routerConfig: router,
                          builder: (context, child) {
                            final theme = Theme.of(context);
                            final isDark = theme.brightness == Brightness.dark;
                            setWebShellAccent(theme.colorScheme.primary);
                            final mq = MediaQuery.of(context);
                            final webBottom = webSafeAreaInsets().bottom;
                            final effectiveWebBottom =
                                mq.viewInsets.bottom > 0 ? 0.0 : webBottom;
                            final paddedMq = effectiveWebBottom > 0
                                ? mq.copyWith(
                                    padding: mq.padding.copyWith(
                                      bottom:
                                          mq.padding.bottom >
                                                  effectiveWebBottom
                                              ? mq.padding.bottom
                                              : effectiveWebBottom,
                                    ),
                                  )
                                : mq;
                            return MediaQuery(
                              data: paddedMq,
                              child: AnnotatedRegion<SystemUiOverlayStyle>(
                              value: SystemUiOverlayStyle(
                                statusBarColor: Colors.transparent,
                                statusBarIconBrightness:
                                    isDark ? Brightness.light : Brightness.dark,
                                statusBarBrightness:
                                    isDark ? Brightness.light : Brightness.dark,
                                systemNavigationBarColor:
                                    theme.colorScheme.surface,
                                systemNavigationBarIconBrightness:
                                    isDark ? Brightness.light : Brightness.dark,
                              ),
                              child: ScanlineOverlay(
                                enabled: prefs.scanlinesEnabled,
                                child: PixelationScope(
                                  enabled: prefs.pixelateGraphics,
                                  child: VerificationRequestListener(
                                    router: router,
                                    child: IncomingCallOverlay(
                                      router: router,
                                      child: child ?? const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                          },
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
