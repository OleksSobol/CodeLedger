import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/expense_categories_table.dart';
import '../tables/expense_transactions_table.dart';

part 'expense_transaction_dao.g.dart';

class ExpenseTransactionWithCategory {
  final ExpenseTransaction transaction;
  final ExpenseCategory category;

  const ExpenseTransactionWithCategory({
    required this.transaction,
    required this.category,
  });

  double get deductibleAmount => transaction.deductibleAmount > 0
      ? transaction.deductibleAmount
      : double.parse(
          (transaction.amount * (transaction.businessUsePct / 100.0))
              .toStringAsFixed(2),
        );
}

@DriftAccessor(tables: [ExpenseTransactions, ExpenseCategories])
class ExpenseTransactionDao extends DatabaseAccessor<AppDatabase>
    with _$ExpenseTransactionDaoMixin {
  ExpenseTransactionDao(super.db);

  Stream<List<ExpenseTransactionWithCategory>> watchAllWithCategory() {
    final query = select(db.expenseTransactions).join([
      innerJoin(
        db.expenseCategories,
        db.expenseCategories.id.equalsExp(db.expenseTransactions.categoryId),
      ),
    ])..orderBy([
      OrderingTerm.desc(db.expenseTransactions.date),
      OrderingTerm.desc(db.expenseTransactions.createdAt),
    ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return ExpenseTransactionWithCategory(
          transaction: row.readTable(db.expenseTransactions),
          category: row.readTable(db.expenseCategories),
        );
      }).toList();
    });
  }

  Future<List<ExpenseTransactionWithCategory>> getAllWithCategory() async {
    final query = select(db.expenseTransactions).join([
      innerJoin(
        db.expenseCategories,
        db.expenseCategories.id.equalsExp(db.expenseTransactions.categoryId),
      ),
    ])..orderBy([
      OrderingTerm.desc(db.expenseTransactions.date),
      OrderingTerm.desc(db.expenseTransactions.createdAt),
    ]);

    final rows = await query.get();
    return rows.map((row) {
      return ExpenseTransactionWithCategory(
        transaction: row.readTable(db.expenseTransactions),
        category: row.readTable(db.expenseCategories),
      );
    }).toList();
  }

  Stream<List<ExpenseCategory>> watchCategories() {
    return (select(db.expenseCategories)
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<List<ExpenseCategory>> getAllCategories() {
    return (select(db.expenseCategories)
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
  }

  Future<ExpenseCategory?> getCategoryById(String id) {
    return (select(db.expenseCategories)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertTransaction(ExpenseTransactionsCompanion t) {
    return into(db.expenseTransactions).insert(t);
  }

  Future<bool> updateTransaction(ExpenseTransactionsCompanion t) {
    return update(db.expenseTransactions).replace(t);
  }

  Future<int> deleteTransaction(String id) {
    return (delete(db.expenseTransactions)..where((t) => t.id.equals(id))).go();
  }

  Future<ExpenseTransactionWithCategory?> getTransactionWithCategoryById(
    String id,
  ) async {
    final query = select(db.expenseTransactions).join([
      innerJoin(
        db.expenseCategories,
        db.expenseCategories.id.equalsExp(db.expenseTransactions.categoryId),
      ),
    ])..where(db.expenseTransactions.id.equals(id));

    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return ExpenseTransactionWithCategory(
      transaction: row.readTable(db.expenseTransactions),
      category: row.readTable(db.expenseCategories),
    );
  }
}

