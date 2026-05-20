import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../domain/time_entry_field.dart';
import '../providers/field_config_provider.dart';
import '../widgets/time_entry_tile_body.dart';

class TimeEntryLayoutPage extends ConsumerStatefulWidget {
  const TimeEntryLayoutPage({super.key});

  @override
  ConsumerState<TimeEntryLayoutPage> createState() =>
      _TimeEntryLayoutPageState();
}

class _TimeEntryLayoutPageState extends ConsumerState<TimeEntryLayoutPage> {
  List<FieldConfig> _configs = FieldConfig.defaults();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(fieldConfigProvider.future).then((configs) {
      if (mounted) setState(() => _configs = List.from(configs));
    });
  }

  // ── Mutations ────────────────────────────────────────────────────

  void _toggle(int index) {
    setState(() {
      _configs[index] = _configs[index].copyWith(isVisible: !_configs[index].isVisible);
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final items = List<FieldConfig>.from(_configs);
      final moved = items.removeAt(oldIndex);
      items.insert(newIndex, moved);
      _configs = [
        for (var i = 0; i < items.length; i++) items[i].copyWith(order: i),
      ];
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(fieldConfigProvider.notifier).save(_configs);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    setState(() => _configs = FieldConfig.defaults());
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entry Layout'),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Live preview ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: Spacing.sm),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md, vertical: 12),
                    child: TimeEntryTileBody(
                      entry: _sampleEntry(),
                      clientName: 'Acme Corp',
                      configs: _configs,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Spacing.sm),
          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.md, 10, Spacing.md, 4),
            child: Text(
              'Drag to reorder · toggle to show / hide',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),

          // ── Field list ────────────────────────────────────────────
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: EdgeInsets.zero,
              itemCount: _configs.length,
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final cfg = _configs[index];
                return _FieldRow(
                  key: ValueKey(cfg.field),
                  index: index,
                  config: cfg,
                  onToggle: () => _toggle(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Sample entry for the preview ─────────────────────────────────

  static TimeEntry _sampleEntry() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9, 30);
    final end = DateTime(now.year, now.month, now.day, 17, 45);
    return TimeEntry(
      id: 'sample',
      clientId: 'sample-client',
      startTime: start,
      endTime: end,
      durationMinutes: 495,
      description: 'Implement OAuth flow, write unit tests',
      issueReference: '#142',
      repository: 'my-app',
      tags: '["backend","auth"]',
      isManual: true,
      hourlyRateSnapshot: 95.0,
      isInvoiced: false,
      createdAt: now,
      updatedAt: now,
    );
  }
}

// ── Field row widget ─────────────────────────────────────────────────────────

class _FieldRow extends StatelessWidget {
  final int index;
  final FieldConfig config;
  final VoidCallback onToggle;

  const _FieldRow({
    super.key,
    required this.index,
    required this.config,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = config.isVisible;

    return ListTile(
      leading: Icon(
        config.field.icon,
        color: active ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(
        config.field.label,
        style: TextStyle(
          color: active ? null : theme.colorScheme.outline,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: active,
            onChanged: (_) => onToggle(),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Icon(Icons.drag_handle,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
