import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/time_entry_dao.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/multi_timer_provider.dart';
import '../../../../core/utils/rate_resolver.dart';
import '../../../../core/utils/tag_utils.dart';
import '../../../profile/presentation/providers/profile_provider.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../projects/presentation/providers/project_providers.dart';

final timeEntryDaoProvider = Provider<TimeEntryDao>((ref) {
  return TimeEntryDao(ref.watch(databaseProvider));
});

/// Watches the currently running timer entry (null if none).
final runningEntryProvider = StreamProvider<TimeEntry?>((ref) {
  return ref.watch(timeEntryDaoProvider).watchRunningEntry();
});

/// Watches ALL currently running timer entries (empty list if none).
final runningEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  return ref.watch(timeEntryDaoProvider).watchAllRunningEntries();
});

/// Most recent completed entry (for quick clock-in repeat).
final lastCompletedEntryProvider = FutureProvider<TimeEntry?>((ref) {
  return ref.watch(timeEntryDaoProvider).getMostRecentCompleted();
});

/// Date range filter state for the entries list.
class DateRangeFilter {
  final DateTime start;
  final DateTime end;

  DateRangeFilter({required this.start, required this.end});

  factory DateRangeFilter.today() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return DateRangeFilter(start: start, end: start.add(const Duration(days: 1)));
  }

  factory DateRangeFilter.thisWeek() {
    final now = DateTime.now();
    final weekday = now.weekday; // Mon=1 .. Sun=7
    final start = DateTime(now.year, now.month, now.day - (weekday - 1));
    return DateRangeFilter(start: start, end: start.add(const Duration(days: 7)));
  }

  factory DateRangeFilter.thisMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    return DateRangeFilter(start: start, end: end);
  }
}

class DateRangeFilterNotifier extends Notifier<DateRangeFilter> {
  @override
  DateRangeFilter build() => DateRangeFilter.thisWeek();
  void set(DateRangeFilter v) => state = v;
}

final dateRangeFilterProvider =
    NotifierProvider<DateRangeFilterNotifier, DateRangeFilter>(
        DateRangeFilterNotifier.new);

class TagFilterNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};
  void set(Set<String> v) => state = v;
}

/// Active tag filter — entries must contain ALL selected tags.
final tagFilterProvider =
    NotifierProvider<TagFilterNotifier, Set<String>>(TagFilterNotifier.new);

/// All unique tags used across all time entries.
final allTagsProvider = FutureProvider<Set<String>>((ref) {
  return ref.watch(timeEntryDaoProvider).getAllTags();
});

class ClientIdFilterNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => {};
  void set(Set<int> v) => state = v;
}

/// Active company filter — entries must belong to one of the selected client IDs.
final clientIdFilterProvider =
    NotifierProvider<ClientIdFilterNotifier, Set<int>>(
        ClientIdFilterNotifier.new);

/// Watch entries for the selected date range, filtered by selected tags and companies.
final filteredEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  final filter = ref.watch(dateRangeFilterProvider);
  final tagFilter = ref.watch(tagFilterProvider);
  final clientFilter = ref.watch(clientIdFilterProvider);
  return ref
      .watch(timeEntryDaoProvider)
      .watchEntriesForDateRange(filter.start, filter.end)
      .map((entries) {
    var result = entries;
    if (tagFilter.isNotEmpty) {
      result = result.where((e) {
        final entryTags = parseTags(e.tags);
        return tagFilter.every((t) => entryTags.contains(t));
      }).toList();
    }
    if (clientFilter.isNotEmpty) {
      result =
          result.where((e) => clientFilter.contains(e.clientId)).toList();
    }
    return result;
  });
});

/// Timer notifier — handles clock in, clock out, manual entry.
final timerNotifierProvider =
    AsyncNotifierProvider<TimerNotifier, void>(TimerNotifier.new);

class TimerNotifier extends AsyncNotifier<void> {
  late TimeEntryDao _dao;

  @override
  Future<void> build() async {
    _dao = ref.watch(timeEntryDaoProvider);
  }

  /// Clock in: start a new running timer.
  Future<int> clockIn({
    required int clientId,
    int? projectId,
    String? description,
    String? issueReference,
    String? repository,
    String? tags,
  }) async {
    final multiTimer = await ref.read(multiTimerProvider.future);
    final running = await _dao.getAllRunningEntries();

    if (!multiTimer && running.isNotEmpty) {
      throw Exception(
        'A timer is already running. Clock out first, or enable '
        'multi-company clocking in Settings → Time Tracking.',
      );
    }
    if (multiTimer && running.any((e) => e.clientId == clientId)) {
      throw Exception('A timer for this company is already running.');
    }

    // Resolve the hourly rate
    final profile = await ref.read(userProfileDaoProvider).getProfile();
    final clientDao = ref.read(clientDaoProvider);
    final client = await clientDao.getClient(clientId);

    double? projectRate;
    if (projectId != null) {
      final projectDao = ref.read(projectDaoProvider);
      final project = await projectDao.getProject(projectId);
      projectRate = project.hourlyRateOverride;
    }

    final rate = resolveHourlyRate(
      projectRateOverride: projectRate,
      clientRate: client.hourlyRate,
      profileDefaultRate: profile.defaultHourlyRate,
    );

    final id = await _dao.insertWithOverlapCheck(
      TimeEntriesCompanion.insert(
        clientId: clientId,
        projectId: Value(projectId),
        startTime: DateTime.now(),
        hourlyRateSnapshot: rate,
        description: Value(description),
        issueReference: Value(issueReference),
        repository: Value(repository),
        tags: Value(tags),
      ),
    );
    return id;
  }

  /// Clock out the running entry.
  Future<bool> clockOut(
    int entryId, {
    String? description,
    bool truncateOverlaps = false,
  }) {
    return _dao.clockOut(
      entryId,
      description: description,
      truncateOverlaps: truncateOverlaps,
    );
  }

  /// Update a time entry's start/end times and details with overlap checking.
  Future<bool> updateEntryTimes({
    required int entryId,
    required DateTime startTime,
    required DateTime endTime,
    int? projectId,
    bool clearProject = false,
    String? description,
    String? issueReference,
    String? repository,
    String? tags,
    double? hourlyRateSnapshot,
  }) async {
    final duration = endTime.difference(startTime).inMinutes;
    return _dao.updateWithOverlapCheck(
      entryId,
      TimeEntriesCompanion(
        startTime: Value(startTime),
        endTime: Value(endTime),
        durationMinutes: Value(duration),
        projectId: clearProject ? const Value(null) : (projectId != null ? Value(projectId) : const Value.absent()),
        description: Value(description),
        issueReference: Value(issueReference),
        repository: Value(repository),
        tags: Value(tags),
        hourlyRateSnapshot: hourlyRateSnapshot != null
            ? Value(hourlyRateSnapshot)
            : const Value.absent(),
      ),
    );
  }

  /// Update only metadata on a running (or any) entry without touching times.
  Future<bool> updateEntryMeta({
    required int entryId,
    int? projectId,
    bool clearProject = false,
    String? description,
    String? issueReference,
    String? repository,
    String? tags,
    double? hourlyRateSnapshot,
  }) async {
    return _dao.updateWithOverlapCheck(
      entryId,
      TimeEntriesCompanion(
        projectId: clearProject ? const Value(null) : (projectId != null ? Value(projectId) : const Value.absent()),
        description: Value(description),
        issueReference: Value(issueReference),
        repository: Value(repository),
        tags: Value(tags),
        hourlyRateSnapshot: hourlyRateSnapshot != null
            ? Value(hourlyRateSnapshot)
            : const Value.absent(),
      ),
    );
  }

  /// Add a manual time entry (already has start + end).
  Future<int> addManualEntry({
    required int clientId,
    int? projectId,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
    String? issueReference,
    String? repository,
    String? tags,
  }) async {
    final profile = await ref.read(userProfileDaoProvider).getProfile();
    final clientDao = ref.read(clientDaoProvider);
    final client = await clientDao.getClient(clientId);

    double? projectRate;
    if (projectId != null) {
      final projectDao = ref.read(projectDaoProvider);
      final project = await projectDao.getProject(projectId);
      projectRate = project.hourlyRateOverride;
    }

    final rate = resolveHourlyRate(
      projectRateOverride: projectRate,
      clientRate: client.hourlyRate,
      profileDefaultRate: profile.defaultHourlyRate,
    );

    final duration = endTime.difference(startTime).inMinutes;

    return _dao.insertWithOverlapCheck(
      TimeEntriesCompanion.insert(
        clientId: clientId,
        projectId: Value(projectId),
        startTime: startTime,
        endTime: Value(endTime),
        durationMinutes: Value(duration),
        hourlyRateSnapshot: rate,
        isManual: const Value(true),
        description: Value(description),
        issueReference: Value(issueReference),
        repository: Value(repository),
        tags: Value(tags),
      ),
    );
  }

  /// Delete a time entry (only non-invoiced).
  Future<void> deleteEntry(int entryId) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.timeEntries)..where((t) => t.id.equals(entryId))).go();
  }

  /// Update a time entry's description/details.
  Future<bool> updateEntry(int entryId, TimeEntriesCompanion companion) async {
    final db = ref.read(databaseProvider);
    return (db.update(db.timeEntries)..where((t) => t.id.equals(entryId)))
        .write(companion.copyWith(updatedAt: Value(DateTime.now())))
        .then((rows) => rows > 0);
  }
}
