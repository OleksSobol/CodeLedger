import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../../shared/widgets/spacing.dart';
import '../providers/time_entry_providers.dart';
import '../widgets/active_timer_widget.dart';
import '../widgets/time_entries_list.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/time_summary_bar.dart';
import '../widgets/manual_entry_sheet.dart';
import '../widgets/tag_filter_bar.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../../../export/presentation/providers/export_providers.dart';

class TimeTrackingPage extends ConsumerWidget {
  const TimeTrackingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final runningAsync = ref.watch(runningEntryProvider);
    final filter = ref.watch(dateRangeFilterProvider);

    final entriesAsync = ref.watch(filteredEntriesProvider);
    final totalMinutes = entriesAsync.whenOrNull(
            data: (entries) => entries
                .where((e) => e.endTime != null)
                .fold<int>(
                    0, (sum, e) => sum + (e.durationMinutes ?? 0))) ??
        0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Time Tracking'),
            Text(
              '${_filterLabel(filter)} · ${formatDuration(totalMinutes)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'export') _exportCsv(context, ref);
              if (value == 'manual') ManualEntrySheet.show(context);
              if (value == 'github_sync') _syncGitHub(context, ref, filter);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.file_download_outlined),
                    title: Text('Export CSV'),
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )),
              PopupMenuItem(
                  value: 'manual',
                  child: ListTile(
                    leading: Icon(Icons.edit_note),
                    title: Text('Manual Entry'),
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )),
              PopupMenuItem(
                  value: 'github_sync',
                  child: ListTile(
                    leading: Icon(Icons.sync),
                    title: Text('Sync GitHub Issues'),
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(filteredEntriesProvider);
          ref.invalidate(runningEntryProvider);
          await Future.delayed(const Duration(milliseconds: 300));
        },
        child: CustomScrollView(
          slivers: [
            // Active Timer (if running)
            if (runningAsync.value != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child:
                      ActiveTimerWidget(entry: runningAsync.value!),
                ),
              ),

            // Date Filter
            SliverToBoxAdapter(
              child: DateRangeSelector(),
            ),

            // Tag Filter Bar
            const SliverToBoxAdapter(child: TagFilterBar()),

            // Insight Strip
            const SliverToBoxAdapter(child: TimeSummaryBar()),

            // Entries Timeline
            const TimeEntriesSliver(),

            // Bottom padding for FAB
            const SliverToBoxAdapter(
                child: SizedBox(height: Spacing.xl + 80)),
          ],
        ),
      ),
    );
  }

  String _filterLabel(DateRangeFilter f) {
    final today = DateRangeFilter.today();
    if (f.start == today.start && f.end == today.end) return 'Today';
    final week = DateRangeFilter.thisWeek();
    if (f.start == week.start && f.end == week.end) return 'This Week';
    final month = DateRangeFilter.thisMonth();
    if (f.start == month.start && f.end == month.end) return 'This Month';
    final fmt = DateFormat.MMMd();
    return '${fmt.format(f.start)} – ${fmt.format(f.end)}';
  }

  void _syncGitHub(
      BuildContext context, WidgetRef ref, DateRangeFilter filter) {
    context.push('/github-sync', extra: {
      'start': filter.start,
      'end': filter.end,
    });
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final filter = ref.read(dateRangeFilterProvider);
      final timeDao = ref.read(timeEntryDaoProvider);
      final entries = await timeDao.getAllEntries(
        from: filter.start,
        to: filter.end,
      );

      if (entries.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No entries to export')),
          );
        }
        return;
      }

      // Resolve client and project names
      final clientDao = ref.read(clientDaoProvider);
      final projectDao = ref.read(projectDaoProvider);

      final clientIds = entries.map((e) => e.clientId).toSet();
      final clientNames = <int, String>{};
      for (final id in clientIds) {
        try {
          final c = await clientDao.getClient(id);
          clientNames[id] = c.name;
        } catch (_) {
          clientNames[id] = 'Unknown';
        }
      }

      final projectIds =
          entries.map((e) => e.projectId).whereType<int>().toSet();
      final projectNames = <int, String>{};
      for (final id in projectIds) {
        try {
          final p = await projectDao.getProject(id);
          projectNames[id] = p.name;
        } catch (_) {
          projectNames[id] = 'Unknown';
        }
      }

      final exportService = ref.read(exportServiceProvider);
      final file = await exportService.generateTimeEntriesCsv(
        entries: entries,
        projectNames: projectNames,
        clientNames: clientNames,
      );

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)]),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
        );
      }
    }
  }
}
