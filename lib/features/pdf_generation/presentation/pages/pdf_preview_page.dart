import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../../../../core/database/app_database.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../email/presentation/providers/email_providers.dart';
import '../../../invoices/presentation/providers/invoice_providers.dart';
import '../../../invoices/presentation/providers/template_providers.dart';
import '../../../profile/presentation/providers/profile_provider.dart';
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
  bool _initialized = false;
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(allTemplatesProvider);
    final invoiceAsync = ref.watch(invoiceDetailProvider(widget.invoiceId));

    if (!_initialized) {
      invoiceAsync.whenData((invoice) {
        if (!_initialized) {
          _selectedTemplateId = invoice.templateId;
          _initialized = true;
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice ${widget.invoiceNumber}'),
        actions: [
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.send_outlined),
              tooltip: 'Email / Share',
              onPressed: () => _sendInvoice(context),
            ),
        ],
        bottom: templatesAsync.whenOrNull(
          data: (templates) => PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _TemplateSelector(
                templates: templates,
                selectedId: _selectedTemplateId,
                onChanged: (id) async {
                  setState(() => _selectedTemplateId = id);
                  final messenger = ScaffoldMessenger.of(context);
                  await ref
                      .read(invoiceNotifierProvider.notifier)
                      .setInvoiceTemplate(widget.invoiceId, id);
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Template saved for this invoice'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
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

  Future<void> _sendInvoice(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final invoiceDao = ref.read(invoiceDaoProvider);
      final invoice = await invoiceDao.getInvoice(widget.invoiceId);

      final doc = await ref.refresh(
        invoicePdfWithTemplateProvider((
          invoiceId: widget.invoiceId,
          templateId: _selectedTemplateId,
        )).future,
      );
      final bytes = await doc.save();

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/${invoice.invoiceNumber.replaceAll(RegExp(r'[^\w]'), '_')}.pdf');
      await file.writeAsBytes(bytes);

      final profile = await ref.read(userProfileDaoProvider).getProfile();
      final subject = profile.defaultEmailSubjectFormat
          .replaceAll('{number}', invoice.invoiceNumber)
          .replaceAll('{client}', '')
          .replaceAll(
            '{period}',
            invoice.periodStart != null
                ? '${DateFormat.yMMMd().format(invoice.periodStart!)} – ${DateFormat.yMMMd().format(invoice.periodEnd!)}'
                : '',
          );

      final clientDao = ref.read(clientDaoProvider);
      final client = await clientDao.getClient(invoice.clientId);
      final recipients = <String>[if (client.email != null) client.email!];

      final emailService = ref.read(emailServiceProvider);
      await emailService.sendInvoice(
        file: file,
        subject: subject,
        body: 'Please find attached invoice ${invoice.invoiceNumber}.',
        recipients: recipients,
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
