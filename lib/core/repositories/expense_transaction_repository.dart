import '../database/app_database.dart';
import '../database/daos/expense_transaction_dao.dart';

abstract class ExpenseTransactionRepository {
  Stream<List<ExpenseTransactionWithCategory>> watchAllWithCategory();
  Future<List<ExpenseTransactionWithCategory>> getAllWithCategory();
  Stream<List<ExpenseCategory>> watchCategories();
  Future<List<ExpenseCategory>> getAllCategories();
  Future<ExpenseTransactionWithCategory?> getById(String id);
  Future<void> insertTransaction(ExpenseTransactionsCompanion companion);
  Future<bool> updateTransaction(ExpenseTransactionsCompanion companion);
  Future<int> deleteTransaction(String id);
}

