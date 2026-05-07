import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/time_entry_dao.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../clients/presentation/providers/client_providers.dart';

/// Provides the 5 most recent completed time entries.
final recentEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  final dao = TimeEntryDao(ref.watch(databaseProvider));
  final now = DateTime.now();
  final weekAgo = now.subtract(const Duration(days: 7));
  return dao.watchEntriesForDateRange(weekAgo, now);
});

/// Sliver-based recent activity list for the dashboard CustomScrollView.
class RecentActivitySliver extends ConsumerWidget {
  const RecentActivitySliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentEntriesProvider);

    return recentAsync.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (entries) {
        final completed =
            entries.where((e) => e.endTime != null).take(5).toList();
        if (completed.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Center(
                    child: Text(
                      'No recent activity',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          sliver: SliverList.list(
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < completed.length; i++) ...[
                      _InteractiveEntryTile(entry: completed[i]),
                      if (i < completed.length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/time-tracking'),
                  child: const Text('View All'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InteractiveEntryTile extends ConsumerWidget {
  final TimeEntry entry;
  const _InteractiveEntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final clientAsync = ref.watch(clientByIdProvider(entry.clientId));
    final clientName =
        clientAsync.whenOrNull(data: (c) => c.name) ?? '...';

    final hours = (entry.durationMinutes ?? 0) / 60.0;
    final desc = entry.description ?? 'Work session';
    final timeAgo = _formatTimeAgo(entry.startTime);

    return Dismissible(
      key: ValueKey(entry.id),
      background: Container(
        color: theme.colorScheme.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: Spacing.md),
        child: Icon(Icons.edit, color: theme.colorScheme.onPrimary),
      ),
      secondaryBackground: Container(
        color: theme.colorScheme.tertiary,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Spacing.md),
        child:
            Icon(Icons.receipt_long, color: theme.colorScheme.onTertiary),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          context.push('/time-tracking/edit', extra: entry);
        } else {
          context.push('/invoices/create');
        }
        return false;
      },
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            hours.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          desc,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          '$clientName · $timeAgo',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => _showDetailSheet(context, theme, clientName),
      ),
    );
  }

  void _showDetailSheet(
      BuildContext context, ThemeData theme, String clientName) {
    final timeFmt = DateFormat.jm();
    final dateFmt = DateFormat.yMMMd();
    final minutes = entry.durationMinutes ?? 0;
    final rate = entry.hourlyRateSnapshot;
    final total = (minutes / 60.0) * rate;

    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.description ?? 'Work session',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: Spacing.md),
            _DetailRow(
                'Client', clientName),
            _DetailRow(
                'Date', dateFmt.format(entry.startTime)),
            _DetailRow(
                'Time',
                '${timeFmt.format(entry.startTime)} - '
                    '${entry.endTime != null ? timeFmt.format(entry.endTime!) : 'Running'}'),
            _DetailRow('Duration', formatDuration(minutes)),
            _DetailRow('Rate',
                '\$${rate.toStringAsFixed(2)}/hr'),
            _DetailRow('Value',
                '\$${total.toStringAsFixed(2)}'),
            const SizedBox(height: Spacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/time-tracking/edit', extra: entry);
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit Entry'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(dt);
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
