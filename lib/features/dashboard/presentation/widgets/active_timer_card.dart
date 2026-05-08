import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/time_entry_dao.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../time_tracking/presentation/providers/time_entry_providers.dart';
import '../../../clients/presentation/providers/client_providers.dart';

class ActiveTimerCard extends ConsumerStatefulWidget {
  const ActiveTimerCard({super.key});

  @override
  ConsumerState<ActiveTimerCard> createState() => _ActiveTimerCardState();
}

class _ActiveTimerCardState extends ConsumerState<ActiveTimerCard>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runningAsync = ref.watch(runningEntriesProvider);
    final theme = Theme.of(context);

    return runningAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (entries) {
        if (entries.isEmpty) {
          _stopTicker();
          return _buildIdleCard(context, theme);
        }
        _startTicker();
        return _buildRunningCard(context, theme, entries);
      },
    );
  }

  Widget _buildIdleCard(BuildContext context, ThemeData theme) {
    final lastEntryAsync = ref.watch(lastCompletedEntryProvider);
    final lastEntry = lastEntryAsync.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start tracking your time',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        context.push('/time-tracking/clock-in'),
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: const Text('Start Timer'),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: lastEntry != null
                      ? _QuickRepeatButton(
                          entry: lastEntry,
                          onTap: () => _quickClockIn(lastEntry),
                        )
                      : OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.replay, size: 20),
                          label: const Text('Quick Repeat'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunningCard(
      BuildContext context, ThemeData theme, List<TimeEntry> entries) {
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 20),
              _TimerRow(
                entry: entries[i],
                pulseAnimation: _pulseAnimation,
                onClockOut: () => _clockOut(context, entries[i].id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _clockOut(BuildContext context, int entryId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(timerNotifierProvider.notifier).clockOut(entryId);
    } on OverlappingTimeEntryException catch (e) {
      if (!mounted) return;
      final timeFmt = DateFormat.jm();
      final overlap = e.existing;
      final confirmed = await showDialog<bool>(
        context: context, // ignore: use_build_context_synchronously
        builder: (ctx) => AlertDialog(
          title: const Text('Overlapping Entry'),
          content: Text(
            'Clocking out now overlaps with an entry from '
            '${timeFmt.format(overlap.startTime)} - '
            '${timeFmt.format(overlap.endTime!)}.\n\n'
            'Adjust the conflicting entry to make room?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Adjust & Clock Out'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        try {
          await ref
              .read(timerNotifierProvider.notifier)
              .clockOut(entryId, truncateOverlaps: true);
        } catch (e2) {
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text('Error: $e2')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _quickClockIn(TimeEntry lastEntry) async {
    try {
      await ref.read(timerNotifierProvider.notifier).clockIn(
            clientId: lastEntry.clientId,
            projectId: lastEntry.projectId,
            description: lastEntry.description,
            repository: lastEntry.repository,
            issueReference: lastEntry.issueReference,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

/// One running timer row inside the active-timer card.
class _TimerRow extends ConsumerWidget {
  final TimeEntry entry;
  final Animation<double> pulseAnimation;
  final VoidCallback onClockOut;

  const _TimerRow({
    required this.entry,
    required this.pulseAnimation,
    required this.onClockOut,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final clientAsync = ref.watch(clientByIdProvider(entry.clientId));
    final clientName = clientAsync.value?.name;
    final elapsed = DateTime.now().difference(entry.startTime);

    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    final display = h > 0
        ? '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s'
        : '${m}m ${s.toString().padLeft(2, '0')}s';

    final earnings = elapsed.inSeconds / 3600 * entry.hourlyRateSnapshot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: pulsing dot + client name
        Row(
          children: [
            AnimatedBuilder(
              animation: pulseAnimation,
              builder: (_, _) => Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.error
                      .withValues(alpha: pulseAnimation.value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                clientName ?? entry.description ?? 'Timer',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '\$${earnings.toStringAsFixed(2)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer
                    .withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),

        // Elapsed time
        Text(
          display,
          style: theme.textTheme.displaySmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Spacing.md),

        // Clock Out button
        FilledButton(
          onPressed: onClockOut,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: const Text('Clock Out'),
        ),
      ],
    );
  }
}

/// Quick Repeat button that shows the client name.
class _QuickRepeatButton extends ConsumerWidget {
  final TimeEntry entry;
  final VoidCallback onTap;

  const _QuickRepeatButton({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(entry.clientId));
    final clientName =
        clientAsync.whenOrNull(data: (c) => c.name) ?? '...';

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.replay, size: 20),
      label: Text(
        'Repeat: $clientName',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
