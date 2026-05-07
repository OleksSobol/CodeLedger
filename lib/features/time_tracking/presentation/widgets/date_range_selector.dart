import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../shared/widgets/spacing.dart';
import '../providers/time_entry_providers.dart';

class DateRangeSelector extends ConsumerWidget {
  const DateRangeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(dateRangeFilterProvider);
    final theme = Theme.of(context);
    final fmt = DateFormat.MMMd();

    final selected = _selectedSegment(filter);
    final rangeText = selected == 'custom'
        ? '${fmt.format(filter.start)} - ${fmt.format(filter.end.subtract(const Duration(days: 1)))}'
        : '${fmt.format(filter.start)} - ${fmt.format(filter.end.subtract(const Duration(days: 1)))}';

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'today', label: Text('Today')),
                    ButtonSegment(value: 'week', label: Text('Week')),
                    ButtonSegment(value: 'month', label: Text('Month')),
                  ],
                  selected: {
                    if (selected == 'custom') 'week' else selected,
                  },
                  onSelectionChanged: (selection) {
                    final value = selection.first;
                    ref.read(dateRangeFilterProvider.notifier).set(
                      switch (value) {
                        'today' => DateRangeFilter.today(),
                        'week' => DateRangeFilter.thisWeek(),
                        'month' => DateRangeFilter.thisMonth(),
                        _ => DateRangeFilter.thisWeek(),
                      },
                    );
                  },
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                rangeText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => _pickCustomRange(context, ref, filter),
            icon: Icon(Icons.date_range, size: 16,
                color: selected == 'custom'
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
            label: Text(
              selected == 'custom' ? 'Custom range selected' : 'Custom range...',
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected == 'custom'
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  String _selectedSegment(DateRangeFilter f) {
    final today = DateRangeFilter.today();
    if (f.start == today.start && f.end == today.end) return 'today';
    final week = DateRangeFilter.thisWeek();
    if (f.start == week.start && f.end == week.end) return 'week';
    final month = DateRangeFilter.thisMonth();
    if (f.start == month.start && f.end == month.end) return 'month';
    return 'custom';
  }

  Future<void> _pickCustomRange(
      BuildContext context, WidgetRef ref, DateRangeFilter current) async {
    final initialEnd = current.end.subtract(const Duration(days: 1));
    final lastDate = initialEnd.isAfter(DateTime.now())
        ? initialEnd
        : DateTime.now().add(const Duration(days: 1));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: lastDate,
      initialDateRange: DateTimeRange(
        start: current.start,
        end: initialEnd,
      ),
    );
    if (picked != null) {
      ref.read(dateRangeFilterProvider.notifier).set(DateRangeFilter(
        start: picked.start,
        end: picked.end.add(const Duration(days: 1)),
      ));
    }
  }
}
