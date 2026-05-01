import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/pdf_font_utils.dart';
import '../models/work_report_data.dart';
import 'work_report_template.dart';

/// Clean timesheet PDF suitable for sharing with employers.
/// Shows one row per day with: Date | Start | End | Hours | Description
/// Columns shown are controlled by [TimesheetColumns].
class TimesheetTemplate implements ReportTemplate {
  final TimesheetColumns columns;

  const TimesheetTemplate({this.columns = const TimesheetColumns()});

  @override
  String get templateKey => 'timesheet';

  @override
  String get templateName => 'Timesheet';

  String _fmtDate(DateTime dt) => DateFormat('EEE, MMM d').format(dt);
  String _fmtTime(DateTime dt) => DateFormat.jm().format(dt);

  String _fmtHours(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Future<pw.Document> build(WorkReportData data) async {
    final doc = await newPdfDocument();

    // Group entries by date, sorted ascending
    final sorted = List<TimeEntry>.from(data.entries)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final grouped = <DateTime, List<TimeEntry>>{};
    for (final e in sorted) {
      final day =
          DateTime(e.startTime.year, e.startTime.month, e.startTime.day);
      (grouped[day] ??= []).add(e);
    }
    final dates = grouped.keys.toList()..sort();

    // Build table rows — one row per time entry
    final headerCells = <String>['Date'];
    if (columns.showStartEnd) {
      headerCells.addAll(['Start', 'End']);
    }
    headerCells.add('Hours');
    if (columns.showDescription) headerCells.add('Description');
    if (columns.showProject) headerCells.add('Project');

    final rows = <List<String>>[];
    final dayTotals = <DateTime, int>{};

    for (final date in dates) {
      final entries = grouped[date]!;
      final dayMinutes =
          entries.fold<int>(0, (s, e) => s + (e.durationMinutes ?? 0));
      dayTotals[date] = dayMinutes;

      for (int i = 0; i < entries.length; i++) {
        final e = entries[i];
        final row = <String>[];

        // Date — show on first entry for the day only
        row.add(i == 0 ? _fmtDate(date) : '');

        if (columns.showStartEnd) {
          row.add(_fmtTime(e.startTime));
          row.add(e.endTime != null ? _fmtTime(e.endTime!) : '—');
        }
        row.add(_fmtHours(e.durationMinutes ?? 0));

        if (columns.showDescription) {
          row.add(e.description ?? '');
        }
        if (columns.showProject) {
          row.add(e.projectId != null
              ? (data.projectNames[e.projectId] ?? '')
              : '');
        }
        rows.add(row);
      }

      // Day total row (only if more than one entry)
      if (entries.length > 1) {
        final totalRow = List<String>.filled(headerCells.length, '');
        totalRow[0] = ''; // date
        // hours column index
        final hoursIdx = columns.showStartEnd ? 3 : 1;
        if (hoursIdx < totalRow.length) {
          totalRow[hoursIdx] = 'Day total: ${_fmtHours(dayMinutes)}';
        }
        rows.add(totalRow);
      }
    }

    // Column widths
    final widths = <int, pw.TableColumnWidth>{};
    int col = 0;
    widths[col++] = const pw.FlexColumnWidth(1.6); // Date
    if (columns.showStartEnd) {
      widths[col++] = const pw.FlexColumnWidth(0.8); // Start
      widths[col++] = const pw.FlexColumnWidth(0.8); // End
    }
    widths[col++] = const pw.FlexColumnWidth(0.7); // Hours
    if (columns.showDescription) {
      widths[col++] = const pw.FlexColumnWidth(3.0); // Description
    }
    if (columns.showProject) {
      widths[col++] = const pw.FlexColumnWidth(1.2); // Project
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        header: (_) => _buildHeader(data),
        footer: (_) => _buildFooterBar(data, dayTotals),
        build: (_) => [
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder(
              bottom: const pw.BorderSide(width: 0.5, color: PdfColors.grey400),
              horizontalInside:
                  const pw.BorderSide(width: 0.3, color: PdfColors.grey200),
              verticalInside:
                  const pw.BorderSide(width: 0.3, color: PdfColors.grey200),
              left: const pw.BorderSide(width: 0.3, color: PdfColors.grey300),
              right: const pw.BorderSide(width: 0.3, color: PdfColors.grey300),
              top: const pw.BorderSide(width: 0.5, color: PdfColors.grey400),
            ),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey100),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6, vertical: 4),
            columnWidths: widths,
            headers: headerCells,
            data: rows,
          ),
        ],
      ),
    );

    return doc;
  }

  pw.Widget _buildHeader(WorkReportData data) {
    final period =
        '${DateFormat.yMMMd().format(data.startDate)} – ${DateFormat.yMMMd().format(data.endDate)}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('TIMESHEET',
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
            if (data.profile.businessName.isNotEmpty)
              pw.Text(data.profile.businessName,
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text('Period: $period',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            if (data.client != null) ...[
              pw.Text('   |   Client: ${data.client!.name}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            ],
            if (data.project != null) ...[
              pw.Text('   |   Project: ${data.project!.name}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            ],
          ],
        ),
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
      ],
    );
  }

  pw.Widget _buildFooterBar(
      WorkReportData data, Map<DateTime, int> dayTotals) {
    final totalMinutes = dayTotals.values.fold<int>(0, (a, b) => a + b);
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
                'Generated ${DateFormat.yMMMd().format(DateTime.now())}',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600)),
            pw.Text(
              'Total: ${_fmtHours(totalMinutes)}  '
              '(${(totalMinutes / 60.0).toStringAsFixed(2)} hrs)',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900),
            ),
          ],
        ),
      ],
    );
  }
}

/// Controls which optional columns appear in the timesheet.
class TimesheetColumns {
  final bool showStartEnd;
  final bool showDescription;
  final bool showProject;

  const TimesheetColumns({
    this.showStartEnd = true,
    this.showDescription = true,
    this.showProject = false,
  });
}
