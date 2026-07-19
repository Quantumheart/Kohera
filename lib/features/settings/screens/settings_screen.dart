import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/features/calling/services/call_service.dart';
import 'package:kohera/features/settings/widgets/account_switcher.dart';
import 'package:kohera/features/settings/widgets/profile_avatar_card.dart';
import 'package:kohera/shared/widgets/kohera_mark.dart';
import 'package:kohera/shared/widgets/section_header.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _lastShownError;
  StreamSubscription<SyncUpdate>? _syncSub;
  int _ignoredCount = 0;

  @override
  void initState() {
    super.initState();
    final client = context.read<MatrixService>().client;
    _ignoredCount = client.ignoredUsers.length;
    _syncSub = client.onSync.stream.listen((_) {
      if (!mounted) return;
      final count = client.ignoredUsers.length;
      if (count != _ignoredCount) {
        setState(() => _ignoredCount = count);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    context.watch<ChatBackupService>();
    final manager = context.watch<ClientManager>();
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;

    // Surface backup errors via SnackBar.
    final error = matrix.chatBackup.chatBackupError;
    if (error != null && error != _lastShownError) {
      _lastShownError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.showSnack(error);
      });
    } else if (error == null) {
      _lastShownError = null;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(Routes.home),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ProfileAvatarCard(),

          const AccountSwitcher(),

          const SizedBox(height: 16),

          // ── Add Account ──
          OutlinedButton.icon(
            onPressed: () => _addAccount(context, manager),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Add account'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Preferences ──
          const SectionHeader(label: 'PREFERENCES'),
          Card(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: prefs.themeModeLabel,
                  onTap: () => context.pushOrGo(Routes.settingsAppearance),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: prefs.notificationLevelLabel,
                  onTap: () => context.pushOrGo(Routes.settingsNotifications),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.emoji_emotions_outlined,
                  title: 'Sticker & emoji packs',
                  subtitle: context.select<StickerPackService, String>(
                    (s) {
                      final count = s.accountPacks.length;
                      return count == 0
                          ? 'No packs added'
                          : '$count pack${count == 1 ? '' : 's'} active';
                    },
                  ),
                  onTap: () => context.pushOrGo(Routes.settingsStickerPacks),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.link_rounded),
                  title: const Text('Link previews'),
                  subtitle:
                      const Text('Show previews for URLs in messages'),
                  value: prefs.showLinkPreviews,
                  onChanged: prefs.setShowLinkPreviews,
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.keyboard_rounded),
                  title: const Text('Typing indicators'),
                  subtitle:
                      const Text('Send and show typing notifications'),
                  value: prefs.typingIndicators,
                  onChanged: prefs.setTypingIndicators,
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.done_all_rounded),
                  title: const Text('Read receipts'),
                  subtitle:
                      const Text('Send and show read receipts'),
                  value: prefs.readReceipts,
                  onChanged: prefs.setReadReceipts,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Calling ──
          const SectionHeader(label: 'CALLING'),
          Card(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.call_rounded,
                  title: 'Voice & video',
                  subtitle: context.select<CallService, bool>(
                            (s) => s.isCallingAvailable,
                          )
                      ? 'Supported by your homeserver'
                      : 'Not supported by your homeserver',
                  onTap: () => context.goNamed(Routes.settingsVoiceVideo),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Security ──
          const SectionHeader(label: 'SECURITY'),
          Card(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.cloud_outlined,
                  title: 'Chat backup',
                  subtitle: matrix.chatBackup.chatBackupLoading
                      ? 'Setting up…'
                      : matrix.chatBackup.chatBackupNeeded == null
                          ? 'Checking...'
                          : matrix.chatBackup.chatBackupEnabled
                              ? 'Your keys are backed up'
                              : 'Not set up',
                  onTap: matrix.chatBackup.chatBackupLoading
                      ? () {}
                      : () => context.go(RoutePaths.e2eeSetup),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.devices_rounded,
                  title: 'Devices',
                  subtitle: 'Manage your devices',
                  onTap: () => context.pushOrGo(Routes.settingsDevices),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.do_not_disturb_alt_outlined,
                  title: 'Ignored users',
                  subtitle: _ignoredUsersLabel(_ignoredCount),
                  onTap: () => context.goNamed(Routes.settingsIgnoredUsers),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── About ──
          const SectionHeader(label: 'ABOUT'),
          Card(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  leading: const KoheraMark(size: 24),
                  title: 'Kohera',
                  subtitle: prefs.currentVersion != null
                      ? "v${prefs.currentVersion} · What's new"
                      : "What's new",
                  onTap: () => context.pushNamed(Routes.whatsNew),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(56, 4, 16, 12),
                  child: Text(
                    'Kohera is a retro-pixel Matrix client. The mark — a pixel '
                    'mushroom above a mycelial root network — stands for the '
                    'coherent threads of a decentralized chat network: the '
                    'visible conversation and the hidden web that carries it.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.code_rounded,
                  title: 'Source code',
                  subtitle: 'View on GitHub',
                  onTap: () {
                    unawaited(launchUrl(Uri.parse('https://github.com/Quantumheart/Kohera')));
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Logout ──
          FilledButton.tonal(
            onPressed: () => _confirmLogout(context),
            style: FilledButton.styleFrom(
              backgroundColor: cs.errorContainer,
              foregroundColor: cs.onErrorContainer,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
              ),
            ),
            child: const Text('Sign Out'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _addAccount(BuildContext context, ClientManager manager) async {
    await manager.createLoginService();
    if (context.mounted) context.go(RoutePaths.addAccount);
  }

  void _confirmLogout(BuildContext context) {
    final matrix = context.read<MatrixService>();
    final manager = context.read<ClientManager>();
    final backupMissing = !matrix.chatBackup.chatBackupEnabled;

    unawaited(showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (backupMissing) ...[
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Theme.of(ctx).colorScheme.error,),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your encryption keys are not backed up. You will '
                      'permanently lose access to your encrypted messages.',
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'You will need to sign in again to access your messages.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (backupMissing)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go(RoutePaths.e2eeSetup);
              },
              child: const Text('Set up backup first'),
            ),
          FilledButton(
            style: backupMissing
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  )
                : null,
            onPressed: () async {
              Navigator.pop(ctx);
              await manager.signOut(matrix);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    ),);
  }

}

String _ignoredUsersLabel(int count) {
  if (count == 0) return 'None';
  return '$count user${count == 1 ? '' : 's'}';
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: leading ?? Icon(icon, color: cs.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
    );
  }
}
