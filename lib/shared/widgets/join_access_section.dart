import 'package:flutter/material.dart';
import 'package:kohera/core/models/join_mode.dart';

/// A self-contained (id + displayname) reference to a space, used by the
/// SDK-free [JoinAccessSection] so shared widgets do not depend on
/// features-layer domain models or the Matrix SDK.
typedef SpaceRef = ({String id, String displayname});

class JoinAccessSection extends StatelessWidget {
  const JoinAccessSection({
    required this.mode,
    required List<SpaceRef> allowedSpaces,
    required List<SpaceRef> candidateSpaces,
    required this.needsUpgrade,
    required this.canEdit,
    required this.onModeChanged,
    required ValueChanged<List<String>> onAllowedSpacesChanged,
    this.onUpgradeRequested,
    this.disabledModes = const {},
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.saving = false,
    this.savedHint = false,
    super.key,
  })  : _allowedRefs = allowedSpaces,
        _candidateRefs = candidateSpaces,
        _onAllowedChangedIds = onAllowedSpacesChanged;

  final JoinMode mode;
  final bool needsUpgrade;
  final bool canEdit;

  /// Modes that should be disabled in the dropdown, mapped to the tooltip
  /// explaining why. Pass an empty map for no restrictions.
  final Map<JoinMode, String> disabledModes;
  final EdgeInsetsGeometry padding;
  final bool saving;
  final bool savedHint;
  final ValueChanged<JoinMode> onModeChanged;
  final VoidCallback? onUpgradeRequested;

  final List<SpaceRef> _allowedRefs;
  final List<SpaceRef> _candidateRefs;
  final ValueChanged<List<String>> _onAllowedChangedIds;

  bool get _allowedIsEmpty => _allowedRefs.isEmpty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final restrictedFamily = mode.isRestrictedFamily;
    final showPicker = restrictedFamily;
    final showUpgrade = needsUpgrade && restrictedFamily;
    final emptyAllowError =
        restrictedFamily && _allowedIsEmpty ? _emptyError(tt, cs) : null;

    final dropdown = DropdownButtonFormField<JoinMode>(
      key: const Key('join_access_mode_dropdown'),
      initialValue: mode,
      decoration: InputDecoration(
        labelText: 'Join',
        border: const OutlineInputBorder(),
        suffixIcon: _statusIcon(cs),
      ),
      items: JoinMode.values.map((m) {
        final tooltip = disabledModes[m];
        final disabled = tooltip != null;
        final label = Text(m.displayLabel);
        return DropdownMenuItem<JoinMode>(
          value: m,
          enabled: !disabled,
          child: disabled ? Tooltip(message: tooltip, child: label) : label,
        );
      }).toList(),
      onChanged: canEdit
          ? (v) {
              if (v == null) return;
              if (disabledModes.containsKey(v)) return;
              onModeChanged(v);
            }
          : null,
    );

    final disabledTooltip = canEdit
        ? dropdown
        : Tooltip(
            message: 'Requires higher power level',
            child: AbsorbPointer(child: dropdown),
          );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          disabledTooltip,
          if (!canEdit)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Requires higher power level to change.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          if (showPicker) ...[
            const SizedBox(height: 12),
            _spacePicker,
          ],
          if (emptyAllowError != null) ...[
            const SizedBox(height: 8),
            emptyAllowError,
          ],
          if (showUpgrade) ...[
            const SizedBox(height: 12),
            _UpgradeBanner(
              key: const Key('join_access_upgrade_banner'),
              onUpgrade: canEdit ? onUpgradeRequested : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget get _spacePicker {
    return _SpaceRefPicker(
      key: const Key('join_access_space_picker'),
      candidates: _candidateRefs,
      selected: _allowedRefs,
      enabled: canEdit,
      onChanged: _onAllowedChangedIds,
    );
  }

  Widget _emptyError(TextTheme tt, ColorScheme cs) {
    return Text(
      'Pick at least one space',
      key: const Key('join_access_empty_error'),
      style: tt.bodySmall?.copyWith(color: cs.error),
    );
  }

  Widget? _statusIcon(ColorScheme cs) {
    if (saving) {
      return const Padding(
        key: Key('join_access_saving_indicator'),
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (savedHint) {
      return Padding(
        key: const Key('join_access_saved_indicator'),
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.check_circle_outline, color: cs.primary, size: 20),
      );
    }
    return null;
  }
}

/// SDK-free space picker operating on [SpaceRef] records and emitting
/// selected room IDs.
class _SpaceRefPicker extends StatelessWidget {
  const _SpaceRefPicker({
    required this.candidates,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final List<SpaceRef> candidates;
  final List<SpaceRef> selected;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (candidates.isEmpty) {
      return Text(
        'No eligible parent spaces',
        style: tt.bodySmall,
      );
    }
    final selectedIds = selected.map((r) => r.id).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Spaces whose members can join', style: tt.labelMedium),
        const SizedBox(height: 4),
        ...candidates.map(
          (ref) => CheckboxListTile(
            key: Key('join_access_space_${ref.id}'),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(ref.displayname),
            value: selectedIds.contains(ref.id),
            onChanged: enabled
                ? (checked) {
                    final next = [...selectedIds];
                    if (checked ?? false) {
                      if (!next.contains(ref.id)) next.add(ref.id);
                    } else {
                      next.remove(ref.id);
                    }
                    onChanged(next);
                  }
                : null,
          ),
        ),
      ],
    );
  }
}

class _UpgradeBanner extends StatelessWidget {
  const _UpgradeBanner({required this.onUpgrade, super.key});

  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This room must be upgraded before space members can join.',
              style: tt.bodyMedium?.copyWith(color: cs.onSecondaryContainer),
            ),
          ),
          TextButton(
            key: const Key('join_access_upgrade_button'),
            onPressed: onUpgrade,
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}
