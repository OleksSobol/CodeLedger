import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/pdf_font_utils.dart';
import '../models/tax_report_data.dart';

class TaxReportTemplate {
  const TaxReportTemplate();

  String _fmtDate(DateTime dt) => DateFormat('M/d/yyyy').format(dt);

  Future<pw.Document> build(TaxReportData data) async {
    final doc = await newPdfDocument();

    final headers = [
      'Paid Date',
      'Client',
      'State',
      'Invoice #',
      'Net Amount',
      if (data.includeTax) 'Tax',
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
        row.normalizedState,
        inv.invoiceNumber,
        formatCurrency(inv.subtotal, currency: inv.currency),
        if (data.includeTax) taxCell,
        formatCurrency(
          data.includeTax
              ? inv.amountPaid
              : (inv.amountPaid - inv.taxAmount).clamp(0.0, double.infinity),
          currency: inv.currency,
        ),
        inv.notes ?? '',
        'Yes',
      ]);
    }

    // Totals row
    rows.add([
      'TOTALS',
      '',
      '',
      '',
      formatCurrency(data.totalSubtotal, currency: data.currency),
      if (data.includeTax)
        formatCurrency(data.totalTax, currency: data.currency),
      formatCurrency(data.totalPaid, currency: data.currency),
      '',
      '',
    ]);

    final totalRowIndex = rows.length - 1;

    final columnWidths = {
      0: const pw.FlexColumnWidth(1.0), // Date
      1: const pw.FlexColumnWidth(2.0), // Client
      2: const pw.FlexColumnWidth(0.7), // State
      3: const pw.FlexColumnWidth(1.3), // Invoice #
      4: const pw.FlexColumnWidth(1.1), // Net Amount
      if (data.includeTax) 5: const pw.FlexColumnWidth(1.3), // Tax
      if (data.includeTax) 6: const pw.FlexColumnWidth(1.1), // Total Paid
      if (data.includeTax) 7: const pw.FlexColumnWidth(1.4), // Notes
      if (data.includeTax) 8: const pw.FlexColumnWidth(0.6), // Paid
      if (!data.includeTax) 5: const pw.FlexColumnWidth(1.1), // Total Paid
      if (!data.includeTax) 6: const pw.FlexColumnWidth(1.7), // Notes
      if (!data.includeTax) 7: const pw.FlexColumnWidth(0.6), // Paid
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
              bottom: const pw.BorderSide(width: 0.5, color: PdfColors.grey400),
              horizontalInside: const pw.BorderSide(
                width: 0.3,
                color: PdfColors.grey200,
              ),
              verticalInside: const pw.BorderSide(
                width: 0.3,
                color: PdfColors.grey200,
              ),
              left: const pw.BorderSide(width: 0.3, color: PdfColors.grey300),
              right: const pw.BorderSide(width: 0.3, color: PdfColors.grey300),
              top: const pw.BorderSide(width: 0.5, color: PdfColors.grey400),
            ),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey100,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 3,
            ),
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
          if (data.hasOutOfState) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'State Apportionment Summary (${data.businessState})',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'In-State (${data.businessState}) Taxable Sales',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        formatCurrency(
                          data.inStateSubtotal,
                          currency: data.currency,
                        ),
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Out-of-State Sales (Interstate/Foreign Deduction)',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        formatCurrency(
                          data.outOfStateSubtotal,
                          currency: data.currency,
                        ),
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Total Gross Sales',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        formatCurrency(
                          data.totalSubtotal,
                          currency: data.currency,
                        ),
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (data.bankReserve > 0) ...[
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Bank Reserve Summary',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Tax Collected (Sales Tax)',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        formatCurrency(data.totalTax, currency: data.currency),
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Est. Income & SE Tax on Net Profit',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        formatCurrency(
                          data.estimatedIncomeTax,
                          currency: data.currency,
                        ),
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Total Bank Reserve (Amount to save)',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        formatCurrency(
                          data.bankReserve,
                          currency: data.currency,
                        ),
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            if (data.profile.businessName.isNotEmpty)
              pw.Text(
                data.profile.businessName,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text(
              'Period: ${data.dateRangeText}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            if (data.clientFilterName != null)
              pw.Text(
                '   |   Client: ${data.clientFilterName}',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
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
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Paid invoices only  |  ${data.rows.length} invoice(s)',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }
}
