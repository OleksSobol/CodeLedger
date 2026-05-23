import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/multi_timer_provider.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/time_entry_repository.dart';
import '../../../../core/utils/rate_resolver.dart';
import '../../../../core/utils/tag_utils.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';

final runningEntryProvider = StreamProvider<TimeEntry?>((ref) {
  return ref.watch(timeEntryRepositoryProvider).watchRunningEntry();
});

final runningEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  return ref.watch(timeEntryRepositoryProvider).watchAllRunningEntries();
});

final lastCompletedEntryProvider = FutureProvider<TimeEntry?>((ref) {
  return ref.watch(timeEntryRepositoryProvider).getMostRecentCompleted();
});

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
    final weekday = now.weekday;
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

final tagFilterProvider =
    NotifierProvider<TagFilterNotifier, Set<String>>(TagFilterNotifier.new);

final allTagsProvider = FutureProvider<Set<String>>((ref) {
  return ref.watch(timeEntryRepositoryProvider).getAllTags();
});

class ClientIdFilterNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};
  void set(Set<String> v) => state = v;
}

final clientIdFilterProvider =
    NotifierProvider<ClientIdFilterNotifier, Set<String>>(
        ClientIdFilterNotifier.new);

final filteredEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  final filter = ref.watch(dateRangeFilterProvider);
  final tagFilter = ref.watch(tagFilterProvider);
  final clientFilter = ref.watch(clientIdFilterProvider);
  return ref
      .watch(timeEntryRepositoryProvider)
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

final timerNotifierProvider =
    AsyncNotifierProvider<TimerNotifier, void>(TimerNotifier.new);

class TimerNotifier extends AsyncNotifier<void> {
  late TimeEntryRepository _dao;

  @override
  Future<void> build() async {
    _dao = ref.watch(timeEntryRepositoryProvider);
  }

  Future<String> clockIn({
    required String clientId,
    String? projectId,
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

    final profile = await ref.read(userProfileRepositoryProvider).getProfile();
    final client =
        await ref.read(clientRepositoryProvider).getClient(clientId);

    double? projectRate;
    if (projectId != null) {
      final project =
          await ref.read(projectRepositoryProvider).getProject(projectId);
      projectRate = project.hourlyRateOverride;
    }

    final rate = resolveHourlyRate(
      projectRateOverride: projectRate,
      clientRate: client.hourlyRate,
      profileDefaultRate: profile.defaultHourlyRate,
    );

    final id = await _dao.insertWithOverlapCheck(
      TimeEntriesCompanion(
        clientId: Value(clientId),
        projectId: Value(projectId),
        startTime: Value(DateTime.now()),
        hourlyRateSnapshot: Value(rate),
        description: Value(description),
        issueReference: Value(issueReference),
        repository: Value(repository),
        tags: Value(tags),
      ),
    );
    return id;
  }

  Future<bool> clockOut(
    String entryId, {
    String? description,
    bool truncateOverlaps = false,
  }) async {
    final result = await _dao.clockOut(
      entryId,
      description: description,
      truncateOverlaps: truncateOverlaps,
    );
    ref.invalidate(lastCompletedEntryProvider);
    ref.invalidate(weeklyHoursProvider);
    ref.invalidate(uninvoicedByClientProvider);
    return result;
  }

  Future<bool> updateEntryTimes({
    required String entryId,
    required DateTime startTime,
    required DateTime endTime,
    String? projectId,
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
        projectId: clearProject
            ? const Value(null)
            : (projectId != null ? Value(projectId) : const Value.absent()),
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

  Future<bool> updateEntryMeta({
    required String entryId,
    String? projectId,
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
        projectId: clearProject
            ? const Value(null)
            : (projectId != null ? Value(projectId) : const Value.absent()),
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

  Future<String> addManualEntry({
    required String clientId,
    String? projectId,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
    String? issueReference,
    String? repository,
    String? tags,
  }) async {
    final profile = await ref.read(userProfileRepositoryProvider).getProfile();
    final client =
        await ref.read(clientRepositoryProvider).getClient(clientId);

    double? projectRate;
    if (projectId != null) {
      final project =
          await ref.read(projectRepositoryProvider).getProject(projectId);
      projectRate = project.hourlyRateOverride;
    }

    final rate = resolveHourlyRate(
      projectRateOverride: projectRate,
      clientRate: client.hourlyRate,
      profileDefaultRate: profile.defaultHourlyRate,
    );

    final duration = endTime.difference(startTime).inMinutes;

    final id = await _dao.insertWithOverlapCheck(
      TimeEntriesCompanion(
        clientId: Value(clientId),
        projectId: Value(projectId),
        startTime: Value(startTime),
        endTime: Value(endTime),
        durationMinutes: Value(duration),
        hourlyRateSnapshot: Value(rate),
        isManual: const Value(true),
        description: Value(description),
        issueReference: Value(issueReference),
        repository: Value(repository),
        tags: Value(tags),
      ),
    );
    ref.invalidate(lastCompletedEntryProvider);
    ref.invalidate(weeklyHoursProvider);
    ref.invalidate(uninvoicedByClientProvider);
    return id;
  }

  Future<void> deleteEntry(String entryId) async {
    await _dao.deleteEntry(entryId);
    ref.invalidate(lastCompletedEntryProvider);
    ref.invalidate(weeklyHoursProvider);
    ref.invalidate(uninvoicedByClientProvider);
  }

  Future<bool> updateEntry(
          String entryId, TimeEntriesCompanion companion) =>
      _dao.updateEntry(entryId, companion);
}
