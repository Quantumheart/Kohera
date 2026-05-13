import 'package:flutter/material.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:matrix/matrix.dart';

class JoinAccessSection extends StatelessWidget {
  const JoinAccessSection({
    required this.mode,
    required this.allowedSpaces,
    required this.candidateSpaces,
    required this.needsUpgrade,
    required this.canEdit,
    required this.onModeChanged,
    required this.onAllowedSpacesChanged,
    this.onUpgradeRequested,
    this.disabledModes = const {},
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    super.key,
  });

  final JoinMode mode;
  final List<Room> allowedSpaces;
  final List<Room> candidateSpaces;
  final bool needsUpgrade;
  final bool canEdit;
  final Set<JoinMode> disabledModes;
  final EdgeInsetsGeometry padding;
  final ValueChanged<JoinMode> onModeChanged;
  final ValueChanged<List<Room>> onAllowedSpacesChanged;
  final VoidCallback? onUpgradeRequested;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final restrictedFamily = mode.isRestrictedFamily;
    final showPicker = restrictedFamily;
    final showUpgrade = needsUpgrade && restrictedFamily;
    final emptyAllowError =
        restrictedFamily && allowedSpaces.isEmpty ? _emptyError(tt, cs) : null;

    final dropdown = DropdownButtonFormField<JoinMode>(
      key: const Key('join_access_mode_dropdown'),
      initialValue: mode,
      decoration: const InputDecoration(
        labelText: 'Join',
        border: OutlineInputBorder(),
      ),
      items: JoinMode.values.map((m) {
        final disabled = disabledModes.contains(m);
        final label = Text(m.displayLabel);
        return DropdownMenuItem<JoinMode>(
          value: m,
          enabled: !disabled,
          child: disabled
              ? Tooltip(
                  message: 'Not supported by this server',
                  child: label,
                )
              : label,
        );
      }).toList(),
      onChanged: canEdit
          ? (v) {
              if (v == null) return;
              if (disabledModes.contains(v)) return;
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
            _SpacePicker(
              key: const Key('join_access_space_picker'),
              candidates: candidateSpaces,
              selected: allowedSpaces,
              enabled: canEdit,
              onChanged: onAllowedSpacesChanged,
            ),
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

  Widget _emptyError(TextTheme tt, ColorScheme cs) {
    return Text(
      'Pick at least one space',
      key: const Key('join_access_empty_error'),
      style: tt.bodySmall?.copyWith(color: cs.error),
    );
  }
}

class _SpacePicker extends StatelessWidget {
  const _SpacePicker({
    required this.candidates,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final List<Room> candidates;
  final List<Room> selected;
  final bool enabled;
  final ValueChanged<List<Room>> onChanged;

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
          (room) => CheckboxListTile(
            key: Key('join_access_space_${room.id}'),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(room.getLocalizedDisplayname()),
            value: selectedIds.contains(room.id),
            onChanged: enabled
                ? (checked) {
                    final next = [...selected];
                    if (checked ?? false) {
                      if (!selectedIds.contains(room.id)) next.add(room);
                    } else {
                      next.removeWhere((r) => r.id == room.id);
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
        borderRadius: BorderRadius.circular(8),
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
