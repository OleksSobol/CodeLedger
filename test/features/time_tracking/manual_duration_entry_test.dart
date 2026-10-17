import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:code_ledger/core/database/app_database.dart';
import 'package:code_ledger/core/providers/database_provider.dart';
import 'package:code_ledger/core/providers/dao_providers.dart';
import 'package:code_ledger/core/providers/repository_providers.dart';
import 'package:code_ledger/core/utils/duration_formatter.dart';
import 'package:code_ledger/features/time_tracking/domain/manual_entry_mode.dart';
import 'package:code_ledger/features/time_tracking/presentation/providers/time_entry_providers.dart';

AppDatabase _openTestDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('ManualEntryMode (DEV-76)', () {
    test('defines duration and exactTime modes with correct labels', () {
      expect(ManualEntryMode.duration.label, equals('Duration'));
      expect(ManualEntryMode.exactTime.label, equals('Exact Time'));
    });
  });

  group('Duration Parsing and Formatting (DEV-76)', () {
    int parseDuration(String hoursText, String minutesText) {
      final hours = double.tryParse(hoursText.trim()) ?? 0.0;
      final minutes = int.tryParse(minutesText.trim()) ?? 0;
      final total = (hours * 60).round() + minutes;
      return total > 0 ? total : 0;
    }

    test('parses integer hours correctly', () {
      expect(parseDuration('4', '0'), equals(240));
      expect(formatDuration(parseDuration('4', '0')), equals('4h'));
    });

    test('parses decimal hours correctly', () {
      // 4.5 hours = 270 minutes (4h 30m)
      final mins = parseDuration('4.5', '0');
      expect(mins, equals(270));
      expect(formatDuration(mins), equals('4h 30m'));

      // 1.25 hours = 75 minutes (1h 15m)
      final mins2 = parseDuration('1.25', '0');
      expect(mins2, equals(75));
      expect(formatDuration(mins2), equals('1h 15m'));
    });

    test('parses combined hours and minutes correctly', () {
      final mins = parseDuration('2', '30');
      expect(mins, equals(150));
      expect(formatDuration(mins), equals('2h 30m'));
    });

    test('returns 0 for empty or invalid inputs', () {
      expect(parseDuration('', ''), equals(0));
      expect(parseDuration('abc', 'def'), equals(0));
      expect(parseDuration('-2', '0'), equals(0));
    });
  });

  group('TimerNotifier addManualDurationEntry (DEV-76)', () {
    late AppDatabase db;
    late ProviderContainer container;
    late String clientId;

    setUp(() async {
      db = _openTestDb();

      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );

      // Seed profile and client
      await container.read(userProfileRepositoryProvider).getProfile();
      clientId = await container.read(clientRepositoryProvider).insertClient(
            const ClientsCompanion(
              name: Value('Acme Corp'),
              hourlyRate: Value(120.0),
            ),
          );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('slots entry at 9:00 AM on date when day is free', () async {
      final notifier = container.read(timerNotifierProvider.notifier);
      final date = DateTime(2026, 10, 16);

      final (start, end) = await notifier.findSlotForDuration(
        date: date,
        durationMinutes: 240, // 4 hours
        clientId: clientId,
      );

      expect(start, equals(DateTime(2026, 10, 16, 9, 0)));
      expect(end, equals(DateTime(2026, 10, 16, 13, 0)));
    });

    test('slots next manual duration after existing entry without collision', () async {
      final notifier = container.read(timerNotifierProvider.notifier);
      final date = DateTime(2026, 10, 16);

      // Add an initial 2-hour entry (9:00 AM to 11:00 AM)
      await notifier.addManualEntry(
        clientId: clientId,
        startTime: DateTime(2026, 10, 16, 9, 0),
        endTime: DateTime(2026, 10, 16, 11, 0),
        description: 'Morning session',
      );

      // Find slot for 3 hours (180 minutes)
      final (start, end) = await notifier.findSlotForDuration(
        date: date,
        durationMinutes: 180,
        clientId: clientId,
      );

      // Should automatically slot right after the 11:00 AM entry
      expect(start, equals(DateTime(2026, 10, 16, 11, 0)));
      expect(end, equals(DateTime(2026, 10, 16, 14, 0)));
    });

    test('addManualDurationEntry records duration, rate snapshot, and isManual flag', () async {
      final notifier = container.read(timerNotifierProvider.notifier);
      final date = DateTime(2026, 10, 16);

      final entryId = await notifier.addManualDurationEntry(
        clientId: clientId,
        date: date,
        durationMinutes: 240, // 4 hours
        description: 'Backend feature implementation',
        issueReference: 'DEV-76',
        repository: 'owner/code_ledger',
        tags: '["flutter", "invoicing"]',
      );

      expect(entryId, isNotEmpty);

      final dao = container.read(timeEntryDaoProvider);
      final entry = await (dao.select(dao.timeEntries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();

      expect(entry.durationMinutes, equals(240));
      expect(entry.isManual, isTrue);
      expect(entry.hourlyRateSnapshot, equals(120.0));
      expect(entry.description, equals('Backend feature implementation'));
      expect(entry.issueReference, equals('DEV-76'));
      expect(entry.repository, equals('owner/code_ledger'));
      expect(entry.endTime, isNotNull);
      expect(entry.endTime!.difference(entry.startTime).inMinutes, equals(240));
    });

    test('can log multiple manual duration entries on the same day without overlapping error', () async {
      final notifier = container.read(timerNotifierProvider.notifier);
      final date = DateTime(2026, 10, 16);

      // First duration entry: 4 hours
      final id1 = await notifier.addManualDurationEntry(
        clientId: clientId,
        date: date,
        durationMinutes: 240,
        description: 'First block',
      );

      // Second duration entry: 2 hours on same day
      final id2 = await notifier.addManualDurationEntry(
        clientId: clientId,
        date: date,
        durationMinutes: 120,
        description: 'Second block',
      );

      expect(id1, isNotEmpty);
      expect(id2, isNotEmpty);
      expect(id1, isNot(equals(id2)));

      final dao = container.read(timeEntryDaoProvider);
      final all = await dao.getAllEntries(
        from: DateTime(2026, 10, 16),
        to: DateTime(2026, 10, 17),
        clientId: clientId,
      );

      expect(all.length, equals(2));
      final totalMinutes = all.fold<int>(0, (sum, e) => sum + (e.durationMinutes ?? 0));
      expect(totalMinutes, equals(360)); // 6 hours total
    });
  });
}
