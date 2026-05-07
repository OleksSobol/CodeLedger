import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/time_tracking/presentation/providers/time_entry_providers.dart';
import '../../../features/time_tracking/presentation/widgets/clock_in_sheet.dart';

class ShellScaffold extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      floatingActionButton: _buildFab(context, ref, currentIndex),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Time',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Invoices',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget? _buildFab(BuildContext context, WidgetRef ref, int index) {
    final theme = Theme.of(context);
    switch (index) {
      case 0:
        // Home: context-aware — Clock Out if running, Start Timer if idle
        final running = ref.watch(runningEntryProvider);
        final runningEntry = running.value;
        if (runningEntry != null) {
          return FloatingActionButton.extended(
            onPressed: () => _clockOut(context, ref, runningEntry.id),
            icon: const Icon(Icons.stop),
            label: const Text('Clock Out'),
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          );
        }
        return FloatingActionButton.extended(
          onPressed: () => context.push('/time-tracking/clock-in'),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Timer'),
        );
      case 1:
        // Time tab: context-aware — Clock Out if running, Clock In if idle
        final timeRunning = ref.watch(runningEntryProvider);
        final timeRunningEntry = timeRunning.value;
        if (timeRunningEntry != null) {
          return FloatingActionButton.extended(
            onPressed: () =>
                _clockOut(context, ref, timeRunningEntry.id),
            icon: const Icon(Icons.stop),
            label: const Text('Clock Out'),
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          );
        }
        return FloatingActionButton.extended(
          onPressed: () => ClockInSheet.show(context),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Clock In'),
        );
      case 2:
        // Invoices: New Invoice
        return FloatingActionButton.extended(
          onPressed: () => context.push('/invoices/create'),
          icon: const Icon(Icons.add),
          label: const Text('New Invoice'),
        );
      default:
        return null;
    }
  }

  Future<void> _clockOut(
      BuildContext context, WidgetRef ref, int entryId) async {
    try {
      await ref.read(timerNotifierProvider.notifier).clockOut(entryId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
