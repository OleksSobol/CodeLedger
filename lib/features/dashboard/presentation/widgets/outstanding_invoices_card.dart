import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../providers/dashboard_provider.dart';

class OutstandingInvoicesCard extends ConsumerWidget {
  const OutstandingInvoicesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outstandingAsync = ref.watch(outstandingInvoicesProvider);
    final theme = Theme.of(context);

    return outstandingAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (summary) {
        if (summary.count == 0) {
          return Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline,
                  color: theme.colorScheme.secondary),
              title: const Text('No outstanding invoices'),
              subtitle: const Text('All sent invoices have been paid'),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.send_outlined,
                    size: 32, color: theme.colorScheme.secondary),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Outstanding',
                        style: theme.textTheme.labelMedium),
                    Text(
                      formatCurrency(summary.total),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Spacer(),
                Chip(
                  label: Text('${summary.count}'),
                  backgroundColor:
                      theme.colorScheme.secondaryContainer,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
