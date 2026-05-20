import 'package:drift/drift.dart';
import 'invoice_templates_table.dart';

class UserProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get businessName => text().withDefault(const Constant(''))();
  TextColumn get ownerName => text().withDefault(const Constant(''))();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get addressLine1 => text().nullable()();
  TextColumn get addressLine2 => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get stateProvince => text().nullable()();
  TextColumn get postalCode => text().nullable()();
  TextColumn get country => text().nullable()();

  // Tax & License
  TextColumn get taxId => text().nullable()();
  BoolColumn get showTaxId => boolean().withDefault(const Constant(true))();
  TextColumn get waBusinessLicense => text().nullable()();
  BoolColumn get showWaLicense =>
      boolean().withDefault(const Constant(false))();

  // Logo
  TextColumn get logoPath => text().nullable()();

  // Bank / ACH
  TextColumn get bankName => text().nullable()();
  TextColumn get bankAccountName => text().nullable()();
  TextColumn get bankAccountNumber => text().nullable()();
  TextColumn get bankRoutingNumber => text().nullable()();
  TextColumn get bankAccountType =>
      text().withDefault(const Constant('checking'))();
  TextColumn get bankSwift => text().nullable()();
  TextColumn get bankIban => text().nullable()();
  BoolColumn get showBankDetails =>
      boolean().withDefault(const Constant(true))();

  // Stripe
  TextColumn get stripePaymentLink => text().nullable()();
  BoolColumn get showStripeLink =>
      boolean().withDefault(const Constant(false))();

  // Other payment
  TextColumn get paymentInstructions => text().nullable()();

  // Defaults
  TextColumn get defaultCurrency =>
      text().withDefault(const Constant('USD'))();
  RealColumn get defaultHourlyRate =>
      real().withDefault(const Constant(0.0))();
  TextColumn get defaultTaxLabel =>
      text().withDefault(const Constant('Tax'))();
  RealColumn get defaultTaxRate => real().withDefault(const Constant(0.0))();
  TextColumn get defaultPaymentTerms =>
      text().withDefault(const Constant('net_30'))();
  IntColumn get defaultPaymentTermsDays =>
      integer().withDefault(const Constant(30))();
  RealColumn get lateFeePercentage => real().nullable()();
  TextColumn get defaultTemplateId =>
      text().nullable().references(InvoiceTemplates, #id)();
  TextColumn get defaultEmailSubjectFormat => text()
      .withDefault(const Constant('Invoice #{number} - {period}'))();

  // Invoice numbering
  IntColumn get nextInvoiceNumber =>
      integer().withDefault(const Constant(1))();
  TextColumn get invoiceNumberPrefix =>
      text().withDefault(const Constant('INV-'))();

  // Timestamps
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
