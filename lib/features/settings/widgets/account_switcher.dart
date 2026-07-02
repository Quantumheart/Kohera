import 'package:flutter/material.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/shared/widgets/section_header.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:provider/provider.dart';

class AccountSwitcher extends StatelessWidget {
  const AccountSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ClientManager>();
    if (!manager.hasMultipleAccounts) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const SectionHeader(label: 'ACCOUNTS'),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < manager.services.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                ListTile(
                  leading: UserAvatar(
                    avatarResolver: manager.services[i].avatarResolver,
                    userId: manager.services[i].client.userID ?? '',
                    displayname: manager.services[i].client.userID ?? 'Unknown',
                    presence: manager.services[i].presence,
                    size: 36,
                  ),
                  title: Text(
                    manager.services[i].client.userID ?? 'Unknown',
                    style: i == manager.activeIndex
                        ? tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
                        : null,
                  ),
                  trailing: i == manager.activeIndex
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => manager.setActiveAccount(i),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
