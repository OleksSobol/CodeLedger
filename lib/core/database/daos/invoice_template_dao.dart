import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
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

  Future<InvoiceTemplate?> getById(String id) {
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

  Future<bool> updateTemplate(String id, InvoiceTemplatesCompanion companion) {
    return (update(invoiceTemplates)..where((t) => t.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
  }

  Future<String> insertTemplate(InvoiceTemplatesCompanion companion) async {
    const uuid = Uuid();
    final id = uuid.v4();
    await into(invoiceTemplates).insert(companion.copyWith(id: Value(id)));
    return id;
  }

  Future<void> deleteTemplate(String id) async {
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

  Future<void> setDefault(String id) async {
    await customStatement(
        'UPDATE invoice_templates SET is_default = 0');
    await (update(invoiceTemplates)..where((t) => t.id.equals(id)))
        .write(const InvoiceTemplatesCompanion(isDefault: Value(true)));
  }
}
