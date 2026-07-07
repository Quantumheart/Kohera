import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/core/theme/theme_presets.dart';
import 'package:provider/provider.dart';
/// Light / Dark / System brightness picker for the Appearance screen.
///
/// Binds to the correct preference for the active theme configuration:
///  - **Custom theme** (`themePreset == 'custom'`) → `customThemeMode`.
///  - **Mode-locked preset** (`preset.forcedMode != null`) → disabled, fixed.
///  - **Otherwise** → `themeMode`.
///
/// This mirrors the resolution used in `main.dart` so the picker never
/// fights the app root's `themeMode` selection.
class ThemeModePicker extends StatelessWidget {
  const ThemeModePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final isCustom = prefs.themePreset == 'custom';
    final preset = isCustom ? null : getPreset(prefs.themePreset);
    final forcedMode = preset?.forcedMode;

    // Effective mode + which preference to drive.
    final ThemeMode selected;
    final ValueChanged<ThemeMode>? onChanged;
    if (isCustom) {
      selected = prefs.customThemeMode;
      onChanged = prefs.setCustomThemeMode;
    } else if (forcedMode != null) {
      selected = forcedMode;
      onChanged = null; // Locked preset.
    } else {
      selected = prefs.themeMode;
      onChanged = prefs.setThemeMode;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<ThemeMode>(
          style: _segmentStyle(cs),
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(KIcons.brightnessAutoOutlined),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(KIcons.lightModeOutlined),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(KIcons.darkModeOutlined),
              label: Text('Dark'),
            ),
          ],
          selected: {selected},
          onSelectionChanged: onChanged == null
              ? null
              : (selection) {
                  if (selection.isNotEmpty) onChanged!(selection.first);
                },
        ),
        if (forcedMode != null) ...[
          const SizedBox(height: 8),
          Text(
            'This preset is fixed to ${_modeLabel(forcedMode)} mode.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  static ButtonStyle _segmentStyle(ColorScheme cs) => ButtonStyle(
        // Sharp corners to match the pixel aesthetic used across the screen.
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        ),
      );

  static String _modeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}
