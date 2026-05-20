import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../../database/daos/time_entry_dao.dart';
import '../time_entry_repository.dart';

class DriftTimeEntryRepository implements TimeEntryRepository {
  final TimeEntryDao _dao;
  final AppDatabase _db;
  DriftTimeEntryRepository(this._dao, this._db);

  @override Future<TimeEntry?> getRunningEntry() => _dao.getRunningEntry();
  @override Stream<TimeEntry?> watchRunningEntry() => _dao.watchRunningEntry();
  @override Stream<List<TimeEntry>> watchAllRunningEntries() => _dao.watchAllRunningEntries();
  @override Future<List<TimeEntry>> getAllRunningEntries() => _dao.getAllRunningEntries();
  @override Future<String> insertWithOverlapCheck(TimeEntriesCompanion e) => _dao.insertWithOverlapCheck(e);
  @override Future<bool> clockOut(String id, {String? description, bool truncateOverlaps = false}) =>
      _dao.clockOut(id, description: description, truncateOverlaps: truncateOverlaps);
  @override Future<bool> updateWithOverlapCheck(String id, TimeEntriesCompanion c) => _dao.updateWithOverlapCheck(id, c);
  @override Stream<List<TimeEntry>> watchEntriesForDateRange(DateTime s, DateTime e) => _dao.watchEntriesForDateRange(s, e);
  @override Future<List<TimeEntry>> getUninvoicedForClient(String id) => _dao.getUninvoicedForClient(id);
  @override Future<List<TimeEntry>> getUninvoicedForProject(String id) => _dao.getUninvoicedForProject(id);
  @override Future<TimeEntry?> getMostRecentCompleted() => _dao.getMostRecentCompleted();
  @override Future<int> updateRateForClient(String id, double rate) => _dao.updateRateForClient(id, rate);
  @override Future<int> countUninvoicedAtRate(String id, double rate) => _dao.countUninvoicedAtRate(id, rate);
  @override Future<Set<String>> getAllTags() => _dao.getAllTags();
  @override Future<void> markAsInvoiced(List<String> ids, String invoiceId) => _dao.markAsInvoiced(ids, invoiceId);
  @override Future<void> unmarkInvoiced(String invoiceId) => _dao.unmarkInvoiced(invoiceId);
  @override Future<List<TimeEntry>> getAllEntries({DateTime? from, DateTime? to, String? clientId, String? projectId}) =>
      _dao.getAllEntries(from: from, to: to, clientId: clientId, projectId: projectId);

  @override
  Future<void> deleteEntry(String entryId) =>
      (_db.delete(_db.timeEntries)..where((t) => t.id.equals(entryId))).go();

  @override
  Future<bool> updateEntry(String entryId, TimeEntriesCompanion companion) =>
      (_db.update(_db.timeEntries)..where((t) => t.id.equals(entryId)))
          .write(companion.copyWith(updatedAt: Value(DateTime.now())))
          .then((rows) => rows > 0);
}
