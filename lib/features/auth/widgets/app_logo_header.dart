import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
            child: SvgPicture.asset(
              'assets/icons/kohera_mark.svg',
              width: 42,
              height: 42,
              colorFilter: ColorFilter.mode(cs.onPrimaryContainer, BlendMode.srcIn),
            ),
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
