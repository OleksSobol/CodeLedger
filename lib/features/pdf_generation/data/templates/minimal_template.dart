import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/utils/pdf_font_utils.dart';
import 'base_invoice_template.dart';
import '../models/pdf_invoice_data.dart';

/// Plain, traditional invoice — no color banners, just clean black & white
/// with minimal styling. Looks like a standard official invoice.
class MinimalTemplate extends BaseInvoiceTemplate {
  @override
  String get templateKey => 'minimal';
  @override
  String get templateName => 'Minimal';

  @override
  Future<pw.Document> build(PdfInvoiceData data) async {
    final doc = await newPdfDocument();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(48),
        build: (context) => [
          _buildPlainHeader(data),
          pw.SizedBox(height: 24),
          _buildAddressRow(data),
          pw.SizedBox(height: 8),
          _buildDateRow(data),
          pw.SizedBox(height: 24),
          pw.Divider(thickness: 1, color: PdfColors.black),
          pw.SizedBox(height: 4),
          _buildLineItemsTable(data),
          pw.SizedBox(height: 20),
          _buildTotals(data),
          pw.SizedBox(height: 32),
          _buildPaymentInfo(data),
          pw.SizedBox(height: 16),
          _buildFooterNotes(data),
        ],
      ),
    );

    return doc;
  }

  pw.Widget _buildPlainHeader(PdfInvoiceData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (data.profile.businessName.isNotEmpty)
                pw.Text(data.profile.businessName,
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
              if (data.profile.ownerName.isNotEmpty)
                pw.Text(data.profile.ownerName,
                    style: const pw.TextStyle(fontSize: 10)),
              if (data.formattedAddress.isNotEmpty)
                pw.Text(data.formattedAddress,
                    style: const pw.TextStyle(fontSize: 9)),
              if (data.profile.email != null)
                pw.Text(data.profile.email!,
                    style: const pw.TextStyle(fontSize: 9)),
              if (data.profile.phone != null)
                pw.Text(data.profile.phone!,
                    style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('INVOICE',
                style: pw.TextStyle(
                    fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(data.invoice.invoiceNumber,
                style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildAddressRow(PdfInvoiceData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Bill To:',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(data.client.name,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              if (data.client.contactName != null)
                pw.Text(data.client.contactName!,
                    style: const pw.TextStyle(fontSize: 9)),
              if (data.clientAddress.isNotEmpty)
                pw.Text(data.clientAddress,
                    style: const pw.TextStyle(fontSize: 9)),
              if (data.client.email != null)
                pw.Text(data.client.email!,
                    style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildDateRow(PdfInvoiceData data) {
    final inv = data.invoice;
    return pw.Row(
      children: [
        _labelValue('Invoice Date:', fmtDate(inv.issueDate)),
        pw.SizedBox(width: 24),
        _labelValue('Due Date:', fmtDate(inv.dueDate)),
        if (inv.periodStart != null && inv.periodEnd != null) ...[
          pw.SizedBox(width: 24),
          _labelValue('Period:',
              '${fmtDate(inv.periodStart!)} - ${fmtDate(inv.periodEnd!)}'),
        ],
      ],
    );
  }

  pw.Widget _labelValue(String label, String value) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 4),
        pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  pw.Widget _buildLineItemsTable(PdfInvoiceData data) {
    final mode = data.template.lineItemDisplayMode;
    final showDesc = data.template.showDescription;

    return pw.TableHelper.fromTextArray(
      border: null,
      headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 1, color: PdfColors.black),
        ),
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      columnWidths: colWidthsForMode(mode, showDescription: showDesc),
      headerAlignment: pw.Alignment.centerLeft,
      headers: [
        ...lineItemPrefixHeaders(mode, showDescription: showDesc),
        'Qty',
        'Rate',
        'Amount',
      ],
      data: data.lineItems.map((item) {
        final prefix = lineItemPrefix(item, mode, showDescription: showDesc);
        return [
          ...prefix,
          item.quantity.toStringAsFixed(2),
          fmtCurrency(item.unitPrice),
          fmtCurrency(item.total),
        ];
      }).toList(),
    );
  }

  pw.Widget _buildTotals(PdfInvoiceData data) {
    final inv = data.invoice;
    final hours = data.totalHours;
    final rows = <pw.Widget>[];

    if (hours > 0) rows.add(_totalLine('Total Hours', '${hours.toStringAsFixed(2)}h'));
    rows.add(_totalLine('Subtotal', fmtCurrency(inv.subtotal)));

    if (inv.taxRate > 0) {
      rows.add(_totalLine(
          '${inv.taxLabel} (${inv.taxRate.toStringAsFixed(1)}%)',
          fmtCurrency(inv.taxAmount)));
    }
    if (inv.lateFeeAmount > 0) {
      rows.add(_totalLine('Late Fee', fmtCurrency(inv.lateFeeAmount)));
    }

    rows.add(pw.Divider(thickness: 0.5));
    rows.add(pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Total Due',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.Text(fmtCurrency(inv.total),
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 12)),
        ],
      ),
    ));

    if (inv.amountPaid > 0) {
      rows.add(_totalLine('Amount Paid', fmtCurrency(inv.amountPaid)));
      final remaining = inv.total - inv.amountPaid;
      if (remaining > 0) {
        rows.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Balance Due',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text(fmtCurrency(remaining),
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 11)),
            ],
          ),
        ));
      }
    }

    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(width: 220, child: pw.Column(children: rows)),
    );
  }

  pw.Widget _totalLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _buildPaymentInfo(PdfInvoiceData data) {
    final profile = data.profile;
    final tmpl = data.template;
    final sections = <pw.Widget>[];

    if (tmpl.showPaymentTerms) {
      final days = data.invoice.dueDate
          .difference(data.invoice.issueDate)
          .inDays;
      sections.add(pw.Text(
        'Payment due within $days days of invoice date.',
        style: const pw.TextStyle(fontSize: 9),
      ));
      sections.add(pw.SizedBox(height: 6));
    }

    if (tmpl.showBankDetails && profile.showBankDetails) {
      final bankLines = <String>[];
      if (profile.bankName != null) bankLines.add('Bank: ${profile.bankName}');
      if (profile.bankRoutingNumber != null) {
        bankLines.add('Routing: ${profile.bankRoutingNumber}');
      }
      if (profile.bankAccountNumber != null) {
        final acct = profile.bankAccountNumber!;
        final masked = acct.length > 4
            ? '${'*' * (acct.length - 4)}${acct.substring(acct.length - 4)}'
            : acct;
        bankLines.add('Account: $masked (${profile.bankAccountType})');
      }
      if (bankLines.isNotEmpty) {
        sections.add(pw.Text('ACH Payment:',
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold)));
        for (final line in bankLines) {
          sections.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 8),
            child: pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
          ));
        }
        sections.add(pw.SizedBox(height: 6));
      }
    }

    if (tmpl.showStripeLink &&
        profile.showStripeLink &&
        profile.stripePaymentLink != null) {
      sections.add(pw.Text('Online Payment:',
          style:
              pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)));
      sections.add(pw.Padding(
        padding: const pw.EdgeInsets.only(left: 8),
        child: pw.Text(profile.stripePaymentLink!,
            style: const pw.TextStyle(fontSize: 9)),
      ));
      sections.add(pw.SizedBox(height: 6));
    }

    if (profile.paymentInstructions != null &&
        profile.paymentInstructions!.isNotEmpty) {
      sections.add(pw.Text(profile.paymentInstructions!,
          style: const pw.TextStyle(fontSize: 9)));
    }

    if (tmpl.showLateFeeClause && profile.lateFeePercentage != null) {
      sections.add(pw.SizedBox(height: 4));
      sections.add(pw.Text(
        'A late fee of ${profile.lateFeePercentage!.toStringAsFixed(1)}% '
        'may be applied to overdue balances.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ));
    }

    if (sections.isEmpty) return pw.SizedBox.shrink();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 8),
        ...sections,
      ],
    );
  }

  pw.Widget _buildFooterNotes(PdfInvoiceData data) {
    final parts = <pw.Widget>[];

    if (data.template.showTaxId &&
        data.profile.showTaxId &&
        data.profile.taxId != null) {
      parts.add(pw.Text('Tax ID: ${data.profile.taxId}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)));
    }

    if (data.template.showBusinessLicense &&
        data.profile.showWaLicense &&
        data.profile.waBusinessLicense != null) {
      parts.add(pw.Text(
          'WA Business License: ${data.profile.waBusinessLicense}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)));
    }

    if (data.template.footerText != null) {
      parts.add(pw.Text(data.template.footerText!,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)));
    }

    if (data.invoice.notes != null && data.invoice.notes!.isNotEmpty) {
      if (parts.isNotEmpty) parts.add(pw.SizedBox(height: 6));
      parts.add(pw.Text('Notes:',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)));
      parts.add(pw.Text(data.invoice.notes!,
          style: const pw.TextStyle(fontSize: 9)));
    }

    if (parts.isEmpty) return pw.SizedBox.shrink();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: parts,
    );
  }
}
