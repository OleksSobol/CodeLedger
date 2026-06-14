import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/expenses_table.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../shared/widgets/app_page_scaffold.dart';
import '../../../export/presentation/providers/export_providers.dart';
import '../providers/expense_providers.dart';

class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);
    final totalMonthly = ref.watch(totalMonthlyDeductibleProvider);
    final thisYearDeductible = ref.watch(thisYearDeductibleProvider);
    final fmt = NumberFormat.currency(symbol: '\$');

    return AppPageScaffold(
      title: 'Expenses',
      actions: [
        IconButton(
          icon: const Icon(Icons.download_outlined),
          onPressed: () => _exportCsv(context, ref),
          tooltip: 'Export CSV',
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => context.push('/expenses/add'),
          tooltip: 'Add Expense',
        ),
      ],
      body: Column(
        children: [
          _SummaryCard(
              totalMonthly: totalMonthly,
              yearlyDeductible: thisYearDeductible,
              fmt: fmt),
          Expanded(
            child: expensesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: \$e')),
              data: (expenses) => expenses.isEmpty
                  ? _EmptyState(onAdd: () => context.push('/expenses/add'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: expenses.length,
                      itemBuilder: (ctx, i) => _ExpenseTile(
                        expense: expenses[i],
                        fmt: fmt,
                        onTap: () =>
                            context.push('/expenses/edit', extra: expenses[i]),
                        onDelete: () => _delete(ctx, ref, expenses[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final expenses = ref.read(expensesProvider).value ?? [];
    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No expenses to export')),
      );
      return;
    }
    try {
      final service = ref.read(exportServiceProvider);
      final file = await service.generateExpensesCsv(expenses: expenses);
      if (!context.mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Expenses export',
      ));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: Text('Remove "\${expense.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('Delete', style: TextStyle(color: Colors.red.shade400))),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(expenseRepositoryProvider).deleteExpense(expense.id);
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final double totalMonthly;
  final double yearlyDeductible;
  final NumberFormat fmt;

  const _SummaryCard({
    required this.totalMonthly,
    required this.yearlyDeductible,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly deductible',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fmt.format(totalMonthly),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'This year',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              Text(
                fmt.format(yearlyDeductible),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final Expense expense;
  final NumberFormat fmt;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ExpenseTile({
    required this.expense,
    required this.fmt,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = expense.isActiveNow;
    final pct = (expense.deductibleFraction * 100).toStringAsFixed(0);
    final label = kExpenseCategoryLabels[expense.category] ?? 'Other';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            _categoryIcon(expense.category),
            size: 20,
            color: isActive
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.outline,
          ),
        ),
        title: Text(
          expense.name,
          style: theme.textTheme.titleSmall?.copyWith(
            color: isActive ? null : theme.colorScheme.outline,
          ),
        ),
        subtitle: Text(
          '\$label · \$pct% deductible',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmt.format(expense.monthlyDeductible),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color:
                    isActive ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
            ),
            Text(
              '/mo',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        onTap: onTap,
        onLongPress: onDelete,
      ),
    );
  }

  IconData _categoryIcon(String category) => switch (category) {
        'internet' => Icons.wifi,
        'rent' => Icons.home_outlined,
        'software' => Icons.apps_outlined,
        'phone' => Icons.phone_outlined,
        'equipment' => Icons.computer_outlined,
        'utilities' => Icons.bolt_outlined,
        _ => Icons.receipt_outlined,
      };
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.savings_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('No expenses yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 8),
          Text(
            'Track recurring business expenses\nfor tax deduction.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Expense'),
          ),
        ],
      ),
    );
  }
}
