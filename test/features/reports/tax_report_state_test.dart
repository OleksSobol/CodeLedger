import 'package:flutter_test/flutter_test.dart';
import 'package:code_ledger/core/database/app_database.dart';
import 'package:code_ledger/features/reports/data/models/tax_report_data.dart';

void main() {
  group('TaxReportData State Apportionment', () {
    final now = DateTime(2026, 7, 1);
    final profile = UserProfile(
      id: 'profile-1',
      businessName: 'My Dev Business',
      ownerName: 'Dev',
      stateProvince: 'WA',
      showTaxId: true,
      showWaLicense: false,
      bankAccountType: 'checking',
      showBankDetails: true,
      showStripeLink: false,
      defaultCurrency: 'USD',
      defaultHourlyRate: 100.0,
      defaultTaxRate: 6.5,
      defaultTaxLabel: 'WA Sales Tax',
      defaultPaymentTerms: 'net30',
      defaultPaymentTermsDays: 30,
      defaultEmailSubjectFormat: 'Invoice #{number}',
      invoiceNumberPrefix: 'INV-',
      nextInvoiceNumber: 1,
      createdAt: now,
      updatedAt: now,
    );

    Invoice makeInvoice({
      required String id,
      required String clientId,
      required double subtotal,
      required double taxRate,
      required double taxAmount,
    }) {
      return Invoice(
        id: id,
        clientId: clientId,
        invoiceNumber: id,
        issueDate: DateTime(2026, 7, 1),
        dueDate: DateTime(2026, 7, 31),
        status: 'paid',
        subtotal: subtotal,
        taxRate: taxRate,
        taxLabel: 'Tax',
        taxAmount: taxAmount,
        lateFeeAmount: 0.0,
        total: subtotal + taxAmount,
        amountPaid: subtotal + taxAmount,
        currency: 'USD',
        templateType: 'standard',
        createdAt: now,
        updatedAt: now,
      );
    }

    test('calculates inState and outOfState subtotals based on client states', () {
      final rows = [
        TaxReportRow(
          invoice: makeInvoice(
            id: 'INV-001',
            clientId: 'client-wa',
            subtotal: 13028.00,
            taxRate: 6.5,
            taxAmount: 846.82,
          ),
          clientName: 'Local WA Client',
          clientState: 'WA',
        ),
        TaxReportRow(
          invoice: makeInvoice(
            id: 'INV-002',
            clientId: 'client-ca',
            subtotal: 283.50,
            taxRate: 0.0,
            taxAmount: 0.0,
          ),
          clientName: 'Out of State Client',
          clientState: 'CA',
        ),
      ];

      final data = TaxReportData(
        profile: profile,
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 9, 30),
        rows: rows,
      );

      expect(data.businessState, 'WA');
      expect(data.totalSubtotal, 13311.50);
      expect(data.inStateSubtotal, 13028.00);
      expect(data.outOfStateSubtotal, 283.50);
      expect(data.hasOutOfState, isTrue);
    });

    test('hasOutOfState is false when all clients are in-state', () {
      final rows = [
        TaxReportRow(
          invoice: makeInvoice(
            id: 'INV-001',
            clientId: 'client-wa',
            subtotal: 5000.00,
            taxRate: 6.5,
            taxAmount: 325.00,
          ),
          clientName: 'Local WA Client',
          clientState: 'WA',
        ),
      ];

      final data = TaxReportData(
        profile: profile,
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 9, 30),
        rows: rows,
      );

      expect(data.inStateSubtotal, 5000.00);
      expect(data.outOfStateSubtotal, 0.0);
      expect(data.hasOutOfState, isFalse);
    });
  });
}
