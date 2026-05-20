import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../email/presentation/providers/email_providers.dart';
import '../../../pdf_generation/presentation/pages/pdf_preview_page.dart';
import '../../../pdf_generation/presentation/providers/pdf_providers.dart';
import '../providers/invoice_providers.dart';

/// Dedicated screen for the "send invoices" routine. Shows only drafts
/// that are ready to email, with one-tap send and a shortcut to append
/// more time entries before sending.
class SendInvoicesPage extends ConsumerWidget {
  const SendInvoicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(allInvoicesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Send Invoices')),
      body: invoicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final drafts = all.where((i) => i.status == 'draft').toList()
            ..sort((a, b) => a.issueDate.compareTo(b.issueDate));

          if (drafts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mark_email_read_outlined,
                        size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('Nothing to send',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Drafts you create will show up here, ready to email.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: drafts.length,
            itemBuilder: (context, i) =>
                _DraftCard(invoice: drafts[i]),
          );
        },
      ),
    );
  }
}

class _DraftCard extends ConsumerStatefulWidget {
  final Invoice invoice;
  const _DraftCard({required this.invoice});

  @override
  ConsumerState<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends ConsumerState<_DraftCard> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd();
    final clientAsync =
        ref.watch(clientByIdProvider(widget.invoice.clientId));
    final clientName =
        clientAsync.whenOrNull(data: (c) => c.name) ?? '...';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.invoice.invoiceNumber,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  formatCurrency(widget.invoice.total,
                      currency: widget.invoice.currency),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$clientName - Due ${dateFmt.format(widget.invoice.dueDate)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sending
                        ? null
                        : () => context.push(
                              '/invoices/${widget.invoice.id}/add-time',
                              extra: widget.invoice,
                            ),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Add Time'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PdfPreviewPage(
                                  invoiceId: widget.invoice.id,
                                  invoiceNumber:
                                      widget.invoice.invoiceNumber,
                                ),
                              ),
                            ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Preview'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Sending...' : 'Email Invoice'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final invoice = widget.invoice;
      final doc =
          await ref.refresh(invoicePdfProvider(invoice.id).future);
      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/${invoice.invoiceNumber.replaceAll(RegExp(r'[^\w]'), '_')}.pdf');
      await file.writeAsBytes(bytes);

      final profile =
          await ref.read(userProfileRepositoryProvider).getProfile();
      final subject = profile.defaultEmailSubjectFormat
          .replaceAll('{number}', invoice.invoiceNumber)
          .replaceAll('{client}', '')
          .replaceAll(
              '{period}',
              invoice.periodStart != null && invoice.periodEnd != null
                  ? '${DateFormat.yMMMd().format(invoice.periodStart!)} - '
                      '${DateFormat.yMMMd().format(invoice.periodEnd!)}'
                  : '');

      final client =
          await ref.read(clientRepositoryProvider).getClient(invoice.clientId);
      final recipients =
          <String>[if (client.email != null) client.email!];

      final emailService = ref.read(emailServiceProvider);
      await emailService.sendInvoice(
        file: file,
        subject: subject,
        body: 'Please find attached invoice ${invoice.invoiceNumber}.',
        recipients: recipients,
      );

      await ref
          .read(invoiceNotifierProvider.notifier)
          .updateStatus(invoice.id, 'sent');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${invoice.invoiceNumber} marked as sent.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
