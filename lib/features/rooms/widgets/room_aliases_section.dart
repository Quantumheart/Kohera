import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/features/rooms/models/kohera_room_aliases.dart';

/// Renders the room alias management UI: canonical alias, list of local
/// aliases, create field, set-canonical and delete actions.
///
/// SDK-free presentational widget. All data comes from [aliases] and all
/// actions are callbacks owned by [RoomAliasesController].
class RoomAliasesSection extends StatefulWidget {
  const RoomAliasesSection({
    required this.aliases,
    required this.onCreate,
    required this.onDelete,
    required this.onSetCanonical,
    required this.onClearCanonical,
    super.key,
  });

  final KoheraRoomAliases aliases;

  /// Creates a new local alias from a localpart (without `#` or `:domain`).
  final Future<void> Function(String localpart) onCreate;

  /// Deletes the given full alias (`#room:server`).
  final Future<void> Function(String alias) onDelete;

  /// Sets the given existing alias as the canonical alias.
  final Future<void> Function(String alias) onSetCanonical;

  /// Clears the canonical alias.
  final Future<void> Function() onClearCanonical;

  @override
  State<RoomAliasesSection> createState() => _RoomAliasesSectionState();
}

class _RoomAliasesSectionState extends State<RoomAliasesSection> {
  final _controller = TextEditingController();
  final Set<String> _inFlight = {};
  String? _error;
  String? _success;
  bool _expanded = false;

  bool get _loading => _inFlight.isNotEmpty;
  bool _busy(String action) => _inFlight.contains(action);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(
    String action,
    Future<void> Function() task, {
    String? successMessage,
  }) async {
    setState(() {
      _inFlight.add(action);
      _error = null;
      _success = null;
    });
    try {
      await task();
      if (mounted && successMessage != null) {
        setState(() => _success = successMessage);
      }
    } catch (e) {
      debugPrint('[Kohera] alias $action failed: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _inFlight.remove(action));
    }
  }

  Future<void> _create() async {
    final localpart = _controller.text.trim().toLowerCase();
    if (localpart.isEmpty) return;
    await _run('create', () => widget.onCreate(localpart), successMessage: 'Alias created');
    if (mounted && _error == null) _controller.clear();
  }

  Future<void> _confirmDelete(String alias) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Delete alias?',
      message: 'Remove $alias? Users will no longer be able to join via this alias.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run('delete:$alias', () => widget.onDelete(alias), successMessage: 'Alias deleted');
  }

  Future<void> _setCanonical(String alias) async {
    await _run('canonical:$alias', () => widget.onSetCanonical(alias),
        successMessage: 'Canonical alias set');
  }

  Future<void> _clearCanonical() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Clear canonical alias?',
      message: 'Remove the canonical alias for this room?',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run('canonical:clear', widget.onClearCanonical, successMessage: 'Canonical alias cleared');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final a = widget.aliases;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'ALIASES',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),

        // Canonical alias
        if (a.canonicalAlias != null && a.canonicalAlias!.isNotEmpty)
          ListTile(
            leading: Icon(Icons.push_pin_rounded, color: cs.primary, size: 22),
            title: Text(a.canonicalAlias!),
            subtitle: const Text('Canonical alias'),
            trailing: a.canEdit
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    tooltip: 'Clear canonical alias',
                    onPressed: _busy('canonical:clear') ? null : _clearCanonical,
                  )
                : null,
          )
        else
          ListTile(
            leading: Icon(Icons.push_pin_outlined, color: cs.onSurfaceVariant, size: 22),
            title: Text('No canonical alias', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),

        // Create field
        if (a.canEdit && a.homeserverDomain != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_busy('create'),
                    decoration: InputDecoration(
                      labelText: 'New alias',
                      hintText: 'roomname',
                      prefixText: '#',
                      suffixText: ':${a.homeserverDomain}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: _busy('create') ? null : (_) => _create(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _busy('create') ? null : _create,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Create alias',
                ),
              ],
            ),
          ),

        // Alias list toggle
        if (a.aliases.isNotEmpty)
          ListTile(
            dense: true,
            leading: Icon(Icons.alternate_email_rounded, color: cs.onSurfaceVariant, size: 20),
            title: Text('${a.aliases.length} alias${a.aliases.length == 1 ? '' : 'es'}'),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
        if (_expanded) ...a.aliases.map((alias) => _buildAliasTile(alias, cs, tt)),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        if (_success != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_success!, style: TextStyle(color: cs.primary, fontSize: 13)),
          ),
      ],
    );
  }

  Widget _buildAliasTile(String alias, ColorScheme cs, TextTheme tt) {
    final isCanonical = alias == widget.aliases.canonicalAlias;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 40, right: 16),
      leading: Icon(
        isCanonical ? Icons.push_pin_rounded : Icons.tag_rounded,
        size: 18,
        color: isCanonical ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(alias, style: tt.bodySmall),
      trailing: widget.aliases.canEdit
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              itemBuilder: (_) => [
                if (!isCanonical)
                  const PopupMenuItem(value: 'canonical', child: Text('Set as canonical')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
              onSelected: (v) {
                if (v == 'canonical') {
                  unawaited(_setCanonical(alias));
                } else if (v == 'delete') {
                  unawaited(_confirmDelete(alias));
                }
              },
            )
          : null,
    );
  }
}
