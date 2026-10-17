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

  final federalRate = (double.tryParse(fedStr ?? '') ?? 22.0) / 100.0;
  final seRate = (double.tryParse(seStr ?? '') ?? 15.3) / 100.0;
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
