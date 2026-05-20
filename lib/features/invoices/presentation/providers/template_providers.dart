import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/invoice_template_repository.dart';

final allTemplatesProvider = StreamProvider<List<InvoiceTemplate>>((ref) {
  return ref.watch(invoiceTemplateRepositoryProvider).watchAll();
});

final defaultTemplateProvider = FutureProvider<InvoiceTemplate?>((ref) {
  return ref.watch(invoiceTemplateRepositoryProvider).getDefault();
});

/// Notifier for template mutations (create, update, delete, set default).
final templateNotifierProvider =
    AsyncNotifierProvider<TemplateNotifier, void>(TemplateNotifier.new);

class TemplateNotifier extends AsyncNotifier<void> {
  late InvoiceTemplateRepository _dao;

  @override
  Future<void> build() async {
    _dao = ref.watch(invoiceTemplateRepositoryProvider);
  }

  Future<bool> updateTemplate(
      String id, InvoiceTemplatesCompanion companion) {
    return _dao.updateTemplate(id, companion);
  }

  Future<String> duplicateTemplate(
      InvoiceTemplate source, String newName) {
    return _dao.insertTemplate(InvoiceTemplatesCompanion(
      name: Value(newName),
      templateKey: Value(
          '${source.templateKey}_copy_${DateTime.now().millisecondsSinceEpoch}'),
      description: Value(source.description),
      isDefault: const Value(false),
      primaryColor: Value(source.primaryColor),
      accentColor: Value(source.accentColor),
      fontFamily: Value(source.fontFamily),
      showLogo: Value(source.showLogo),
      showPaymentInfo: Value(source.showPaymentInfo),
      showTaxBreakdown: Value(source.showTaxBreakdown),
      showTaxId: Value(source.showTaxId),
      showBusinessLicense: Value(source.showBusinessLicense),
      showBankDetails: Value(source.showBankDetails),
      showStripeLink: Value(source.showStripeLink),
      showDetailedBreakdown: Value(source.showDetailedBreakdown),
      showPaymentTerms: Value(source.showPaymentTerms),
      showLateFeeClause: Value(source.showLateFeeClause),
      isBuiltIn: const Value(false),
      footerText: Value(source.footerText),
    ));
  }

  Future<void> deleteTemplate(String id) => _dao.deleteTemplate(id);

  Future<void> setDefault(String id) => _dao.setDefault(id);
}
