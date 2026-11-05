import 'package:drift/drift.dart';
import 'expense_categories_table.dart';

/// Transactional one-off business purchases (receipts, hardware, subscriptions).
class ExpenseTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get vendor => text().nullable()();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get categoryId => text().references(ExpenseCategories, #id)();
  IntColumn get businessUsePct => integer().withDefault(const Constant(100))();
  RealColumn get deductibleAmount =>
      real().withDefault(const Constant(0.0))();
  TextColumn get receiptPath => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

