import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/daos/time_entry_dao.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../providers/time_entry_providers.dart';

/// Persistent top notification banner/widget displaying active timer status,
/// live ticking duration, client info, and one-tap clock-out action. (DEV-75)
class TopTimerNotificationWidget extends ConsumerStatefulWidget {
  const TopTimerNotificationWidget({super.key});

  @override
  ConsumerState<TopTimerNotificationWidget> createState() =>
      _TopTimerNotificationWidgetState();
}

class _TopTimerNotificationWidgetState
    extends ConsumerState<TopTimerNotificationWidget>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startTicker();
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatElapsed(DateTime startTime) {
    final diff = DateTime.now().difference(startTime);
    final hours = diff.inHours.toString().padLeft(2, '0');
    final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Future<void> _clockOut(String entryId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(timerNotifierProvider.notifier).clockOut(entryId);
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Clocked out successfully'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on OverlappingTimeEntryException catch (e) {
      if (!mounted) return;
      final timeFmt = DateFormat.jm();
      final overlap = e.existing;
      final confirmed = await showDialog<bool>(
        context: context,
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
            messenger.showSnackBar(SnackBar(content: Text('Error: $e2')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runningAsync = ref.watch(runningEntriesProvider);

    return runningAsync.when(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();

        final primaryEntry = entries.first;
        final clientAsync = ref.watch(clientByIdProvider(primaryEntry.clientId));
        final clientName = clientAsync.whenOrNull(data: (c) => c.name) ?? 'Timer';
        final desc = primaryEntry.description?.trim();
        final hasDesc = desc != null && desc.isNotEmpty;
        final timerText = _formatElapsed(primaryEntry.startTime);
        final multipleRunning = entries.length > 1;

        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Material(
                color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  context.go('/time-tracking');
                },
                child: Ink(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.shadowColor.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        // Pulsing status dot
                        FadeTransition(
                          opacity: _pulseAnimation,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent,
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Timer text & client info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    timerText,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                  if (multipleRunning) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '+${entries.length - 1}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                              color: theme
                                                  .colorScheme.onPrimaryContainer,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                hasDesc ? '$clientName • $desc' : clientName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer
                                      .withValues(alpha: 0.8),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Quick Clock-Out action
                        IconButton.filled(
                          icon: const Icon(Icons.stop, size: 16),
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                            minimumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                          ),
                          tooltip: 'Clock out',
                          onPressed: () => _clockOut(primaryEntry.id),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
