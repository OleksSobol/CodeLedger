import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../tables/clients_table.dart';
import '../tables/time_entries_table.dart';
import '../tables/invoices_table.dart';

part 'client_dao.g.dart';

@DriftAccessor(tables: [Clients, TimeEntries, Invoices])
class ClientDao extends DatabaseAccessor<AppDatabase>
    with _$ClientDaoMixin {
  ClientDao(super.db);

  Stream<List<Client>> watchAllClients() {
    return (select(clients)
          ..orderBy([
            (t) => OrderingTerm.asc(t.isArchived),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  Stream<List<Client>> watchActiveClients() {
    return (select(clients)
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<List<Client>> getActiveClients() {
    return (select(clients)
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<Client> getClient(String id) {
    return (select(clients)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<String> insertClient(ClientsCompanion companion) async {
    const uuid = Uuid();
    final id = uuid.v4();
    await into(clients).insert(companion.copyWith(id: Value(id)));
    return id;
  }

  Future<bool> updateClient(String id, ClientsCompanion companion) {
    return (update(clients)..where((t) => t.id.equals(id)))
        .write(companion.copyWith(updatedAt: Value(DateTime.now())))
        .then((rows) => rows > 0);
  }

  Future<bool> archiveClient(String id) {
    return updateClient(
      id,
      const ClientsCompanion(isArchived: Value(true)),
    );
  }

  Future<bool> hasLinkedRecords(String clientId) async {
    final entryCount = await (select(timeEntries)
          ..where((t) => t.clientId.equals(clientId))
          ..limit(1))
        .get();
    if (entryCount.isNotEmpty) return true;
    final invoiceCount = await (select(invoices)
          ..where((t) => t.clientId.equals(clientId))
          ..limit(1))
        .get();
    return invoiceCount.isNotEmpty;
  }

  Future<int> deleteClient(String id) {
    return (delete(clients)..where((t) => t.id.equals(id))).go();
  }

  Future<double> getUninvoicedHours(String clientId) async {
    final query = select(timeEntries)
      ..where((t) =>
          t.clientId.equals(clientId) &
          t.isInvoiced.equals(false) &
          t.endTime.isNotNull());
    final entries = await query.get();
    return entries.fold<double>(
        0, (sum, e) => sum + (e.durationMinutes ?? 0) / 60.0);
  }

  Future<double> getTotalBilled(String clientId) async {
    final query = select(invoices)
      ..where((t) => t.clientId.equals(clientId));
    final inv = await query.get();
    return inv.fold<double>(0, (sum, i) => sum + i.total);
  }

  Future<double> getTotalPaid(String clientId) async {
    final query = select(invoices)
      ..where((t) =>
          t.clientId.equals(clientId) & t.status.equals('paid'));
    final inv = await query.get();
    return inv.fold<double>(0, (sum, i) => sum + i.amountPaid);
  }
}
