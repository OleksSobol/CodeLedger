import 'package:drift/drift.dart';

/// IRS Schedule C categories for business expenses.
class ExpenseCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get irsScheduleCLine => text()();
  IntColumn get defaultBusinessPct =>
      integer().withDefault(const Constant(100))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Standard Schedule C categories seeded by default.
class DefaultExpenseCategorySeed {
  final String id;
  final String name;
  final String irsScheduleCLine;
  final int defaultBusinessPct;

  const DefaultExpenseCategorySeed({
    required this.id,
    required this.name,
    required this.irsScheduleCLine,
    this.defaultBusinessPct = 100,
  });
}

const kDefaultExpenseCategories = [
  DefaultExpenseCategorySeed(
    id: 'cat_office',
    name: 'Office Expenses',
    irsScheduleCLine: 'Line 18 (Office expense)',
    defaultBusinessPct: 100,
  ),
  DefaultExpenseCategorySeed(
    id: 'cat_supplies',
    name: 'Supplies & Materials',
    irsScheduleCLine: 'Line 22 (Supplies)',
    defaultBusinessPct: 100,
  ),
  DefaultExpenseCategorySeed(
    id: 'cat_hardware',
    name: 'Hardware & Tech (< \$2,500)',
    irsScheduleCLine: 'Line 18 / 22 (De Minimis Safe Harbor)',
    defaultBusinessPct: 100,
  ),
  DefaultExpenseCategorySeed(
    id: 'cat_software',
    name: 'Software & Hosting',
    irsScheduleCLine: 'Line 27a (Other expenses)',
    defaultBusinessPct: 100,
  ),
  DefaultExpenseCategorySeed(
    id: 'cat_travel',
    name: 'Travel & Transport',
    irsScheduleCLine: 'Line 24a (Travel)',
    defaultBusinessPct: 100,
  ),
];

