import 'package:drift/drift.dart';

/// Recurring business expenses for tax deduction tracking.
///
/// Deduction methods:
///   'manual' — user enters a fixed percentage
///   'hours'  — workHoursPerDay / totalHoursPerDay
///   'space'  — workSpaceSqft / totalSpaceSqft
///
/// Frequency:
///   'monthly' — amount is per month
///   'annual'  — amount is per year (divided by 12 for monthly equivalent)
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category =>
      text().withDefault(const Constant('other'))(); // see kExpenseCategories
  RealColumn get amount => real()();
  TextColumn get frequency =>
      text().withDefault(const Constant('monthly'))(); // monthly | annual
  TextColumn get deductionMethod =>
      text().withDefault(const Constant('manual'))(); // manual | hours | space
  RealColumn get manualPercentage => real().nullable()(); // 0–100
  RealColumn get workHoursPerDay => real().nullable()();
  RealColumn get totalHoursPerDay => real().nullable()(); // defaults to 24
  RealColumn get workSpaceSqft => real().nullable()();
  RealColumn get totalSpaceSqft => real().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

const kExpenseCategories = [
  'internet',
  'rent',
  'software',
  'phone',
  'equipment',
  'utilities',
  'other',
];

const kExpenseCategoryLabels = {
  'internet': 'Internet',
  'rent': 'Rent / Home Office',
  'software': 'Software & Subscriptions',
  'phone': 'Phone',
  'equipment': 'Equipment & Hardware',
  'utilities': 'Utilities',
  'other': 'Other',
};
