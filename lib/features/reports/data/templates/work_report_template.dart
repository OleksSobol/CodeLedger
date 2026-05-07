import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/pdf_font_utils.dart';
import '../models/work_report_data.dart';

abstract class ReportTemplate {
  String get templateKey;
  String get templateName;
  Future<pw.Document> build(WorkReportData data);
}

class SimpleWorkReportTemplate implements ReportTemplate {
  @override
  String get templateKey => 'simple_work_report';

  @override
  String get templateName => 'Standard Report';

  String fmtDate(DateTime dt) => DateFormat.yMMMd().format(dt);
  
  String fmtDuration(int minutes) {
    final hours = minutes / 60.0;
    return '${hours.toStringAsFixed(2)} h';
  }

  @override
  Future<pw.Document> build(WorkReportData data) async {
    final doc = await newPdfDocument();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildHeader(data),
          pw.SizedBox(height: 20),
          _buildFilters(data),
          pw.SizedBox(height: 24),
          _buildContent(data),
          pw.SizedBox(height: 20),
          _buildFooter(data),
        ],
      ),
    );

    return doc;
  }

  pw.Widget _buildHeader(WorkReportData data) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('WORK REPORT',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Generated: ${fmtDate(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
        ),
        if (data.profile.businessName.isNotEmpty)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(data.profile.businessName,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              if (data.profile.ownerName.isNotEmpty)
                pw.Text(data.profile.ownerName, style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
      ],
    );
  }

  pw.Widget _buildFilters(WorkReportData data) {
    final filters = <String>[];
    filters.add('Period: ${fmtDate(data.startDate)} - ${fmtDate(data.endDate)}');
    
    if (data.client != null) {
      filters.add('Client: ${data.client!.name}');
    }
    if (data.project != null) {
      filters.add('Project: ${data.project!.name}');
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: filters
            .map((f) => pw.Text(f, style: const pw.TextStyle(fontSize: 10)))
            .toList(),
      ),
    );
  }

  pw.Widget _buildContent(WorkReportData data) {
    // Group by date
    final groupedMap = <DateTime, List<TimeEntry>>{};

    // safe sort
    final sorted = List<TimeEntry>.from(data.entries)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    for (final entry in sorted) {
      final date = DateTime(entry.startTime.year, entry.startTime.month, entry.startTime.day);
      groupedMap.putIfAbsent(date, () => []).add(entry);
    }

    final widgets = <pw.Widget>[];
    final dates = groupedMap.keys.toList()..sort();

    for (final date in dates) {
        final entries = groupedMap[date]!;
        // Sum durationMinutes (nullable)
        final dayTotal = entries.fold<int>(0, (sum, e) => sum + (e.durationMinutes ?? 0));
        
        widgets.add(pw.Container(
          margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(DateFormat.yMMMMEEEEd().format(date), 
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text('Day Total: ${fmtDuration(dayTotal)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey700)),
            ],
          ),
        ));

        // Build rows
        final rows = <List<String>>[];
        for (final e in entries) {
           final projectName = e.projectId != null ? (data.projectNames[e.projectId] ?? '-') : '-';
           final desc = e.description ?? '';
           
           final refs = <String>[];
           if (e.repository != null && e.repository!.isNotEmpty) refs.add(e.repository!);
           if (e.issueReference != null && e.issueReference!.isNotEmpty) refs.add(e.issueReference!);
           final refStr = refs.join(' ');
           
           rows.add([
             projectName,
             desc,
             refStr,
             fmtDuration(e.durationMinutes ?? 0),
           ]);
        }

        widgets.add(
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder(
              bottom: const pw.BorderSide(width: 0.5, color: PdfColors.grey300),
              horizontalInside: const pw.BorderSide(width: 0.5, color: PdfColors.grey200),
            ),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2), // Project
              1: const pw.FlexColumnWidth(3),   // Description
              2: const pw.FlexColumnWidth(1),   // Issue/Ref
              3: const pw.FlexColumnWidth(0.8), // Duration
            },
            headers: ['Project', 'Description', 'Ref/Repo', 'Duration'],
            data: rows,
          )
        );
    }
    
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: widgets);
  }
  
  pw.Widget _buildFooter(WorkReportData data) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text('Total Hours: ', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.Text(fmtDuration((data.totalHours * 60).round()), 
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
      ],
    );
  }
}
