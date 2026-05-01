import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Creates a [pw.Document] with NotoSans as the default font.
/// NotoSans has broad Unicode coverage, fixing the Helvetica warning.
/// Fonts are fetched from Google on first use and cached locally.
Future<pw.Document> newPdfDocument() async {
  final regular = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();
  final italic = await PdfGoogleFonts.notoSansItalic();
  final boldItalic = await PdfGoogleFonts.notoSansBoldItalic();
  return pw.Document(
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
    ),
  );
}
