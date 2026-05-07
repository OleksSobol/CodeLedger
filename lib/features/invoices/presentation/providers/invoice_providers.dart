import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/invoice_dao.dart';
import '../../../../core/database/daos/user_profile_dao.dart';
import '../../../../core/constants/payment_terms.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../time_tracking/presentation/providers/time_entry_providers.dart';
import '../../../profile/presentation/providers/profile_provider.dart';

// ── Status filter ──────────────────────────────────────────────────
class InvoiceStatusFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

final invoiceStatusFilterProvider =
    NotifierProvider<InvoiceStatusFilterNotifier, String?>(
        InvoiceStatusFilterNotifier.new);

// ── All invoices stream ────────────────────────────────────────────
final allInvoicesProvider = StreamProvider<List<Invoice>>((ref) {
  return ref.watch(invoiceDaoProvider).watchInvoices();
});

// ── Filtered invoices ──────────────────────────────────────────────
final filteredInvoicesProvider = Provider<AsyncValue<List<Invoice>>>((ref) {
  final allAsync = ref.watch(allInvoicesProvider);
  final statusFilter = ref.watch(invoiceStatusFilterProvider);

  return allAsync.whenData((invoices) {
    if (statusFilter == null) {
      // "All" hides archived invoices
      return invoices.where((i) => i.status != 'archived').toList();
    }
    return invoices.where((i) => i.status == statusFilter).toList();
  });
});

// ── Single invoice by ID ───────────────────────────────────────────
final invoiceDetailProvider =
    FutureProvider.family<Invoice, int>((ref, id) async {
  return ref.watch(invoiceDaoProvider).getInvoice(id);
});

// ── Line items for invoice ─────────────────────────────────────────
final invoiceLineItemsProvider =
    StreamProvider.family<List<InvoiceLineItem>, int>((ref, invoiceId) {
  return ref.watch(invoiceDaoProvider).watchLineItems(invoiceId);
});

// ── Uninvoiced entries for a client ────────────────────────────────
// Using autoDispose so this re-fetches each time the wizard opens,
// picking up any recently-added manual entries.
final uninvoicedEntriesProvider = FutureProvider.autoDispose
    .family<List<TimeEntry>, int>((ref, clientId) async {
  return ref.watch(timeEntryDaoProvider).getUninvoicedForClient(clientId);
});

// ── Invoice wizard state ───────────────────────────────────────────

class InvoiceWizardState {
  final int? clientId;
  final List<TimeEntry> selectedEntries;
  final List<ManualLineItem> manualLineItems;
  final String? notes;
  final double? taxRateOverride;
  final int? templateId;

  const InvoiceWizardState({
    this.clientId,
    this.selectedEntries = const [],
    this.manualLineItems = const [],
    this.notes,
    this.taxRateOverride,
    this.templateId,
  });

  InvoiceWizardState copyWith({
    int? clientId,
    List<TimeEntry>? selectedEntries,
    List<ManualLineItem>? manualLineItems,
    String? notes,
    double? taxRateOverride,
    int? templateId,
  }) {
    return InvoiceWizardState(
      clientId: clientId ?? this.clientId,
      selectedEntries: selectedEntries ?? this.selectedEntries,
      manualLineItems: manualLineItems ?? this.manualLineItems,
      notes: notes ?? this.notes,
      taxRateOverride: taxRateOverride ?? this.taxRateOverride,
      templateId: templateId ?? this.templateId,
    );
  }

  double get subtotal {
    final entriesTotal = selectedEntries.fold<double>(0, (sum, e) {
      final hours = (e.durationMinutes ?? 0) / 60.0;
      return sum + hours * e.hourlyRateSnapshot;
    });
    final manualTotal =
        manualLineItems.fold<double>(0, (sum, m) => sum + m.total);
    return entriesTotal + manualTotal;
  }
}

class ManualLineItem {
  final String description;
  final double quantity;
  final double unitPrice;

  const ManualLineItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;
}

final invoiceWizardProvider =
    NotifierProvider<InvoiceWizardNotifier, InvoiceWizardState>(
        InvoiceWizardNotifier.new);

class InvoiceWizardNotifier extends Notifier<InvoiceWizardState> {
  @override
  InvoiceWizardState build() => const InvoiceWizardState();

  void setClient(int clientId) {
    state = InvoiceWizardState(clientId: clientId);
  }

  void setSelectedEntries(List<TimeEntry> entries) {
    state = state.copyWith(selectedEntries: entries);
  }

  void toggleEntry(TimeEntry entry) {
    final current = List<TimeEntry>.from(state.selectedEntries);
    final idx = current.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      current.removeAt(idx);
    } else {
      current.add(entry);
    }
    state = state.copyWith(selectedEntries: current);
  }

  void selectAll(List<TimeEntry> entries) {
    state = state.copyWith(selectedEntries: entries);
  }

  void deselectAll() {
    state = state.copyWith(selectedEntries: []);
  }

  void addManualLineItem(ManualLineItem item) {
    state = state.copyWith(
      manualLineItems: [...state.manualLineItems, item],
    );
  }

  void removeManualLineItem(int index) {
    final items = List<ManualLineItem>.from(state.manualLineItems);
    items.removeAt(index);
    state = state.copyWith(manualLineItems: items);
  }

  void setNotes(String? notes) {
    state = state.copyWith(notes: notes);
  }

  void setTaxRateOverride(double? rate) {
    state = state.copyWith(taxRateOverride: rate);
  }

  void setTemplate(int? templateId) {
    state = state.copyWith(templateId: templateId);
  }

  void reset() {
    state = const InvoiceWizardState();
  }
}

// ── Invoice notifier — create, update status, record payment ───────
final invoiceNotifierProvider =
    AsyncNotifierProvider<InvoiceNotifier, void>(InvoiceNotifier.new);

class InvoiceNotifier extends AsyncNotifier<void> {
  late InvoiceDao _invoiceDao;
  late UserProfileDao _profileDao;

  @override
  Future<void> build() async {
    _invoiceDao = ref.watch(invoiceDaoProvider);
    _profileDao = ref.watch(userProfileDaoProvider);
  }

  /// Create an invoice from the wizard state.
  Future<int> createInvoice() async {
    final wizard = ref.read(invoiceWizardProvider);
    if (wizard.clientId == null) throw Exception('No client selected');
    if (wizard.selectedEntries.isEmpty && wizard.manualLineItems.isEmpty) {
      throw Exception('No entries or line items selected');
    }

    final profile = await _profileDao.getProfile();
    final client =
        await ref.read(clientDaoProvider).getClient(wizard.clientId!);

    // Resolve payment terms
    final termsStr =
        client.paymentTermsOverride ?? profile.defaultPaymentTerms;
    final terms = PaymentTerms.fromString(termsStr);
    final termsDays = terms.resolveDays(
      customDays:
          client.paymentTermsDaysOverride ?? profile.defaultPaymentTermsDays,
    );

    // Resolve tax rate
    final taxRate =
        wizard.taxRateOverride ?? client.taxRate ?? profile.defaultTaxRate;
    final taxLabel = profile.defaultTaxLabel;

    // Get invoice number
    final invoiceNumber = await _profileDao.getNextInvoiceNumber();

    // Calculate totals
    final subtotal = wizard.subtotal;
    final taxAmount = subtotal * (taxRate / 100);
    final total = subtotal + taxAmount;

    // Determine period
    DateTime? periodStart;
    DateTime? periodEnd;
    if (wizard.selectedEntries.isNotEmpty) {
      periodStart = wizard.selectedEntries
          .map((e) => e.startTime)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      periodEnd = wizard.selectedEntries
          .map((e) => e.endTime ?? e.startTime)
          .reduce((a, b) => a.isAfter(b) ? a : b);
    }

    final now = DateTime.now();
    final dueDate = now.add(Duration(days: termsDays));

    // Build line items from time entries, grouping same-day + same-rate
    final lineItems = <InvoiceLineItemsCompanion>[];
    var sortOrder = 0;
    final dateFmt = DateFormat.yMMMd();

    // Group entries by (date string, hourly rate)
    final groups = <(String, double), List<TimeEntry>>{};
    for (final entry in wizard.selectedEntries) {
      final (String, double) key = (dateFmt.format(entry.startTime), entry.hourlyRateSnapshot);
      (groups[key] ??= []).add(entry);
    }

    // Sort groups by earliest start time
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => groups[a]!.first.startTime
          .compareTo(groups[b]!.first.startTime));

    for (final key in sortedKeys) {
      final entries = groups[key]!;
      final dateStr = key.$1;
      final rate = key.$2;

      final totalHours = entries.fold<double>(
          0, (sum, e) => sum + (e.durationMinutes ?? 0) / 60.0);
      final descriptions = entries
          .map((e) => e.description ?? 'Work session')
          .join('; ');
      final desc = '$dateStr | $descriptions';

      // Aggregate unique issue references from all entries in this group
      final issueRefs = entries
          .map((e) => e.issueReference)
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .join(', ');

      // Use shared project if all entries are the same, otherwise null
      final projectIds = entries.map((e) => e.projectId).toSet();
      final sharedProject =
          projectIds.length == 1 ? projectIds.first : null;

      lineItems.add(InvoiceLineItemsCompanion.insert(
        invoiceId: 0, // will be set by DAO
        description: desc,
        quantity: totalHours,
        unitPrice: rate,
        total: totalHours * rate,
        sortOrder: Value(sortOrder++),
        projectId: Value(sharedProject),
        issueReference: Value(issueRefs.isEmpty ? null : issueRefs),
      ));
    }

    for (final manual in wizard.manualLineItems) {
      lineItems.add(InvoiceLineItemsCompanion.insert(
        invoiceId: 0,
        description: manual.description,
        quantity: manual.quantity,
        unitPrice: manual.unitPrice,
        total: manual.total,
        sortOrder: Value(sortOrder++),
      ));
    }

    // Only store templateId if the user explicitly chose one in the wizard.
    // Otherwise leave null so the PDF provider resolves it at render time
    // using the cascade: invoice -> client -> profile -> default.
    final templateId = wizard.templateId;

    final invoiceId = await _invoiceDao.createInvoice(
      invoice: InvoicesCompanion.insert(
        clientId: wizard.clientId!,
        invoiceNumber: invoiceNumber,
        issueDate: now,
        dueDate: dueDate,
        periodStart: Value(periodStart),
        periodEnd: Value(periodEnd),
        subtotal: Value(subtotal),
        taxRate: Value(taxRate),
        taxLabel: Value(taxLabel),
        taxAmount: Value(taxAmount),
        total: Value(total),
        currency: Value(client.currency),
        notes: Value(wizard.notes),
        templateId: Value(templateId),
      ),
      lineItems: lineItems,
      timeEntryIds: wizard.selectedEntries.map((e) => e.id).toList(),
    );

    // Reset wizard & invalidate dependent providers
    ref.read(invoiceWizardProvider.notifier).reset();
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(uninvoicedByClientProvider);
    ref.invalidate(monthlyIncomeProvider);

    return invoiceId;
  }

  /// Update invoice status (draft -> sent -> paid / overdue / cancelled).
  Future<void> updateStatus(int invoiceId, String status) async {
    await _invoiceDao.updateStatus(invoiceId, status);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(outstandingInvoicesProvider);
    ref.invalidate(overdueInvoicesProvider);
    ref.invalidate(monthlyIncomeProvider);
  }

  /// Record a payment on an invoice.
  Future<void> recordPayment({
    required int invoiceId,
    required double amount,
    required String method,
  }) async {
    await _invoiceDao.recordPayment(
      invoiceId: invoiceId,
      amount: amount,
      method: method,
    );
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(outstandingInvoicesProvider);
    ref.invalidate(overdueInvoicesProvider);
    ref.invalidate(monthlyIncomeProvider);
  }

  /// Delete a draft invoice.
  Future<void> deleteDraft(int invoiceId) async {
    await _invoiceDao.deleteDraftInvoice(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(uninvoicedByClientProvider);
  }

  /// Archive a paid invoice.
  Future<void> archiveInvoice(int invoiceId) async {
    await _invoiceDao.archiveInvoice(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
  }

  /// Unarchive an invoice.
  Future<void> unarchiveInvoice(int invoiceId) async {
    await _invoiceDao.unarchiveInvoice(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
  }

  /// Update all editable fields of a draft invoice.
  Future<void> updateDraftInvoice({
    required int invoiceId,
    required int clientId,
    required String invoiceNumber,
    required DateTime issueDate,
    required DateTime dueDate,
    required double subtotal,
    required double taxRate,
    required String taxLabel,
    required String currency,
    String? notes,
  }) async {
    await _invoiceDao.updateDraftInvoice(
      invoiceId: invoiceId,
      clientId: clientId,
      invoiceNumber: invoiceNumber,
      issueDate: issueDate,
      dueDate: dueDate,
      subtotal: subtotal,
      taxRate: taxRate,
      taxLabel: taxLabel,
      currency: currency,
      notes: notes,
    );
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
  }

  /// Persist the user's chosen PDF template so the email/share flow uses
  /// the same style that was previewed.
  Future<void> setInvoiceTemplate(int invoiceId, int? templateId) async {
    await _invoiceDao.updateTemplate(invoiceId, templateId);
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(allInvoicesProvider);
  }

  /// Append additional time entries to an existing draft invoice, grouping
  /// by (date, hourly rate) the same way createInvoice does.
  Future<void> addEntriesToInvoice({
    required int invoiceId,
    required List<TimeEntry> entries,
  }) async {
    if (entries.isEmpty) return;

    final lineItems = <InvoiceLineItemsCompanion>[];
    final dateFmt = DateFormat.yMMMd();

    final groups = <(String, double), List<TimeEntry>>{};
    for (final entry in entries) {
      final key = (dateFmt.format(entry.startTime), entry.hourlyRateSnapshot);
      (groups[key] ??= []).add(entry);
    }

    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => groups[a]!.first.startTime
          .compareTo(groups[b]!.first.startTime));

    for (final key in sortedKeys) {
      final groupEntries = groups[key]!;
      final dateStr = key.$1;
      final rate = key.$2;

      final totalHours = groupEntries.fold<double>(
          0, (sum, e) => sum + (e.durationMinutes ?? 0) / 60.0);
      final descriptions = groupEntries
          .map((e) => e.description ?? 'Work session')
          .join('; ');
      final desc = '$dateStr | $descriptions';

      final issueRefs = groupEntries
          .map((e) => e.issueReference)
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .join(', ');

      final projectIds = groupEntries.map((e) => e.projectId).toSet();
      final sharedProject =
          projectIds.length == 1 ? projectIds.first : null;

      lineItems.add(InvoiceLineItemsCompanion.insert(
        invoiceId: 0, // overwritten by DAO
        description: desc,
        quantity: totalHours,
        unitPrice: rate,
        total: totalHours * rate,
        projectId: Value(sharedProject),
        issueReference: Value(issueRefs.isEmpty ? null : issueRefs),
      ));
    }

    await _invoiceDao.appendLineItems(
      invoiceId: invoiceId,
      lineItems: lineItems,
      timeEntryIds: entries.map((e) => e.id).toList(),
    );

    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(invoiceLineItemsProvider(invoiceId));
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(uninvoicedByClientProvider);
    ref.invalidate(monthlyIncomeProvider);
  }

  /// Rename an invoice number.
  Future<void> updateInvoiceNumber(int invoiceId, String invoiceNumber) async {
    await _invoiceDao.updateInvoiceNumber(invoiceId, invoiceNumber);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
  }

  /// Edit a single line item and recalculate invoice totals.
  Future<void> editLineItem({
    required int lineItemId,
    required int invoiceId,
    required String description,
    required double quantity,
    required double unitPrice,
  }) async {
    await _invoiceDao.updateLineItem(
      lineItemId: lineItemId,
      invoiceId: invoiceId,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
    );
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(invoiceLineItemsProvider(invoiceId));
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(monthlyIncomeProvider);
  }

  /// Revert a sent invoice back to draft so it can be edited / resent.
  Future<void> revertToDraft(int invoiceId) async {
    await _invoiceDao.revertToDraft(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(outstandingInvoicesProvider);
    ref.invalidate(overdueInvoicesProvider);
  }

  /// Permanently delete any invoice.
  Future<void> deleteInvoice(int invoiceId) async {
    await _invoiceDao.deleteInvoice(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(uninvoicedByClientProvider);
    ref.invalidate(monthlyIncomeProvider);
  }
}
