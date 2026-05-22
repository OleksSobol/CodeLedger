import '../database/app_database.dart';

abstract class ExpenseRepository {
  Stream<List<Expense>> watchAll();
  Future<List<Expense>> getAll();
  Future<Expense?> getById(String id);
  Future<void> insertExpense(ExpensesCompanion companion);
  Future<bool> updateExpense(ExpensesCompanion companion);
  Future<int> deleteExpense(String id);
}
