import 'package:drift/drift.dart';
import 'invoices_table.dart';
import 'time_entries_table.dart';
import 'projects_table.dart';

class InvoiceLineItems extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceId => text().references(Invoices, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get description => text()();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get total => real()();
  TextColumn get timeEntryId =>
      text().nullable().references(TimeEntries, #id)();
  TextColumn get projectId =>
      text().nullable().references(Projects, #id)();
  TextColumn get issueReference => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
