import 'package:flutter/material.dart';

import 'package:kohera/shared/widgets/kohera_mark.dart';

class AppLogoHeader extends StatelessWidget {
  const AppLogoHeader({required this.subtitle, super.key});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Logo ──
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: KoheraMark(size: 42, color: cs.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 20),
        Text('Kohera', style: tt.displayLarge),
        const SizedBox(height: 4),
        Text(subtitle, style: tt.bodyMedium),
        const SizedBox(height: 40),
      ],
    );
  }
}
