import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/database/app_database.dart';
import 'base_invoice_template.dart';
import '../models/pdf_invoice_data.dart';

/// Tech-focused template with repository and issue references.
class ModernDeveloperTemplate extends BaseInvoiceTemplate {
  @override
  String get templateKey => 'modern_developer';
  @override
  String get templateName => 'Modern Developer';

  @override
  Future<pw.Document> build(PdfInvoiceData data) async {
    final doc = pw.Document();
    final primary = colorFromArgb(data.template.primaryColor);
    final accent = colorFromArgb(data.template.accentColor);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // Developer-style header with accent bar
          _buildDevHeader(data, primary),
          pw.SizedBox(height: 20),
          buildAddresses(data),
          pw.SizedBox(height: 20),

          // Items table with project/repo context
          _buildDevTable(data, accent, primary),
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

  pw.Widget _buildDevHeader(PdfInvoiceData data, PdfColor primary) {
    return pw.Column(
      children: [
        // Accent bar at top
        pw.Container(
          height: 4,
          color: primary,
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('INVOICE',
                      style: pw.TextStyle(
                        fontSize: 32,
                        fontWeight: pw.FontWeight.bold,
                        color: primary,
                      )),
                  pw.Text(data.invoice.invoiceNumber,
                      style: pw.TextStyle(
                          fontSize: 14, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (data.profile.businessName.isNotEmpty)
                  pw.Text(data.profile.businessName,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      )),
                if (data.profile.ownerName.isNotEmpty)
                  pw.Text(data.profile.ownerName,
                      style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 6),
                pw.Text('Issued: ${fmtDate(data.invoice.issueDate)}',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Due: ${fmtDate(data.invoice.dueDate)}',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 1, color: PdfColors.grey300),
      ],
    );
  }

  static bool _looksLikeDate(String s) =>
      RegExp(r'^[A-Za-z]+ \d+, \d{4}$').hasMatch(s.trim());

  pw.Widget _buildDevTable(
      PdfInvoiceData data, PdfColor accent, PdfColor primary) {
    final mode = data.template.lineItemDisplayMode;
    final showDesc = data.template.showDescription;

    // Determine whether each item is time-based by description format,
    // not by timeEntryId (grouped items have null timeEntryId).
    final timeItems = <InvoiceLineItem>[];
    final manualItems = <InvoiceLineItem>[];

    for (final item in data.lineItems) {
      final parts = item.description.split(' | ');
      final isTimeBased = item.timeEntryId != null ||
          (parts.length > 1 && _looksLikeDate(parts.first));
      if (isTimeBased) {
        timeItems.add(item);
      } else {
        manualItems.add(item);
      }
    }

    // Group time items by project
    final byProject = <int?, List<InvoiceLineItem>>{};
    for (final item in timeItems) {
      byProject.putIfAbsent(item.projectId, () => []).add(item);
    }

    final widgets = <pw.Widget>[];

    final tableBorder = pw.TableBorder(
      bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
    );
    final headerStyle = pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
        color: PdfColors.grey700);

    for (final entry in byProject.entries) {
      final projectName = entry.key != null
          ? data.projectNames[entry.key] ?? 'Project'
          : 'General';
      final items = entry.value;
      final projectTotal = items.fold<double>(0, (sum, i) => sum + i.total);

      widgets.add(pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Project header
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                color: primary.shade(0.9),
                borderRadius: pw.BorderRadius.circular(2),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(projectName,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        color: primary,
                      )),
                  pw.Text(fmtCurrency(projectTotal),
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        color: primary,
                      )),
                ],
              ),
            ),
            // Items
            pw.TableHelper.fromTextArray(
              border: tableBorder,
              headerStyle: headerStyle,
              headerAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: colWidthsForMode(mode, showDescription: showDesc),
              headers: [
                ...lineItemPrefixHeaders(mode, showDescription: showDesc),
                'Hours',
                'Rate',
                'Amount',
              ],
              data: items.map((item) {
                final prefix = lineItemPrefix(item, mode, showDescription: showDesc);
                return [
                  ...prefix,
                  '${item.quantity.toStringAsFixed(2)}h',
                  fmtCurrency(item.unitPrice),
                  fmtCurrency(item.total),
                ];
              }).toList(),
            ),
          ],
        ),
      ));
    }

    // Manual items (no date prefix)
    if (manualItems.isNotEmpty) {
      widgets.add(pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(2),
              ),
              child: pw.Text('Additional Items',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  )),
            ),
            pw.TableHelper.fromTextArray(
              border: tableBorder,
              headerStyle: headerStyle,
              headerAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: colWidthsForMode(mode, showDescription: showDesc),
              headers: [
                ...lineItemPrefixHeaders(mode, showDescription: showDesc),
                'Qty',
                'Rate',
                'Amount',
              ],
              data: manualItems.map((item) {
                final prefix = lineItemPrefix(item, mode, showDescription: showDesc);
                return [
                  ...prefix,
                  item.quantity.toStringAsFixed(2),
                  fmtCurrency(item.unitPrice),
                  fmtCurrency(item.total),
                ];
              }).toList(),
            ),
          ],
        ),
      ));
    }

    return pw.Column(children: widgets);
  }
}
