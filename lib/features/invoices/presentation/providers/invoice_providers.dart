import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/constants/payment_terms.dart';
import '../../../../core/constants/us_states.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/invoice_repository.dart';
import '../../../../core/repositories/user_profile_repository.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../domain/entities/tax_bank_split.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';

import '../../../clients/presentation/providers/client_providers.dart';

// ── Search query ───────────────────────────────────────────────────
class InvoiceSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
  void clear() => state = '';
}

final invoiceSearchQueryProvider =
    NotifierProvider<InvoiceSearchQueryNotifier, String>(
      InvoiceSearchQueryNotifier.new,
    );

// ── Sort order ─────────────────────────────────────────────────────
enum InvoiceSortOrder {
  newest('Newest First'),
  oldest('Oldest First'),
  dueDate('Due Date'),
  amountHigh('Amount (High-Low)'),
  amountLow('Amount (Low-High)'),
  clientName('Client (A-Z)');

  final String label;
  const InvoiceSortOrder(this.label);
}

class InvoiceSortOrderNotifier extends Notifier<InvoiceSortOrder> {
  @override
  InvoiceSortOrder build() => InvoiceSortOrder.newest;
  void set(InvoiceSortOrder o) => state = o;
}

final invoiceSortOrderProvider =
    NotifierProvider<InvoiceSortOrderNotifier, InvoiceSortOrder>(
      InvoiceSortOrderNotifier.new,
    );

// ── Status filter ──────────────────────────────────────────────────
class InvoiceStatusFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

final invoiceStatusFilterProvider =
    NotifierProvider<InvoiceStatusFilterNotifier, String?>(
      InvoiceStatusFilterNotifier.new,
    );

// ── Metrics Summary ────────────────────────────────────────────────
class InvoiceMetricsSummary {
  final double totalOutstanding;
  final int outstandingCount;
  final double totalPaid;
  final int paidCount;
  final double totalOverdue;
  final int overdueCount;
  final int draftCount;

  const InvoiceMetricsSummary({
    required this.totalOutstanding,
    required this.outstandingCount,
    required this.totalPaid,
    required this.paidCount,
    required this.totalOverdue,
    required this.overdueCount,
    required this.draftCount,
  });

  factory InvoiceMetricsSummary.fromInvoices(List<Invoice> invoices) {
    double outstanding = 0;
    int outstandingCount = 0;
    double paid = 0;
    int paidCount = 0;
    double overdue = 0;
    int overdueCount = 0;
    int drafts = 0;
    final now = DateTime.now();

    for (final inv in invoices) {
      if (inv.status == 'archived') continue;
      if (inv.status == 'draft') {
        drafts++;
      } else if (inv.status == 'paid') {
        paid += inv.amountPaid > 0 ? inv.amountPaid : inv.total;
        paidCount++;
      } else if (inv.status == 'sent' || inv.status == 'overdue') {
        final balance = inv.total - inv.amountPaid;
        if (balance > 0) {
          outstanding += balance;
          outstandingCount++;
          if (inv.status == 'overdue' || inv.dueDate.isBefore(now)) {
            overdue += balance;
            overdueCount++;
          }
        }
      }
    }
    return InvoiceMetricsSummary(
      totalOutstanding: outstanding,
      outstandingCount: outstandingCount,
      totalPaid: paid,
      paidCount: paidCount,
      totalOverdue: overdue,
      overdueCount: overdueCount,
      draftCount: drafts,
    );
  }
}

final invoiceMetricsSummaryProvider = Provider<InvoiceMetricsSummary>((ref) {
  final all = ref.watch(allInvoicesProvider).value ?? const [];
  return InvoiceMetricsSummary.fromInvoices(all);
});

final invoiceStatusCountsProvider = Provider<Map<String?, int>>((ref) {
  final all = ref.watch(allInvoicesProvider).value ?? const [];
  final now = DateTime.now();
  int allNonArchived = 0;
  int drafts = 0;
  int sent = 0;
  int paid = 0;
  int overdue = 0;
  int archived = 0;

  for (final i in all) {
    if (i.status == 'archived') {
      archived++;
      continue;
    }
    allNonArchived++;
    if (i.status == 'draft') {
      drafts++;
    } else if (i.status == 'sent') {
      sent++;
      if (i.dueDate.isBefore(now)) {
        overdue++;
      }
    } else if (i.status == 'paid') {
      paid++;
    } else if (i.status == 'overdue') {
      overdue++;
      sent++;
    }
  }

  return {
    null: allNonArchived,
    'draft': drafts,
    'sent': sent,
    'paid': paid,
    'overdue': overdue,
    'archived': archived,
  };
});

// ── All invoices stream ────────────────────────────────────────────
final allInvoicesProvider = StreamProvider<List<Invoice>>((ref) {
  return ref.watch(invoiceRepositoryProvider).watchInvoices();
});

// ── Filtered invoices ──────────────────────────────────────────────
final filteredInvoicesProvider = Provider<AsyncValue<List<Invoice>>>((ref) {
  final allAsync = ref.watch(allInvoicesProvider);
  final statusFilter = ref.watch(invoiceStatusFilterProvider);
  final searchQuery = ref
      .watch(invoiceSearchQueryProvider)
      .trim()
      .toLowerCase();
  final sortOrder = ref.watch(invoiceSortOrderProvider);
  final clients = ref.watch(allClientsProvider).value ?? const [];
  final clientMap = {for (final c in clients) c.id: c.name};

  return allAsync.whenData((invoices) {
    final now = DateTime.now();
    var list = invoices.where((i) {
      if (statusFilter == null) {
        if (i.status == 'archived') return false;
      } else if (statusFilter == 'overdue') {
        final isOverdue =
            i.status == 'overdue' ||
            (i.status == 'sent' && i.dueDate.isBefore(now));
        if (!isOverdue) return false;
      } else {
        if (i.status != statusFilter) return false;
      }

      if (searchQuery.isNotEmpty) {
        final matchesNumber = i.invoiceNumber.toLowerCase().contains(
          searchQuery,
        );
        final clientName = (clientMap[i.clientId] ?? '').toLowerCase();
        final matchesClient = clientName.contains(searchQuery);
        if (!matchesNumber && !matchesClient) return false;
      }

      return true;
    }).toList();

    switch (sortOrder) {
      case InvoiceSortOrder.newest:
        list.sort((a, b) => b.issueDate.compareTo(a.issueDate));
        break;
      case InvoiceSortOrder.oldest:
        list.sort((a, b) => a.issueDate.compareTo(b.issueDate));
        break;
      case InvoiceSortOrder.dueDate:
        list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        break;
      case InvoiceSortOrder.amountHigh:
        list.sort((a, b) => b.total.compareTo(a.total));
        break;
      case InvoiceSortOrder.amountLow:
        list.sort((a, b) => a.total.compareTo(b.total));
        break;
      case InvoiceSortOrder.clientName:
        list.sort((a, b) {
          final nameA = clientMap[a.clientId] ?? '';
          final nameB = clientMap[b.clientId] ?? '';
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
        });
        break;
    }

    return list;
  });
});

// ── Single invoice by ID ───────────────────────────────────────────
final invoiceDetailProvider = FutureProvider.family<Invoice, String>((
  ref,
  id,
) async {
  return ref.watch(invoiceRepositoryProvider).getInvoice(id);
});

// ── Line items for invoice ─────────────────────────────────────────
final invoiceLineItemsProvider =
    StreamProvider.family<List<InvoiceLineItem>, String>((ref, invoiceId) {
      return ref.watch(invoiceRepositoryProvider).watchLineItems(invoiceId);
    });

// ── Uninvoiced entries for a client ────────────────────────────────
final uninvoicedEntriesProvider = FutureProvider.autoDispose
    .family<List<TimeEntry>, String>((ref, clientId) async {
      return ref
          .watch(timeEntryRepositoryProvider)
          .getUninvoicedForClient(clientId);
    });

// ── Invoice wizard state ───────────────────────────────────────────

class InvoiceWizardState {
  final String? clientId;
  final List<TimeEntry> selectedEntries;
  final List<ManualLineItem> manualLineItems;
  final String? notes;
  final double? taxRateOverride;
  final String? templateId;

  const InvoiceWizardState({
    this.clientId,
    this.selectedEntries = const [],
    this.manualLineItems = const [],
    this.notes,
    this.taxRateOverride,
    this.templateId,
  });

  InvoiceWizardState copyWith({
    String? clientId,
    List<TimeEntry>? selectedEntries,
    List<ManualLineItem>? manualLineItems,
    String? notes,
    double? taxRateOverride,
    String? templateId,
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
    final manualTotal = manualLineItems.fold<double>(
      0,
      (sum, m) => sum + m.total,
    );
    return entriesTotal + manualTotal;
  }

  /// Total duration in minutes of all selected time entries.
  int get totalDurationMinutes {
    return selectedEntries.fold<int>(
      0,
      (sum, e) => sum + (e.durationMinutes ?? 0),
    );
  }

  /// Total hours of all selected time entries.
  double get totalHours {
    return totalDurationMinutes / 60.0;
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
      InvoiceWizardNotifier.new,
    );

class InvoiceWizardNotifier extends Notifier<InvoiceWizardState> {
  @override
  InvoiceWizardState build() => const InvoiceWizardState();

  void setClient(String clientId) {
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
    state = state.copyWith(manualLineItems: [...state.manualLineItems, item]);
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

  void setTemplate(String? templateId) {
    state = state.copyWith(templateId: templateId);
  }

  void reset() {
    state = const InvoiceWizardState();
  }
}

// ── Invoice notifier — create, update status, record payment ───────
final invoiceNotifierProvider = AsyncNotifierProvider<InvoiceNotifier, void>(
  InvoiceNotifier.new,
);

class InvoiceNotifier extends AsyncNotifier<void> {
  late InvoiceRepository _invoiceDao;
  late UserProfileRepository _profileDao;

  @override
  Future<void> build() async {
    _invoiceDao = ref.watch(invoiceRepositoryProvider);
    _profileDao = ref.watch(userProfileRepositoryProvider);
  }

  Future<String> createInvoice() async {
    final wizard = ref.read(invoiceWizardProvider);
    if (wizard.clientId == null) throw Exception('No client selected');
    if (wizard.selectedEntries.isEmpty && wizard.manualLineItems.isEmpty) {
      throw Exception('No entries or line items selected');
    }

    final profile = await _profileDao.getProfile();
    final client = await ref
        .read(clientRepositoryProvider)
        .getClient(wizard.clientId!);

    final termsStr = client.paymentTermsOverride ?? profile.defaultPaymentTerms;
    final terms = PaymentTerms.fromString(termsStr);
    final termsDays = terms.resolveDays(
      customDays:
          client.paymentTermsDaysOverride ?? profile.defaultPaymentTermsDays,
    );

    final isOutOfState = UsStates.isOutOfState(
      client.stateProvince,
      businessState: profile.stateProvince,
    );
    final taxRate =
        wizard.taxRateOverride ??
        client.taxRate ??
        (isOutOfState ? 0.0 : profile.defaultTaxRate);
    final taxLabel = profile.defaultTaxLabel;

    final invoiceNumber = await _profileDao.getNextInvoiceNumber();

    final subtotal = wizard.subtotal;
    final taxAmount = subtotal * (taxRate / 100);
    final total = subtotal + taxAmount;

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

    final lineItems = <InvoiceLineItemsCompanion>[];
    var sortOrder = 0;
    final dateFmt = DateFormat.yMMMd();

    final groups = <(String, double), List<TimeEntry>>{};
    for (final entry in wizard.selectedEntries) {
      final key = (dateFmt.format(entry.startTime), entry.hourlyRateSnapshot);
      (groups[key] ??= []).add(entry);
    }

    final sortedKeys = groups.keys.toList()
      ..sort(
        (a, b) =>
            groups[a]!.first.startTime.compareTo(groups[b]!.first.startTime),
      );

    for (final key in sortedKeys) {
      final entries = groups[key]!;
      final dateStr = key.$1;
      final rate = key.$2;

      final totalHours = entries.fold<double>(
        0,
        (sum, e) => sum + (e.durationMinutes ?? 0) / 60.0,
      );
      final descriptions = entries
          .map((e) => e.description ?? 'Work session')
          .join('; ');
      final desc = '$dateStr | $descriptions';

      final issueRefs = entries
          .map((e) => e.issueReference)
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .join(', ');

      final projectIds = entries.map((e) => e.projectId).toSet();
      final sharedProject = projectIds.length == 1 ? projectIds.first : null;

      lineItems.add(
        InvoiceLineItemsCompanion(
          invoiceId: const Value(''), // overwritten by repo
          description: Value(desc),
          quantity: Value(totalHours),
          unitPrice: Value(rate),
          total: Value(totalHours * rate),
          sortOrder: Value(sortOrder++),
          projectId: Value(sharedProject),
          issueReference: Value(issueRefs.isEmpty ? null : issueRefs),
        ),
      );
    }

    for (final manual in wizard.manualLineItems) {
      lineItems.add(
        InvoiceLineItemsCompanion(
          invoiceId: const Value(''), // overwritten by repo
          description: Value(manual.description),
          quantity: Value(manual.quantity),
          unitPrice: Value(manual.unitPrice),
          total: Value(manual.total),
          sortOrder: Value(sortOrder++),
        ),
      );
    }

    final templateId = wizard.templateId;

    final invoiceId = await _invoiceDao.createInvoice(
      invoice: InvoicesCompanion(
        clientId: Value(wizard.clientId!),
        invoiceNumber: Value(invoiceNumber),
        issueDate: Value(now),
        dueDate: Value(dueDate),
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

    ref.read(invoiceWizardProvider.notifier).reset();
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(uninvoicedByClientProvider);
    ref.invalidate(monthlyIncomeProvider);

    return invoiceId;
  }

  Future<void> updateStatus(String invoiceId, String status) async {
    await _invoiceDao.updateStatus(invoiceId, status);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(outstandingInvoicesProvider);
    ref.invalidate(overdueInvoicesProvider);
    ref.invalidate(monthlyIncomeProvider);
  }

  Future<void> recordPayment({
    required String invoiceId,
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

  Future<void> deleteDraft(String invoiceId) async {
    await _invoiceDao.deleteDraftInvoice(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(uninvoicedByClientProvider);
  }

  Future<void> archiveInvoice(String invoiceId) async {
    await _invoiceDao.archiveInvoice(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(outstandingInvoicesProvider);
    ref.invalidate(overdueInvoicesProvider);
    ref.invalidate(monthlyIncomeProvider);
  }

  Future<void> unarchiveInvoice(String invoiceId) async {
    await _invoiceDao.unarchiveInvoice(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(outstandingInvoicesProvider);
    ref.invalidate(overdueInvoicesProvider);
    ref.invalidate(monthlyIncomeProvider);
  }

  Future<void> updateDraftInvoice({
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

  Future<void> setInvoiceTemplate(String invoiceId, String? templateId) async {
    await _invoiceDao.updateTemplate(invoiceId, templateId);
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(allInvoicesProvider);
  }

  Future<void> addEntriesToInvoice({
    required String invoiceId,
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
      ..sort(
        (a, b) =>
            groups[a]!.first.startTime.compareTo(groups[b]!.first.startTime),
      );

    for (final key in sortedKeys) {
      final groupEntries = groups[key]!;
      final dateStr = key.$1;
      final rate = key.$2;

      final totalHours = groupEntries.fold<double>(
        0,
        (sum, e) => sum + (e.durationMinutes ?? 0) / 60.0,
      );
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
      final sharedProject = projectIds.length == 1 ? projectIds.first : null;

      lineItems.add(
        InvoiceLineItemsCompanion(
          invoiceId: const Value(''), // overwritten by repo
          description: Value(desc),
          quantity: Value(totalHours),
          unitPrice: Value(rate),
          total: Value(totalHours * rate),
          projectId: Value(sharedProject),
          issueReference: Value(issueRefs.isEmpty ? null : issueRefs),
        ),
      );
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

  Future<void> updateInvoiceNumber(
    String invoiceId,
    String invoiceNumber,
  ) async {
    await _invoiceDao.updateInvoiceNumber(invoiceId, invoiceNumber);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
  }

  Future<void> editLineItem({
    required String lineItemId,
    required String invoiceId,
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

  Future<void> revertToDraft(String invoiceId) async {
    await _invoiceDao.revertToDraft(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(outstandingInvoicesProvider);
    ref.invalidate(overdueInvoicesProvider);
  }

  Future<void> deleteInvoice(String invoiceId) async {
    final invoices = await _invoiceDao.watchInvoices().first;
    final invoice = invoices.firstWhereOrNull((i) => i.id == invoiceId);
    if (invoice != null) {
      await _profileDao.revertInvoiceNumber(invoice.invoiceNumber);
    }

    await _invoiceDao.deleteInvoice(invoiceId);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(uninvoicedByClientProvider);
    ref.invalidate(monthlyIncomeProvider);
  }
}

// ── Bank Account Tax Split Providers (DEV-78) ──────────────────────

class BankSplitFederalTaxRateNotifier extends Notifier<double> {
  static const _key = 'tax.federal_rate';

  @override
  double build() {
    _loadFromDao();
    return 20.0;
  }

  Future<void> _loadFromDao() async {
    try {
      final dao = ref.read(appSettingsDaoProvider);
      final raw = await dao.getValue(_key);
      if (raw != null) {
        final parsed = double.tryParse(raw);
        if (parsed != null && parsed > 0) {
          state = parsed <= 1.0 ? parsed * 100.0 : parsed;
        }
      }
    } catch (_) {}
  }

  Future<void> setRate(double rate) async {
    state = rate;
    try {
      final dao = ref.read(appSettingsDaoProvider);
      await dao.setValue(_key, (rate / 100.0).toString());
    } catch (_) {}
  }
}

final bankSplitFederalTaxRateProvider =
    NotifierProvider<BankSplitFederalTaxRateNotifier, double>(
      BankSplitFederalTaxRateNotifier.new,
    );

final invoiceBankSplitProvider =
    Provider.family<TaxBankSplit, Invoice>((ref, invoice) {
      final fedRate = ref.watch(bankSplitFederalTaxRateProvider);
      return TaxBankSplit.calculate(
        subtotal: invoice.subtotal,
        taxAmount: invoice.taxAmount,
        taxRate: invoice.taxRate,
        taxLabel: invoice.taxLabel,
        federalTaxRate: fedRate,
        lateFeeAmount: invoice.lateFeeAmount,
        total: invoice.total,
      );
    });
