import '../database/app_database.dart';
import '../database/daos/invoice_dao.dart';

export '../database/daos/invoice_dao.dart' show LineItemWithDetails;

abstract class InvoiceRepository {
  Stream<List<Invoice>> watchInvoices({String? clientId});
  Future<Invoice> getInvoice(String id);
  Future<List<InvoiceLineItem>> getLineItems(String invoiceId);
  Stream<List<InvoiceLineItem>> watchLineItems(String invoiceId);
  Future<String> createInvoice({
    required InvoicesCompanion invoice,
    required List<InvoiceLineItemsCompanion> lineItems,
    required List<String> timeEntryIds,
  });
  Future<bool> updateStatus(String id, String status);
  Future<bool> recordPayment({required String invoiceId, required double amount, required String method});
  Future<void> deleteDraftInvoice(String invoiceId);
  Future<bool> archiveInvoice(String invoiceId);
  Future<bool> unarchiveInvoice(String invoiceId);
  Future<void> deleteInvoice(String invoiceId);
  Future<void> appendLineItems({
    required String invoiceId,
    required List<InvoiceLineItemsCompanion> lineItems,
    required List<String> timeEntryIds,
  });
  Future<void> updateLineItem({
    required String lineItemId,
    required String invoiceId,
    required String description,
    required double quantity,
    required double unitPrice,
  });
  Future<bool> revertToDraft(String invoiceId);
  Future<List<Invoice>> getByStatus(String status);
  Future<List<Invoice>> getOverdueInvoices();
  Future<bool> updateInvoiceNumber(String invoiceId, String invoiceNumber);
  Future<bool> updateDraftInvoice({
    required String invoiceId,
    required String clientId,
    required String invoiceNumber,
    required DateTime issueDate,
    required DateTime dueDate,
    required double subtotal,
    required double taxRate,
    required String taxLabel,
    required String currency,
    String? notes,
  });
  Future<bool> updateTemplate(String invoiceId, String? templateId);
  Future<bool> updatePdfPath(String invoiceId, String path);
  Future<List<LineItemWithDetails>> getLineItemsWithDetails(String invoiceId);
}
