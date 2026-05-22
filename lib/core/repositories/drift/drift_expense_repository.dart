import '../../database/app_database.dart';
import '../../database/daos/expense_dao.dart';
import '../expense_repository.dart';

class DriftExpenseRepository implements ExpenseRepository {
  final ExpenseDao _dao;
  DriftExpenseRepository(this._dao);

  @override
  Stream<List<Expense>> watchAll() => _dao.watchAll();

  @override
  Future<List<Expense>> getAll() => _dao.getAll();

  @override
  Future<Expense?> getById(String id) => _dao.getById(id);

  @override
  Future<void> insertExpense(ExpensesCompanion companion) =>
      _dao.insertExpense(companion);

  @override
  Future<bool> updateExpense(ExpensesCompanion companion) =>
      _dao.updateExpense(companion);

  @override
  Future<int> deleteExpense(String id) => _dao.deleteExpense(id);
}
