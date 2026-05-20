import '../../database/app_database.dart';
import '../../database/daos/invoice_dao.dart';
import '../invoice_repository.dart';

class DriftInvoiceRepository implements InvoiceRepository {
  final InvoiceDao _dao;
  DriftInvoiceRepository(this._dao);

  @override Stream<List<Invoice>> watchInvoices({String? clientId}) => _dao.watchInvoices(clientId: clientId);
  @override Future<Invoice> getInvoice(String id) => _dao.getInvoice(id);
  @override Future<List<InvoiceLineItem>> getLineItems(String invoiceId) => _dao.getLineItems(invoiceId);
  @override Stream<List<InvoiceLineItem>> watchLineItems(String invoiceId) => _dao.watchLineItems(invoiceId);
  @override Future<String> createInvoice({required InvoicesCompanion invoice, required List<InvoiceLineItemsCompanion> lineItems, required List<String> timeEntryIds}) =>
      _dao.createInvoice(invoice: invoice, lineItems: lineItems, timeEntryIds: timeEntryIds);
  @override Future<bool> updateStatus(String id, String status) => _dao.updateStatus(id, status);
  @override Future<bool> recordPayment({required String invoiceId, required double amount, required String method}) =>
      _dao.recordPayment(invoiceId: invoiceId, amount: amount, method: method);
  @override Future<void> deleteDraftInvoice(String invoiceId) => _dao.deleteDraftInvoice(invoiceId);
  @override Future<bool> archiveInvoice(String invoiceId) => _dao.archiveInvoice(invoiceId);
  @override Future<bool> unarchiveInvoice(String invoiceId) => _dao.unarchiveInvoice(invoiceId);
  @override Future<void> deleteInvoice(String invoiceId) => _dao.deleteInvoice(invoiceId);
  @override Future<void> appendLineItems({required String invoiceId, required List<InvoiceLineItemsCompanion> lineItems, required List<String> timeEntryIds}) =>
      _dao.appendLineItems(invoiceId: invoiceId, lineItems: lineItems, timeEntryIds: timeEntryIds);
  @override Future<void> updateLineItem({required String lineItemId, required String invoiceId, required String description, required double quantity, required double unitPrice}) =>
      _dao.updateLineItem(lineItemId: lineItemId, invoiceId: invoiceId, description: description, quantity: quantity, unitPrice: unitPrice);
  @override Future<bool> revertToDraft(String invoiceId) => _dao.revertToDraft(invoiceId);
  @override Future<List<Invoice>> getByStatus(String status) => _dao.getByStatus(status);
  @override Future<List<Invoice>> getOverdueInvoices() => _dao.getOverdueInvoices();
  @override Future<bool> updateInvoiceNumber(String invoiceId, String invoiceNumber) => _dao.updateInvoiceNumber(invoiceId, invoiceNumber);
  @override Future<bool> updateDraftInvoice({required String invoiceId, required String clientId, required String invoiceNumber, required DateTime issueDate, required DateTime dueDate, required double subtotal, required double taxRate, required String taxLabel, required String currency, String? notes}) =>
      _dao.updateDraftInvoice(invoiceId: invoiceId, clientId: clientId, invoiceNumber: invoiceNumber, issueDate: issueDate, dueDate: dueDate, subtotal: subtotal, taxRate: taxRate, taxLabel: taxLabel, currency: currency, notes: notes);
  @override Future<bool> updateTemplate(String invoiceId, String? templateId) => _dao.updateTemplate(invoiceId, templateId);
  @override Future<bool> updatePdfPath(String invoiceId, String path) => _dao.updatePdfPath(invoiceId, path);
  @override Future<List<LineItemWithDetails>> getLineItemsWithDetails(String invoiceId) => _dao.getLineItemsWithDetails(invoiceId);
}
