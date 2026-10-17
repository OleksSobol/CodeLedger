import 'package:intl/intl.dart';

/// Models the recommended bank account split for an invoice payment.
/// Allows freelancers to immediately know how much of an incoming invoice
/// payment to transfer into their dedicated tax bank accounts (sales tax & federal tax)
/// vs their operating/take-home checking account. (DEV-78)
class TaxBankSplit {
  final double subtotal;
  final double taxRate;
  final String taxLabel;
  final double salesTaxAmount;
  final double federalTaxRate;
  final double federalTaxAmount;
  final double lateFeeAmount;
  final double total;
  final double totalTaxReserve;
  final double takeHomeAmount;
  final double? paymentAmount;

  const TaxBankSplit({
    required this.subtotal,
    required this.taxRate,
    required this.taxLabel,
    required this.salesTaxAmount,
    required this.federalTaxRate,
    required this.federalTaxAmount,
    this.lateFeeAmount = 0.0,
    required this.total,
    required this.totalTaxReserve,
    required this.takeHomeAmount,
    this.paymentAmount,
  });

  /// Calculates bank account split from invoice figures.
  /// [federalTaxRate] is represented as percentage (e.g. 20.0 for 20%).
  factory TaxBankSplit.calculate({
    required double subtotal,
    required double taxAmount,
    double taxRate = 0.0,
    String taxLabel = 'Sales Tax',
    double federalTaxRate = 20.0,
    double lateFeeAmount = 0.0,
    double? total,
    double? paymentAmount,
  }) {
    final computedTotal = total ?? (subtotal + taxAmount + lateFeeAmount);

    if (paymentAmount != null && computedTotal > 0) {
      final ratio = (paymentAmount / computedTotal).clamp(0.0, 1.0);
      final proportionalSubtotal = subtotal * ratio;
      final propSalesTax = taxAmount * ratio;
      final propFedTax = proportionalSubtotal * (federalTaxRate / 100.0);
      final propTotalTax = propSalesTax + propFedTax;
      final propTakeHome = (paymentAmount - propTotalTax).clamp(0.0, double.infinity);

      return TaxBankSplit(
        subtotal: proportionalSubtotal,
        taxRate: taxRate,
        taxLabel: taxLabel,
        salesTaxAmount: propSalesTax,
        federalTaxRate: federalTaxRate,
        federalTaxAmount: propFedTax,
        lateFeeAmount: lateFeeAmount * ratio,
        total: paymentAmount,
        totalTaxReserve: propTotalTax,
        takeHomeAmount: propTakeHome,
        paymentAmount: paymentAmount,
      );
    }

    final computedFedTax = subtotal * (federalTaxRate / 100.0);
    final totalTax = taxAmount + computedFedTax;
    final takeHome = (computedTotal - totalTax).clamp(0.0, double.infinity);

    return TaxBankSplit(
      subtotal: subtotal,
      taxRate: taxRate,
      taxLabel: taxLabel,
      salesTaxAmount: taxAmount,
      federalTaxRate: federalTaxRate,
      federalTaxAmount: computedFedTax,
      lateFeeAmount: lateFeeAmount,
      total: computedTotal,
      totalTaxReserve: totalTax,
      takeHomeAmount: takeHome,
      paymentAmount: paymentAmount,
    );
  }

  /// Generates a clipboard-ready text summary of the transfer instructions
  /// for mobile or online banking.
  String toClipboardSummary({
    String? invoiceNumber,
    String currency = 'USD',
  }) {
    final currencyFmt = NumberFormat.simpleCurrency(name: currency);
    final invHeader = invoiceNumber != null && invoiceNumber.isNotEmpty
        ? 'Bank Transfer Split for Invoice $invoiceNumber'
        : 'Bank Transfer Split';

    final buf = StringBuffer();
    buf.writeln('$invHeader:');
    buf.writeln('Total Received: ${currencyFmt.format(total)}');
    if (salesTaxAmount > 0) {
      final rateStr = taxRate > 0 ? ' (${taxRate.toStringAsFixed(1)}%)' : '';
      buf.writeln('→ $taxLabel Account$rateStr: ${currencyFmt.format(salesTaxAmount)}');
    }
    buf.writeln('→ Federal Tax Account (${federalTaxRate.toStringAsFixed(1)}%): ${currencyFmt.format(federalTaxAmount)}');
    buf.writeln('Total Tax Reserve to Move: ${currencyFmt.format(totalTaxReserve)}');
    buf.writeln('→ Operating / Take-Home Account: ${currencyFmt.format(takeHomeAmount)}');

    return buf.toString();
  }
}
