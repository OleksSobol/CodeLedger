import '../../../../core/constants/us_states.dart';
import '../../../../core/database/app_database.dart';

/// One resolved row in the tax / income report.
class TaxReportRow {
  final Invoice invoice;
  final String clientName;
  final String? clientState;

  const TaxReportRow({
    required this.invoice,
    required this.clientName,
    this.clientState,
  });

  /// Normalized 2-letter state code (or 'INTL'), or empty string if unset.
  String get normalizedState => UsStates.normalizeCode(clientState) ?? '';

  /// Tax column label for the PDF cell.
  /// Shows label + rate when tax > 0, otherwise empty string.
  String get taxColumnLabel {
    if (invoice.taxRate == 0.0) return '';
    return '${invoice.taxLabel} ${invoice.taxRate.toStringAsFixed(0)}%';
  }
}

class TaxReportData {
  final UserProfile profile;
  final DateTime startDate;
  final DateTime endDate;
  final List<TaxReportRow> rows;
  final String? clientFilterName; // null = all clients

  final bool includeTax;

  final double estimatedIncomeTax;
  final double bankReserve;

  const TaxReportData({
    required this.profile,
    required this.startDate,
    required this.endDate,
    required this.rows,
    this.clientFilterName,
    this.includeTax = true,
    this.estimatedIncomeTax = 0.0,
    this.bankReserve = 0.0,
  });

  String get businessState =>
      UsStates.normalizeCode(profile.stateProvince) ?? 'WA';

  double get totalSubtotal => rows.fold(0.0, (s, r) => s + r.invoice.subtotal);

  double get inStateSubtotal => rows
      .where(
        (r) => !UsStates.isOutOfState(
          r.clientState,
          businessState: businessState,
        ),
      )
      .fold(0.0, (s, r) => s + r.invoice.subtotal);

  double get outOfStateSubtotal => rows
      .where(
        (r) => UsStates.isOutOfState(
          r.clientState,
          businessState: businessState,
        ),
      )
      .fold(0.0, (s, r) => s + r.invoice.subtotal);

  bool get hasOutOfState => outOfStateSubtotal > 0;

  double get totalTax =>
      rows.fold(0.0, (s, r) => s + (includeTax ? r.invoice.taxAmount : 0.0));
  double get totalPaid => rows.fold(0.0, (s, r) {
    if (includeTax) return s + r.invoice.amountPaid;
    return s +
        (r.invoice.amountPaid - r.invoice.taxAmount).clamp(
          0.0,
          double.infinity,
        );
  });
  String get currency => rows.isEmpty ? 'USD' : rows.first.invoice.currency;

  String _fmt(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.year}';
  String get dateRangeText => '${_fmt(startDate)} - ${_fmt(endDate)}';
}
