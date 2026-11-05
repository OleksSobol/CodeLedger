import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/expense_dao.dart';
import '../../../../core/database/daos/expense_transaction_dao.dart';
import '../../../../core/database/tables/expenses_table.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../shared/widgets/app_page_scaffold.dart';
import '../../../export/presentation/providers/export_providers.dart';
import '../providers/expense_providers.dart';
import '../widgets/expense_transaction_tile.dart';

class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _fmt = NumberFormat.currency(symbol: '\$');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onAddPressed() {
    if (_tabController.index == 0) {
      context.push('/expenses/quick-capture');
    } else {
      context.push('/expenses/add');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMonthly = ref.watch(totalMonthlyDeductibleProvider);
    final recurringYearly = ref.watch(thisYearDeductibleProvider);
    final transactionYearly = ref.watch(transactionDeductibleThisYearProvider);
    final combinedYearly = ref.watch(combinedThisYearDeductibleProvider);

    return AppPageScaffold(
      title: 'Expenses',
      actions: [
        IconButton(
          icon: const Icon(Icons.download_outlined),
          onPressed: () => _exportCsv(context),
          tooltip: 'Export CSV',
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: _onAddPressed,
          tooltip: 'Add',
        ),
      ],
      body: Column(
        children: [
          // ── Header Summary Card ──
          _ExpensesSummaryCard(
            totalMonthly: totalMonthly,
            recurringYearly: recurringYearly,
            transactionYearly: transactionYearly,
            combinedYearly: combinedYearly,
            fmt: _fmt,
          ),

          // ── Segmented Tab Selector ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: theme.colorScheme.primary,
              ),
              labelColor: theme.colorScheme.onPrimary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              tabs: const [
                Tab(
                  icon: Icon(Icons.receipt_long_outlined, size: 18),
                  text: 'Transactions',
                ),
                Tab(
                  icon: Icon(Icons.repeat, size: 18),
                  text: 'Recurring Overhead',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Tab Views ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _TransactionsListView(
                  fmt: _fmt,
                  onAdd: () => context.push('/expenses/quick-capture'),
                ),
                _RecurringExpensesListView(
                  fmt: _fmt,
                  onAdd: () => context.push('/expenses/add'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    final service = ref.read(exportServiceProvider);
    try {
      if (_tabController.index == 0) {
        final transactions =
            ref.read(expenseTransactionsProvider).value ?? [];
        if (transactions.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No transactions to export')),
          );
          return;
        }
        final file = await service.generateExpenseTransactionsCsv(
          transactions: transactions,
        );
        if (!context.mounted) return;
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/csv')],
            subject: 'Expense Transactions export',
          ),
        );
      } else {
        final expenses = ref.read(expensesProvider).value ?? [];
        if (expenses.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No recurring expenses to export')),
          );
          return;
        }
        final file = await service.generateExpensesCsv(expenses: expenses);
        if (!context.mounted) return;
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/csv')],
            subject: 'Recurring expenses export',
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}

// ── One-Off Transactions Tab View ──────────────────────────────────────────

class _TransactionsListView extends ConsumerWidget {
  final NumberFormat fmt;
  final VoidCallback onAdd;

  const _TransactionsListView({
    required this.fmt,
    required this.onAdd,
  });

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ExpenseTransactionWithCategory item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: Text('Remove "${item.transaction.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final repo = ref.read(expenseTransactionRepositoryProvider);
      final storage = ref.read(receiptStorageServiceProvider);

      // Remove local image file if present
      await storage.deleteReceipt(item.transaction.receiptPath);
      // Remove DB record
      await repo.deleteTransaction(item.transaction.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(expenseTransactionsProvider);

    return transactionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No one-off transactions yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Snap receipt photos and quickly log one-off purchases\nmapped to Schedule C tax lines.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Quick Capture Expense'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
          itemCount: items.length,
          itemBuilder: (ctx, i) => ExpenseTransactionTile(
            item: items[i],
            fmt: fmt,
            onTap: () => context.push(
              '/expenses/quick-capture',
              extra: items[i],
            ),
            onDelete: () => _delete(ctx, ref, items[i]),
          ),
        );
      },
    );
  }
}

// ── Recurring Overhead Tab View ────────────────────────────────────────────

class _RecurringExpensesListView extends ConsumerWidget {
  final NumberFormat fmt;
  final VoidCallback onAdd;

  const _RecurringExpensesListView({
    required this.fmt,
    required this.onAdd,
  });

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: Text('Remove "${expense.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(expenseRepositoryProvider).deleteExpense(expense.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);

    return expensesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (expenses) => expenses.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.repeat,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No recurring overhead rules',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track recurring office, internet, and utilities\nusing space or hour proration.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Recurring Rule'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              itemCount: expenses.length,
              itemBuilder: (ctx, i) => _ExpenseTile(
                expense: expenses[i],
                fmt: fmt,
                onTap: () => context.push('/expenses/edit', extra: expenses[i]),
                onDelete: () => _delete(ctx, ref, expenses[i]),
              ),
            ),
    );
  }
}

// ── Summary Card ───────────────────────────────────────────────────────────

class _ExpensesSummaryCard extends StatelessWidget {
  final double totalMonthly;
  final double recurringYearly;
  final double transactionYearly;
  final double combinedYearly;
  final NumberFormat fmt;

  const _ExpensesSummaryCard({
    required this.totalMonthly,
    required this.recurringYearly,
    required this.transactionYearly,
    required this.combinedYearly,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateTime.now().year} Total Deductible',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fmt.format(combinedYearly),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Monthly Overhead',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    '${fmt.format(totalMonthly)}/mo',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Receipts YTD: ${fmt.format(transactionYearly)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer.withValues(
                    alpha: 0.85,
                  ),
                ),
              ),
              Text(
                'Overhead YTD: ${fmt.format(recurringYearly)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer.withValues(
                    alpha: 0.85,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Existing Recurring Expense Tile ─────────────────────────────────────────

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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
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
            fontWeight: FontWeight.w600,
            color: isActive ? null : theme.colorScheme.outline,
          ),
        ),
        subtitle: Text(
          '$label · $pct% deductible',
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
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
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
