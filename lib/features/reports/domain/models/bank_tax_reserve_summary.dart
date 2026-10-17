import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';

/// Models the quarterly breakdown of money that belongs in the tax bank account
/// versus operating cash withdrawn by the business owner. (DEV-71)
class QuarterBankReserve {
  final int quarter;
  final String label;
  final int invoicesCount;
  final double grossCollected;
  final double subtotal;
  final double salesTax;
  final double boTax;
  final double stateTax;
  final double federalTax;
  final double totalTaxReserve;
  final double takeHomeWithdrawn;

  const QuarterBankReserve({
    required this.quarter,
    required this.label,
    required this.invoicesCount,
    required this.grossCollected,
    required this.subtotal,
    required this.salesTax,
    required this.boTax,
    required this.stateTax,
    required this.federalTax,
    required this.totalTaxReserve,
    required this.takeHomeWithdrawn,
  });
}

/// Models the dedicated annual bank reserve ledger summary. (DEV-71)
/// Shows how much money should be in the tax bank account at year end,
/// realistic numbers from all invoices, and how much was taken out.
class BankTaxReserveSummary {
  final int year;
  final int totalInvoicesCount;
  final double totalGrossCollected;
  final double totalSubtotal;
  final double totalSalesTax;
  final double totalBoTax;
  final double totalStateTax;
  final double totalReceiptDeductions;
  final double totalRecurringDeductions;
  final double netTaxableIncome;
  final double seTax;
  final double federalIncomeTax;
  final double totalFederalTax;
  final double totalBankReserve;
  final double totalTakeHomeWithdrawn;
  final double federalRate;
  final double seRate;
  final double boRate;
  final List<QuarterBankReserve> quarters;

  const BankTaxReserveSummary({
    required this.year,
    required this.totalInvoicesCount,
    required this.totalGrossCollected,
    required this.totalSubtotal,
    required this.totalSalesTax,
    required this.totalBoTax,
    required this.totalStateTax,
    required this.totalReceiptDeductions,
    required this.totalRecurringDeductions,
    required this.netTaxableIncome,
    required this.seTax,
    required this.federalIncomeTax,
    required this.totalFederalTax,
    required this.totalBankReserve,
    required this.totalTakeHomeWithdrawn,
    required this.federalRate,
    required this.seRate,
    required this.boRate,
    required this.quarters,
  });

  /// Factory calculator that computes the bank reserve ledger across all invoices for a given year.
  factory BankTaxReserveSummary.calculate({
    required int year,
    required List<Invoice> invoices,
    double federalRate = 0.22,
    double seRate = 0.153,
    double boRate = 0.00471,
    double monthlyRecurringDeductible = 0.0,
    double totalDeductibleReceipts = 0.0,
    bool includeArchived = true,
  }) {
    // Filter invoices for the year using cash basis paidDate (fallback to issueDate)
    final yearInvoices = invoices.where((inv) {
      if (inv.status != 'paid' && (!includeArchived || inv.status != 'archived')) {
        return false;
      }
      final d = inv.paidDate ?? inv.issueDate;
      return d.year == year;
    }).toList();

    final quarterConfigs = [
      (q: 1, label: 'Q1 (Jan–Mar)', start: DateTime(year, 1, 1), end: DateTime(year, 4, 1)),
      (q: 2, label: 'Q2 (Apr–Jun)', start: DateTime(year, 4, 1), end: DateTime(year, 7, 1)),
      (q: 3, label: 'Q3 (Jul–Sep)', start: DateTime(year, 7, 1), end: DateTime(year, 10, 1)),
      (q: 4, label: 'Q4 (Oct–Dec)', start: DateTime(year, 10, 1), end: DateTime(year + 1, 1, 1)),
    ];

    final quarters = <QuarterBankReserve>[];

    for (final qc in quarterConfigs) {
      final qInvoices = yearInvoices.where((inv) {
        final d = inv.paidDate ?? inv.issueDate;
        return (d.isAtSameMomentAs(qc.start) || d.isAfter(qc.start)) && d.isBefore(qc.end);
      }).toList();

      double qGross = 0.0;
      double qSubtotal = 0.0;
      double qSalesTax = 0.0;

      for (final inv in qInvoices) {
        qGross += inv.total;
        qSubtotal += inv.subtotal;
        qSalesTax += inv.taxAmount;
      }

      final qBoTax = qSubtotal * boRate;
      final qStateTax = qSalesTax + qBoTax;

      final receiptAlloc = totalDeductibleReceipts / 4.0;
      final recurringAlloc = monthlyRecurringDeductible * 3.0;
      final qNet = (qSubtotal - receiptAlloc - recurringAlloc).clamp(0.0, double.infinity);

      final qSeTax = qNet * 0.9235 * seRate;
      final qFedBase = (qNet - qSeTax / 2.0).clamp(0.0, double.infinity);
      final qFedTax = qFedBase * federalRate;
      final qTotalFedTax = qSeTax + qFedTax;

      final qTotalTaxReserve = qStateTax + qTotalFedTax;
      final qTakeHome = (qGross - qTotalTaxReserve).clamp(0.0, double.infinity);

      quarters.add(
        QuarterBankReserve(
          quarter: qc.q,
          label: qc.label,
          invoicesCount: qInvoices.length,
          grossCollected: qGross,
          subtotal: qSubtotal,
          salesTax: qSalesTax,
          boTax: qBoTax,
          stateTax: qStateTax,
          federalTax: qTotalFedTax,
          totalTaxReserve: qTotalTaxReserve,
          takeHomeWithdrawn: qTakeHome,
        ),
      );
    }

    double totalGross = 0.0;
    double totalSub = 0.0;
    double totalSales = 0.0;

    for (final inv in yearInvoices) {
      totalGross += inv.total;
      totalSub += inv.subtotal;
      totalSales += inv.taxAmount;
    }

    final totalBo = totalSub * boRate;
    final totalState = totalSales + totalBo;

    final totalRecurring = monthlyRecurringDeductible * 12.0;
    final netTaxable = (totalSub - totalDeductibleReceipts - totalRecurring).clamp(0.0, double.infinity);

    final seTax = netTaxable * 0.9235 * seRate;
    final fedBase = (netTaxable - seTax / 2.0).clamp(0.0, double.infinity);
    final fedIncomeTax = fedBase * federalRate;
    final totalFed = seTax + fedIncomeTax;

    final totalReserve = totalState + totalFed;
    final totalTakeHome = (totalGross - totalReserve).clamp(0.0, double.infinity);

    return BankTaxReserveSummary(
      year: year,
      totalInvoicesCount: yearInvoices.length,
      totalGrossCollected: totalGross,
      totalSubtotal: totalSub,
      totalSalesTax: totalSales,
      totalBoTax: totalBo,
      totalStateTax: totalState,
      totalReceiptDeductions: totalDeductibleReceipts,
      totalRecurringDeductions: totalRecurring,
      netTaxableIncome: netTaxable,
      seTax: seTax,
      federalIncomeTax: fedIncomeTax,
      totalFederalTax: totalFed,
      totalBankReserve: totalReserve,
      totalTakeHomeWithdrawn: totalTakeHome,
      federalRate: federalRate,
      seRate: seRate,
      boRate: boRate,
      quarters: quarters,
    );
  }

  /// Formatted clipboard summary for mobile/web banking checks.
  String toClipboardSummary({String currency = 'USD'}) {
    final cur = NumberFormat.simpleCurrency(name: currency);
    final buf = StringBuffer();
    buf.writeln('=== CodeLedger Bank Reserve ($year) ===');
    buf.writeln('Money Supposed to be in Bank (Tax Reserve): ${cur.format(totalBankReserve)}');
    buf.writeln('  • Washington State Tax: ${cur.format(totalStateTax)} (Sales Tax: ${cur.format(totalSalesTax)}, B&O: ${cur.format(totalBoTax)})');
    buf.writeln('  • Federal (IRS): ${cur.format(totalFederalTax)} (SE Tax: ${cur.format(seTax)}, Income Tax: ${cur.format(federalIncomeTax)})');
    buf.writeln('');
    buf.writeln('Realistic Invoices & Withdrawals:');
    buf.writeln('  • Total Collected: ${cur.format(totalGrossCollected)} ($totalInvoicesCount paid invoices)');
    buf.writeln('  • Amount Taken Out (Operating): ${cur.format(totalTakeHomeWithdrawn)}');
    buf.writeln('  • What Stays in Bank (Taxes): ${cur.format(totalBankReserve)}');
    buf.writeln('');
    buf.writeln('Quarterly Ledger:');
    for (final q in quarters) {
      buf.writeln('  ${q.label}: Invoiced ${cur.format(q.grossCollected)} | Bank Reserve: ${cur.format(q.totalTaxReserve)} | Taken Out: ${cur.format(q.takeHomeWithdrawn)}');
    }
    return buf.toString();
  }
}
