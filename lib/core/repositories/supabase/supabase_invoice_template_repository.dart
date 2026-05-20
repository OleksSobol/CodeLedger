import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../database/app_database.dart';
import '../invoice_template_repository.dart';

class SupabaseInvoiceTemplateRepository implements InvoiceTemplateRepository {
  final SupabaseClient _client;
  SupabaseInvoiceTemplateRepository(this._client);

  String get _uid => _client.auth.currentUser!.id;

  InvoiceTemplate _fromRow(Map<String, dynamic> r) => InvoiceTemplate(
        id: r['id'] as String,
        name: r['name'] as String,
        templateKey: r['template_key'] as String,
        description: r['description'] as String?,
        isDefault: r['is_default'] as bool? ?? false,
        primaryColor: r['primary_color'] as int? ?? 0xFF2196F3,
        accentColor: r['accent_color'] as int? ?? 0xFF1565C0,
        fontFamily: r['font_family'] as String? ?? 'Helvetica',
        showLogo: r['show_logo'] as bool? ?? true,
        showPaymentInfo: r['show_payment_info'] as bool? ?? true,
        showTaxBreakdown: r['show_tax_breakdown'] as bool? ?? true,
        showTaxId: r['show_tax_id'] as bool? ?? true,
        showBusinessLicense: r['show_business_license'] as bool? ?? false,
        showBankDetails: r['show_bank_details'] as bool? ?? true,
        showStripeLink: r['show_stripe_link'] as bool? ?? false,
        showDetailedBreakdown: r['show_detailed_breakdown'] as bool? ?? true,
        showPaymentTerms: r['show_payment_terms'] as bool? ?? true,
        showLateFeeClause: r['show_late_fee_clause'] as bool? ?? false,
        showDescription: r['show_description'] as bool? ?? true,
        footerText: r['footer_text'] as String?,
        isBuiltIn: r['is_built_in'] as bool? ?? true,
        lineItemDisplayMode: r['line_item_display_mode'] as String? ?? 'full',
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  @override
  Stream<List<InvoiceTemplate>> watchAll() =>
      Stream.fromFuture(getAll());

  @override
  Future<List<InvoiceTemplate>> getAll() async {
    final rows = await _client
        .from('invoice_templates')
        .select()
        .order('name');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<InvoiceTemplate?> getById(String id) async {
    final row = await _client
        .from('invoice_templates')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row != null ? _fromRow(row) : null;
  }

  @override
  Future<InvoiceTemplate?> getByKey(String key) async {
    final row = await _client
        .from('invoice_templates')
        .select()
        .eq('template_key', key)
        .maybeSingle();
    return row != null ? _fromRow(row) : null;
  }

  @override
  Future<InvoiceTemplate?> getDefault() async {
    final row = await _client
        .from('invoice_templates')
        .select()
        .eq('is_default', true)
        .maybeSingle();
    return row != null ? _fromRow(row) : null;
  }

  @override
  Future<bool> updateTemplate(
      String id, InvoiceTemplatesCompanion companion) async {
    final map = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (companion.name.present) map['name'] = companion.name.value;
    if (companion.templateKey.present) map['template_key'] = companion.templateKey.value;
    if (companion.description.present) map['description'] = companion.description.value;
    if (companion.isDefault.present) map['is_default'] = companion.isDefault.value;
    if (companion.primaryColor.present) map['primary_color'] = companion.primaryColor.value;
    if (companion.accentColor.present) map['accent_color'] = companion.accentColor.value;
    if (companion.fontFamily.present) map['font_family'] = companion.fontFamily.value;
    if (companion.showLogo.present) map['show_logo'] = companion.showLogo.value;
    if (companion.showPaymentInfo.present) map['show_payment_info'] = companion.showPaymentInfo.value;
    if (companion.showTaxBreakdown.present) map['show_tax_breakdown'] = companion.showTaxBreakdown.value;
    if (companion.showTaxId.present) map['show_tax_id'] = companion.showTaxId.value;
    if (companion.showBusinessLicense.present) map['show_business_license'] = companion.showBusinessLicense.value;
    if (companion.showBankDetails.present) map['show_bank_details'] = companion.showBankDetails.value;
    if (companion.showStripeLink.present) map['show_stripe_link'] = companion.showStripeLink.value;
    if (companion.showDetailedBreakdown.present) map['show_detailed_breakdown'] = companion.showDetailedBreakdown.value;
    if (companion.showPaymentTerms.present) map['show_payment_terms'] = companion.showPaymentTerms.value;
    if (companion.showLateFeeClause.present) map['show_late_fee_clause'] = companion.showLateFeeClause.value;
    if (companion.showDescription.present) map['show_description'] = companion.showDescription.value;
    if (companion.footerText.present) map['footer_text'] = companion.footerText.value;
    if (companion.isBuiltIn.present) map['is_built_in'] = companion.isBuiltIn.value;
    if (companion.lineItemDisplayMode.present) map['line_item_display_mode'] = companion.lineItemDisplayMode.value;
    final result = await _client
        .from('invoice_templates')
        .update(map)
        .eq('id', id)
        .select();
    return result.isNotEmpty;
  }

  @override
  Future<String> insertTemplate(InvoiceTemplatesCompanion companion) async {
    const uuid = Uuid();
    final id = uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('invoice_templates').insert({
      'id': id,
      'user_id': _uid,
      'name': companion.name.value,
      'template_key': companion.templateKey.value,
      if (companion.description.present) 'description': companion.description.value,
      'is_default': companion.isDefault.present ? companion.isDefault.value : false,
      'primary_color': companion.primaryColor.present ? companion.primaryColor.value : 0xFF2196F3,
      'accent_color': companion.accentColor.present ? companion.accentColor.value : 0xFF1565C0,
      'font_family': companion.fontFamily.present ? companion.fontFamily.value : 'Helvetica',
      'show_logo': companion.showLogo.present ? companion.showLogo.value : true,
      'show_payment_info': companion.showPaymentInfo.present ? companion.showPaymentInfo.value : true,
      'show_tax_breakdown': companion.showTaxBreakdown.present ? companion.showTaxBreakdown.value : true,
      'show_tax_id': companion.showTaxId.present ? companion.showTaxId.value : true,
      'show_business_license': companion.showBusinessLicense.present ? companion.showBusinessLicense.value : false,
      'show_bank_details': companion.showBankDetails.present ? companion.showBankDetails.value : true,
      'show_stripe_link': companion.showStripeLink.present ? companion.showStripeLink.value : false,
      'show_detailed_breakdown': companion.showDetailedBreakdown.present ? companion.showDetailedBreakdown.value : true,
      'show_payment_terms': companion.showPaymentTerms.present ? companion.showPaymentTerms.value : true,
      'show_late_fee_clause': companion.showLateFeeClause.present ? companion.showLateFeeClause.value : false,
      'show_description': companion.showDescription.present ? companion.showDescription.value : true,
      if (companion.footerText.present) 'footer_text': companion.footerText.value,
      'is_built_in': companion.isBuiltIn.present ? companion.isBuiltIn.value : false,
      'line_item_display_mode': companion.lineItemDisplayMode.present ? companion.lineItemDisplayMode.value : 'full',
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  @override
  Future<void> deleteTemplate(String id) async {
    await _client.from('invoice_templates').delete().eq('id', id);
  }

  @override
  Future<void> setDefault(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('invoice_templates').update({
      'is_default': false,
      'updated_at': now,
    }).neq('id', id);
    await _client.from('invoice_templates').update({
      'is_default': true,
      'updated_at': now,
    }).eq('id', id);
  }
}
