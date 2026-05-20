import '../../database/app_database.dart';
import '../../database/daos/invoice_template_dao.dart';
import '../invoice_template_repository.dart';

class DriftInvoiceTemplateRepository implements InvoiceTemplateRepository {
  final InvoiceTemplateDao _dao;
  DriftInvoiceTemplateRepository(this._dao);

  @override Stream<List<InvoiceTemplate>> watchAll() => _dao.watchAll();
  @override Future<List<InvoiceTemplate>> getAll() => _dao.getAll();
  @override Future<InvoiceTemplate?> getById(String id) => _dao.getById(id);
  @override Future<InvoiceTemplate?> getByKey(String key) => _dao.getByKey(key);
  @override Future<InvoiceTemplate?> getDefault() => _dao.getDefault();
  @override Future<bool> updateTemplate(String id, InvoiceTemplatesCompanion c) => _dao.updateTemplate(id, c);
  @override Future<String> insertTemplate(InvoiceTemplatesCompanion c) => _dao.insertTemplate(c);
  @override Future<void> deleteTemplate(String id) => _dao.deleteTemplate(id);
  @override Future<void> setDefault(String id) => _dao.setDefault(id);
}
