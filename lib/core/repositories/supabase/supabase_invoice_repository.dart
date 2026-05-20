import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../database/app_database.dart';
import '../invoice_repository.dart';

class SupabaseInvoiceRepository implements InvoiceRepository {
  final SupabaseClient _client;
  SupabaseInvoiceRepository(this._client);

  String get _uid => _client.auth.currentUser!.id;

  Invoice _fromInvoiceRow(Map<String, dynamic> r) => Invoice(
        id: r['id'] as String,
        clientId: r['client_id'] as String,
        invoiceNumber: r['invoice_number'] as String,
        status: r['status'] as String? ?? 'draft',
        issueDate: DateTime.parse(r['issue_date'] as String),
        dueDate: DateTime.parse(r['due_date'] as String),
        periodStart: r['period_start'] != null
            ? DateTime.parse(r['period_start'] as String)
            : null,
        periodEnd: r['period_end'] != null
            ? DateTime.parse(r['period_end'] as String)
            : null,
        subtotal: (r['subtotal'] as num?)?.toDouble() ?? 0.0,
        taxRate: (r['tax_rate'] as num?)?.toDouble() ?? 0.0,
        taxLabel: r['tax_label'] as String? ?? 'Tax',
        taxAmount: (r['tax_amount'] as num?)?.toDouble() ?? 0.0,
        lateFeeAmount: (r['late_fee_amount'] as num?)?.toDouble() ?? 0.0,
        total: (r['total'] as num?)?.toDouble() ?? 0.0,
        amountPaid: (r['amount_paid'] as num?)?.toDouble() ?? 0.0,
        currency: r['currency'] as String? ?? 'USD',
        notes: r['notes'] as String?,
        templateId: r['template_id'] as String?,
        templateType: r['template_type'] as String? ?? 'detailed',
        pdfPath: r['pdf_path'] as String?,
        paymentMethod: r['payment_method'] as String?,
        paidDate: r['paid_date'] != null
            ? DateTime.parse(r['paid_date'] as String)
            : null,
        sentDate: r['sent_date'] != null
            ? DateTime.parse(r['sent_date'] as String)
            : null,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  InvoiceLineItem _fromLineItemRow(Map<String, dynamic> r) => InvoiceLineItem(
        id: r['id'] as String,
        invoiceId: r['invoice_id'] as String,
        sortOrder: r['sort_order'] as int? ?? 0,
        description: r['description'] as String,
        quantity: (r['quantity'] as num).toDouble(),
        unitPrice: (r['unit_price'] as num).toDouble(),
        total: (r['total'] as num).toDouble(),
        timeEntryId: r['time_entry_id'] as String?,
        projectId: r['project_id'] as String?,
        issueReference: r['issue_reference'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
      );

  TimeEntry _fromTimeEntryRow(Map<String, dynamic> r) => TimeEntry(
        id: r['id'] as String,
        clientId: r['client_id'] as String,
        projectId: r['project_id'] as String?,
        startTime: DateTime.parse(r['start_time'] as String),
        endTime: r['end_time'] != null
            ? DateTime.parse(r['end_time'] as String)
            : null,
        durationMinutes: r['duration_minutes'] as int?,
        description: r['description'] as String?,
        issueReference: r['issue_reference'] as String?,
        repository: r['repository'] as String?,
        tags: r['tags'] as String?,
        isManual: r['is_manual'] as bool? ?? false,
        hourlyRateSnapshot: (r['hourly_rate_snapshot'] as num).toDouble(),
        isInvoiced: r['is_invoiced'] as bool? ?? false,
        invoiceId: r['invoice_id'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  Project _fromProjectRow(Map<String, dynamic> r) => Project(
        id: r['id'] as String,
        clientId: r['client_id'] as String,
        name: r['name'] as String,
        description: r['description'] as String?,
        hourlyRateOverride: (r['hourly_rate_override'] as num?)?.toDouble(),
        color: r['color'] as int? ?? 0xFF2196F3,
        githubRepo: r['github_repo'] as String?,
        isActive: r['is_active'] as bool? ?? true,
        isArchived: r['is_archived'] as bool? ?? false,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  @override
  Stream<List<Invoice>> watchInvoices({String? clientId}) =>
      Stream.fromFuture(_fetchInvoices(clientId: clientId));

  Future<List<Invoice>> _fetchInvoices({String? clientId}) async {
    var query = _client.from('invoices').select();
    if (clientId != null) {
      query = query.eq('client_id', clientId);
    }
    final rows = await query.order('issue_date', ascending: false);
    return rows.map(_fromInvoiceRow).toList();
  }

  @override
  Future<Invoice> getInvoice(String id) async {
    final row =
        await _client.from('invoices').select().eq('id', id).single();
    return _fromInvoiceRow(row);
  }

  @override
  Future<List<InvoiceLineItem>> getLineItems(String invoiceId) async {
    final rows = await _client
        .from('invoice_line_items')
        .select()
        .eq('invoice_id', invoiceId)
        .order('sort_order');
    return rows.map(_fromLineItemRow).toList();
  }

  @override
  Stream<List<InvoiceLineItem>> watchLineItems(String invoiceId) =>
      Stream.fromFuture(getLineItems(invoiceId));

  @override
  Future<String> createInvoice({
    required InvoicesCompanion invoice,
    required List<InvoiceLineItemsCompanion> lineItems,
    required List<String> timeEntryIds,
  }) async {
    const uuid = Uuid();
    final invoiceId = uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await _client.from('invoices').insert({
      'id': invoiceId,
      'user_id': _uid,
      'client_id': invoice.clientId.value,
      'invoice_number': invoice.invoiceNumber.value,
      'status': invoice.status.present ? invoice.status.value : 'draft',
      'issue_date': invoice.issueDate.value.toUtc().toIso8601String(),
      'due_date': invoice.dueDate.value.toUtc().toIso8601String(),
      'period_start': invoice.periodStart.present
          ? invoice.periodStart.value?.toUtc().toIso8601String()
          : null,
      'period_end': invoice.periodEnd.present
          ? invoice.periodEnd.value?.toUtc().toIso8601String()
          : null,
      'subtotal': invoice.subtotal.present ? invoice.subtotal.value : 0.0,
      'tax_rate': invoice.taxRate.present ? invoice.taxRate.value : 0.0,
      'tax_label': invoice.taxLabel.present ? invoice.taxLabel.value : 'Tax',
      'tax_amount': invoice.taxAmount.present ? invoice.taxAmount.value : 0.0,
      'late_fee_amount': invoice.lateFeeAmount.present ? invoice.lateFeeAmount.value : 0.0,
      'total': invoice.total.present ? invoice.total.value : 0.0,
      'amount_paid': 0.0,
      'currency': invoice.currency.present ? invoice.currency.value : 'USD',
      'notes': invoice.notes.present ? invoice.notes.value : null,
      'template_id': invoice.templateId.present ? invoice.templateId.value : null,
      'template_type': invoice.templateType.present ? invoice.templateType.value : 'detailed',
      'created_at': now,
      'updated_at': now,
    });

    for (var i = 0; i < lineItems.length; i++) {
      final item = lineItems[i];
      await _client.from('invoice_line_items').insert({
        'id': uuid.v4(),
        'user_id': _uid,
        'invoice_id': invoiceId,
        'sort_order': i,
        'description': item.description.value,
        'quantity': item.quantity.value,
        'unit_price': item.unitPrice.value,
        'total': item.total.value,
        'time_entry_id': item.timeEntryId.present ? item.timeEntryId.value : null,
        'project_id': item.projectId.present ? item.projectId.value : null,
        'issue_reference': item.issueReference.present ? item.issueReference.value : null,
        'created_at': now,
      });
    }

    if (timeEntryIds.isNotEmpty) {
      await _client.from('time_entries').update({
        'is_invoiced': true,
        'invoice_id': invoiceId,
        'updated_at': now,
      }).inFilter('id', timeEntryIds);
    }

    return invoiceId;
  }

  @override
  Future<bool> updateStatus(String id, String status) async {
    final map = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (status == 'sent') map['sent_date'] = map['updated_at'];
    final result =
        await _client.from('invoices').update(map).eq('id', id).select();
    return result.isNotEmpty;
  }

  @override
  Future<bool> recordPayment({
    required String invoiceId,
    required double amount,
    required String method,
  }) async {
    final invoice = await getInvoice(invoiceId);
    final newPaid = invoice.amountPaid + amount;
    final isPaid = newPaid >= invoice.total - 0.005;
    final now = DateTime.now().toUtc().toIso8601String();
    final map = <String, dynamic>{
      'amount_paid': newPaid,
      'payment_method': method,
      'updated_at': now,
    };
    if (isPaid) {
      map['status'] = 'paid';
      map['paid_date'] = now;
    }
    final result = await _client
        .from('invoices')
        .update(map)
        .eq('id', invoiceId)
        .select();
    return result.isNotEmpty;
  }

  @override
  Future<void> deleteDraftInvoice(String invoiceId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('time_entries').update({
      'is_invoiced': false,
      'invoice_id': null,
      'updated_at': now,
    }).eq('invoice_id', invoiceId);
    await _client
        .from('invoice_line_items')
        .delete()
        .eq('invoice_id', invoiceId);
    await _client.from('invoices').delete().eq('id', invoiceId);
  }

  @override
  Future<bool> archiveInvoice(String invoiceId) async {
    final result = await _client.from('invoices').update({
      'status': 'archived',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invoiceId).select();
    return result.isNotEmpty;
  }

  @override
  Future<bool> unarchiveInvoice(String invoiceId) async {
    final result = await _client.from('invoices').update({
      'status': 'paid',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invoiceId).select();
    return result.isNotEmpty;
  }

  @override
  Future<void> deleteInvoice(String invoiceId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('time_entries').update({
      'is_invoiced': false,
      'invoice_id': null,
      'updated_at': now,
    }).eq('invoice_id', invoiceId);
    await _client
        .from('invoice_line_items')
        .delete()
        .eq('invoice_id', invoiceId);
    await _client.from('invoices').delete().eq('id', invoiceId);
  }

  @override
  Future<void> appendLineItems({
    required String invoiceId,
    required List<InvoiceLineItemsCompanion> lineItems,
    required List<String> timeEntryIds,
  }) async {
    const uuid = Uuid();
    final now = DateTime.now().toUtc().toIso8601String();

    final existing = await getLineItems(invoiceId);
    var sortOrder = existing.isEmpty
        ? 0
        : existing.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    for (final item in lineItems) {
      await _client.from('invoice_line_items').insert({
        'id': uuid.v4(),
        'user_id': _uid,
        'invoice_id': invoiceId,
        'sort_order': sortOrder++,
        'description': item.description.value,
        'quantity': item.quantity.value,
        'unit_price': item.unitPrice.value,
        'total': item.total.value,
        'time_entry_id': item.timeEntryId.present ? item.timeEntryId.value : null,
        'project_id': item.projectId.present ? item.projectId.value : null,
        'issue_reference': item.issueReference.present ? item.issueReference.value : null,
        'created_at': now,
      });
    }

    if (timeEntryIds.isNotEmpty) {
      await _client.from('time_entries').update({
        'is_invoiced': true,
        'invoice_id': invoiceId,
        'updated_at': now,
      }).inFilter('id', timeEntryIds);
    }

    final allItems = await getLineItems(invoiceId);
    final subtotal = allItems.fold<double>(0, (sum, i) => sum + i.total);
    final invoice = await getInvoice(invoiceId);
    final taxAmount = subtotal * (invoice.taxRate / 100);
    final total = subtotal + taxAmount + invoice.lateFeeAmount;

    await _client.from('invoices').update({
      'subtotal': subtotal,
      'tax_amount': taxAmount,
      'total': total,
      'updated_at': now,
    }).eq('id', invoiceId);
  }

  @override
  Future<void> updateLineItem({
    required String lineItemId,
    required String invoiceId,
    required String description,
    required double quantity,
    required double unitPrice,
  }) async {
    final itemTotal = quantity * unitPrice;
    await _client.from('invoice_line_items').update({
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total': itemTotal,
    }).eq('id', lineItemId);

    final items = await getLineItems(invoiceId);
    final subtotal = items.fold<double>(0, (sum, i) => sum + i.total);
    final invoice = await getInvoice(invoiceId);
    final taxAmount = subtotal * (invoice.taxRate / 100);
    final total = subtotal + taxAmount + invoice.lateFeeAmount;

    await _client.from('invoices').update({
      'subtotal': subtotal,
      'tax_amount': taxAmount,
      'total': total,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invoiceId);
  }

  @override
  Future<bool> revertToDraft(String invoiceId) async {
    final result = await _client.from('invoices').update({
      'status': 'draft',
      'sent_date': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invoiceId).select();
    return result.isNotEmpty;
  }

  @override
  Future<List<Invoice>> getByStatus(String status) async {
    final rows = await _client
        .from('invoices')
        .select()
        .eq('status', status)
        .order('issue_date', ascending: false);
    return rows.map(_fromInvoiceRow).toList();
  }

  @override
  Future<List<Invoice>> getOverdueInvoices() async {
    final rows = await _client
        .from('invoices')
        .select()
        .eq('status', 'sent')
        .lt('due_date', DateTime.now().toUtc().toIso8601String());
    return rows.map(_fromInvoiceRow).toList();
  }

  @override
  Future<bool> updateInvoiceNumber(
      String invoiceId, String invoiceNumber) async {
    final result = await _client.from('invoices').update({
      'invoice_number': invoiceNumber,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invoiceId).select();
    return result.isNotEmpty;
  }

  @override
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
  }) async {
    final invoice = await getInvoice(invoiceId);
    final taxAmount = subtotal * (taxRate / 100);
    final total = subtotal + taxAmount + invoice.lateFeeAmount;
    final result = await _client.from('invoices').update({
      'client_id': clientId,
      'invoice_number': invoiceNumber,
      'issue_date': issueDate.toUtc().toIso8601String(),
      'due_date': dueDate.toUtc().toIso8601String(),
      'subtotal': subtotal,
      'tax_rate': taxRate,
      'tax_label': taxLabel,
      'tax_amount': taxAmount,
      'total': total,
      'currency': currency,
      'notes': notes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invoiceId).select();
    return result.isNotEmpty;
  }

  @override
  Future<bool> updateTemplate(String invoiceId, String? templateId) async {
    final result = await _client.from('invoices').update({
      'template_id': templateId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invoiceId).select();
    return result.isNotEmpty;
  }

  @override
  Future<bool> updatePdfPath(String invoiceId, String path) async {
    final result = await _client.from('invoices').update({
      'pdf_path': path,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invoiceId).select();
    return result.isNotEmpty;
  }

  @override
  Future<List<LineItemWithDetails>> getLineItemsWithDetails(
      String invoiceId) async {
    final items = await getLineItems(invoiceId);
    return Future.wait(items.map((item) async {
      TimeEntry? timeEntry;
      Project? project;
      if (item.timeEntryId != null) {
        final teRow = await _client
            .from('time_entries')
            .select()
            .eq('id', item.timeEntryId!)
            .maybeSingle();
        if (teRow != null) timeEntry = _fromTimeEntryRow(teRow);
      }
      if (item.projectId != null) {
        final pRow = await _client
            .from('projects')
            .select()
            .eq('id', item.projectId!)
            .maybeSingle();
        if (pRow != null) project = _fromProjectRow(pRow);
      }
      return LineItemWithDetails(
          lineItem: item, timeEntry: timeEntry, project: project);
    }));
  }
}
