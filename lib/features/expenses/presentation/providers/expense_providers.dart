import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/expense_dao.dart';
import '../../../../core/database/daos/expense_transaction_dao.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../data/receipt_storage_service.dart';

final receiptStorageServiceProvider = Provider<ReceiptStorageService>((ref) {
  return ReceiptStorageService();
});

final expenseTransactionsProvider =
    StreamProvider<List<ExpenseTransactionWithCategory>>((ref) {
  return ref.watch(expenseTransactionRepositoryProvider).watchAllWithCategory();
});

final expenseCategoriesProvider = StreamProvider<List<ExpenseCategory>>((ref) {
  return ref.watch(expenseTransactionRepositoryProvider).watchCategories();
});

final transactionDeductibleThisYearProvider = Provider<double>((ref) {
  final transactions = ref.watch(expenseTransactionsProvider).value ?? [];
  final currentYear = DateTime.now().year;
  return transactions
      .where((t) => t.transaction.date.year == currentYear)
      .fold(0.0, (sum, t) => sum + t.deductibleAmount);
});

final expensesProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchAll();
});

final activeExpensesProvider = Provider<List<Expense>>((ref) {
  final all = ref.watch(expensesProvider).value ?? [];
  return all.where((e) => e.isActiveNow).toList();
});

final totalMonthlyDeductibleProvider = Provider<double>((ref) {
  return ref
      .watch(activeExpensesProvider)
      .fold(0.0, (sum, e) => sum + e.monthlyDeductible);
});

/// Deductible for the current calendar year across ALL expenses (active or not),
/// prorated to only the months each expense overlaps with the year.
final thisYearDeductibleProvider = Provider<double>((ref) {
  final all = ref.watch(expensesProvider).value ?? [];
  return annualDeductibleForYear(all, DateTime.now().year);
});

/// Annual deductible for a given calendar year across all active expenses.
double annualDeductibleForYear(List<Expense> expenses, int year) {
  double total = 0;
  final start = DateTime(year, 1, 1);
  final end = DateTime(year, 12, 31);
  for (final e in expenses) {
    final effectiveStart = e.startDate.isAfter(start) ? e.startDate : start;
    final effectiveEnd = (e.endDate != null && e.endDate!.isBefore(end))
        ? e.endDate!
        : end;
    if (effectiveStart.isAfter(effectiveEnd)) continue;
    final months =
        (effectiveEnd.year - effectiveStart.year) * 12 +
        effectiveEnd.month -
        effectiveStart.month +
        1;
    total += e.monthlyDeductible * months;
  }
  return total;
}

final combinedThisYearDeductibleProvider = Provider<double>((ref) {
  final recurring = ref.watch(thisYearDeductibleProvider);
  final transactions = ref.watch(transactionDeductibleThisYearProvider);
  return recurring + transactions;
});
