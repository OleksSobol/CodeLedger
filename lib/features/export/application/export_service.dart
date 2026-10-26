import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/expense_dao.dart';
import '../../reports/data/models/tax_report_data.dart';

class ExportService {
  Future<File> generateTimeEntriesCsv({
    required List<TimeEntry> entries,
    required Map<String, String> projectNames,
    required Map<String, String> clientNames,
  }) async {
    final rows = <List<dynamic>>[];

    // Header
    rows.add([
      'Date',
      'Client',
      'Project',
      'Start Time',
      'End Time',
      'Duration (min)',
      'Description',
      'Repository',
      'Issue Ref',
      'Is Invoiced',
      'Invoice ID',
    ]);

    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm');

    for (final e in entries) {
      final date = dateFormat.format(e.startTime);
      final clientName = clientNames[e.clientId] ?? 'Unknown Client';
      final projectName = e.projectId != null
          ? (projectNames[e.projectId] ?? '')
          : '';
      final start = timeFormat.format(e.startTime);
      final end = e.endTime != null ? timeFormat.format(e.endTime!) : '';

      rows.add([
        date,
        clientName,
        projectName,
        start,
        end,
        e.durationMinutes ?? 0,
        e.description ?? '',
        e.repository ?? '',
        e.issueReference ?? '',
        e.isInvoiced ? 'Yes' : 'No',
        e.invoiceId ?? '',
      ]);
    }

    final csv = const CsvEncoder().convert(rows);
    final dir = await getTemporaryDirectory();
    final filename =
        'time_entries_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${dir.path}/$filename');

    await file.writeAsString(csv);
    return file;
  }

  Future<File> generateExpensesCsv({required List<Expense> expenses}) async {
    final rows = <List<dynamic>>[];
    rows.add([
      'Name',
      'Category',
      'Amount',
      'Frequency',
      'Monthly Amount',
      'Deduction Method',
      'Deduction %',
      'Monthly Deductible',
      'Annual Deductible',
      'Start Date',
      'End Date',
      'Active',
      'Notes',
    ]);

    final dateFmt = DateFormat('yyyy-MM-dd');
    final numFmt = NumberFormat('0.00');

    for (final e in expenses) {
      final pct = (e.deductibleFraction * 100).toStringAsFixed(1);
      rows.add([
        e.name,
        e.category,
        numFmt.format(e.amount),
        e.frequency,
        numFmt.format(e.monthlyAmount),
        e.deductionMethod,
        '$pct%',
        numFmt.format(e.monthlyDeductible),
        numFmt.format(e.annualDeductible),
        dateFmt.format(e.startDate),
        e.endDate != null ? dateFmt.format(e.endDate!) : 'Ongoing',
        e.isActiveNow ? 'Yes' : 'No',
        e.notes ?? '',
      ]);
    }

    final csv = const CsvEncoder().convert(rows);
    final dir = await getTemporaryDirectory();
    final filename =
        'expenses_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv);
    return file;
  }

  Future<File> generateTaxReportCsv({required TaxReportData data}) async {
    final csvRows = <List<dynamic>>[];
    final headers = [
      'Paid Date',
      'Client',
      'State',
      'Invoice #',
      'Net Amount',
      if (data.includeTax) 'Tax Label',
      if (data.includeTax) 'Tax Rate %',
      if (data.includeTax) 'Tax Amount',
      'Total Paid',
      'Currency',
      'Notes',
      'Paid',
    ];
    csvRows.add(headers);

    final fmt = DateFormat('M/d/yyyy');
    for (final row in data.rows) {
      final inv = row.invoice;
      final totalPaid = data.includeTax
          ? inv.amountPaid
          : (inv.amountPaid - inv.taxAmount).clamp(0.0, double.infinity);
      csvRows.add([
        fmt.format(inv.paidDate ?? inv.issueDate),
        row.clientName,
        row.normalizedState,
        inv.invoiceNumber,
        inv.subtotal.toStringAsFixed(2),
        if (data.includeTax) inv.taxLabel,
        if (data.includeTax) inv.taxRate.toStringAsFixed(2),
        if (data.includeTax) inv.taxAmount.toStringAsFixed(2),
        totalPaid.toStringAsFixed(2),
        inv.currency,
        inv.notes ?? '',
        'Yes',
      ]);
    }

    if (data.hasOutOfState) {
      csvRows.add([
        'IN-STATE (${data.businessState})',
        '',
        data.businessState,
        '',
        data.inStateSubtotal.toStringAsFixed(2),
        if (data.includeTax) '',
        if (data.includeTax) '',
        if (data.includeTax) '',
        '',
        '',
        '',
        '',
      ]);
      csvRows.add([
        'OUT-OF-STATE (EXCLUDED)',
        '',
        'Non-${data.businessState}',
        '',
        data.outOfStateSubtotal.toStringAsFixed(2),
        if (data.includeTax) '',
        if (data.includeTax) '',
        if (data.includeTax) '',
        '',
        '',
        '',
        '',
      ]);
    }

    csvRows.add([
      'TOTALS',
      '',
      '',
      '',
      data.totalSubtotal.toStringAsFixed(2),
      if (data.includeTax) '',
      if (data.includeTax) '',
      if (data.includeTax) data.totalTax.toStringAsFixed(2),
      data.totalPaid.toStringAsFixed(2),
      '',
      '',
      '',
    ]);

    final csv = const CsvEncoder().convert(csvRows);
    final dir = await getTemporaryDirectory();
    final filename =
        'tax_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv);
    return file;
  }
}
