import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:code_ledger/core/database/app_database.dart';
import 'package:code_ledger/core/providers/database_provider.dart';
import 'package:code_ledger/core/providers/theme_provider.dart';
import 'package:code_ledger/features/invoices/domain/entities/tax_bank_split.dart';
import 'package:code_ledger/features/invoices/presentation/providers/invoice_providers.dart';

AppDatabase _openTestDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('TaxBankSplit (DEV-78)', () {
    test('calculates exact bank deposit split from DEV-78 prompt example', () {
      // DEV-78 user example:
      // Subtotal: 1609.33, sales tax 8.3% -> 133.57.
      // Federal tax 20% -> 321.87
      final split = TaxBankSplit.calculate(
        subtotal: 1609.33,
        taxAmount: 133.57,
        taxRate: 8.3,
        taxLabel: 'Sales Tax',
        federalTaxRate: 20.0,
      );

      expect(split.subtotal, closeTo(1609.33, 0.01));
      expect(split.salesTaxAmount, closeTo(133.57, 0.01));
      expect(split.taxRate, equals(8.3));
      expect(split.taxLabel, equals('Sales Tax'));

      // Federal tax: 1609.33 * 0.20 = 321.866 -> ~321.87
      expect(split.federalTaxRate, equals(20.0));
      expect(split.federalTaxAmount, closeTo(321.87, 0.01));

      // Total tax to move to separate tax bank accounts: 133.57 + 321.87 = 455.44
      expect(split.totalTaxReserve, closeTo(455.44, 0.01));

      // Total invoice amount: 1609.33 + 133.57 = 1742.90
      expect(split.total, closeTo(1742.90, 0.01));

      // Take-home operating funds: 1742.90 - 455.44 = 1287.46
      expect(split.takeHomeAmount, closeTo(1287.46, 0.01));
    });

    test('handles zero sales tax invoices correctly', () {
      final split = TaxBankSplit.calculate(
        subtotal: 2000.0,
        taxAmount: 0.0,
        taxRate: 0.0,
        federalTaxRate: 20.0,
      );

      expect(split.salesTaxAmount, equals(0.0));
      expect(split.federalTaxAmount, closeTo(400.0, 0.01));
      expect(split.totalTaxReserve, closeTo(400.0, 0.01));
      expect(split.takeHomeAmount, closeTo(1600.0, 0.01));
      expect(split.total, equals(2000.0));
    });

    test('recalculates accurately when federal rate changes', () {
      final split15 = TaxBankSplit.calculate(
        subtotal: 1000.0,
        taxAmount: 80.0,
        taxRate: 8.0,
        federalTaxRate: 15.0,
      );
      expect(split15.federalTaxAmount, closeTo(150.0, 0.01));
      expect(split15.totalTaxReserve, closeTo(230.0, 0.01));
      expect(split15.takeHomeAmount, closeTo(850.0, 0.01));

      final split30 = TaxBankSplit.calculate(
        subtotal: 1000.0,
        taxAmount: 80.0,
        taxRate: 8.0,
        federalTaxRate: 30.0,
      );
      expect(split30.federalTaxAmount, closeTo(300.0, 0.01));
      expect(split30.totalTaxReserve, closeTo(380.0, 0.01));
      expect(split30.takeHomeAmount, closeTo(700.0, 0.01));
    });

    test('proportionately allocates split for partial payments', () {
      // Full invoice total: 1000 subtotal + 100 tax = 1100 total
      // Customer makes partial payment of 550 (50%)
      final split = TaxBankSplit.calculate(
        subtotal: 1000.0,
        taxAmount: 100.0,
        taxRate: 10.0,
        federalTaxRate: 20.0,
        paymentAmount: 550.0,
      );

      expect(split.total, equals(550.0));
      expect(split.subtotal, closeTo(500.0, 0.01));
      expect(split.salesTaxAmount, closeTo(50.0, 0.01));
      expect(split.federalTaxAmount, closeTo(100.0, 0.01));
      expect(split.totalTaxReserve, closeTo(150.0, 0.01));
      expect(split.takeHomeAmount, closeTo(400.0, 0.01));
    });

    test('includes late fee in take-home operating revenue', () {
      final split = TaxBankSplit.calculate(
        subtotal: 1000.0,
        taxAmount: 100.0,
        taxRate: 10.0,
        lateFeeAmount: 50.0,
        federalTaxRate: 20.0,
      );

      expect(split.total, equals(1150.0));
      expect(split.salesTaxAmount, equals(100.0));
      expect(split.federalTaxAmount, equals(200.0));
      expect(split.totalTaxReserve, equals(300.0));
      // Take-home: 1150 - 300 = 850
      expect(split.takeHomeAmount, equals(850.0));
    });

    test('generates detailed clipboard summary for banking notes', () {
      final split = TaxBankSplit.calculate(
        subtotal: 1609.33,
        taxAmount: 133.57,
        taxRate: 8.3,
        taxLabel: 'WA Sales Tax',
        federalTaxRate: 20.0,
      );

      final summary = split.toClipboardSummary(invoiceNumber: 'INV-0042');

      expect(summary, contains('Bank Transfer Split for Invoice INV-0042:'));
      expect(summary, contains('Total Received: \$1,742.90'));
      expect(summary, contains('→ WA Sales Tax Account (8.3%): \$133.57'));
      expect(summary, contains('→ Federal Tax Account (20.0%): \$321.87'));
      expect(summary, contains('Total Tax Reserve to Move: \$455.44'));
      expect(summary, contains('→ Operating / Take-Home Account: \$1,287.46'));
    });
  });

  group('Invoice Bank Split Providers (DEV-78)', () {
    test('invoiceBankSplitProvider uses reactive federal tax rate', () {
      final db = _openTestDb();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      final testInvoice = Invoice(
        id: 'test-inv-1',
        invoiceNumber: 'INV-101',
        clientId: 'client-1',
        issueDate: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 10, 31),
        status: 'sent',
        subtotal: 2000.0,
        taxRate: 10.0,
        taxAmount: 200.0,
        lateFeeAmount: 0.0,
        total: 2200.0,
        amountPaid: 0.0,
        currency: 'USD',
        taxLabel: 'Sales Tax',
        templateType: 'minimal',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      );

      // Default federal rate is 20.0%
      final initialSplit = container.read(invoiceBankSplitProvider(testInvoice));
      expect(initialSplit.federalTaxRate, equals(20.0));
      expect(initialSplit.federalTaxAmount, equals(400.0));
      expect(initialSplit.totalTaxReserve, equals(600.0));
      expect(initialSplit.takeHomeAmount, equals(1600.0));

      // Update federal rate to 25.0%
      container.read(bankSplitFederalTaxRateProvider.notifier).setRate(25.0);

      final updatedSplit = container.read(invoiceBankSplitProvider(testInvoice));
      expect(updatedSplit.federalTaxRate, equals(25.0));
      expect(updatedSplit.federalTaxAmount, equals(500.0));
      expect(updatedSplit.totalTaxReserve, equals(700.0));
      expect(updatedSplit.takeHomeAmount, equals(1500.0));
    });
  });
}
