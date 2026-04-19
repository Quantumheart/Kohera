import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/home/widgets/inbox_screen.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';
import 'package:kohera/features/rooms/widgets/room_list.dart';
import 'package:kohera/features/settings/screens/settings_screen.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

class NarrowLayout extends StatefulWidget {
  const NarrowLayout({
    required this.routerChild,
    required this.routeName,
    required this.roomId,
    super.key,
  });

  final Widget routerChild;
  final String? routeName;
  final String? roomId;

  @override
  State<NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends State<NarrowLayout> {
  bool _initialTabApplied = false;

  MobileTab _tabForRoute(String? name) {
    if (name == Routes.inbox) return MobileTab.inbox;
    if (name == Routes.settings) return MobileTab.you;
    return MobileTab.chats;
  }

  String _routeForTab(MobileTab tab) {
    switch (tab) {
      case MobileTab.inbox:
        return Routes.inbox;
      case MobileTab.chats:
        return Routes.home;
      case MobileTab.you:
        return Routes.settings;
    }
  }

  bool _isHideChromeRoute(String? name) {
    if (name == null) return false;
    if ((name == Routes.room || name == Routes.call || name == Routes.roomDetails) &&
        widget.roomId != null) {
      return true;
    }
    return name == Routes.settingsAppearance ||
        name == Routes.settingsNotifications ||
        name == Routes.settingsDevices ||
        name == Routes.settingsVoiceVideo ||
        name == Routes.settingsShareInvite ||
        name == Routes.spaceDetails;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.routeName;

    if (_isHideChromeRoute(name)) {
      return widget.routerChild;
    }

    MobileTab currentTab;
    if (!_initialTabApplied && name == Routes.home) {
      _initialTabApplied = true;
      final remembered = context.read<PreferencesService>().lastMobileTab;
      currentTab = remembered;
      if (remembered != MobileTab.chats) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.goNamed(_routeForTab(remembered));
        });
      }
    } else {
      currentTab = _tabForRoute(name);
    }
    final unread = context.select<InboxController, int>((c) => c.unreadCount);

    return Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: currentTab.index,
            children: const [
              InboxScreen(),
              RoomList(),
              SettingsScreen(),
            ],
          ),
        ),
        _CompactBottomNav(
          selectedIndex: currentTab.index,
          onDestinationSelected: (i) async {
            final tab = MobileTab.values[i];
            final prefs = context.read<PreferencesService>();
            await prefs.setLastMobileTab(tab);
            if (context.mounted) context.goNamed(_routeForTab(tab));
          },
          destinations: [
            _CompactDestination(
              icon: unread > 0
                  ? Badge(
                      label: Text(unread > 99 ? '99+' : '$unread'),
                      child: const Icon(Icons.inbox_outlined),
                    )
                  : const Icon(Icons.inbox_outlined),
              selectedIcon: const Icon(Icons.inbox),
              label: MobileTab.inbox.label,
            ),
            const _CompactDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            const _CompactDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'You',
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactDestination {
  const _CompactDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

class _CompactBottomNav extends StatelessWidget {
  const _CompactBottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_CompactDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _CompactDestinationItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onDestinationSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactDestinationItem extends StatelessWidget {
  const _CompactDestinationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _CompactDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
            decoration: BoxDecoration(
              color: selected ? cs.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconTheme(
              data: IconThemeData(
                size: 22,
                color: selected
                    ? cs.onPrimaryContainer
                    : cs.onSurfaceVariant,
              ),
              child:
                  selected ? destination.selectedIcon : destination.icon,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            destination.label,
            style: tt.labelSmall?.copyWith(
              color: selected ? cs.onSurface : cs.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
// coverage:ignore-end
