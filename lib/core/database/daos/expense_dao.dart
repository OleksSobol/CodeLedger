import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/expenses_table.dart';

part 'expense_dao.g.dart';

@DriftAccessor(tables: [Expenses])
class ExpenseDao extends DatabaseAccessor<AppDatabase>
    with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  Stream<List<Expense>> watchAll() =>
      (select(db.expenses)..orderBy([(e) => OrderingTerm.asc(e.name)]))
          .watch();

  Future<List<Expense>> getAll() =>
      (select(db.expenses)..orderBy([(e) => OrderingTerm.asc(e.name)])).get();

  Future<void> insertExpense(ExpensesCompanion e) =>
      into(db.expenses).insert(e);

  Future<bool> updateExpense(ExpensesCompanion e) =>
      update(db.expenses).replace(e);

  Future<int> deleteExpense(String id) =>
      (delete(db.expenses)..where((e) => e.id.equals(id))).go();

  Future<Expense?> getById(String id) =>
      (select(db.expenses)..where((e) => e.id.equals(id))).getSingleOrNull();
}

/// Business logic helpers for an [Expense] row.
extension ExpenseCalc on Expense {
  double get deductibleFraction {
    double raw;
    switch (deductionMethod) {
      case 'hours':
        final total = totalHoursPerDay ?? 24.0;
        if (total == 0) return 0;
        raw = (workHoursPerDay ?? 0) / total;
      case 'space':
        final total = totalSpaceSqft ?? 0.0;
        if (total == 0) return 0;
        raw = (workSpaceSqft ?? 0) / total;
      case 'manual':
      default:
        raw = (manualPercentage ?? 0) / 100;
    }
    return raw.clamp(0.0, 1.0);
  }

  double get monthlyAmount =>
      frequency == 'annual' ? amount / 12 : amount;

  double get monthlyDeductible => monthlyAmount * deductibleFraction;

  double get annualDeductible => monthlyDeductible * 12;

  bool isActiveOn(DateTime date) {
    if (date.isBefore(startDate)) return false;
    if (endDate != null && date.isAfter(endDate!)) return false;
    return true;
  }

  bool get isActiveNow => isActiveOn(DateTime.now());
}
