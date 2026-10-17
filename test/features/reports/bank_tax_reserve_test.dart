import 'package:code_ledger/core/database/app_database.dart';
import 'package:code_ledger/features/clients/presentation/providers/client_providers.dart';
import 'package:code_ledger/features/expenses/presentation/providers/expense_providers.dart';
import 'package:code_ledger/features/invoices/presentation/providers/invoice_providers.dart';
import 'package:code_ledger/features/reports/domain/models/bank_tax_reserve_summary.dart';
import 'package:code_ledger/features/reports/presentation/pages/taxes_page.dart';
import 'package:code_ledger/features/reports/presentation/providers/tax_reserve_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BankTaxReserveSummary Domain Tests (DEV-71)', () {
    test('computes realistic numbers for all invoices and money taken out vs bank reserve', () {
      final summary = BankTaxReserveSummary(
        year: 2026,
        totalInvoicesCount: 2,
        totalGrossCollected: 11030.0, // $10,000 subtotal + $1,030 sales tax
        totalSubtotal: 10000.0,
        totalSalesTax: 1030.0,
        totalBoTax: 47.10, // 10,000 * 0.00471
        totalStateTax: 1077.10,
        totalReceiptDeductions: 500.0,
        totalRecurringDeductions: 500.0,
        netTaxableIncome: 9000.0,
        seTax: 1271.74, // 9000 * 0.9235 * 0.153
        federalIncomeTax: 1840.11, // (9000 - 1271.74/2) * 0.22
        totalFederalTax: 3111.85,
        totalBankReserve: 4188.95, // 1077.10 + 3111.85
        totalTakeHomeWithdrawn: 6841.05, // 11030.0 - 4188.95
        federalRate: 0.22,
        seRate: 0.153,
        boRate: 0.00471,
        quarters: const [],
      );

      // Verify reconciliation: money in bank + money taken out = all invoices collected
      expect(
        (summary.totalTakeHomeWithdrawn + summary.totalBankReserve).toStringAsFixed(2),
        equals(summary.totalGrossCollected.toStringAsFixed(2)),
      );

      final clip = summary.toClipboardSummary();
      expect(clip, contains('Money Supposed to be in Bank (Tax Reserve): \$4,188.95'));
      expect(clip, contains('Total Collected: \$11,030.00 (2 paid invoices)'));
      expect(clip, contains('Amount Taken Out (Operating): \$6,841.05'));
      expect(clip, contains('What Stays in Bank (Taxes): \$4,188.95'));
      expect(clip, contains('Washington State Tax: \$1,077.10'));
      expect(clip, contains('Federal (IRS): \$3,111.85'));
    });

    test('BankTaxReserveSummary.calculate partitions invoices into quarters and computes accurate taxes', () {
      final q1Date = DateTime(2026, 2, 10);
      final q2Date = DateTime(2026, 5, 20);

      final inv1 = Invoice(
        id: 'inv-1',
        invoiceNumber: 'INV-001',
        clientId: 'client-1',
        issueDate: q1Date,
        dueDate: q1Date.add(const Duration(days: 30)),
        paidDate: q1Date,
        subtotal: 5000.0,
        taxRate: 10.3,
        taxLabel: 'Sales Tax',
        taxAmount: 515.0,
        lateFeeAmount: 0.0,
        total: 5515.0,
        amountPaid: 5515.0,
        currency: 'USD',
        templateType: 'standard',
        status: 'paid',
        createdAt: q1Date,
        updatedAt: q1Date,
      );

      final inv2 = Invoice(
        id: 'inv-2',
        invoiceNumber: 'INV-002',
        clientId: 'client-1',
        issueDate: q2Date,
        dueDate: q2Date.add(const Duration(days: 30)),
        paidDate: q2Date,
        subtotal: 6000.0,
        taxRate: 10.3,
        taxLabel: 'Sales Tax',
        taxAmount: 618.0,
        lateFeeAmount: 0.0,
        total: 6618.0,
        amountPaid: 6618.0,
        currency: 'USD',
        templateType: 'standard',
        status: 'paid',
        createdAt: q2Date,
        updatedAt: q2Date,
      );

      // Unpaid invoice should be excluded
      final invUnpaid = Invoice(
        id: 'inv-3',
        invoiceNumber: 'INV-003',
        clientId: 'client-1',
        issueDate: q2Date,
        dueDate: q2Date.add(const Duration(days: 30)),
        paidDate: null,
        subtotal: 3000.0,
        taxRate: 10.3,
        taxLabel: 'Sales Tax',
        taxAmount: 309.0,
        lateFeeAmount: 0.0,
        total: 3309.0,
        amountPaid: 0.0,
        currency: 'USD',
        templateType: 'standard',
        status: 'sent',
        createdAt: q2Date,
        updatedAt: q2Date,
      );

      final summary = BankTaxReserveSummary.calculate(
        year: 2026,
        invoices: [inv1, inv2, invUnpaid],
        federalRate: 0.20,
        seRate: 0.153,
        boRate: 0.00471,
        monthlyRecurringDeductible: 100.0,
        totalDeductibleReceipts: 0.0,
      );

      expect(summary.year, equals(2026));
      expect(summary.totalInvoicesCount, equals(2));
      // Total collected: $5515 + $6618 = $12,133
      expect(summary.totalGrossCollected, equals(12133.0));
      // Subtotal: 5000 + 6000 = 11,000
      expect(summary.totalSubtotal, equals(11000.0));
      // Sales tax: 515 + 618 = 1133
      expect(summary.totalSalesTax, equals(1133.0));
      // B&O: 11000 * 0.00471 = 51.81
      expect(summary.totalBoTax, closeTo(51.81, 0.01));

      // Net taxable: 11000 - 1200 recurring = 9800
      expect(summary.netTaxableIncome, equals(9800.0));

      // Reconciles perfectly
      expect(
        summary.totalTakeHomeWithdrawn + summary.totalBankReserve,
        closeTo(summary.totalGrossCollected, 0.001),
      );

      // Verify quarter breakdown
      expect(summary.quarters.length, equals(4));
      final q1 = summary.quarters[0];
      final q2 = summary.quarters[1];
      final q3 = summary.quarters[2];
      final q4 = summary.quarters[3];

      expect(q1.invoicesCount, equals(1));
      expect(q1.grossCollected, equals(5515.0));

      expect(q2.invoicesCount, equals(1));
      expect(q2.grossCollected, equals(6618.0));

      expect(q3.invoicesCount, equals(0));
      expect(q3.grossCollected, equals(0.0));

      expect(q4.invoicesCount, equals(0));
      expect(q4.grossCollected, equals(0.0));
    });
  });

  group('TaxesPage Bank Reserve Tab Widget Tests (DEV-71)', () {
    testWidgets('renders Bank Reserve tab, hero card, and realistic withdrawals reconciliation', (tester) async {
      final now = DateTime.now();
      final testSummary = BankTaxReserveSummary(
        year: now.year,
        totalInvoicesCount: 3,
        totalGrossCollected: 15000.0,
        totalSubtotal: 13500.0,
        totalSalesTax: 1500.0,
        totalBoTax: 63.59,
        totalStateTax: 1563.59,
        totalReceiptDeductions: 0.0,
        totalRecurringDeductions: 0.0,
        netTaxableIncome: 13500.0,
        seTax: 1907.61,
        federalIncomeTax: 2759.72,
        totalFederalTax: 4667.33,
        totalBankReserve: 6230.92,
        totalTakeHomeWithdrawn: 8769.08,
        federalRate: 0.22,
        seRate: 0.153,
        boRate: 0.00471,
        quarters: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bankTaxReserveSummaryProvider(now.year).overrideWith((ref) => Future.value(testSummary)),
            allInvoicesProvider.overrideWith((ref) => Stream.value([])),
            activeClientsProvider.overrideWith((ref) => Stream.value(<Client>[])),
            totalMonthlyDeductibleProvider.overrideWith((ref) => 0.0),
          ],
          child: const MaterialApp(
            home: TaxesPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Bank Reserve'), findsOneWidget);
      expect(find.text('Money Supposed to be in Bank'), findsOneWidget);
      expect(find.text('Realistic Invoices & Withdrawals'), findsOneWidget);
      expect(find.byIcon(Icons.copy_all), findsWidgets);
    });
  });
}
