import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/openmoji_catalog.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';

// ── OpenMojiPicker ───────────────────────────────────────────

/// In-house emoji picker rendering OpenMoji image assets in a tabbed,
/// searchable grid. Calls [onSelected] with the Unicode emoji on tap.
class OpenMojiPicker extends StatefulWidget {
  const OpenMojiPicker({required this.onSelected, super.key, this.columns = 8});

  final void Function(String emoji) onSelected;
  final int columns;

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
        Expanded(
          child: _query.isEmpty
              ? _CategoryTabs(
                  categories: categories,
                  icons: _icons,
                  columns: widget.columns,
                  onSelected: widget.onSelected,
                )
              : _EmojiGrid(
                  emoji: OpenMojiCatalog.search(_query),
                  columns: widget.columns,
                  onSelected: widget.onSelected,
                ),
        ),
      ],
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.categories,
    required this.icons,
    required this.columns,
    required this.onSelected,
  });

  final List<OpenMojiCategory> categories;
  final Map<String, IconData> icons;
  final int columns;
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
    required this.onSelected,
  });

  final List<OpenMojiEmoji> emoji;
  final int columns;
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
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSelected(e.emoji),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: OpenMojiImage(grapheme: e.emoji),
          ),
        );
      },
    );
  }
}
