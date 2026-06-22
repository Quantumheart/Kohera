import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class KoheraMark extends StatelessWidget {
  const KoheraMark({required this.size, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SvgPicture.asset(
      'assets/icons/kohera_mark.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
