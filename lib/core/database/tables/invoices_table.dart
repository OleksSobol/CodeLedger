import 'package:drift/drift.dart';
import 'clients_table.dart';
import 'invoice_templates_table.dart';

class Invoices extends Table {
  TextColumn get id => text()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get invoiceNumber => text().unique()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get issueDate => dateTime()();
  DateTimeColumn get dueDate => dateTime()();
  DateTimeColumn get periodStart => dateTime().nullable()();
  DateTimeColumn get periodEnd => dateTime().nullable()();
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  RealColumn get taxRate => real().withDefault(const Constant(0.0))();
  TextColumn get taxLabel => text().withDefault(const Constant('Tax'))();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get lateFeeAmount => real().withDefault(const Constant(0.0))();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  RealColumn get amountPaid => real().withDefault(const Constant(0.0))();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get notes => text().nullable()();
  TextColumn get templateId =>
      text().nullable().references(InvoiceTemplates, #id)();
  TextColumn get templateType =>
      text().withDefault(const Constant('detailed'))();
  TextColumn get pdfPath => text().nullable()();
  TextColumn get paymentMethod => text().nullable()();
  DateTimeColumn get paidDate => dateTime().nullable()();
  DateTimeColumn get sentDate => dateTime().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
