import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../../core/utils/tag_utils.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../providers/field_config_provider.dart';
import '../providers/time_entry_providers.dart';
import '../../domain/time_entry_field.dart';
import 'time_entry_tile_body.dart';

class TimeEntryTile extends ConsumerWidget {
  final TimeEntry entry;

  const TimeEntryTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final clientAsync = ref.watch(clientByIdProvider(entry.clientId));
    final clientName = clientAsync.value?.name;
    final configs = ref.watch(fieldConfigProvider).value ??
        FieldConfig.defaults();

    return Dismissible(
      key: ValueKey(entry.id),
      direction: entry.isInvoiced
          ? DismissDirection.none
          : DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: theme.colorScheme.primary,
        child: Icon(Icons.copy, color: theme.colorScheme.onPrimary),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.error,
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Entry'),
              content: const Text('Delete this time entry?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete')),
              ],
            ),
          );
        }
        // Swipe right = duplicate
        if (direction == DismissDirection.startToEnd) {
          _duplicateEntry(context, ref);
          return false; // Don't dismiss, just duplicate
        }
        return false;
      },
      onDismissed: (_) {
        ref.read(timerNotifierProvider.notifier).deleteEntry(entry.id);
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showDetailSheet(context, ref, clientName),
          onLongPress: () => _showActionSheet(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md, vertical: 12),
            child: TimeEntryTileBody(
              entry: entry,
              clientName: clientName,
              configs: configs,
            ),
          ),
        ),
      ),
    );
  }

  void _duplicateEntry(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final duration = entry.endTime?.difference(entry.startTime);
    final start = DateTime(now.year, now.month, now.day,
        entry.startTime.hour, entry.startTime.minute);
    final end = duration != null ? start.add(duration) : null;

    if (end == null) return;

    ref.read(timerNotifierProvider.notifier).addManualEntry(
          clientId: entry.clientId,
          projectId: entry.projectId,
          startTime: start,
          endTime: end,
          description: entry.description,
          issueReference: entry.issueReference,
          repository: entry.repository,
          tags: entry.tags,
        );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry duplicated to today')),
    );
  }

  void _showActionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                context.pushNamed('editTimeEntry', extra: entry);
              },
            ),
            if (!entry.isInvoiced) ...[
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Duplicate'),
                onTap: () {
                  Navigator.pop(ctx);
                  _duplicateEntry(context, ref);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: Text('Delete',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dlg) => AlertDialog(
                      title: const Text('Delete Entry'),
                      content: const Text('Delete this time entry?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dlg, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(dlg, true),
                            child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    ref
                        .read(timerNotifierProvider.notifier)
                        .deleteEntry(entry.id);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetailSheet(
      BuildContext context, WidgetRef ref, String? clientName) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat.jm();
    final dateFmt = DateFormat.yMMMEd();
    final isRunning = entry.endTime == null;
    final minutes = entry.durationMinutes ?? 0;
    final earnings = minutes / 60.0 * entry.hourlyRateSnapshot;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date
              Text(
                dateFmt.format(entry.startTime),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: Spacing.sm),

              // Time range + duration
              Row(
                children: [
                  Icon(Icons.schedule,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    isRunning
                        ? '${timeFmt.format(entry.startTime)} – running'
                        : '${timeFmt.format(entry.startTime)} – ${timeFmt.format(entry.endTime!)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (!isRunning) ...[
                    const Spacer(),
                    Text(
                      formatDuration(minutes),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: Spacing.sm),

              // Client
              if (clientName != null)
                _DetailRow(
                    icon: Icons.business_outlined, text: clientName),

              // Rate + Earnings
              if (!isRunning)
                _DetailRow(
                  icon: Icons.attach_money,
                  text:
                      '${formatCurrency(entry.hourlyRateSnapshot)}/hr · ${formatCurrency(earnings)} total',
                ),

              // Description
              if (entry.description != null &&
                  entry.description!.isNotEmpty)
                _DetailRow(
                    icon: Icons.notes_outlined, text: entry.description!),

              // Repository
              if (entry.repository != null)
                _DetailRow(
                    icon: Icons.folder_outlined, text: entry.repository!),

              // Issue ref
              if (entry.issueReference != null)
                _DetailRow(icon: Icons.tag, text: entry.issueReference!),

              // Tags
              Builder(builder: (context) {
                final tags = parseTags(entry.tags);
                if (tags.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.label_outline,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: tags
                              .map((t) => Chip(
                                    label: Text(t,
                                        style: theme.textTheme.labelSmall),
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: Spacing.md),

              // Edit button
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.pushNamed('editTimeEntry', extra: entry);
                  },
                  child: const Text('Edit Entry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

