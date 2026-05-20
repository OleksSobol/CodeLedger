import '../database/app_database.dart';

abstract class InvoiceTemplateRepository {
  Stream<List<InvoiceTemplate>> watchAll();
  Future<List<InvoiceTemplate>> getAll();
  Future<InvoiceTemplate?> getById(String id);
  Future<InvoiceTemplate?> getByKey(String key);
  Future<InvoiceTemplate?> getDefault();
  Future<bool> updateTemplate(String id, InvoiceTemplatesCompanion companion);
  Future<String> insertTemplate(InvoiceTemplatesCompanion companion);
  Future<void> deleteTemplate(String id);
  Future<void> setDefault(String id);
}
