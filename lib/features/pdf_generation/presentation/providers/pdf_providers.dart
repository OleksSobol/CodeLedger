import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../data/models/pdf_invoice_data.dart';
import '../../data/pdf_generator.dart';

/// Builds PdfInvoiceData from an invoice ID, then generates the PDF document.
final invoicePdfProvider =
    FutureProvider.family<pw.Document, String>((ref, invoiceId) async {
  final invoiceDao = ref.watch(invoiceRepositoryProvider);
  final invoice = await invoiceDao.getInvoice(invoiceId);
  final lineItems = await invoiceDao.getLineItems(invoiceId);

  final client = await ref.watch(clientRepositoryProvider).getClient(invoice.clientId);
  final profile = await ref.watch(userProfileRepositoryProvider).getProfile();

  // Resolve template: invoice -> client -> profile -> first available
  final templateDao = ref.watch(invoiceTemplateRepositoryProvider);
  InvoiceTemplate? template;
  if (invoice.templateId != null) {
    template = await templateDao.getById(invoice.templateId!);
  }
  if (template == null && client.defaultTemplateId != null) {
    template = await templateDao.getById(client.defaultTemplateId!);
  }
  if (template == null && profile.defaultTemplateId != null) {
    template = await templateDao.getById(profile.defaultTemplateId!);
  }
  template ??= await templateDao.getDefault();
  template ??= (await templateDao.getAll()).first;

  // Collect project names for line items referencing projects
  final projectIds = lineItems
      .where((li) => li.projectId != null)
      .map((li) => li.projectId!)
      .toSet();
  final projectNames = <String, String>{};
  final projectDao = ref.watch(projectRepositoryProvider);
  for (final pid in projectIds) {
    try {
      final project = await projectDao.getProject(pid);
      projectNames[pid] = project.name;
    } catch (_) {
      // Project may have been deleted
    }
  }

  final data = PdfInvoiceData(
    invoice: invoice,
    client: client,
    profile: profile,
    template: template,
    lineItems: lineItems,
    projectNames: projectNames,
  );

  return PdfGenerator.generateInvoice(data);
});

/// Same as [invoicePdfProvider] but allows overriding the template at preview time.
final invoicePdfWithTemplateProvider = FutureProvider.family<pw.Document,
    ({String invoiceId, String? templateId})>((ref, params) async {
  final invoiceDao = ref.watch(invoiceRepositoryProvider);
  final invoice = await invoiceDao.getInvoice(params.invoiceId);
  final lineItems = await invoiceDao.getLineItems(params.invoiceId);

  final client =
      await ref.watch(clientRepositoryProvider).getClient(invoice.clientId);
  final profile = await ref.watch(userProfileRepositoryProvider).getProfile();

  final templateDao = ref.watch(invoiceTemplateRepositoryProvider);
  InvoiceTemplate? template;

  // If a template override was provided, use it
  if (params.templateId != null) {
    template = await templateDao.getById(params.templateId!);
  }

  // Otherwise fall back to the normal resolution chain
  if (template == null && invoice.templateId != null) {
    template = await templateDao.getById(invoice.templateId!);
  }
  if (template == null && client.defaultTemplateId != null) {
    template = await templateDao.getById(client.defaultTemplateId!);
  }
  if (template == null && profile.defaultTemplateId != null) {
    template = await templateDao.getById(profile.defaultTemplateId!);
  }
  template ??= await templateDao.getDefault();
  template ??= (await templateDao.getAll()).first;

  final projectIds = lineItems
      .where((li) => li.projectId != null)
      .map((li) => li.projectId!)
      .toSet();
  final projectNames = <String, String>{};
  final projectDao = ref.watch(projectRepositoryProvider);
  for (final pid in projectIds) {
    try {
      final project = await projectDao.getProject(pid);
      projectNames[pid] = project.name;
    } catch (_) {}
  }

  final data = PdfInvoiceData(
    invoice: invoice,
    client: client,
    profile: profile,
    template: template,
    lineItems: lineItems,
    projectNames: projectNames,
  );

  return PdfGenerator.generateInvoice(data);
});
