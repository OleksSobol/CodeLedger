import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../tables/time_entries_table.dart';
import '../../utils/tag_utils.dart';

part 'time_entry_dao.g.dart';

@DriftAccessor(tables: [TimeEntries])
class TimeEntryDao extends DatabaseAccessor<AppDatabase>
    with _$TimeEntryDaoMixin {
  TimeEntryDao(super.db);

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

  Future<String> insertWithOverlapCheck(TimeEntriesCompanion entry) {
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
      const uuid = Uuid();
      final id = uuid.v4();
      await into(timeEntries).insert(entry.copyWith(id: Value(id)));
      return id;
    });
  }

  Future<bool> clockOut(
    String entryId, {
    String? description,
    bool truncateOverlaps = false,
  }) {
    final now = DateTime.now();
    return transaction(() async {
      final entry =
          await (select(timeEntries)..where((t) => t.id.equals(entryId)))
              .getSingle();
      final duration = now.difference(entry.startTime).inMinutes;

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

  Future<bool> updateWithOverlapCheck(
    String entryId,
    TimeEntriesCompanion companion,
  ) {
    return transaction(() async {
      final start = companion.startTime;
      final end = companion.endTime;

      final existing =
          await (select(timeEntries)..where((t) => t.id.equals(entryId)))
              .getSingle();
      final clientId = existing.clientId;

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

  Future<List<TimeEntry>> _findOverlapping(
    DateTime start,
    DateTime end, {
    String? excludeId,
    String? clientId,
  }) {
    final query = select(timeEntries)
      ..where((t) {
        var condition = t.startTime.isSmallerThanValue(end) &
            t.endTime.isNotNull() &
            t.endTime.isBiggerThanValue(start);
        if (excludeId != null) {
          condition = condition & t.id.equals(excludeId).not();
        }
        if (clientId != null) {
          condition = condition & t.clientId.equals(clientId);
        }
        return condition;
      });
    return query.get();
  }

  Future<void> _resolveOverlaps(
    List<TimeEntry> overlapping,
    DateTime start,
    DateTime end,
  ) async {
    for (final entry in overlapping) {
      final eStart = entry.startTime;
      final eEnd = entry.endTime!;

      if (eStart.compareTo(start) >= 0 && eEnd.compareTo(end) <= 0) {
        await (delete(timeEntries)..where((t) => t.id.equals(entry.id))).go();
      } else if (eStart.isBefore(start)) {
        final newDuration = start.difference(eStart).inMinutes;
        await (update(timeEntries)..where((t) => t.id.equals(entry.id))).write(
          TimeEntriesCompanion(
            endTime: Value(start),
            durationMinutes: Value(newDuration),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
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

  Future<List<TimeEntry>> getUninvoicedForClient(String clientId) {
    return (select(timeEntries)
          ..where((t) =>
              t.clientId.equals(clientId) &
              t.isInvoiced.equals(false) &
              t.endTime.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .get();
  }

  Future<List<TimeEntry>> getUninvoicedForProject(String projectId) {
    return (select(timeEntries)
          ..where((t) =>
              t.projectId.equals(projectId) &
              t.isInvoiced.equals(false) &
              t.endTime.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .get();
  }

  Future<TimeEntry?> getMostRecentCompleted() async {
    final results = await (select(timeEntries)
          ..where((t) => t.endTime.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)])
          ..limit(1))
        .get();
    return results.isEmpty ? null : results.first;
  }

  Future<int> updateRateForClient(String clientId, double newRate) {
    return (update(timeEntries)
          ..where((t) =>
              t.clientId.equals(clientId) &
              t.isInvoiced.equals(false)))
        .write(TimeEntriesCompanion(
          hourlyRateSnapshot: Value(newRate),
          updatedAt: Value(DateTime.now()),
        ));
  }

  Future<int> countUninvoicedAtRate(String clientId, double rate) async {
    final entries = await (select(timeEntries)
          ..where((t) =>
              t.clientId.equals(clientId) &
              t.isInvoiced.equals(false) &
              t.endTime.isNotNull() &
              t.hourlyRateSnapshot.equals(rate)))
        .get();
    return entries.length;
  }

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

  Future<void> markAsInvoiced(List<String> entryIds, String invoiceId) {
    return (update(timeEntries)..where((t) => t.id.isIn(entryIds))).write(
      TimeEntriesCompanion(
        isInvoiced: const Value(true),
        invoiceId: Value(invoiceId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> unmarkInvoiced(String invoiceId) {
    return (update(timeEntries)
          ..where((t) => t.invoiceId.equals(invoiceId)))
        .write(const TimeEntriesCompanion(
          isInvoiced: Value(false),
          invoiceId: Value(null),
        ));
  }

  Future<List<TimeEntry>> getAllEntries({
    DateTime? from,
    DateTime? to,
    String? clientId,
    String? projectId,
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
