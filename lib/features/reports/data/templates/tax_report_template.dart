import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/utils/currency_formatter.dart';
import '../models/tax_report_data.dart';

class TaxReportTemplate {
  const TaxReportTemplate();

  String _fmtDate(DateTime dt) => DateFormat('M/d/yyyy').format(dt);

  Future<pw.Document> build(TaxReportData data) async {
    final doc = pw.Document();

    const headers = [
      'Paid Date',
      'Client',
      'Invoice #',
      'Net Amount',
      'Tax',
      'Total Paid',
      'Notes',
      'Paid',
    ];

    // Build data rows
    final rows = <List<String>>[];
    for (final row in data.rows) {
      final inv = row.invoice;
      final taxCell = inv.taxAmount == 0.0
          ? formatCurrency(0.0, currency: inv.currency)
          : '${row.taxColumnLabel}\n'
              '${formatCurrency(inv.taxAmount, currency: inv.currency)}';

      rows.add([
        _fmtDate(inv.paidDate ?? inv.issueDate),
        row.clientName,
        inv.invoiceNumber,
        formatCurrency(inv.subtotal, currency: inv.currency),
        taxCell,
        formatCurrency(inv.amountPaid, currency: inv.currency),
        inv.notes ?? '',
        'Yes',
      ]);
    }

    // Totals row
    rows.add([
      'TOTALS',
      '',
      '',
      formatCurrency(data.totalSubtotal, currency: data.currency),
      formatCurrency(data.totalTax, currency: data.currency),
      formatCurrency(data.totalPaid, currency: data.currency),
      '',
      '',
    ]);

    final totalRowIndex = rows.length - 1;

    const columnWidths = {
      0: pw.FlexColumnWidth(1.0), // Date
      1: pw.FlexColumnWidth(2.2), // Client
      2: pw.FlexColumnWidth(1.4), // Invoice #
      3: pw.FlexColumnWidth(1.1), // Net Amount
      4: pw.FlexColumnWidth(1.3), // Tax
      5: pw.FlexColumnWidth(1.1), // Total Paid
      6: pw.FlexColumnWidth(1.5), // Notes
      7: pw.FlexColumnWidth(0.6), // Paid
    };

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        header: (_) => _buildHeader(data),
        footer: (_) => _buildFooter(data),
        build: (_) => [
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder(
              bottom:
                  const pw.BorderSide(width: 0.5, color: PdfColors.grey400),
              horizontalInside:
                  const pw.BorderSide(width: 0.3, color: PdfColors.grey200),
              verticalInside:
                  const pw.BorderSide(width: 0.3, color: PdfColors.grey200),
              left:
                  const pw.BorderSide(width: 0.3, color: PdfColors.grey300),
              right:
                  const pw.BorderSide(width: 0.3, color: PdfColors.grey300),
              top:
                  const pw.BorderSide(width: 0.5, color: PdfColors.grey400),
            ),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey100),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 5, vertical: 3),
            columnWidths: columnWidths,
            headers: headers,
            data: rows,
            cellDecoration: (index, cellData, rowNum) {
              if (rowNum == totalRowIndex) {
                return const pw.BoxDecoration(color: PdfColors.grey100);
              }
              return const pw.BoxDecoration();
            },
          ),
        ],
      ),
    );

    return doc;
  }

  pw.Widget _buildHeader(TaxReportData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'TAX / INCOME REPORT',
              style: pw.TextStyle(
                  fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            if (data.profile.businessName.isNotEmpty)
              pw.Text(
                data.profile.businessName,
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text(
              'Period: ${data.dateRangeText}',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey700),
            ),
            if (data.clientFilterName != null)
              pw.Text(
                '   |   Client: ${data.clientFilterName}',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey700),
              ),
          ],
        ),
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
      ],
    );
  }

  pw.Widget _buildFooter(TaxReportData data) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated ${DateFormat.yMMMd().format(DateTime.now())}',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Paid invoices only  |  ${data.rows.length} invoice(s)',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }
}
