import '../../database/app_database.dart';
import '../../database/daos/expense_transaction_dao.dart';
import '../expense_transaction_repository.dart';

class DriftExpenseTransactionRepository
    implements ExpenseTransactionRepository {
  final ExpenseTransactionDao _dao;

  DriftExpenseTransactionRepository(this._dao);

  @override
  Stream<List<ExpenseTransactionWithCategory>> watchAllWithCategory() =>
      _dao.watchAllWithCategory();

  @override
  Future<List<ExpenseTransactionWithCategory>> getAllWithCategory() =>
      _dao.getAllWithCategory();

  @override
  Stream<List<ExpenseCategory>> watchCategories() => _dao.watchCategories();

  @override
  Future<List<ExpenseCategory>> getAllCategories() => _dao.getAllCategories();

  @override
  Future<ExpenseTransactionWithCategory?> getById(String id) =>
      _dao.getTransactionWithCategoryById(id);

  @override
  Future<void> insertTransaction(ExpenseTransactionsCompanion companion) =>
      _dao.insertTransaction(companion);

  @override
  Future<bool> updateTransaction(ExpenseTransactionsCompanion companion) =>
      _dao.updateTransaction(companion);

  @override
  Future<int> deleteTransaction(String id) => _dao.deleteTransaction(id);
}

