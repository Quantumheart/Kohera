import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/openmoji.dart';
import 'package:kohera/core/utils/openmoji_catalog.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';

// ── OpenMojiPicker ───────────────────────────────────────────

/// In-house emoji picker rendering OpenMoji image assets in a tabbed,
/// searchable grid. Calls [onSelected] with the Unicode emoji on tap.
///
/// Tone-supporting emoji render with [skinTone] applied; long-pressing one
/// offers a per-emoji tone override. When [onSkinToneChanged] is provided a
/// tone selector is shown for changing the default.
class OpenMojiPicker extends StatefulWidget {
  const OpenMojiPicker({
    required this.onSelected,
    super.key,
    this.columns = 8,
    this.skinTone = SkinTone.none,
    this.onSkinToneChanged,
  });

  final void Function(String emoji) onSelected;
  final int columns;
  final SkinTone skinTone;
  final ValueChanged<SkinTone>? onSkinToneChanged;

  @override
  State<OpenMojiPicker> createState() => _OpenMojiPickerState();
}

class _OpenMojiPickerState extends State<OpenMojiPicker> {
  static const _icons = <String, IconData>{
    'smileys-emotion': Icons.emoji_emotions_outlined,
    'people-body': Icons.emoji_people_outlined,
    'animals-nature': Icons.pets_outlined,
    'food-drink': Icons.fastfood_outlined,
    'travel-places': Icons.directions_car_outlined,
    'activities': Icons.sports_basketball_outlined,
    'objects': Icons.lightbulb_outline,
    'symbols': Icons.emoji_symbols_outlined,
    'flags': Icons.flag_outlined,
  };

  List<OpenMojiCategory>? _categories;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(OpenMojiCatalog.load().then((categories) {
      if (mounted) setState(() => _categories = categories);
    }),);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final categories = _categories;
    if (categories == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search emoji',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              if (widget.onSkinToneChanged != null) ...[
                const SizedBox(width: 4),
                _SkinToneSelector(
                  tone: widget.skinTone,
                  onChanged: widget.onSkinToneChanged!,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _query.isEmpty
              ? _CategoryTabs(
                  categories: categories,
                  icons: _icons,
                  columns: widget.columns,
                  skinTone: widget.skinTone,
                  onSelected: widget.onSelected,
                )
              : _EmojiGrid(
                  emoji: OpenMojiCatalog.search(_query),
                  columns: widget.columns,
                  skinTone: widget.skinTone,
                  onSelected: widget.onSelected,
                ),
        ),
      ],
    );
  }
}

/// Default skin-tone chooser shown in the picker header.
class _SkinToneSelector extends StatelessWidget {
  const _SkinToneSelector({required this.tone, required this.onChanged});

  final SkinTone tone;
  final ValueChanged<SkinTone> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SkinTone>(
      tooltip: 'Default skin tone',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final t in SkinTone.values)
          PopupMenuItem(
            value: t,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: OpenMojiImage(grapheme: t.sample, size: 24),
                ),
                const SizedBox(width: 12),
                Text(t.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width: 28,
          height: 28,
          child: OpenMojiImage(grapheme: tone.sample, size: 28),
        ),
      ),
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.categories,
    required this.icons,
    required this.columns,
    required this.skinTone,
    required this.onSelected,
  });

  final List<OpenMojiCategory> categories;
  final Map<String, IconData> icons;
  final int columns;
  final SkinTone skinTone;
  final void Function(String emoji) onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: categories.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            indicatorColor: cs.primary,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            tabs: [
              for (final c in categories)
                Tab(icon: Icon(icons[c.key] ?? Icons.tag, size: 20)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final c in categories)
                  _EmojiGrid(
                    emoji: c.emoji,
                    columns: columns,
                    skinTone: skinTone,
                    onSelected: onSelected,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({
    required this.emoji,
    required this.columns,
    required this.skinTone,
    required this.onSelected,
  });

  final List<OpenMojiEmoji> emoji;
  final int columns;
  final SkinTone skinTone;
  final void Function(String emoji) onSelected;

  @override
  Widget build(BuildContext context) {
    if (emoji.isEmpty) {
      return Center(
        child: Text(
          'No emoji found',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
      ),
      itemCount: emoji.length,
      itemBuilder: (context, i) {
        final e = emoji[i];
        final supportsTone = openMojiSupportsSkinTone(e.emoji);
        final shown = supportsTone ? applySkinTone(e.emoji, skinTone) : e.emoji;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSelected(shown),
          onLongPress: supportsTone
              ? () => _pickTone(context, e.emoji)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: OpenMojiImage(grapheme: shown),
          ),
        );
      },
    );
  }

  Future<void> _pickTone(BuildContext context, String base) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final box = context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      topLeft & box.size,
      Offset.zero & overlay.size,
    );

    final picked = await showMenu<SkinTone>(
      context: context,
      position: position,
      items: [
        for (final t in SkinTone.values)
          PopupMenuItem(
            value: t,
            child: SizedBox(
              width: 32,
              height: 32,
              child: OpenMojiImage(grapheme: applySkinTone(base, t), size: 32),
            ),
          ),
      ],
    );
    if (picked != null) onSelected(applySkinTone(base, picked));
  }
}
