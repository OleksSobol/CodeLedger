import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import 'tables/user_profiles_table.dart';
import 'tables/clients_table.dart';
import 'tables/projects_table.dart';
import 'tables/time_entries_table.dart';
import 'tables/invoices_table.dart';
import 'tables/invoice_line_items_table.dart';
import 'tables/invoice_templates_table.dart';
import 'tables/app_settings_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  UserProfiles,
  Clients,
  Projects,
  TimeEntries,
  Invoices,
  InvoiceLineItems,
  InvoiceTemplates,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // For testing
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _seedDefaults();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (!kIsWeb) {
            await customStatement('PRAGMA journal_mode = WAL');
          }
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await customStatement(
              "ALTER TABLE invoice_templates ADD COLUMN "
              "line_item_display_mode TEXT NOT NULL DEFAULT 'full'",
            );
            await customStatement(
              'ALTER TABLE invoice_line_items ADD COLUMN '
              'issue_reference TEXT',
            );
          }
          if (from < 3) {
            await customStatement(
              'ALTER TABLE projects ADD COLUMN github_repo TEXT',
            );
          }
          if (from < 4) {
            await customStatement(
              'ALTER TABLE invoice_templates ADD COLUMN '
              'show_description INTEGER NOT NULL DEFAULT 1',
            );
          }
          if (from < 5) {
            await _migrateIntPksToUuids(m);
          }
        },
      );

  Future<void> _seedDefaults() async {
    const uuid = Uuid();

    await into(userProfiles).insert(UserProfilesCompanion.insert(
      id: uuid.v4(),
    ));

    await batch((b) {
      b.insertAll(invoiceTemplates, [
        InvoiceTemplatesCompanion.insert(
          id: uuid.v4(),
          name: 'Minimal',
          templateKey: 'minimal',
          description: const Value('Clean single-line invoice'),
          isDefault: const Value(true),
          showDetailedBreakdown: const Value(false),
        ),
        InvoiceTemplatesCompanion.insert(
          id: uuid.v4(),
          name: 'Detailed Breakdown',
          templateKey: 'detailed',
          description:
              const Value('Grouped by date with session descriptions'),
          showDetailedBreakdown: const Value(true),
        ),
        InvoiceTemplatesCompanion.insert(
          id: uuid.v4(),
          name: 'Modern Developer',
          templateKey: 'modern_developer',
          description: const Value(
              'Tech-focused with repository and issue references'),
          primaryColor: const Value(0xFF00897B),
          accentColor: const Value(0xFF004D40),
          showDetailedBreakdown: const Value(true),
        ),
      ]);
    });
  }

  Future<void> eraseAllData() async {
    await transaction(() async {
      await delete(invoiceLineItems).go();
      await delete(timeEntries).go();
      await delete(invoices).go();
      await delete(projects).go();
      await delete(userProfiles).go();
      await delete(clients).go();
      await delete(invoiceTemplates).go();
      await _seedDefaults();
    });
  }

  static Future<String> get databasePath async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, AppConstants.dbFileName);
  }

  // ── UUID migration (v4 → v5) ─────────────────────────────────────

  static String _sqlLiteral(Object? v) {
    if (v == null) return 'NULL';
    if (v is int) return '$v';
    if (v is double) return '$v';
    if (v is bool) return v ? '1' : '0';
    if (v is String) return "'${v.replaceAll("'", "''")}'";
    return "'${v.toString().replaceAll("'", "''")}'";
  }

  Future<void> _insertRow(String table, Map<String, Object?> row) async {
    final cols = row.keys.join(', ');
    final vals = row.values.map(_sqlLiteral).join(', ');
    await customStatement('INSERT INTO $table ($cols) VALUES ($vals)');
  }

  Future<void> _migrateIntPksToUuids(Migrator m) async {
    await customStatement('PRAGMA foreign_keys = OFF');

    const uuid = Uuid();

    // Read all rows from the old int-PK tables
    final templateRows =
        await customSelect('SELECT * FROM invoice_templates').get();
    final clientRows = await customSelect('SELECT * FROM clients').get();
    final profileRows = await customSelect('SELECT * FROM user_profiles').get();
    final projectRows = await customSelect('SELECT * FROM projects').get();
    final invoiceRows = await customSelect('SELECT * FROM invoices').get();
    final entryRows = await customSelect('SELECT * FROM time_entries').get();
    final lineItemRows =
        await customSelect('SELECT * FROM invoice_line_items').get();

    // Build old-int-id → new-UUID maps
    final templateUuids = <int, String>{};
    for (final r in templateRows) {
      templateUuids[r.data['id'] as int] = uuid.v4();
    }
    final clientUuids = <int, String>{};
    for (final r in clientRows) {
      clientUuids[r.data['id'] as int] = uuid.v4();
    }
    final profileUuids = <int, String>{};
    for (final r in profileRows) {
      profileUuids[r.data['id'] as int] = uuid.v4();
    }
    final projectUuids = <int, String>{};
    for (final r in projectRows) {
      projectUuids[r.data['id'] as int] = uuid.v4();
    }
    final invoiceUuids = <int, String>{};
    for (final r in invoiceRows) {
      invoiceUuids[r.data['id'] as int] = uuid.v4();
    }
    final entryUuids = <int, String>{};
    for (final r in entryRows) {
      entryUuids[r.data['id'] as int] = uuid.v4();
    }
    final lineItemUuids = <int, String>{};
    for (final r in lineItemRows) {
      lineItemUuids[r.data['id'] as int] = uuid.v4();
    }

    // Drop old tables (reverse FK order so deps go first)
    await customStatement('DROP TABLE IF EXISTS invoice_line_items');
    await customStatement('DROP TABLE IF EXISTS time_entries');
    await customStatement('DROP TABLE IF EXISTS invoices');
    await customStatement('DROP TABLE IF EXISTS projects');
    await customStatement('DROP TABLE IF EXISTS user_profiles');
    await customStatement('DROP TABLE IF EXISTS clients');
    await customStatement('DROP TABLE IF EXISTS invoice_templates');

    // Recreate with new UUID schema (app_settings unchanged, IF NOT EXISTS)
    await m.createAll();

    // 1. invoice_templates (no FK)
    for (final r in templateRows) {
      final oldId = r.data['id'] as int;
      final row = Map<String, Object?>.from(r.data);
      row['id'] = templateUuids[oldId]!;
      await _insertRow('invoice_templates', row);
    }

    // 2. clients (FK → invoice_templates)
    for (final r in clientRows) {
      final oldId = r.data['id'] as int;
      final row = Map<String, Object?>.from(r.data);
      row['id'] = clientUuids[oldId]!;
      final oldTpl = r.data['default_template_id'] as int?;
      row['default_template_id'] =
          oldTpl != null ? templateUuids[oldTpl] : null;
      await _insertRow('clients', row);
    }

    // 3. user_profiles (FK → invoice_templates)
    for (final r in profileRows) {
      final oldId = r.data['id'] as int;
      final row = Map<String, Object?>.from(r.data);
      row['id'] = profileUuids[oldId]!;
      final oldTpl = r.data['default_template_id'] as int?;
      row['default_template_id'] =
          oldTpl != null ? templateUuids[oldTpl] : null;
      await _insertRow('user_profiles', row);
    }

    // 4. projects (FK → clients)
    for (final r in projectRows) {
      final oldId = r.data['id'] as int;
      final row = Map<String, Object?>.from(r.data);
      row['id'] = projectUuids[oldId]!;
      row['client_id'] = clientUuids[r.data['client_id'] as int]!;
      await _insertRow('projects', row);
    }

    // 5. invoices (FK → clients, invoice_templates)
    for (final r in invoiceRows) {
      final oldId = r.data['id'] as int;
      final row = Map<String, Object?>.from(r.data);
      row['id'] = invoiceUuids[oldId]!;
      row['client_id'] = clientUuids[r.data['client_id'] as int]!;
      final oldTpl = r.data['template_id'] as int?;
      row['template_id'] = oldTpl != null ? templateUuids[oldTpl] : null;
      await _insertRow('invoices', row);
    }

    // 6. time_entries (FK → clients, projects, invoices)
    for (final r in entryRows) {
      final oldId = r.data['id'] as int;
      final row = Map<String, Object?>.from(r.data);
      row['id'] = entryUuids[oldId]!;
      row['client_id'] = clientUuids[r.data['client_id'] as int]!;
      final oldProj = r.data['project_id'] as int?;
      row['project_id'] = oldProj != null ? projectUuids[oldProj] : null;
      final oldInv = r.data['invoice_id'] as int?;
      row['invoice_id'] = oldInv != null ? invoiceUuids[oldInv] : null;
      await _insertRow('time_entries', row);
    }

    // 7. invoice_line_items (FK → invoices, time_entries, projects)
    for (final r in lineItemRows) {
      final oldId = r.data['id'] as int;
      final row = Map<String, Object?>.from(r.data);
      row['id'] = lineItemUuids[oldId]!;
      row['invoice_id'] = invoiceUuids[r.data['invoice_id'] as int]!;
      final oldEntry = r.data['time_entry_id'] as int?;
      row['time_entry_id'] = oldEntry != null ? entryUuids[oldEntry] : null;
      final oldProj = r.data['project_id'] as int?;
      row['project_id'] = oldProj != null ? projectUuids[oldProj] : null;
      await _insertRow('invoice_line_items', row);
    }

    await customStatement('PRAGMA foreign_keys = ON');
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'code_ledger',
    web: kIsWeb
        ? DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          )
        : null,
  );
}
