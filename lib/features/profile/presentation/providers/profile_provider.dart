import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/user_profile_repository.dart';

final profileProvider = StreamProvider<UserProfile>((ref) {
  return ref.watch(userProfileRepositoryProvider).watchProfile();
});

final profileNotifierProvider =
    AsyncNotifierProvider<ProfileNotifier, UserProfile>(ProfileNotifier.new);

class ProfileNotifier extends AsyncNotifier<UserProfile> {
  late UserProfileRepository _dao;

  @override
  Future<UserProfile> build() async {
    _dao = ref.watch(userProfileRepositoryProvider);
    return _dao.getProfile();
  }

  Future<bool> updateProfile(UserProfilesCompanion companion) async {
    final result = await _dao.updateProfile(companion);
    if (result) {
      state = AsyncData(await _dao.getProfile());
    }
    return result;
  }

  Future<bool> updateBusinessInfo({
    required String businessName,
    required String ownerName,
    String? email,
    String? phone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? stateProvince,
    String? postalCode,
    String? country,
  }) {
    return updateProfile(UserProfilesCompanion(
      businessName: Value(businessName),
      ownerName: Value(ownerName),
      email: Value(email),
      phone: Value(phone),
      addressLine1: Value(addressLine1),
      addressLine2: Value(addressLine2),
      city: Value(city),
      stateProvince: Value(stateProvince),
      postalCode: Value(postalCode),
      country: Value(country),
    ));
  }

  Future<bool> updateTaxInfo({
    String? taxId,
    required bool showTaxId,
    String? waBusinessLicense,
    required bool showWaLicense,
  }) {
    return updateProfile(UserProfilesCompanion(
      taxId: Value(taxId),
      showTaxId: Value(showTaxId),
      waBusinessLicense: Value(waBusinessLicense),
      showWaLicense: Value(showWaLicense),
    ));
  }

  Future<bool> updateBankDetails({
    String? bankName,
    String? bankAccountName,
    String? bankAccountNumber,
    String? bankRoutingNumber,
    required String bankAccountType,
    String? bankSwift,
    String? bankIban,
    required bool showBankDetails,
  }) {
    return updateProfile(UserProfilesCompanion(
      bankName: Value(bankName),
      bankAccountName: Value(bankAccountName),
      bankAccountNumber: Value(bankAccountNumber),
      bankRoutingNumber: Value(bankRoutingNumber),
      bankAccountType: Value(bankAccountType),
      bankSwift: Value(bankSwift),
      bankIban: Value(bankIban),
      showBankDetails: Value(showBankDetails),
    ));
  }

  Future<bool> updatePaymentLinks({
    String? stripePaymentLink,
    required bool showStripeLink,
    String? paymentInstructions,
  }) {
    return updateProfile(UserProfilesCompanion(
      stripePaymentLink: Value(stripePaymentLink),
      showStripeLink: Value(showStripeLink),
      paymentInstructions: Value(paymentInstructions),
    ));
  }

  Future<bool> updateDefaults({
    required String defaultCurrency,
    required double defaultHourlyRate,
    required String defaultTaxLabel,
    required double defaultTaxRate,
    required String defaultPaymentTerms,
    required int defaultPaymentTermsDays,
    double? lateFeePercentage,
  }) {
    return updateProfile(UserProfilesCompanion(
      defaultCurrency: Value(defaultCurrency),
      defaultHourlyRate: Value(defaultHourlyRate),
      defaultTaxLabel: Value(defaultTaxLabel),
      defaultTaxRate: Value(defaultTaxRate),
      defaultPaymentTerms: Value(defaultPaymentTerms),
      defaultPaymentTermsDays: Value(defaultPaymentTermsDays),
      lateFeePercentage: Value(lateFeePercentage),
    ));
  }

  Future<bool> updateInvoiceSettings({
    required String invoiceNumberPrefix,
    required String defaultEmailSubjectFormat,
    String? defaultTemplateId,
    int? nextInvoiceNumber,
  }) {
    return updateProfile(UserProfilesCompanion(
      invoiceNumberPrefix: Value(invoiceNumberPrefix),
      defaultEmailSubjectFormat: Value(defaultEmailSubjectFormat),
      defaultTemplateId: Value(defaultTemplateId),
      nextInvoiceNumber: nextInvoiceNumber != null
          ? Value(nextInvoiceNumber)
          : const Value.absent(),
    ));
  }
}
