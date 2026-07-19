import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class IgnoredUsersScreen extends StatefulWidget {
  const IgnoredUsersScreen({super.key});

  @override
  State<IgnoredUsersScreen> createState() => _IgnoredUsersScreenState();
}

class _IgnoredUsersScreenState extends State<IgnoredUsersScreen> {
  final _displayNames = <String, String>{};
  final _loading = <String>{};

  Future<void> _loadProfile(String userId, Client client) async {
    if (_displayNames.containsKey(userId) || _loading.contains(userId)) return;
    setState(() => _loading.add(userId));
    try {
      final profile = await client.getProfileFromUserId(userId);
      if (mounted) {
        setState(() {
          _displayNames[userId] = profile.displayName ?? userId;
          _loading.remove(userId);
        });
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to load profile for $userId: $e');
      if (mounted) setState(() => _loading.remove(userId));
    }
  }

  Future<void> _unignore(String userId) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Unignore user?',
      message: 'Show messages and invites from this user again?',
      confirmLabel: 'Unignore',
    );
    if (!confirmed || !mounted) return;
    final client = context.read<MatrixService>().client;
    try {
      await client.unignoreUser(userId);
      if (mounted) {
        setState(() {
          _displayNames.remove(userId);
          _loading.remove(userId);
        });
        context.showSnack('User unignored');
      }
    } catch (e) {
      debugPrint('[Kohera] Unignore failed: $e');
      if (mounted) {
        context.showSnack('Failed to unignore: ${MatrixService.friendlyAuthError(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final client = matrix.client;
    final ignored = client.ignoredUsers;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(Routes.settings),
        ),
        title: const Text('Ignored users'),
      ),
      body: ignored.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.do_not_disturb_alt_outlined,
                        size: 48, color: cs.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      'No ignored users',
                      style: tt.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Users you ignore will appear here. Their messages and '
                      'invites are hidden across all rooms.',
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: ignored.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final userId = ignored[index];
                unawaited(_loadProfile(userId, client));
                final displayName = _displayNames[userId] ?? userId;
                return _IgnoredUserTile(
                  userId: userId,
                  displayName: displayName,
                  loading: _loading.contains(userId),
                  avatarResolver: matrix.avatarResolver,
                  onUnignore: () => _unignore(userId),
                );
              },
            ),
    );
  }
}

class _IgnoredUserTile extends StatelessWidget {
  const _IgnoredUserTile({
    required this.userId,
    required this.displayName,
    required this.loading,
    required this.avatarResolver,
    required this.onUnignore,
  });

  final String userId;
  final String displayName;
  final bool loading;
  final AvatarResolver avatarResolver;
  final VoidCallback onUnignore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: UserAvatar(
        avatarResolver: avatarResolver,
        userId: userId,
        displayname: displayName,
        size: 40,
      ),
      title: Text(displayName),
      subtitle: Text(userId, style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: onUnignore,
              child: const Text('Unignore'),
            ),
    );
  }
}
