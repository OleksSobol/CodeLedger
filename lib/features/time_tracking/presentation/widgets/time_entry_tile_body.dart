import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../../core/utils/tag_utils.dart';
import '../../domain/time_entry_field.dart';

/// The inner content of a time-entry card, rendered dynamically based on
/// [configs].  Reused by both [TimeEntryTile] (live data) and the settings
/// preview (sample data + local config state).
class TimeEntryTileBody extends StatelessWidget {
  final TimeEntry entry;
  final String? clientName;
  final List<FieldConfig> configs;

  const TimeEntryTileBody({
    super.key,
    required this.entry,
    required this.clientName,
    required this.configs,
  });

  @override
  Widget build(BuildContext context) {
    final visible = (configs.toList()
          ..sort((a, b) => a.order.compareTo(b.order)))
        .where((c) => c.isVisible)
        .toList();

    final rows = <Widget>[];
    for (final cfg in visible) {
      final w = _buildField(context, cfg.field);
      if (w == null) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 4));
      rows.add(w);
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget? _buildField(BuildContext context, TimeEntryField field) {
    return switch (field) {
      TimeEntryField.timeRange => _TimeRangeRow(entry: entry),
      TimeEntryField.client => clientName != null
          ? _ClientRow(name: clientName!)
          : null,
      TimeEntryField.description =>
        (entry.description?.isNotEmpty ?? false)
            ? _DescriptionRow(text: entry.description!)
            : null,
      TimeEntryField.issue => entry.issueReference != null
          ? _BadgeRow(icon: Icons.tag, text: entry.issueReference!)
          : null,
      TimeEntryField.repository => entry.repository != null
          ? _BadgeRow(icon: Icons.folder_outlined, text: entry.repository!)
          : null,
      TimeEntryField.tags => _TagsRow(tagsJson: entry.tags),
      TimeEntryField.status => _StatusRow(entry: entry),
    };
  }
}

// ── Field sub-widgets ────────────────────────────────────────────────────────

class _TimeRangeRow extends StatelessWidget {
  final TimeEntry entry;
  const _TimeRangeRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat.jm();
    final isRunning = entry.endTime == null;
    final minutes = entry.durationMinutes ?? 0;
    final earnings = minutes / 60.0 * entry.hourlyRateSnapshot;

    return Row(
      children: [
        Text(
          isRunning
              ? '${fmt.format(entry.startTime)} - ...'
              : '${fmt.format(entry.startTime)} - ${fmt.format(entry.endTime!)}',
          style: theme.textTheme.bodyMedium,
        ),
        const Spacer(),
        if (!isRunning) ...[
          Text(
            formatDuration(minutes),
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(formatCurrency(earnings), style: theme.textTheme.bodySmall),
        ] else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Running',
              style: TextStyle(
                  color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}

class _ClientRow extends StatelessWidget {
  final String name;
  const _ClientRow({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      name,
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _DescriptionRow extends StatelessWidget {
  final String text;
  const _DescriptionRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _BadgeRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BadgeRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TagsRow extends StatelessWidget {
  final String? tagsJson;
  const _TagsRow({required this.tagsJson});

  static const _maxVisible = 5;

  @override
  Widget build(BuildContext context) {
    final tags = parseTags(tagsJson);
    if (tags.isEmpty) return const SizedBox.shrink();
    final visible = tags.take(_maxVisible).toList();
    final extra = tags.length - _maxVisible;
    Chip chip(String label) => Chip(
          label: Text(label, style: Theme.of(context).textTheme.labelSmall),
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        );
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ...visible.map(chip),
        if (extra > 0) chip('+$extra'),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final TimeEntry entry;
  const _StatusRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    if (entry.isManual) {
      badges.add(_MetaBadge(icon: Icons.edit_outlined, text: 'Manual'));
    }
    if (entry.isInvoiced) {
      badges.add(_MetaBadge(icon: Icons.receipt_outlined, text: 'Invoiced'));
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 4, children: badges);
  }
}

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 2),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }
}
