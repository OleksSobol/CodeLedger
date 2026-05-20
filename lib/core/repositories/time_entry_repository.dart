import '../database/app_database.dart';
export '../database/daos/time_entry_dao.dart' show OverlappingTimeEntryException;

abstract class TimeEntryRepository {
  Future<TimeEntry?> getRunningEntry();
  Stream<TimeEntry?> watchRunningEntry();
  Stream<List<TimeEntry>> watchAllRunningEntries();
  Future<List<TimeEntry>> getAllRunningEntries();
  Future<String> insertWithOverlapCheck(TimeEntriesCompanion entry);
  Future<bool> clockOut(String entryId, {String? description, bool truncateOverlaps});
  Future<bool> updateWithOverlapCheck(String entryId, TimeEntriesCompanion companion);
  Stream<List<TimeEntry>> watchEntriesForDateRange(DateTime start, DateTime end);
  Future<List<TimeEntry>> getUninvoicedForClient(String clientId);
  Future<List<TimeEntry>> getUninvoicedForProject(String projectId);
  Future<TimeEntry?> getMostRecentCompleted();
  Future<int> updateRateForClient(String clientId, double newRate);
  Future<int> countUninvoicedAtRate(String clientId, double rate);
  Future<Set<String>> getAllTags();
  Future<void> markAsInvoiced(List<String> entryIds, String invoiceId);
  Future<void> unmarkInvoiced(String invoiceId);
  Future<List<TimeEntry>> getAllEntries({DateTime? from, DateTime? to, String? clientId, String? projectId});
  Future<void> deleteEntry(String entryId);
  Future<bool> updateEntry(String entryId, TimeEntriesCompanion companion);
}
