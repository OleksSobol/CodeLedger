import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../../../core/database/app_database.dart';
import '../../../invoices/presentation/providers/template_providers.dart';
import '../providers/pdf_providers.dart';

class PdfPreviewPage extends ConsumerStatefulWidget {
  final int invoiceId;
  final String invoiceNumber;

  const PdfPreviewPage({
    super.key,
    required this.invoiceId,
    required this.invoiceNumber,
  });

  @override
  ConsumerState<PdfPreviewPage> createState() => _PdfPreviewPageState();
}

class _PdfPreviewPageState extends ConsumerState<PdfPreviewPage> {
  int? _selectedTemplateId;

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(allTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice ${widget.invoiceNumber}'),
        bottom: templatesAsync.whenOrNull(
          data: (templates) => PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _TemplateSelector(
                templates: templates,
                selectedId: _selectedTemplateId,
                onChanged: (id) {
                  setState(() => _selectedTemplateId = id);
                },
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: PdfPreview(
          key: ValueKey(_selectedTemplateId),
          build: (format) => _generatePdf(),
          canChangeOrientation: false,
          canDebug: false,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generatePdf() async {
    final doc = await ref.refresh(
      invoicePdfWithTemplateProvider((
        invoiceId: widget.invoiceId,
        templateId: _selectedTemplateId,
      )).future,
    );
    return doc.save();
  }
}

class _TemplateSelector extends StatelessWidget {
  final List<InvoiceTemplate> templates;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  const _TemplateSelector({
    required this.templates,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: templates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final t = templates[index];
          final isSelected = selectedId == t.id ||
              (selectedId == null && index == 0);
          return ChoiceChip(
            label: Text(t.name),
            selected: isSelected,
            onSelected: (_) => onChanged(t.id),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}
