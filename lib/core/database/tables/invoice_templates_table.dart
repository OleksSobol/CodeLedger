import 'package:drift/drift.dart';

class InvoiceTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get templateKey => text().unique()();
  TextColumn get description => text().nullable()();
  BoolColumn get isDefault =>
      boolean().withDefault(const Constant(false))();
  IntColumn get primaryColor =>
      integer().withDefault(const Constant(0xFF2196F3))();
  IntColumn get accentColor =>
      integer().withDefault(const Constant(0xFF1565C0))();
  TextColumn get fontFamily =>
      text().withDefault(const Constant('Helvetica'))();
  BoolColumn get showLogo => boolean().withDefault(const Constant(true))();
  BoolColumn get showPaymentInfo =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showTaxBreakdown =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showTaxId => boolean().withDefault(const Constant(true))();
  BoolColumn get showBusinessLicense =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get showBankDetails =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showStripeLink =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get showDetailedBreakdown =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showPaymentTerms =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showLateFeeClause =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get showDescription =>
      boolean().withDefault(const Constant(true))();
  TextColumn get footerText => text().nullable()();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(true))();
  // 'full' | 'issue_desc' | 'desc_only'
  TextColumn get lineItemDisplayMode =>
      text().withDefault(const Constant('full'))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
