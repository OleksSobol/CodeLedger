import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _seedDefaults();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            // v2: line-item display mode on templates; issue reference on items
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
            // v3: github repo link on projects
            await customStatement(
              'ALTER TABLE projects ADD COLUMN github_repo TEXT',
            );
          }
          if (from < 4) {
            // v4: show_description toggle on templates
            await customStatement(
              'ALTER TABLE invoice_templates ADD COLUMN '
              'show_description INTEGER NOT NULL DEFAULT 1',
            );
          }
        },
      );

  Future<void> _seedDefaults() async {
    // Insert default user profile row
    await into(userProfiles).insert(UserProfilesCompanion.insert());

    // Insert built-in invoice templates
    await batch((batch) {
      batch.insertAll(invoiceTemplates, [
        InvoiceTemplatesCompanion.insert(
          name: 'Minimal',
          templateKey: 'minimal',
          description: const Value('Clean single-line invoice'),
          isDefault: const Value(true),
          showDetailedBreakdown: const Value(false),
        ),
        InvoiceTemplatesCompanion.insert(
          name: 'Detailed Breakdown',
          templateKey: 'detailed',
          description:
              const Value('Grouped by date with session descriptions'),
          showDetailedBreakdown: const Value(true),
        ),
        InvoiceTemplatesCompanion.insert(
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

  /// Deletes all user data and re-seeds defaults.
  ///
  /// Preserves app_settings (passphrase etc.) and resets user profile.
  /// Caller must restart the app after this completes.
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

  /// Returns the path to the database file (for backup operations).
  static Future<String> get databasePath async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, AppConstants.dbFileName);
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'code_ledger');
}
