import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../database/app_database.dart';
import '../time_entry_repository.dart';

class SupabaseTimeEntryRepository implements TimeEntryRepository {
  final SupabaseClient _client;
  SupabaseTimeEntryRepository(this._client);

  String get _uid => _client.auth.currentUser!.id;

  TimeEntry _fromRow(Map<String, dynamic> r) => TimeEntry(
        id: r['id'] as String,
        clientId: r['client_id'] as String,
        projectId: r['project_id'] as String?,
        startTime: DateTime.parse(r['start_time'] as String),
        endTime: r['end_time'] != null
            ? DateTime.parse(r['end_time'] as String)
            : null,
        durationMinutes: r['duration_minutes'] as int?,
        description: r['description'] as String?,
        issueReference: r['issue_reference'] as String?,
        repository: r['repository'] as String?,
        tags: r['tags'] as String?,
        isManual: r['is_manual'] as bool? ?? false,
        hourlyRateSnapshot: (r['hourly_rate_snapshot'] as num).toDouble(),
        isInvoiced: r['is_invoiced'] as bool? ?? false,
        invoiceId: r['invoice_id'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  Future<List<TimeEntry>> _findOverlapping(
    DateTime start,
    DateTime end, {
    String? excludeId,
    String? clientId,
  }) async {
    var query = _client
        .from('time_entries')
        .select()
        .lt('start_time', end.toUtc().toIso8601String())
        .not('end_time', 'is', null)
        .gt('end_time', start.toUtc().toIso8601String());
    if (clientId != null) {
      query = query.eq('client_id', clientId);
    }
    final rows = await query;
    var entries = rows.map(_fromRow).toList();
    if (excludeId != null) {
      entries = entries.where((e) => e.id != excludeId).toList();
    }
    return entries;
  }

  Future<void> _resolveOverlaps(
    List<TimeEntry> overlapping,
    DateTime start,
    DateTime end,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final entry in overlapping) {
      final eStart = entry.startTime;
      final eEnd = entry.endTime!;
      if (eStart.compareTo(start) >= 0 && eEnd.compareTo(end) <= 0) {
        await _client.from('time_entries').delete().eq('id', entry.id);
      } else if (eStart.isBefore(start)) {
        final newDuration = start.difference(eStart).inMinutes;
        await _client.from('time_entries').update({
          'end_time': start.toUtc().toIso8601String(),
          'duration_minutes': newDuration,
          'updated_at': now,
        }).eq('id', entry.id);
      } else {
        final newDuration = eEnd.difference(end).inMinutes;
        await _client.from('time_entries').update({
          'start_time': end.toUtc().toIso8601String(),
          'duration_minutes': newDuration,
          'updated_at': now,
        }).eq('id', entry.id);
      }
    }
  }

  @override
  Future<TimeEntry?> getRunningEntry() async {
    final rows = await _client
        .from('time_entries')
        .select()
        .isFilter('end_time', null)
        .limit(1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Stream<TimeEntry?> watchRunningEntry() =>
      Stream.fromFuture(getRunningEntry());

  @override
  Stream<List<TimeEntry>> watchAllRunningEntries() =>
      Stream.fromFuture(getAllRunningEntries());

  @override
  Future<List<TimeEntry>> getAllRunningEntries() async {
    final rows = await _client
        .from('time_entries')
        .select()
        .isFilter('end_time', null)
        .order('start_time');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<String> insertWithOverlapCheck(TimeEntriesCompanion entry) async {
    final start = entry.startTime.value;
    final end = entry.endTime.present ? entry.endTime.value : null;
    final clientId = entry.clientId.present ? entry.clientId.value : null;

    if (end != null) {
      final overlapping =
          await _findOverlapping(start, end, clientId: clientId);
      if (overlapping.isNotEmpty) {
        throw OverlappingTimeEntryException(overlapping.first);
      }
    }

    const uuid = Uuid();
    final id = uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('time_entries').insert({
      'id': id,
      'user_id': _uid,
      'client_id': entry.clientId.value,
      if (entry.projectId.present) 'project_id': entry.projectId.value,
      'start_time': start.toUtc().toIso8601String(),
      if (end != null) 'end_time': end.toUtc().toIso8601String(),
      if (entry.durationMinutes.present) 'duration_minutes': entry.durationMinutes.value,
      if (entry.description.present) 'description': entry.description.value,
      if (entry.issueReference.present) 'issue_reference': entry.issueReference.value,
      if (entry.repository.present) 'repository': entry.repository.value,
      if (entry.tags.present) 'tags': entry.tags.value,
      'is_manual': entry.isManual.present ? entry.isManual.value : false,
      'hourly_rate_snapshot': entry.hourlyRateSnapshot.value,
      'is_invoiced': false,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  @override
  Future<bool> clockOut(
    String entryId, {
    String? description,
    bool truncateOverlaps = false,
  }) async {
    final now = DateTime.now().toUtc();
    final entryRow = await _client
        .from('time_entries')
        .select()
        .eq('id', entryId)
        .single();
    final entry = _fromRow(entryRow);
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

    final map = <String, dynamic>{
      'end_time': now.toIso8601String(),
      'duration_minutes': duration,
      'updated_at': now.toIso8601String(),
    };
    if (description != null) map['description'] = description;
    final result = await _client
        .from('time_entries')
        .update(map)
        .eq('id', entryId)
        .select();
    return result.isNotEmpty;
  }

  @override
  Future<bool> updateWithOverlapCheck(
    String entryId,
    TimeEntriesCompanion companion,
  ) async {
    final existingRow = await _client
        .from('time_entries')
        .select()
        .eq('id', entryId)
        .single();
    final existing = _fromRow(existingRow);

    final start = companion.startTime.present
        ? companion.startTime.value
        : existing.startTime;
    final end = companion.endTime.present
        ? companion.endTime.value
        : existing.endTime;

    if (end != null) {
      final overlapping = await _findOverlapping(
        start,
        end,
        excludeId: entryId,
        clientId: existing.clientId,
      );
      if (overlapping.isNotEmpty) {
        throw OverlappingTimeEntryException(overlapping.first);
      }
    }

    return updateEntry(entryId, companion);
  }

  @override
  Stream<List<TimeEntry>> watchEntriesForDateRange(
    DateTime start,
    DateTime end,
  ) =>
      Stream.fromFuture(_fetchForDateRange(start, end));

  Future<List<TimeEntry>> _fetchForDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _client
        .from('time_entries')
        .select()
        .gte('start_time', start.toUtc().toIso8601String())
        .lt('start_time', end.toUtc().toIso8601String())
        .order('start_time', ascending: false);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<TimeEntry>> getUninvoicedForClient(String clientId) async {
    final rows = await _client
        .from('time_entries')
        .select()
        .eq('client_id', clientId)
        .eq('is_invoiced', false)
        .not('end_time', 'is', null)
        .order('start_time');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<TimeEntry>> getUninvoicedForProject(String projectId) async {
    final rows = await _client
        .from('time_entries')
        .select()
        .eq('project_id', projectId)
        .eq('is_invoiced', false)
        .not('end_time', 'is', null)
        .order('start_time');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<TimeEntry?> getMostRecentCompleted() async {
    final rows = await _client
        .from('time_entries')
        .select()
        .not('end_time', 'is', null)
        .order('start_time', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<int> updateRateForClient(String clientId, double newRate) async {
    final rows = await _client
        .from('time_entries')
        .update({
          'hourly_rate_snapshot': newRate,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('client_id', clientId)
        .eq('is_invoiced', false)
        .select();
    return rows.length;
  }

  @override
  Future<int> countUninvoicedAtRate(String clientId, double rate) async {
    final rows = await _client
        .from('time_entries')
        .select('id')
        .eq('client_id', clientId)
        .eq('is_invoiced', false)
        .not('end_time', 'is', null)
        .eq('hourly_rate_snapshot', rate);
    return rows.length;
  }

  @override
  Future<Set<String>> getAllTags() async {
    final rows = await _client
        .from('time_entries')
        .select('tags')
        .not('tags', 'is', null);
    final result = <String>{};
    for (final row in rows) {
      final tags = row['tags'] as String?;
      if (tags != null && tags.isNotEmpty) {
        // tags stored as JSON array string e.g. '["tagA","tagB"]'
        // use same parseTags logic: split on comma after stripping brackets/quotes
        final cleaned = tags
            .replaceAll('[', '')
            .replaceAll(']', '')
            .replaceAll('"', '')
            .trim();
        if (cleaned.isNotEmpty) {
          result.addAll(cleaned.split(',').map((t) => t.trim()));
        }
      }
    }
    return result;
  }

  @override
  Future<void> markAsInvoiced(List<String> entryIds, String invoiceId) async {
    if (entryIds.isEmpty) return;
    await _client.from('time_entries').update({
      'is_invoiced': true,
      'invoice_id': invoiceId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).inFilter('id', entryIds);
  }

  @override
  Future<void> unmarkInvoiced(String invoiceId) async {
    await _client.from('time_entries').update({
      'is_invoiced': false,
      'invoice_id': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('invoice_id', invoiceId);
  }

  @override
  Future<List<TimeEntry>> getAllEntries({
    DateTime? from,
    DateTime? to,
    String? clientId,
    String? projectId,
  }) async {
    var query = _client.from('time_entries').select();
    if (from != null) {
      query = query.gte('start_time', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lt('start_time', to.toUtc().toIso8601String());
    }
    if (clientId != null) {
      query = query.eq('client_id', clientId);
    }
    if (projectId != null) {
      query = query.eq('project_id', projectId);
    }
    final rows = await query.order('start_time', ascending: false);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    await _client.from('time_entries').delete().eq('id', entryId);
  }

  @override
  Future<bool> updateEntry(
      String entryId, TimeEntriesCompanion companion) async {
    final map = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (companion.clientId.present) map['client_id'] = companion.clientId.value;
    if (companion.projectId.present) map['project_id'] = companion.projectId.value;
    if (companion.startTime.present) {
      map['start_time'] = companion.startTime.value.toUtc().toIso8601String();
    }
    if (companion.endTime.present) {
      map['end_time'] = companion.endTime.value?.toUtc().toIso8601String();
    }
    if (companion.durationMinutes.present) map['duration_minutes'] = companion.durationMinutes.value;
    if (companion.description.present) map['description'] = companion.description.value;
    if (companion.issueReference.present) map['issue_reference'] = companion.issueReference.value;
    if (companion.repository.present) map['repository'] = companion.repository.value;
    if (companion.tags.present) map['tags'] = companion.tags.value;
    if (companion.isManual.present) map['is_manual'] = companion.isManual.value;
    if (companion.hourlyRateSnapshot.present) map['hourly_rate_snapshot'] = companion.hourlyRateSnapshot.value;
    if (companion.isInvoiced.present) map['is_invoiced'] = companion.isInvoiced.value;
    if (companion.invoiceId.present) map['invoice_id'] = companion.invoiceId.value;
    final result = await _client
        .from('time_entries')
        .update(map)
        .eq('id', entryId)
        .select();
    return result.isNotEmpty;
  }
}
