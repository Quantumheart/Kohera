import 'package:flutter/material.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/shared/models/kohera_presence_type.dart';

/// A presence status dot. Rebuilds independently when [presence] changes and
/// renders nothing (no layout shift) for unknown presence.
///
/// [size] is the diameter of the avatar it decorates; the dot is scaled
/// relative to it. Colours come from the active [ColorScheme] (Material You).
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    required this.presence,
    required this.userId,
    required this.size,
    super.key,
  });

  final PresenceService presence;
  final String userId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: presence,
      builder: (context, _) {
        final cached = presence.presenceFor(userId);
        if (cached == null) return const SizedBox.shrink();
        final (color, label) =
            _styleFor(KoheraPresenceType.fromName(cached.presence.name), cs);
        final diameter = size * 0.3;
        return Semantics(
          label: label,
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: cs.surface, width: size * 0.05),
            ),
          ),
        );
      },
    );
  }

  static (Color, String) _styleFor(
    KoheraPresenceType type,
    ColorScheme cs,
  ) =>
      switch (type) {
        KoheraPresenceType.online => (cs.primary, 'Online'),
        KoheraPresenceType.unavailable => (cs.tertiary, 'Away'),
        KoheraPresenceType.offline => (cs.outline, 'Offline'),
      };
}

/// Overlays a [PresenceDot] on the bottom-right of [child]. When [presence] or
/// [userId] is null the child is returned unchanged (no dot, no layout shift).
class PresenceOverlay extends StatelessWidget {
  const PresenceOverlay({
    required this.size,
    required this.child,
    this.presence,
    this.userId,
    super.key,
  });

  final double size;
  final Widget child;
  final PresenceService? presence;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final presence = this.presence;
    final userId = this.userId;
    if (presence == null || userId == null) return child;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            right: 0,
            bottom: 0,
            child: PresenceDot(
              presence: presence,
              userId: userId,
              size: size,
            ),
          ),
        ],
      ),
    );
  }
}
