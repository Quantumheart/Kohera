import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/models/kohera_export_format.dart';
import 'package:kohera/features/rooms/services/history_export_file_writer.dart';
import 'package:kohera/features/rooms/services/history_export_formatters.dart';
import 'package:kohera/features/rooms/services/room_history_exporter.dart';
import 'package:provider/provider.dart';

/// Room details section for chat history export (issue #169).
///
/// Boundary widget: reads [MatrixService], owns a [RoomHistoryExporter],
/// runs the export with progress, and saves the rendered artifact via the
/// platform file-save dialog. SDK-free below the [RoomHistoryExporter]/
/// [HistoryExportFormatters] boundary.
class RoomHistoryExportSection extends StatefulWidget {
  const RoomHistoryExportSection({
    required this.roomId,
    required this.roomDisplayname,
    this.exporter,
    this.onSaveFile,
    this.onWriteFile,
    super.key,
  });

  final String roomId;
  final String roomDisplayname;

  /// Optional override for the SDK conversion boundary. Defaults to a
  /// [RoomHistoryExporter] built from [MatrixService]. Injected in tests.
  final RoomHistoryExporter? exporter;

  /// Optional override for the platform save step. Receives the rendered
  /// bytes and the suggested file name, returns the chosen path or `null`
  /// if aborted. Defaults to [FilePicker.platform.saveFile]. Injected in
  /// tests.
  final Future<String?> Function(Uint8List bytes, String fileName)?
      onSaveFile;

  /// Optional override for writing the saved bytes to disk on native. Defaults
  /// to [writeExportFile]. Injected in tests to avoid real I/O.
  final Future<void> Function(String path, Uint8List bytes)? onWriteFile;

  @override
  State<RoomHistoryExportSection> createState() =>
      _RoomHistoryExportSectionState();
}

class _RoomHistoryExportSectionState extends State<RoomHistoryExportSection> {
  KoheraExportFormat _format = KoheraExportFormat.json;
  DateTime? _start;
  DateTime? _end;
  bool _includeMedia = false;
  bool _running = false;
  int? _loaded;
  String? _error;
  String? _success;

  RoomHistoryExporter get _exporter =>
      widget.exporter ??
      RoomHistoryExporter(matrix: context.read<MatrixService>());

  Future<String?> _save(Uint8List bytes, String fileName) {
    final override = widget.onSaveFile;
    if (override != null) return override(bytes, fileName);
    return FilePicker.saveFile(
      dialogTitle: 'Export chat history',
      fileName: fileName,
      bytes: bytes,
    );
  }

  KoheraExportOptions get _options => KoheraExportOptions(
        format: _format,
        start: _start,
        end: _end,
        includeMedia: _includeMedia,
      );

  String get _fileName {
    final safeName = widget.roomDisplayname.replaceAll(
      RegExp('[^A-Za-z0-9._-]'),
      '_',
    );
    return '${safeName}_history.${_format.extension}';
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _start = picked;
        _success = null;
        _error = null;
      });
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end ?? _start ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _end = picked;
        _success = null;
        _error = null;
      });
    }
  }

  Future<void> _clearRange() async {
    setState(() {
      _start = null;
      _end = null;
      _success = null;
      _error = null;
    });
  }

  Future<void> _export() async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() {
      _running = true;
      _loaded = null;
      _error = null;
      _success = null;
    });
    try {
      final export = await _exporter.export(
        roomId: widget.roomId,
        options: _options,
        onProgress: (loaded, _) {
          if (mounted) setState(() => _loaded = loaded);
        },
      );
      final content = const HistoryExportFormatters().format(export);
      final bytes = Uint8List.fromList(content.codeUnits);
      final path = await _save(bytes, _fileName);
      if (path != null && bytes.isNotEmpty) {
        final write = widget.onWriteFile ?? writeExportFile;
        await write(path, bytes);
      }
      if (!mounted) return;
      if (path != null) {
        setState(() => _success =
            'Exported ${export.messages.length} messages to $path');
        scaffold.showSnackBar(
          SnackBar(content: Text('Exported ${export.messages.length} messages')),
        );
      }
    } catch (e) {      debugPrint('[Kohera] history export failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'EXPORT',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_running) const LinearProgressIndicator(),

        // Format selection
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            spacing: 8,
            children: [
              for (final f in KoheraExportFormat.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _format == f,
                  onSelected: _running
                      ? null
                      : (selected) {
                          if (selected) {
                            setState(() {
                              _format = f;
                              _success = null;
                              _error = null;
                            });
                          }
                        },
                ),
            ],
          ),
        ),

        // Date range
        ListTile(
          dense: true,
          leading: Icon(Icons.date_range_outlined, color: cs.onSurfaceVariant),
          title: Text(
            _rangeLabel(),
            style: tt.bodyMedium,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _running ? null : _pickStart,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Start date'),
                avatar: const Icon(Icons.event_outlined, size: 18),
                onPressed: _running ? null : _pickStart,
              ),
              ActionChip(
                label: const Text('End date'),
                avatar: const Icon(Icons.event_available_outlined, size: 18),
                onPressed: _running ? null : _pickEnd,
              ),
              if (_start != null || _end != null)
                ActionChip(
                  label: const Text('Clear range'),
                  avatar: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: _running ? null : _clearRange,
                ),
            ],
          ),
        ),

        // Include media
        SwitchListTile(
          dense: true,
          secondary: Icon(Icons.attach_file_outlined, color: cs.onSurfaceVariant),
          title: const Text('Include media references'),
          subtitle: const Text('Adds mxc URLs and filenames (no download)'),
          value: _includeMedia,
          onChanged: _running
              ? null
              : (v) => setState(() {
                    _includeMedia = v;
                    _success = null;
                    _error = null;
                  }),
        ),

        // Export button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.tonalIcon(
            onPressed: _running ? null : _export,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(_running
                ? (_loaded != null ? 'Exporting… $_loaded' : 'Exporting…')
                : 'Export history'),
          ),
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        if (_success != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _success!,
              style: TextStyle(color: cs.primary, fontSize: 13),
            ),
          ),
      ],
    );
  }

  String _rangeLabel() {
    if (_start == null && _end == null) return 'All history';
    final s = _start?.toIso8601String().substring(0, 10) ?? '…';
    final e = _end?.toIso8601String().substring(0, 10) ?? '…';
    return '$s → $e';
  }
}
