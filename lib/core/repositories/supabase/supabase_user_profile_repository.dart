import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../database/app_database.dart';
import '../user_profile_repository.dart';

class SupabaseUserProfileRepository implements UserProfileRepository {
  final SupabaseClient _client;
  SupabaseUserProfileRepository(this._client);

  String get _uid => _client.auth.currentUser!.id;

  UserProfile _fromRow(Map<String, dynamic> r) => UserProfile(
        id: r['id'] as String,
        businessName: r['business_name'] as String? ?? '',
        ownerName: r['owner_name'] as String? ?? '',
        email: r['email'] as String?,
        phone: r['phone'] as String?,
        addressLine1: r['address_line1'] as String?,
        addressLine2: r['address_line2'] as String?,
        city: r['city'] as String?,
        stateProvince: r['state_province'] as String?,
        postalCode: r['postal_code'] as String?,
        country: r['country'] as String?,
        taxId: r['tax_id'] as String?,
        showTaxId: r['show_tax_id'] as bool? ?? true,
        waBusinessLicense: r['wa_business_license'] as String?,
        showWaLicense: r['show_wa_license'] as bool? ?? false,
        logoPath: r['logo_path'] as String?,
        bankName: r['bank_name'] as String?,
        bankAccountName: r['bank_account_name'] as String?,
        bankAccountNumber: r['bank_account_number'] as String?,
        bankRoutingNumber: r['bank_routing_number'] as String?,
        bankAccountType: r['bank_account_type'] as String? ?? 'checking',
        bankSwift: r['bank_swift'] as String?,
        bankIban: r['bank_iban'] as String?,
        showBankDetails: r['show_bank_details'] as bool? ?? true,
        stripePaymentLink: r['stripe_payment_link'] as String?,
        showStripeLink: r['show_stripe_link'] as bool? ?? false,
        paymentInstructions: r['payment_instructions'] as String?,
        defaultCurrency: r['default_currency'] as String? ?? 'USD',
        defaultHourlyRate: (r['default_hourly_rate'] as num?)?.toDouble() ?? 0.0,
        defaultTaxLabel: r['default_tax_label'] as String? ?? 'Tax',
        defaultTaxRate: (r['default_tax_rate'] as num?)?.toDouble() ?? 0.0,
        defaultPaymentTerms: r['default_payment_terms'] as String? ?? 'net_30',
        defaultPaymentTermsDays: r['default_payment_terms_days'] as int? ?? 30,
        lateFeePercentage: (r['late_fee_percentage'] as num?)?.toDouble(),
        defaultTemplateId: r['default_template_id'] as String?,
        defaultEmailSubjectFormat: r['default_email_subject_format'] as String? ?? 'Invoice #{number} - {period}',
        nextInvoiceNumber: r['next_invoice_number'] as int? ?? 1,
        invoiceNumberPrefix: r['invoice_number_prefix'] as String? ?? 'INV-',
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  @override
  Stream<UserProfile> watchProfile() => Stream.fromFuture(getProfile());

  @override
  Future<UserProfile> getProfile() async {
    final rows = await _client
        .from('user_profiles')
        .select()
        .eq('user_id', _uid)
        .limit(1);

    if (rows.isEmpty) {
      const uuid = Uuid();
      final id = uuid.v4();
      final now = DateTime.now().toUtc().toIso8601String();
      await _client.from('user_profiles').insert({
        'id': id,
        'user_id': _uid,
        'business_name': '',
        'owner_name': '',
        'bank_account_type': 'checking',
        'show_tax_id': true,
        'show_wa_license': false,
        'show_bank_details': true,
        'show_stripe_link': false,
        'default_currency': 'USD',
        'default_hourly_rate': 0.0,
        'default_tax_label': 'Tax',
        'default_tax_rate': 0.0,
        'default_payment_terms': 'net_30',
        'default_payment_terms_days': 30,
        'default_email_subject_format': 'Invoice #{number} - {period}',
        'next_invoice_number': 1,
        'invoice_number_prefix': 'INV-',
        'created_at': now,
        'updated_at': now,
      });
      return getProfile();
    }

    return _fromRow(rows.first);
  }

  @override
  Future<bool> updateProfile(UserProfilesCompanion companion) async {
    final map = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (companion.businessName.present) map['business_name'] = companion.businessName.value;
    if (companion.ownerName.present) map['owner_name'] = companion.ownerName.value;
    if (companion.email.present) map['email'] = companion.email.value;
    if (companion.phone.present) map['phone'] = companion.phone.value;
    if (companion.addressLine1.present) map['address_line1'] = companion.addressLine1.value;
    if (companion.addressLine2.present) map['address_line2'] = companion.addressLine2.value;
    if (companion.city.present) map['city'] = companion.city.value;
    if (companion.stateProvince.present) map['state_province'] = companion.stateProvince.value;
    if (companion.postalCode.present) map['postal_code'] = companion.postalCode.value;
    if (companion.country.present) map['country'] = companion.country.value;
    if (companion.taxId.present) map['tax_id'] = companion.taxId.value;
    if (companion.showTaxId.present) map['show_tax_id'] = companion.showTaxId.value;
    if (companion.waBusinessLicense.present) map['wa_business_license'] = companion.waBusinessLicense.value;
    if (companion.showWaLicense.present) map['show_wa_license'] = companion.showWaLicense.value;
    if (companion.logoPath.present) map['logo_path'] = companion.logoPath.value;
    if (companion.bankName.present) map['bank_name'] = companion.bankName.value;
    if (companion.bankAccountName.present) map['bank_account_name'] = companion.bankAccountName.value;
    if (companion.bankAccountNumber.present) map['bank_account_number'] = companion.bankAccountNumber.value;
    if (companion.bankRoutingNumber.present) map['bank_routing_number'] = companion.bankRoutingNumber.value;
    if (companion.bankAccountType.present) map['bank_account_type'] = companion.bankAccountType.value;
    if (companion.bankSwift.present) map['bank_swift'] = companion.bankSwift.value;
    if (companion.bankIban.present) map['bank_iban'] = companion.bankIban.value;
    if (companion.showBankDetails.present) map['show_bank_details'] = companion.showBankDetails.value;
    if (companion.stripePaymentLink.present) map['stripe_payment_link'] = companion.stripePaymentLink.value;
    if (companion.showStripeLink.present) map['show_stripe_link'] = companion.showStripeLink.value;
    if (companion.paymentInstructions.present) map['payment_instructions'] = companion.paymentInstructions.value;
    if (companion.defaultCurrency.present) map['default_currency'] = companion.defaultCurrency.value;
    if (companion.defaultHourlyRate.present) map['default_hourly_rate'] = companion.defaultHourlyRate.value;
    if (companion.defaultTaxLabel.present) map['default_tax_label'] = companion.defaultTaxLabel.value;
    if (companion.defaultTaxRate.present) map['default_tax_rate'] = companion.defaultTaxRate.value;
    if (companion.defaultPaymentTerms.present) map['default_payment_terms'] = companion.defaultPaymentTerms.value;
    if (companion.defaultPaymentTermsDays.present) map['default_payment_terms_days'] = companion.defaultPaymentTermsDays.value;
    if (companion.lateFeePercentage.present) map['late_fee_percentage'] = companion.lateFeePercentage.value;
    if (companion.defaultTemplateId.present) map['default_template_id'] = companion.defaultTemplateId.value;
    if (companion.defaultEmailSubjectFormat.present) map['default_email_subject_format'] = companion.defaultEmailSubjectFormat.value;
    if (companion.nextInvoiceNumber.present) map['next_invoice_number'] = companion.nextInvoiceNumber.value;
    if (companion.invoiceNumberPrefix.present) map['invoice_number_prefix'] = companion.invoiceNumberPrefix.value;
    final result = await _client
        .from('user_profiles')
        .update(map)
        .eq('user_id', _uid)
        .select();
    return result.isNotEmpty;
  }

  @override
  Future<String> getNextInvoiceNumber() async {
    final profile = await getProfile();
    final number = profile.nextInvoiceNumber;
    final formatted =
        '${profile.invoiceNumberPrefix}${number.toString().padLeft(4, '0')}';
    await _client.from('user_profiles').update({
      'next_invoice_number': number + 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', _uid);
    return formatted;
  }
}
