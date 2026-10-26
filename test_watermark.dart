import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      pageTheme: pw.PageTheme(
        buildForeground: (context) {
          return pw.FullPage(
            ignoreMargins: true,
            child: pw.Watermark(
              child: pw.Text('PAID', style: pw.TextStyle(fontSize: 100, color: PdfColors.red100, fontWeight: pw.FontWeight.bold)),
            ),
          );
        },
      ),
      build: (context) => [
        pw.Text('Hello World'),
      ],
    ),
  );

  final bytes = await doc.save();
  // ignore: avoid_print
  print('Saved ${bytes.length} bytes');
}
