import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../providers/dashboard_provider.dart';

class MonthlyIncomeCard extends ConsumerWidget {
  const MonthlyIncomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incomeAsync = ref.watch(monthlyIncomeProvider);
    final theme = Theme.of(context);
    final monthName = DateFormat.MMMM().format(DateTime.now());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.trending_up,
                size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$monthName Income',
                    style: theme.textTheme.labelMedium),
                incomeAsync.when(
                  loading: () => Text('...',
                      style: theme.textTheme.headlineSmall),
                  error: (_, _) => Text('--',
                      style: theme.textTheme.headlineSmall),
                  data: (income) => Text(
                    formatCurrency(income),
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
