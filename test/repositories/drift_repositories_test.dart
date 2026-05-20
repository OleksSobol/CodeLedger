import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;

import 'package:code_ledger/core/database/app_database.dart';
import 'package:code_ledger/core/database/daos/client_dao.dart';
import 'package:code_ledger/core/database/daos/project_dao.dart';
import 'package:code_ledger/core/database/daos/time_entry_dao.dart';
import 'package:code_ledger/core/database/daos/user_profile_dao.dart';
import 'package:code_ledger/core/repositories/drift/drift_client_repository.dart';
import 'package:code_ledger/core/repositories/drift/drift_project_repository.dart';
import 'package:code_ledger/core/repositories/drift/drift_time_entry_repository.dart';
import 'package:code_ledger/core/repositories/drift/drift_user_profile_repository.dart';
import 'package:code_ledger/core/database/daos/time_entry_dao.dart'
    show OverlappingTimeEntryException;

AppDatabase _openTestDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  // ── Client Repository ─────────────────────────────────────────────
  group('DriftClientRepository', () {
    late AppDatabase db;
    late DriftClientRepository repo;

    setUp(() {
      db = _openTestDb();
      repo = DriftClientRepository(ClientDao(db));
    });

    tearDown(() => db.close());

    test('insert and get client', () async {
      final id = await repo.insertClient(
        const ClientsCompanion(name: Value('Acme Corp')),
      );
      expect(id, isNotEmpty);

      final client = await repo.getClient(id);
      expect(client.name, equals('Acme Corp'));
      expect(client.isArchived, isFalse);
    });

    test('getActiveClients excludes archived', () async {
      final id = await repo.insertClient(
        const ClientsCompanion(name: Value('Active')),
      );
      await repo.insertClient(
        const ClientsCompanion(name: Value('Archived')),
      );
      // Archive second client — need to get its id
      final all = await repo.getActiveClients();
      // Archive the one named 'Archived'
      final archivedClient = all.firstWhere((c) => c.name == 'Archived');
      await repo.archiveClient(archivedClient.id);

      final active = await repo.getActiveClients();
      expect(active.length, equals(1));
      expect(active.first.name, equals('Active'));

      // watchActiveClients stream also excludes archived
      final streamResult = await repo.watchActiveClients().first;
      expect(streamResult.length, equals(1));
    });

    test('updateClient changes fields', () async {
      final id = await repo.insertClient(
        const ClientsCompanion(name: Value('Old Name')),
      );
      final ok = await repo.updateClient(
        id,
        const ClientsCompanion(name: Value('New Name')),
      );
      expect(ok, isTrue);
      final client = await repo.getClient(id);
      expect(client.name, equals('New Name'));
    });

    test('deleteClient removes row', () async {
      final id = await repo.insertClient(
        const ClientsCompanion(name: Value('To Delete')),
      );
      await repo.deleteClient(id);
      final active = await repo.getActiveClients();
      expect(active.any((c) => c.id == id), isFalse);
    });

    test('hasLinkedRecords returns false for fresh client', () async {
      final id = await repo.insertClient(
        const ClientsCompanion(name: Value('Isolated')),
      );
      expect(await repo.hasLinkedRecords(id), isFalse);
    });

    test('getTotalBilled and getTotalPaid return 0 for new client', () async {
      final id = await repo.insertClient(
        const ClientsCompanion(name: Value('Empty')),
      );
      expect(await repo.getTotalBilled(id), equals(0.0));
      expect(await repo.getTotalPaid(id), equals(0.0));
    });
  });

  // ── Project Repository ────────────────────────────────────────────
  group('DriftProjectRepository', () {
    late AppDatabase db;
    late DriftClientRepository clientRepo;
    late DriftProjectRepository projectRepo;

    setUp(() {
      db = _openTestDb();
      clientRepo = DriftClientRepository(ClientDao(db));
      projectRepo = DriftProjectRepository(ProjectDao(db));
    });

    tearDown(() => db.close());

    test('insert and get project', () async {
      final clientId = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('Client')),
      );
      final projectId = await projectRepo.insertProject(ProjectsCompanion(
        clientId: Value(clientId),
        name: const Value('Website'),
      ));
      expect(projectId, isNotEmpty);

      final project = await projectRepo.getProject(projectId);
      expect(project.name, equals('Website'));
      expect(project.clientId, equals(clientId));
      expect(project.isArchived, isFalse);
    });

    test('watchProjectsForClient returns only that client\'s projects', () async {
      final c1 = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('Client 1')),
      );
      final c2 = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('Client 2')),
      );
      await projectRepo.insertProject(ProjectsCompanion(
        clientId: Value(c1),
        name: const Value('Proj A'),
      ));
      await projectRepo.insertProject(ProjectsCompanion(
        clientId: Value(c2),
        name: const Value('Proj B'),
      ));

      final c1Projects = await projectRepo.watchProjectsForClient(c1).first;
      expect(c1Projects.length, equals(1));
      expect(c1Projects.first.name, equals('Proj A'));
    });

    test('archiveProject sets isArchived flag', () async {
      final clientId = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('C')),
      );
      final projectId = await projectRepo.insertProject(ProjectsCompanion(
        clientId: Value(clientId),
        name: const Value('Legacy'),
      ));
      await projectRepo.archiveProject(projectId);

      final project = await projectRepo.getProject(projectId);
      expect(project.isArchived, isTrue);
    });
  });

  // ── UserProfile Repository ────────────────────────────────────────
  group('DriftUserProfileRepository', () {
    late AppDatabase db;
    late DriftUserProfileRepository repo;

    setUp(() {
      db = _openTestDb();
      repo = DriftUserProfileRepository(UserProfileDao(db));
    });

    tearDown(() => db.close());

    test('getProfile returns seeded default profile', () async {
      final profile = await repo.getProfile();
      expect(profile.invoiceNumberPrefix, equals('INV-'));
      expect(profile.nextInvoiceNumber, equals(1));
      expect(profile.businessName, equals(''));
    });

    test('getNextInvoiceNumber increments counter', () async {
      final first = await repo.getNextInvoiceNumber();
      final second = await repo.getNextInvoiceNumber();
      final third = await repo.getNextInvoiceNumber();

      expect(first, equals('INV-0001'));
      expect(second, equals('INV-0002'));
      expect(third, equals('INV-0003'));
    });

    test('updateProfile persists changes', () async {
      await repo.updateProfile(const UserProfilesCompanion(
        businessName: Value('My Company'),
        defaultHourlyRate: Value(150.0),
      ));
      final profile = await repo.getProfile();
      expect(profile.businessName, equals('My Company'));
      expect(profile.defaultHourlyRate, equals(150.0));
    });

    test('watchProfile emits updated values', () async {
      await repo.updateProfile(
        const UserProfilesCompanion(ownerName: Value('Alice')),
      );
      final profile = await repo.watchProfile().first;
      expect(profile.ownerName, equals('Alice'));
    });
  });

  // ── TimeEntry Repository ──────────────────────────────────────────
  group('DriftTimeEntryRepository', () {
    late AppDatabase db;
    late DriftClientRepository clientRepo;
    late DriftTimeEntryRepository timeRepo;

    setUp(() {
      db = _openTestDb();
      clientRepo = DriftClientRepository(ClientDao(db));
      timeRepo = DriftTimeEntryRepository(TimeEntryDao(db), db);
    });

    tearDown(() => db.close());

    test('insertWithOverlapCheck inserts running entry', () async {
      final clientId = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('C')),
      );
      final id = await timeRepo.insertWithOverlapCheck(TimeEntriesCompanion(
        clientId: Value(clientId),
        startTime: Value(DateTime(2024, 1, 1, 9, 0)),
        hourlyRateSnapshot: const Value(100.0),
      ));
      expect(id, isNotEmpty);

      final entry = await timeRepo.getRunningEntry();
      expect(entry, isNotNull);
      expect(entry!.id, equals(id));
      expect(entry.endTime, isNull);
    });

    test('clockOut closes running entry', () async {
      final clientId = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('C')),
      );
      final id = await timeRepo.insertWithOverlapCheck(TimeEntriesCompanion(
        clientId: Value(clientId),
        startTime: Value(DateTime.now().subtract(const Duration(hours: 1))),
        hourlyRateSnapshot: const Value(100.0),
      ));
      final ok = await timeRepo.clockOut(id, description: 'Done');
      expect(ok, isTrue);

      final running = await timeRepo.getRunningEntry();
      expect(running, isNull);

      final completed = await timeRepo.getMostRecentCompleted();
      expect(completed, isNotNull);
      expect(completed!.description, equals('Done'));
      expect(completed.endTime, isNotNull);
      expect(completed.durationMinutes, isNotNull);
      expect(completed.durationMinutes, greaterThan(0));
    });

    test('insertWithOverlapCheck throws on overlap', () async {
      final clientId = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('C')),
      );
      // Insert a completed entry: 9:00–10:00
      await timeRepo.insertWithOverlapCheck(TimeEntriesCompanion(
        clientId: Value(clientId),
        startTime: Value(DateTime(2024, 1, 1, 9, 0)),
        endTime: Value(DateTime(2024, 1, 1, 10, 0)),
        durationMinutes: const Value(60),
        hourlyRateSnapshot: const Value(100.0),
      ));

      // Insert another that overlaps: 9:30–10:30
      expect(
        () => timeRepo.insertWithOverlapCheck(TimeEntriesCompanion(
          clientId: Value(clientId),
          startTime: Value(DateTime(2024, 1, 1, 9, 30)),
          endTime: Value(DateTime(2024, 1, 1, 10, 30)),
          durationMinutes: const Value(60),
          hourlyRateSnapshot: const Value(100.0),
        )),
        throwsA(isA<OverlappingTimeEntryException>()),
      );
    });

    test('deleteEntry removes entry', () async {
      final clientId = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('C')),
      );
      final id = await timeRepo.insertWithOverlapCheck(TimeEntriesCompanion(
        clientId: Value(clientId),
        startTime: Value(DateTime(2024, 1, 1, 9, 0)),
        endTime: Value(DateTime(2024, 1, 1, 10, 0)),
        durationMinutes: const Value(60),
        hourlyRateSnapshot: const Value(100.0),
      ));
      await timeRepo.deleteEntry(id);

      final all = await timeRepo.getAllEntries();
      expect(all.any((e) => e.id == id), isFalse);
    });

    test('updateRateForClient updates uninvoiced entries', () async {
      final clientId = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('C')),
      );
      await timeRepo.insertWithOverlapCheck(TimeEntriesCompanion(
        clientId: Value(clientId),
        startTime: Value(DateTime(2024, 1, 1, 9, 0)),
        endTime: Value(DateTime(2024, 1, 1, 10, 0)),
        durationMinutes: const Value(60),
        hourlyRateSnapshot: const Value(100.0),
      ));
      final updated = await timeRepo.updateRateForClient(clientId, 120.0);
      expect(updated, equals(1));

      final entries = await timeRepo.getUninvoicedForClient(clientId);
      expect(entries.first.hourlyRateSnapshot, equals(120.0));
    });

    test('markAsInvoiced and unmarkInvoiced work correctly', () async {
      final clientId = await clientRepo.insertClient(
        const ClientsCompanion(name: Value('C')),
      );
      // Seed a real invoice so the FK constraint is satisfied
      const invoiceId = 'invoice-test-001';
      await db.into(db.invoices).insert(InvoicesCompanion(
        id: const Value(invoiceId),
        clientId: Value(clientId),
        invoiceNumber: const Value('INV-0001'),
        issueDate: Value(DateTime(2024, 1, 1)),
        dueDate: Value(DateTime(2024, 1, 31)),
      ));

      final id = await timeRepo.insertWithOverlapCheck(TimeEntriesCompanion(
        clientId: Value(clientId),
        startTime: Value(DateTime(2024, 1, 1, 9, 0)),
        endTime: Value(DateTime(2024, 1, 1, 10, 0)),
        durationMinutes: const Value(60),
        hourlyRateSnapshot: const Value(100.0),
      ));

      await timeRepo.markAsInvoiced([id], invoiceId);
      final afterMark = await timeRepo.getAllEntries();
      expect(afterMark.first.isInvoiced, isTrue);
      expect(afterMark.first.invoiceId, equals(invoiceId));

      await timeRepo.unmarkInvoiced(invoiceId);
      final afterUnmark = await timeRepo.getAllEntries();
      expect(afterUnmark.first.isInvoiced, isFalse);
      expect(afterUnmark.first.invoiceId, isNull);
    });
  });
}
