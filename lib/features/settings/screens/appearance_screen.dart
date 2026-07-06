import 'package:flutter/material.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/settings/widgets/custom_theme_editor.dart';
import 'package:kohera/features/settings/widgets/theme_mode_picker.dart';
import 'package:kohera/features/settings/widgets/theme_preset_picker.dart';
import 'package:kohera/shared/widgets/section_header.dart';
import 'package:provider/provider.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(Routes.settings),
        ),
        title: const Text('Appearance'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Theme ──────────────────────────────────────────
          const SectionHeader(label: 'THEME'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose your preferred color scheme.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  const ThemePresetPicker(),
                  const SizedBox(height: 16),
                  const ThemeModePicker(),
                  if (prefs.themePreset == 'custom')
                    const CustomThemeEditor(),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Effects ────────────────────────────────────────
          const SectionHeader(label: 'EFFECTS'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('CRT scanlines'),
                  subtitle: const Text(
                    'Faint scanline overlay for the retro console look.',
                  ),
                  value: prefs.scanlinesEnabled,
                  onChanged: prefs.setScanlinesEnabled,
                ),
                SwitchListTile(
                  title: const Text('Pixelate graphics'),
                  subtitle: const Text(
                    'Render uploaded avatars and emoji as pixel art.',
                  ),
                  value: prefs.pixelateGraphics,
                  onChanged: prefs.setPixelateGraphics,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Message density ────────────────────────────────
          const SectionHeader(label: 'MESSAGE DENSITY'),
          Card(
            child: RadioGroup<MessageDensity>(
              groupValue: prefs.messageDensity,
              onChanged: (v) => prefs.setMessageDensity(v!),
              child: Column(
                children: MessageDensity.values.map((density) {
                  return RadioListTile<MessageDensity>(
                    title: Text(density.label),
                    value: density,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
