import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../profile/presentation/providers/profile_provider.dart';
import '../providers/dashboard_provider.dart';

class ContextHeader extends ConsumerWidget {
  const ContextHeader({super.key});

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static IconData _themeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light => Icons.light_mode,
        ThemeMode.dark => Icons.dark_mode,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(profileProvider);
    final weeklyAsync = ref.watch(weeklyHoursProvider);
    final overdueAsync = ref.watch(overdueInvoicesProvider);
    final themeMode =
        ref.watch(themeModeProvider).value ?? ThemeMode.system;

    final name = profileAsync.whenOrNull(
      data: (p) =>
          p.ownerName.isNotEmpty ? p.ownerName : p.businessName,
    );
    final overdueCount =
        overdueAsync.whenOrNull(data: (v) => v.count) ?? 0;
    final weeklyHours =
        weeklyAsync.whenOrNull(data: (v) => v) ?? 0.0;

    final dateStr = DateFormat('EEEE, MMM d, yyyy').format(DateTime.now());

    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      floating: false,
      title: const Text('CodeLedger'),
      actions: [
        IconButton(
          icon: Icon(_themeIcon(themeMode)),
          tooltip: 'Theme: ${themeMode.name}',
          onPressed: () {
            final next = switch (themeMode) {
              ThemeMode.system => ThemeMode.light,
              ThemeMode.light => ThemeMode.dark,
              ThemeMode.dark => ThemeMode.system,
            };
            ref.read(themeModeProvider.notifier).setThemeMode(next);
          },
        ),
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Business Profile',
              onPressed: () => context.push('/profile'),
            ),
            if (overdueCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
                left: 16, right: 16, top: 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name != null && name.isNotEmpty
                      ? '${_greeting()}, $name'
                      : _greeting(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${weeklyHours.toStringAsFixed(1)}h this week',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
