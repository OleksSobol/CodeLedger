import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/time_entries_table.dart';
import '../../utils/tag_utils.dart';

part 'time_entry_dao.g.dart';

@DriftAccessor(tables: [TimeEntries])
class TimeEntryDao extends DatabaseAccessor<AppDatabase>
    with _$TimeEntryDaoMixin {
  TimeEntryDao(super.db);

  /// Check if there's a currently running timer (end_time is null).
  Future<TimeEntry?> getRunningEntry() async {
    final query = select(timeEntries)
      ..where((t) => t.endTime.isNull())
      ..limit(1);
    final results = await query.get();
    return results.isEmpty ? null : results.first;
  }

  Stream<TimeEntry?> watchRunningEntry() {
    return (select(timeEntries)
          ..where((t) => t.endTime.isNull())
          ..limit(1))
        .watchSingleOrNull();
  }

  Stream<List<TimeEntry>> watchAllRunningEntries() {
    return (select(timeEntries)
          ..where((t) => t.endTime.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.startTime)]))
        .watch();
  }

  Future<List<TimeEntry>> getAllRunningEntries() {
    return (select(timeEntries)..where((t) => t.endTime.isNull())).get();
  }

  /// Insert a time entry with overlap check (in a transaction).
  Future<int> insertWithOverlapCheck(TimeEntriesCompanion entry) {
    return transaction(() async {
      final start = entry.startTime.value;
      final end = entry.endTime.value;
      final clientId =
          entry.clientId.present ? entry.clientId.value : null;

      if (end != null) {
        final overlapping =
            await _findOverlapping(start, end, clientId: clientId);
        if (overlapping.isNotEmpty) {
          throw OverlappingTimeEntryException(overlapping.first);
        }
      }
      return into(timeEntries).insert(entry);
    });
  }

  /// Clock out the running entry.
  /// If [truncateOverlaps] is true, overlapping entries will be adjusted
  /// (shortened or deleted) instead of throwing an exception.
  Future<bool> clockOut(
    int entryId, {
    String? description,
    bool truncateOverlaps = false,
  }) {
    final now = DateTime.now();
    return transaction(() async {
      final entry =
          await (select(timeEntries)..where((t) => t.id.equals(entryId)))
              .getSingle();
      final duration = now.difference(entry.startTime).inMinutes;

      // Check for overlaps with the new end time (same client only)
      final overlapping = await _findOverlapping(
        entry.startTime,
        now,
        excludeId: entryId,
        clientId: entry.clientId,
      );
      if (overlapping.isNotEmpty) {
        if (!truncateOverlaps) {
          throw OverlappingTimeEntryException(overlapping.first);
        }
        // Resolve overlaps by adjusting or deleting conflicting entries
        await _resolveOverlaps(overlapping, entry.startTime, now);
      }

      return (update(timeEntries)..where((t) => t.id.equals(entryId)))
          .write(TimeEntriesCompanion(
            endTime: Value(now),
            durationMinutes: Value(duration),
            description:
                description != null ? Value(description) : const Value.absent(),
            updatedAt: Value(now),
          ))
          .then((rows) => rows > 0);
    });
  }

  /// Update a time entry's times/details with overlap check.
  Future<bool> updateWithOverlapCheck(
    int entryId,
    TimeEntriesCompanion companion,
  ) {
    return transaction(() async {
      final start = companion.startTime;
      final end = companion.endTime;

      // Fetch existing entry once so we always have clientId + current times
      final existing =
          await (select(timeEntries)..where((t) => t.id.equals(entryId)))
              .getSingle();
      final clientId = existing.clientId;

      // If both start and end are being set, check overlaps
      if (start.present && end.present && end.value != null) {
        final overlapping = await _findOverlapping(
          start.value,
          end.value!,
          excludeId: entryId,
          clientId: clientId,
        );
        if (overlapping.isNotEmpty) {
          throw OverlappingTimeEntryException(overlapping.first);
        }
      } else if (end.present && end.value != null) {
        // Only end is changing — use existing start
        final overlapping = await _findOverlapping(
          existing.startTime,
          end.value!,
          excludeId: entryId,
          clientId: clientId,
        );
        if (overlapping.isNotEmpty) {
          throw OverlappingTimeEntryException(overlapping.first);
        }
      } else if (start.present) {
        // Only start is changing — use existing end
        if (existing.endTime != null) {
          final overlapping = await _findOverlapping(
            start.value,
            existing.endTime!,
            excludeId: entryId,
            clientId: clientId,
          );
          if (overlapping.isNotEmpty) {
            throw OverlappingTimeEntryException(overlapping.first);
          }
        }
      }

      final updated = companion.copyWith(updatedAt: Value(DateTime.now()));
      return (update(timeEntries)..where((t) => t.id.equals(entryId)))
          .write(updated)
          .then((rows) => rows > 0);
    });
  }

  /// Find overlapping entries for a given time range.
  /// Only entries for the same [clientId] are considered overlapping —
  /// concurrent work for different clients is allowed.
  Future<List<TimeEntry>> _findOverlapping(
    DateTime start,
    DateTime end, {
    int? excludeId,
    int? clientId,
  }) {
    final query = select(timeEntries)
      ..where((t) {
        // Overlap: existing.start < new.end AND existing.end > new.start
        // Also exclude entries with null end_time (running timers handled separately)
        var condition = t.startTime.isSmallerThanValue(end) &
            t.endTime.isNotNull() &
            t.endTime.isBiggerThanValue(start);
        if (excludeId != null) {
          condition = condition & t.id.equals(excludeId).not();
        }
        // Only flag overlaps for the same client
        if (clientId != null) {
          condition = condition & t.clientId.equals(clientId);
        }
        return condition;
      });
    return query.get();
  }

  /// Resolve overlapping entries by truncating or deleting them.
  /// - If an overlapping entry is fully contained within [start, end], delete it.
  /// - If it starts before [start], truncate its end to [start].
  /// - If it ends after [end], move its start to [end].
  Future<void> _resolveOverlaps(
    List<TimeEntry> overlapping,
    DateTime start,
    DateTime end,
  ) async {
    for (final entry in overlapping) {
      final eStart = entry.startTime;
      final eEnd = entry.endTime!;

      if (eStart.compareTo(start) >= 0 && eEnd.compareTo(end) <= 0) {
        // Fully contained — delete it
        await (delete(timeEntries)..where((t) => t.id.equals(entry.id))).go();
      } else if (eStart.isBefore(start)) {
        // Overlaps on the left — truncate end to our start
        final newDuration = start.difference(eStart).inMinutes;
        await (update(timeEntries)..where((t) => t.id.equals(entry.id))).write(
          TimeEntriesCompanion(
            endTime: Value(start),
            durationMinutes: Value(newDuration),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        // Overlaps on the right — move start to our end
        final newDuration = eEnd.difference(end).inMinutes;
        await (update(timeEntries)..where((t) => t.id.equals(entry.id))).write(
          TimeEntriesCompanion(
            startTime: Value(end),
            durationMinutes: Value(newDuration),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }
  }

  /// Get entries for a date range.
  Stream<List<TimeEntry>> watchEntriesForDateRange(
    DateTime start,
    DateTime end,
  ) {
    return (select(timeEntries)
          ..where((t) =>
              t.startTime.isBiggerOrEqualValue(start) &
              t.startTime.isSmallerThanValue(end))
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
        .watch();
  }

  /// Get uninvoiced entries for a client.
  Future<List<TimeEntry>> getUninvoicedForClient(int clientId) {
    return (select(timeEntries)
          ..where((t) =>
              t.clientId.equals(clientId) &
              t.isInvoiced.equals(false) &
              t.endTime.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .get();
  }

  /// Get uninvoiced entries for a specific project.
  Future<List<TimeEntry>> getUninvoicedForProject(int projectId) {
    return (select(timeEntries)
          ..where((t) =>
              t.projectId.equals(projectId) &
              t.isInvoiced.equals(false) &
              t.endTime.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .get();
  }

  /// Get the most recent completed entry (for quick clock-in repeat).
  Future<TimeEntry?> getMostRecentCompleted() async {
    final results = await (select(timeEntries)
          ..where((t) => t.endTime.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)])
          ..limit(1))
        .get();
    return results.isEmpty ? null : results.first;
  }

  /// Update hourly rate on all uninvoiced entries for a client.
  /// Returns the number of affected rows.
  Future<int> updateRateForClient(int clientId, double newRate) {
    return (update(timeEntries)
          ..where((t) =>
              t.clientId.equals(clientId) &
              t.isInvoiced.equals(false)))
        .write(TimeEntriesCompanion(
          hourlyRateSnapshot: Value(newRate),
          updatedAt: Value(DateTime.now()),
        ));
  }

  /// Count uninvoiced entries for a client at a specific rate.
  Future<int> countUninvoicedAtRate(int clientId, double rate) async {
    final entries = await (select(timeEntries)
          ..where((t) =>
              t.clientId.equals(clientId) &
              t.isInvoiced.equals(false) &
              t.endTime.isNotNull() &
              t.hourlyRateSnapshot.equals(rate)))
        .get();
    return entries.length;
  }

  /// Get all unique tags used across all entries.
  Future<Set<String>> getAllTags() async {
    final rows = await (select(timeEntries)
          ..where((t) => t.tags.isNotNull()))
        .get();
    final result = <String>{};
    for (final row in rows) {
      result.addAll(parseTags(row.tags));
    }
    return result;
  }

  /// Mark entries as invoiced.
  Future<void> markAsInvoiced(List<int> entryIds, int invoiceId) {
    return (update(timeEntries)..where((t) => t.id.isIn(entryIds))).write(
      TimeEntriesCompanion(
        isInvoiced: const Value(true),
        invoiceId: Value(invoiceId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Unmark entries (e.g., when deleting a draft invoice).
  Future<void> unmarkInvoiced(int invoiceId) {
    return (update(timeEntries)
          ..where((t) => t.invoiceId.equals(invoiceId)))
        .write(const TimeEntriesCompanion(
          isInvoiced: Value(false),
          invoiceId: Value(null),
        ));
  }

  /// Get all entries (for export).
  Future<List<TimeEntry>> getAllEntries({
    DateTime? from,
    DateTime? to,
    int? clientId,
    int? projectId,
  }) {
    final query = select(timeEntries);
    query.where((t) {
      Expression<bool> condition = const Constant(true);
      if (from != null) {
        condition = condition & t.startTime.isBiggerOrEqualValue(from);
      }
      if (to != null) {
        condition = condition & t.startTime.isSmallerThanValue(to);
      }
      if (clientId != null) {
        condition = condition & t.clientId.equals(clientId);
      }
      if (projectId != null) {
        condition = condition & t.projectId.equals(projectId);
      }
      return condition;
    });
    query.orderBy([(t) => OrderingTerm.desc(t.startTime)]);
    return query.get();
  }
}

class OverlappingTimeEntryException implements Exception {
  final TimeEntry existing;
  OverlappingTimeEntryException(this.existing);

  @override
  String toString() =>
      'Time entry overlaps with existing entry from '
      '${existing.startTime} to ${existing.endTime}';
}
