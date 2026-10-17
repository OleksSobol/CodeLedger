import 'package:code_ledger/core/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTimeRange quarterRange(int year, int quarter) {
  final startMonth = (quarter - 1) * 3 + 1;
  final start = DateTime(year, startMonth, 1);
  final end = quarter == 4
      ? DateTime(year + 1, 1, 1)
      : DateTime(year, startMonth + 3, 1);
  return DateTimeRange(start: start, end: end);
}

double computeExciseGross(List<Invoice> invoices, int year, int quarter) {
  final range = quarterRange(year, quarter);
  double total = 0;
  for (final inv in invoices) {
    if (inv.status != 'paid' && inv.status != 'archived') continue;
    final reportDate = inv.paidDate ?? inv.issueDate;
    if (reportDate.isBefore(range.start)) continue;
    if (!reportDate.isBefore(range.end)) continue;
    total += inv.subtotal;
  }
  return total;
}

void main() {
  group('DEV-100 Taxes Dates and Amounts Tests', () {
    test('quarterRange correctly handles all 4 quarters without year-overflow bugs', () {
      final q1 = quarterRange(2026, 1);
      expect(q1.start, equals(DateTime(2026, 1, 1)));
      expect(q1.end, equals(DateTime(2026, 4, 1)));

      final q2 = quarterRange(2026, 2);
      expect(q2.start, equals(DateTime(2026, 4, 1)));
      expect(q2.end, equals(DateTime(2026, 7, 1)));

      final q3 = quarterRange(2026, 3);
      expect(q3.start, equals(DateTime(2026, 7, 1)));
      expect(q3.end, equals(DateTime(2026, 10, 1)));

      final q4 = quarterRange(2026, 4);
      expect(q4.start, equals(DateTime(2026, 10, 1)));
      expect(q4.end, equals(DateTime(2027, 1, 1)));

      // Ensure December 31 23:59:59 is inside Q4
      final dec31 = DateTime(2026, 12, 31, 23, 59, 59);
      expect(dec31.isBefore(q4.end), isTrue);
      expect(!dec31.isBefore(q4.start), isTrue);
    });

    test('WA excise gross revenue uses cash-basis paidDate and excludes sales tax from gross', () {
      // Invoice issued in March (Q1) but paid in April (Q2)
      final invIssuedQ1PaidQ2 = Invoice(
        id: 'inv-1',
        invoiceNumber: 'INV-001',
        clientId: 'c1',
        status: 'paid',
        issueDate: DateTime(2026, 3, 20),
        dueDate: DateTime(2026, 4, 20),
        paidDate: DateTime(2026, 4, 5),
        subtotal: 5000.0,
        taxRate: 10.3,
        taxLabel: 'Sales Tax',
        taxAmount: 515.0,
        lateFeeAmount: 0.0,
        total: 5515.0,
        amountPaid: 5515.0,
        currency: 'USD',
        templateType: 'standard',
        createdAt: DateTime(2026, 3, 20),
        updatedAt: DateTime(2026, 4, 5),
      );

      // Invoice issued and paid in Q1
      final invQ1 = Invoice(
        id: 'inv-2',
        invoiceNumber: 'INV-002',
        clientId: 'c1',
        status: 'paid',
        issueDate: DateTime(2026, 2, 10),
        dueDate: DateTime(2026, 3, 10),
        paidDate: DateTime(2026, 2, 15),
        subtotal: 3000.0,
        taxRate: 10.3,
        taxLabel: 'Sales Tax',
        taxAmount: 309.0,
        lateFeeAmount: 0.0,
        total: 3309.0,
        amountPaid: 3309.0,
        currency: 'USD',
        templateType: 'standard',
        createdAt: DateTime(2026, 2, 10),
        updatedAt: DateTime(2026, 2, 15),
      );

      final invoices = [invIssuedQ1PaidQ2, invQ1];

      // Q1 should ONLY include invQ1 ($3,000 subtotal, not $3,309 total, and NOT the April payment)
      final q1Gross = computeExciseGross(invoices, 2026, 1);
      expect(q1Gross, equals(3000.0));

      // Q2 should include invIssuedQ1PaidQ2 ($5,000 subtotal) because it was paid in April
      final q2Gross = computeExciseGross(invoices, 2026, 2);
      expect(q2Gross, equals(5000.0));
    });

    test('Calendar Q2 includes June invoices whereas IRS Period 2 stops at May 31', () {
      final juneInvoice = Invoice(
        id: 'inv-june',
        invoiceNumber: 'INV-JUNE',
        clientId: 'c1',
        status: 'paid',
        issueDate: DateTime(2026, 6, 15),
        dueDate: DateTime(2026, 7, 15),
        paidDate: DateTime(2026, 6, 20),
        subtotal: 4500.0,
        taxRate: 10.3,
        taxLabel: 'Sales Tax',
        taxAmount: 463.50,
        lateFeeAmount: 0.0,
        total: 4963.50,
        amountPaid: 4963.50,
        currency: 'USD',
        templateType: 'standard',
        createdAt: DateTime(2026, 6, 15),
        updatedAt: DateTime(2026, 6, 20),
      );

      final q2Calendar = quarterRange(2026, 2);
      final irsPeriod2End = DateTime(2026, 6, 1);

      // June invoice is within Calendar Q2 (Apr 1 - Jul 1)
      expect(juneInvoice.paidDate!.isBefore(q2Calendar.end), isTrue);
      expect(!juneInvoice.paidDate!.isBefore(q2Calendar.start), isTrue);

      // June invoice is NOT within IRS Period 2 (Apr 1 - May 31)
      expect(juneInvoice.paidDate!.isBefore(irsPeriod2End), isFalse);
    });
  });
}
