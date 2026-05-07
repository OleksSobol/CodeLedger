import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/spacing.dart';
import '../providers/time_entry_providers.dart';

class TimeSummaryBar extends ConsumerWidget {
  const TimeSummaryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(filteredEntriesProvider);

    return entriesAsync.when(
      loading: () => const SizedBox(height: 80),
      error: (_, _) => const SizedBox.shrink(),
      data: (entries) {
        final completed = entries.where((e) => e.endTime != null);
        final totalMinutes = completed.fold<int>(
            0, (sum, e) => sum + (e.durationMinutes ?? 0));
        final totalEarnings = completed.fold<double>(
            0,
            (sum, e) =>
                sum +
                (e.durationMinutes ?? 0) / 60.0 * e.hourlyRateSnapshot);
        final uninvoicedCount =
            completed.where((e) => !e.isInvoiced).length;

        final theme = Theme.of(context);

        final tiles = <_TileData>[
          _TileData(
            label: 'Total',
            value: formatDuration(totalMinutes),
            accent: theme.colorScheme.primary,
          ),
          _TileData(
            label: 'Earnings',
            value: formatCurrency(totalEarnings),
            accent: theme.colorScheme.tertiary,
          ),
          _TileData(
            label: 'Entries',
            value: '${completed.length}',
            accent: theme.colorScheme.secondary,
          ),
          if (uninvoicedCount > 0)
            _TileData(
              label: 'Uninvoiced',
              value: '$uninvoicedCount',
              accent: theme.colorScheme.error,
            ),
        ];

        return SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 4),
            itemCount: tiles.length,
            separatorBuilder: (_, _) => const SizedBox(width: Spacing.sm),
            itemBuilder: (context, index) {
              final tile = tiles[index];
              return _InsightTile(
                label: tile.label,
                value: tile.value,
                accent: tile.accent,
              );
            },
          ),
        );
      },
    );
  }
}

class _TileData {
  final String label;
  final String value;
  final Color accent;

  const _TileData({
    required this.label,
    required this.value,
    required this.accent,
  });
}

class _InsightTile extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _InsightTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 130,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Row(
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
