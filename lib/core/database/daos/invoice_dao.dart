import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../tables/invoices_table.dart';
import '../tables/invoice_line_items_table.dart';
import '../tables/time_entries_table.dart';
import '../tables/projects_table.dart';

part 'invoice_dao.g.dart';

@DriftAccessor(tables: [Invoices, InvoiceLineItems, TimeEntries, Projects])
class InvoiceDao extends DatabaseAccessor<AppDatabase>
    with _$InvoiceDaoMixin {
  InvoiceDao(super.db);

  Stream<List<Invoice>> watchInvoices({String? clientId}) {
    final query = select(invoices);
    if (clientId != null) {
      query.where((t) => t.clientId.equals(clientId));
    }
    query.orderBy([(t) => OrderingTerm.desc(t.issueDate)]);
    return query.watch();
  }

  Future<Invoice> getInvoice(String id) {
    return (select(invoices)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<List<InvoiceLineItem>> getLineItems(String invoiceId) {
    return (select(invoiceLineItems)
          ..where((t) => t.invoiceId.equals(invoiceId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Stream<List<InvoiceLineItem>> watchLineItems(String invoiceId) {
    return (select(invoiceLineItems)
          ..where((t) => t.invoiceId.equals(invoiceId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<String> createInvoice({
    required InvoicesCompanion invoice,
    required List<InvoiceLineItemsCompanion> lineItems,
    required List<String> timeEntryIds,
  }) {
    return transaction(() async {
      const uuid = Uuid();
      final invoiceId = uuid.v4();
      await into(invoices).insert(invoice.copyWith(id: Value(invoiceId)));

      for (final item in lineItems) {
        final lineItemId = uuid.v4();
        await into(invoiceLineItems).insert(
          item.copyWith(id: Value(lineItemId), invoiceId: Value(invoiceId)),
        );
      }

      if (timeEntryIds.isNotEmpty) {
        await (update(timeEntries)
              ..where((t) => t.id.isIn(timeEntryIds)))
            .write(TimeEntriesCompanion(
              isInvoiced: const Value(true),
              invoiceId: Value(invoiceId),
              updatedAt: Value(DateTime.now()),
            ));
      }

      return invoiceId;
    });
  }

  Future<bool> updateStatus(String id, String status) {
    final companion = InvoicesCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
    );

    if (status == 'sent') {
      return (update(invoices)..where((t) => t.id.equals(id)))
          .write(companion.copyWith(sentDate: Value(DateTime.now())))
          .then((rows) => rows > 0);
    }

    return (update(invoices)..where((t) => t.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
  }

  Future<bool> recordPayment({
    required String invoiceId,
    required double amount,
    required String method,
  }) {
    return transaction(() async {
      final invoice = await getInvoice(invoiceId);
      final newPaid = invoice.amountPaid + amount;
      final isPaid = newPaid >= invoice.total - 0.005;

      return (update(invoices)..where((t) => t.id.equals(invoiceId)))
          .write(InvoicesCompanion(
            amountPaid: Value(newPaid),
            paymentMethod: Value(method),
            status: isPaid ? const Value('paid') : const Value.absent(),
            paidDate: isPaid ? Value(DateTime.now()) : const Value.absent(),
            updatedAt: Value(DateTime.now()),
          ))
          .then((rows) => rows > 0);
    });
  }

  Future<void> deleteDraftInvoice(String invoiceId) {
    return transaction(() async {
      await (update(timeEntries)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .write(const TimeEntriesCompanion(
            isInvoiced: Value(false),
            invoiceId: Value(null),
          ));

      await (delete(invoiceLineItems)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .go();

      await (delete(invoices)..where((t) => t.id.equals(invoiceId))).go();
    });
  }

  Future<bool> archiveInvoice(String invoiceId) {
    return (update(invoices)..where((t) => t.id.equals(invoiceId)))
        .write(InvoicesCompanion(
          status: const Value('archived'),
          updatedAt: Value(DateTime.now()),
        ))
        .then((rows) => rows > 0);
  }

  Future<bool> unarchiveInvoice(String invoiceId) {
    return (update(invoices)..where((t) => t.id.equals(invoiceId)))
        .write(InvoicesCompanion(
          status: const Value('paid'),
          updatedAt: Value(DateTime.now()),
        ))
        .then((rows) => rows > 0);
  }

  Future<void> deleteInvoice(String invoiceId) {
    return transaction(() async {
      await (update(timeEntries)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .write(const TimeEntriesCompanion(
            isInvoiced: Value(false),
            invoiceId: Value(null),
          ));

      await (delete(invoiceLineItems)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .go();

      await (delete(invoices)..where((t) => t.id.equals(invoiceId))).go();
    });
  }

  Future<void> appendLineItems({
    required String invoiceId,
    required List<InvoiceLineItemsCompanion> lineItems,
    required List<String> timeEntryIds,
  }) {
    return transaction(() async {
      const uuid = Uuid();
      final existing = await getLineItems(invoiceId);
      var sortOrder = existing.isEmpty
          ? 0
          : (existing
                  .map((e) => e.sortOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1);

      for (final item in lineItems) {
        final lineItemId = uuid.v4();
        await into(invoiceLineItems).insert(
          item.copyWith(
            id: Value(lineItemId),
            invoiceId: Value(invoiceId),
            sortOrder: Value(sortOrder++),
          ),
        );
      }

      if (timeEntryIds.isNotEmpty) {
        await (update(timeEntries)
              ..where((t) => t.id.isIn(timeEntryIds)))
            .write(TimeEntriesCompanion(
          isInvoiced: const Value(true),
          invoiceId: Value(invoiceId),
          updatedAt: Value(DateTime.now()),
        ));
      }

      final items = await getLineItems(invoiceId);
      final subtotal = items.fold<double>(0, (sum, i) => sum + i.total);
      final inv = await getInvoice(invoiceId);
      final taxAmount = subtotal * (inv.taxRate / 100);
      final total = subtotal + taxAmount + inv.lateFeeAmount;

      DateTime? periodStart = inv.periodStart;
      DateTime? periodEnd = inv.periodEnd;
      if (timeEntryIds.isNotEmpty) {
        final added = await (select(timeEntries)
              ..where((t) => t.id.isIn(timeEntryIds)))
            .get();
        for (final e in added) {
          final s = e.startTime;
          final eEnd = e.endTime ?? e.startTime;
          periodStart = (periodStart == null || s.isBefore(periodStart))
              ? s
              : periodStart;
          periodEnd = (periodEnd == null || eEnd.isAfter(periodEnd))
              ? eEnd
              : periodEnd;
        }
      }

      await (update(invoices)..where((t) => t.id.equals(invoiceId)))
          .write(InvoicesCompanion(
        subtotal: Value(subtotal),
        taxAmount: Value(taxAmount),
        total: Value(total),
        periodStart: Value(periodStart),
        periodEnd: Value(periodEnd),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  Future<void> updateLineItem({
    required String lineItemId,
    required String invoiceId,
    required String description,
    required double quantity,
    required double unitPrice,
  }) {
    return transaction(() async {
      final itemTotal = quantity * unitPrice;

      await (update(invoiceLineItems)
            ..where((t) => t.id.equals(lineItemId)))
          .write(InvoiceLineItemsCompanion(
        description: Value(description),
        quantity: Value(quantity),
        unitPrice: Value(unitPrice),
        total: Value(itemTotal),
      ));

      final items = await getLineItems(invoiceId);
      final subtotal = items.fold<double>(0, (sum, i) => sum + i.total);
      final inv = await getInvoice(invoiceId);
      final taxAmount = subtotal * (inv.taxRate / 100);
      final total = subtotal + taxAmount + inv.lateFeeAmount;

      await (update(invoices)..where((t) => t.id.equals(invoiceId)))
          .write(InvoicesCompanion(
        subtotal: Value(subtotal),
        taxAmount: Value(taxAmount),
        total: Value(total),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  Future<bool> revertToDraft(String invoiceId) {
    return (update(invoices)..where((t) => t.id.equals(invoiceId)))
        .write(InvoicesCompanion(
          status: const Value('draft'),
          sentDate: const Value(null),
          updatedAt: Value(DateTime.now()),
        ))
        .then((rows) => rows > 0);
  }

  Future<List<Invoice>> getByStatus(String status) {
    return (select(invoices)
          ..where((t) => t.status.equals(status))
          ..orderBy([(t) => OrderingTerm.desc(t.issueDate)]))
        .get();
  }

  Future<List<Invoice>> getOverdueInvoices() {
    return (select(invoices)
          ..where((t) =>
              t.status.equals('sent') &
              t.dueDate.isSmallerThanValue(DateTime.now())))
        .get();
  }

  Future<bool> updateInvoiceNumber(String invoiceId, String invoiceNumber) {
    return (update(invoices)..where((t) => t.id.equals(invoiceId)))
        .write(InvoicesCompanion(
          invoiceNumber: Value(invoiceNumber),
          updatedAt: Value(DateTime.now()),
        ))
        .then((rows) => rows > 0);
  }

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
    final taxAmount = subtotal * (taxRate / 100);
    final inv = await getInvoice(invoiceId);
    final total = subtotal + taxAmount + inv.lateFeeAmount;
    return (update(invoices)..where((t) => t.id.equals(invoiceId)))
        .write(InvoicesCompanion(
          clientId: Value(clientId),
          invoiceNumber: Value(invoiceNumber),
          issueDate: Value(issueDate),
          dueDate: Value(dueDate),
          subtotal: Value(subtotal),
          taxRate: Value(taxRate),
          taxLabel: Value(taxLabel),
          taxAmount: Value(taxAmount),
          total: Value(total),
          currency: Value(currency),
          notes: Value(notes),
          updatedAt: Value(DateTime.now()),
        ))
        .then((rows) => rows > 0);
  }

  Future<bool> updateTemplate(String invoiceId, String? templateId) {
    return (update(invoices)..where((t) => t.id.equals(invoiceId)))
        .write(InvoicesCompanion(
          templateId: Value(templateId),
          updatedAt: Value(DateTime.now()),
        ))
        .then((rows) => rows > 0);
  }

  Future<bool> updatePdfPath(String invoiceId, String path) {
    return (update(invoices)..where((t) => t.id.equals(invoiceId)))
        .write(InvoicesCompanion(
          pdfPath: Value(path),
          updatedAt: Value(DateTime.now()),
        ))
        .then((rows) => rows > 0);
  }

  Future<List<LineItemWithDetails>> getLineItemsWithDetails(
      String invoiceId) async {
    final query = select(invoiceLineItems).join([
      leftOuterJoin(timeEntries,
          timeEntries.id.equalsExp(invoiceLineItems.timeEntryId)),
      leftOuterJoin(
          projects, projects.id.equalsExp(invoiceLineItems.projectId)),
    ]);
    query.where(invoiceLineItems.invoiceId.equals(invoiceId));
    query.orderBy([OrderingTerm.asc(invoiceLineItems.sortOrder)]);

    final rows = await query.get();
    return rows.map((row) {
      return LineItemWithDetails(
        lineItem: row.readTable(invoiceLineItems),
        timeEntry: row.readTableOrNull(timeEntries),
        project: row.readTableOrNull(projects),
      );
    }).toList();
  }
}

class LineItemWithDetails {
  final InvoiceLineItem lineItem;
  final TimeEntry? timeEntry;
  final Project? project;

  LineItemWithDetails({
    required this.lineItem,
    this.timeEntry,
    this.project,
  });
}
