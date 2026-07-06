import 'package:flutter/material.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/features/chat/services/emoji_autocomplete_controller.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:kohera/shared/widgets/mxc_image.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';

/// Displays filtered custom emoji suggestions above the compose field.
class EmojiSuggestionList extends StatelessWidget {
  const EmojiSuggestionList({
    required this.controller,
    required this.mediaResolver,
    super.key,
  });

  final EmojiAutocompleteController controller;
  final MediaResolver mediaResolver;

  static const _maxHeight = 200.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final suggestions = controller.suggestions;

    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          return _EmojiSuggestionTile(
            emoji: suggestions[index],
            isSelected: index == controller.selectedIndex,
            mediaResolver: mediaResolver,
            onTap: () => controller.selectSuggestion(suggestions[index]),
          );
        },
      ),
    );
  }
}

class _EmojiSuggestionTile extends StatelessWidget {
  const _EmojiSuggestionTile({
    required this.emoji,
    required this.isSelected,
    required this.mediaResolver,
    required this.onTap,
  });

  final PackImage emoji;
  final bool isSelected;
  final MediaResolver mediaResolver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: isSelected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              if (emoji.emoji != null)
                OpenMojiImage(grapheme: emoji.emoji!, size: 28)
              else
                MxcImage(
                  mxcUrl: emoji.url.toString(),
                  mediaResolver: mediaResolver,
                  width: 28,
                  height: 28,
                  fallbackText: emoji.altText,
                  fallbackStyle: tt.bodySmall,
                ),
              const SizedBox(width: 10),
              Text(
                ':${emoji.shortcode}:',
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              if (emoji.body != null && emoji.body != emoji.shortcode) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    emoji.body!,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
