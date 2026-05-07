import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/invoice_templates_table.dart';

part 'invoice_template_dao.g.dart';

@DriftAccessor(tables: [InvoiceTemplates])
class InvoiceTemplateDao extends DatabaseAccessor<AppDatabase>
    with _$InvoiceTemplateDaoMixin {
  InvoiceTemplateDao(super.db);

  Stream<List<InvoiceTemplate>> watchAll() {
    return (select(invoiceTemplates)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<List<InvoiceTemplate>> getAll() {
    return (select(invoiceTemplates)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<InvoiceTemplate?> getById(int id) {
    return (select(invoiceTemplates)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<InvoiceTemplate?> getByKey(String key) {
    return (select(invoiceTemplates)
          ..where((t) => t.templateKey.equals(key)))
        .getSingleOrNull();
  }

  Future<InvoiceTemplate?> getDefault() async {
    final results = await (select(invoiceTemplates)
          ..where((t) => t.isDefault.equals(true))
          ..limit(1))
        .get();
    return results.isEmpty ? null : results.first;
  }

  /// Update an existing template's styling fields.
  Future<bool> updateTemplate(int id, InvoiceTemplatesCompanion companion) {
    return (update(invoiceTemplates)..where((t) => t.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
  }

  /// Insert a new custom template.
  Future<int> insertTemplate(InvoiceTemplatesCompanion companion) {
    return into(invoiceTemplates).insert(companion);
  }

  /// Clear all nullable FK references to this template, then delete it.
  Future<void> deleteTemplate(int id) async {
    await customStatement(
        'UPDATE invoices SET template_id = NULL WHERE template_id = ?', [id]);
    await customStatement(
        'UPDATE clients SET default_template_id = NULL WHERE default_template_id = ?',
        [id]);
    await customStatement(
        'UPDATE user_profiles SET default_template_id = NULL WHERE default_template_id = ?',
        [id]);
    await (delete(invoiceTemplates)..where((t) => t.id.equals(id))).go();
  }

  /// Set a template as default (clear others first).
  Future<void> setDefault(int id) async {
    await customStatement(
        'UPDATE invoice_templates SET is_default = 0');
    await (update(invoiceTemplates)..where((t) => t.id.equals(id)))
        .write(const InvoiceTemplatesCompanion(isDefault: Value(true)));
  }
}
