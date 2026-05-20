import 'package:drift/drift.dart';
import 'clients_table.dart';

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  RealColumn get hourlyRateOverride => real().nullable()();
  IntColumn get color => integer().withDefault(const Constant(0xFF2196F3))();
  TextColumn get githubRepo => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isArchived =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {clientId, name}
      ];
}
