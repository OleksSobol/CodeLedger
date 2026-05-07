import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/utils/pdf_font_utils.dart';
import 'base_invoice_template.dart';
import '../models/pdf_invoice_data.dart';

/// Grouped by date, shows each session with description.
class DetailedBreakdownTemplate extends BaseInvoiceTemplate {
  @override
  String get templateKey => 'detailed';
  @override
  String get templateName => 'Detailed Breakdown';

  @override
  Future<pw.Document> build(PdfInvoiceData data) async {
    final doc = await newPdfDocument();
    final primary = colorFromArgb(data.template.primaryColor);
    final accent = colorFromArgb(data.template.accentColor);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          buildHeader(data, accentColor: primary),
          pw.SizedBox(height: 24),
          buildAddresses(data),
          pw.SizedBox(height: 24),
          _buildGroupedTable(data, accent),
          pw.SizedBox(height: 20),
          buildTotals(data, accentColor: accent),
          pw.SizedBox(height: 24),
          buildPaymentSection(data),
          pw.SizedBox(height: 16),
          buildFooter(data),
        ],
      ),
    );

    return doc;
  }

  pw.Widget _buildGroupedTable(PdfInvoiceData data, PdfColor accent) {
    final mode = data.template.lineItemDisplayMode;
    final showDesc = data.template.showDescription;
    final allRows = <List<String>>[];

    for (final item in data.lineItems) {
      final prefix = lineItemPrefix(item, mode, showDescription: showDesc);
      // Inject project name into the description (last element of prefix)
      final projectName = item.projectId != null
          ? data.projectNames[item.projectId] ?? ''
          : '';
      if (showDesc && projectName.isNotEmpty && prefix.isNotEmpty) {
        prefix[prefix.length - 1] =
            '$projectName - ${prefix[prefix.length - 1]}';
      }

      final parts = item.description.split(' | ');
      final looksLikeDate = parts.length > 1 &&
          RegExp(r'^[A-Za-z]+ \d+, \d{4}$').hasMatch(parts.first.trim());
      final qtyStr = looksLikeDate || item.timeEntryId != null
          ? '${item.quantity.toStringAsFixed(2)}h'
          : item.quantity.toStringAsFixed(2);

      allRows.add([
        ...prefix,
        qtyStr,
        fmtCurrency(item.unitPrice),
        fmtCurrency(item.total),
      ]);
    }

    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 10,
          color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: accent),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: colWidthsForMode(mode, showDescription: showDesc),
      headers: [
        ...lineItemPrefixHeaders(mode, showDescription: showDesc),
        'Hours',
        'Rate',
        'Amount',
      ],
      data: allRows,
    );
  }
}
