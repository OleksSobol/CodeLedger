import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../invoices/presentation/providers/invoice_providers.dart';
import '../providers/dashboard_provider.dart';

/// Horizontally scrollable financial insight tiles.
class FinancialSummaryRow extends ConsumerWidget {
  const FinancialSummaryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final monthName = DateFormat.MMMM().format(DateTime.now());

    final incomeAsync = ref.watch(monthlyIncomeProvider);
    final outstandingAsync = ref.watch(outstandingInvoicesProvider);
    final overdueAsync = ref.watch(overdueInvoicesProvider);
    final uninvoicedAsync = ref.watch(uninvoicedByClientProvider);

    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        clipBehavior: Clip.none,
        children: [
          _InsightTile(
            label: '$monthName Income',
            value: incomeAsync.when(
              loading: () => '...',
              error: (_, __) => '--',
              data: (v) => formatCurrency(v),
            ),
            icon: Icons.trending_up,
            accentColor: theme.colorScheme.primary,
            onTap: () => context.push('/reports'),
          ),
          _InsightTile(
            label: 'Outstanding',
            value: outstandingAsync.when(
              loading: () => '...',
              error: (_, __) => '--',
              data: (v) => v.count == 0 ? 'None' : formatCurrency(v.total),
            ),
            icon: Icons.send_outlined,
            accentColor: theme.colorScheme.secondary,
            badge: outstandingAsync.whenOrNull(
                data: (v) => v.count > 0 ? '${v.count}' : null),
            onTap: () {
              ref.read(invoiceStatusFilterProvider.notifier).set('sent');
              context.go('/invoices');
            },
          ),
          _InsightTile(
            label: 'Overdue',
            value: overdueAsync.when(
              loading: () => '...',
              error: (_, __) => '--',
              data: (v) => v.count == 0 ? 'None' : formatCurrency(v.total),
            ),
            icon: overdueAsync.whenOrNull(
                    data: (v) => v.count > 0
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline) ??
                Icons.warning_amber_rounded,
            accentColor: overdueAsync.whenOrNull(
                    data: (v) =>
                        v.count > 0 ? theme.colorScheme.error : null) ??
                theme.colorScheme.tertiary,
            badge: overdueAsync.whenOrNull(
                data: (v) => v.count > 0 ? '${v.count}' : null),
            onTap: () {
              ref.read(invoiceStatusFilterProvider.notifier).set('overdue');
              context.go('/invoices');
            },
          ),
          _InsightTile(
            label: 'Uninvoiced',
            value: uninvoicedAsync.when(
              loading: () => '...',
              error: (_, __) => '--',
              data: (items) {
                final totalHours =
                    items.fold<double>(0, (sum, i) => sum + i.hours);
                return totalHours > 0
                    ? '${totalHours.toStringAsFixed(1)}h'
                    : 'All clear';
              },
            ),
            icon: uninvoicedAsync.whenOrNull(
                    data: (items) {
                      final h = items.fold<double>(0, (s, i) => s + i.hours);
                      return h > 0
                          ? Icons.hourglass_empty
                          : Icons.check_circle_outline;
                    }) ??
                Icons.hourglass_empty,
            accentColor: theme.colorScheme.tertiary,
            onTap: () => context.push('/invoices/create'),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final String? badge;
  final VoidCallback? onTap;

  const _InsightTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: SizedBox(
        width: 175,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Row(
              children: [
                Container(width: 4, color: accentColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm + 4, vertical: Spacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 14, color: accentColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (badge != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: accentColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  badge!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 10,
                                    color: theme.colorScheme.surface,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: Spacing.xs),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontFeatures: [
                                const FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ),
                      ],
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
