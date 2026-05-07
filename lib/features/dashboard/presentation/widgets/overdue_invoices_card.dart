import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../providers/dashboard_provider.dart';

class OverdueInvoicesCard extends ConsumerWidget {
  const OverdueInvoicesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueAsync = ref.watch(overdueInvoicesProvider);
    final theme = Theme.of(context);

    return overdueAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (summary) {
        if (summary.count == 0) return const SizedBox.shrink();
        // Only show when there ARE overdue invoices (warning state)
        return Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 32,
                    color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overdue',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color:
                                theme.colorScheme.onErrorContainer)),
                    Text(
                      formatCurrency(summary.total),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Chip(
                  label: Text('${summary.count}',
                      style: TextStyle(
                          color:
                              theme.colorScheme.onErrorContainer)),
                  backgroundColor: theme.colorScheme.errorContainer,
                  side: BorderSide(
                      color: theme.colorScheme.onErrorContainer
                          .withValues(alpha: 0.3)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
