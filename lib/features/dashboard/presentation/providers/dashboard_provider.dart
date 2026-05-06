import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/invoice_dao.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../time_tracking/presentation/providers/time_entry_providers.dart';

final invoiceDaoProvider = Provider<InvoiceDao>((ref) {
  return InvoiceDao(ref.watch(databaseProvider));
});

/// Uninvoiced hours per client for dashboard cards.
class ClientUninvoiced {
  final Client client;
  final double hours;

  const ClientUninvoiced({required this.client, required this.hours});
}

final uninvoicedByClientProvider =
    FutureProvider<List<ClientUninvoiced>>((ref) async {
  final clientDao = ref.watch(clientDaoProvider);
  final clients = await clientDao.getActiveClients();
  final results = <ClientUninvoiced>[];
  for (final client in clients) {
    final hours = await clientDao.getUninvoicedHours(client.id);
    if (hours > 0) {
      results.add(ClientUninvoiced(client: client, hours: hours));
    }
  }
  return results;
});

/// Monthly income — sum of paid invoices in current month.
final monthlyIncomeProvider = FutureProvider<double>((ref) async {
  final dao = ref.watch(invoiceDaoProvider);
  final paid = await dao.getByStatus('paid');
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  final monthEnd = DateTime(now.year, now.month + 1);
  return paid
      .where((i) =>
          i.paidDate != null &&
          !i.paidDate!.isBefore(monthStart) &&
          i.paidDate!.isBefore(monthEnd))
      .fold<double>(0, (sum, i) => sum + i.amountPaid);
});

/// Outstanding invoices — sent but not paid.
class InvoiceSummary {
  final int count;
  final double total;

  const InvoiceSummary({required this.count, required this.total});
}

final outstandingInvoicesProvider =
    FutureProvider<InvoiceSummary>((ref) async {
  final dao = ref.watch(invoiceDaoProvider);
  final sent = await dao.getByStatus('sent');
  return InvoiceSummary(
    count: sent.length,
    total: sent.fold<double>(0, (sum, i) => sum + i.total - i.amountPaid),
  );
});

/// Total tracked hours this week (Mon–Sun).
final weeklyHoursProvider = FutureProvider<double>((ref) async {
  final dao = ref.watch(timeEntryDaoProvider);
  final now = DateTime.now();
  final weekday = now.weekday;
  final weekStart = DateTime(now.year, now.month, now.day - (weekday - 1));
  final weekEnd = weekStart.add(const Duration(days: 7));
  final entries = await dao
      .watchEntriesForDateRange(weekStart, weekEnd)
      .first;
  return entries
      .where((e) => e.endTime != null)
      .fold<double>(0, (sum, e) => sum + (e.durationMinutes ?? 0) / 60.0);
});

/// Overdue invoices — sent + past due date.
final overdueInvoicesProvider =
    FutureProvider<InvoiceSummary>((ref) async {
  final dao = ref.watch(invoiceDaoProvider);
  final overdue = await dao.getOverdueInvoices();
  return InvoiceSummary(
    count: overdue.length,
    total:
        overdue.fold<double>(0, (sum, i) => sum + i.total - i.amountPaid),
  );
});
