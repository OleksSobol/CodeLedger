import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../expenses/presentation/providers/expense_providers.dart';
import '../../../invoices/presentation/providers/invoice_providers.dart';
import '../../domain/models/bank_tax_reserve_summary.dart';

/// Notifier for the active selected year in Bank Reserve ledger. (DEV-71)
class BankReserveYearNotifier extends Notifier<int> {
  @override
  int build() => DateTime.now().year;

  void setYear(int year) => state = year;
  void increment() => state++;
  void decrement() => state--;
}

final bankReserveYearProvider = NotifierProvider<BankReserveYearNotifier, int>(
  BankReserveYearNotifier.new,
);

double _parseRate(String? raw, double defaultFraction) {
  if (raw == null || raw.trim().isEmpty) return defaultFraction;
  final val = double.tryParse(raw.trim());
  if (val == null || val <= 0) return defaultFraction;
  // If stored as decimal fraction (<= 1.0, e.g. 0.22 or 0.153), use directly.
  // If stored as whole percentage (> 1.0, e.g. 22.0 or 15.3), convert to decimal fraction.
  return val <= 1.0 ? val : val / 100.0;
}

/// Computes the dedicated annual bank reserve ledger summary. (DEV-71)
/// Calculates how much money should be in the tax bank account for Washington DOR
/// and Federal IRS taxes, plus realistic total invoice receipts and operating withdrawals.
final bankTaxReserveSummaryProvider = FutureProvider.family<BankTaxReserveSummary, int>((ref, year) async {
  final invoices = ref.watch(allInvoicesProvider).value ?? [];
  final monthlyRecurring = ref.watch(totalMonthlyDeductibleProvider);
  final dao = ref.watch(appSettingsDaoProvider);

  final fedStr = await dao.getValue('tax.federal_rate');
  final seStr = await dao.getValue('tax.se_rate');
  final boStr = await dao.getValue('wa_bo_rate');
  final receiptsStr = await dao.getValue('tax_receipts');

  final federalRate = _parseRate(fedStr, 0.22);
  final seRate = _parseRate(seStr, 0.153);
  final boRate = double.tryParse(boStr ?? '') ?? 0.00471;

  double totalDeductibleReceipts = 0.0;
  if (receiptsStr != null && receiptsStr.isNotEmpty) {
    try {
      final list = jsonDecode(receiptsStr) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final isDed = map['taxded'] as bool? ?? true;
        final amount = (map['amount'] as num?)?.toDouble() ?? 0.0;
        final dateStr = map['date'] as String? ?? '';
        final dt = DateTime.tryParse(dateStr);
        if (isDed && (dt == null || dt.year == year)) {
          totalDeductibleReceipts += amount;
        }
      }
    } catch (_) {}
  }

  // Live connection to one-off expense transactions recorded in Drift database
  final transactions = ref.watch(expenseTransactionsProvider).value ?? [];
  for (final t in transactions) {
    if (t.transaction.date.year == year) {
      totalDeductibleReceipts += t.deductibleAmount;
    }
  }

  return BankTaxReserveSummary.calculate(
    year: year,
    invoices: invoices,
    federalRate: federalRate,
    seRate: seRate,
    boRate: boRate,
    monthlyRecurringDeductible: monthlyRecurring,
    totalDeductibleReceipts: totalDeductibleReceipts,
  );
});
