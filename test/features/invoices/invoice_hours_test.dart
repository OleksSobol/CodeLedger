import 'package:flutter_test/flutter_test.dart';
import 'package:code_ledger/core/database/app_database.dart';
import 'package:code_ledger/core/utils/duration_formatter.dart';
import 'package:code_ledger/features/invoices/presentation/providers/invoice_providers.dart';

TimeEntry _createEntry({
  required String id,
  required int? durationMinutes,
  double hourlyRate = 100.0,
}) {
  final now = DateTime.now();
  return TimeEntry(
    id: id,
    clientId: 'client-1',
    startTime: now,
    durationMinutes: durationMinutes,
    hourlyRateSnapshot: hourlyRate,
    isManual: false,
    isInvoiced: false,
    createdAt: now,
    updatedAt: now,
  );
}

InvoiceLineItem _createLineItem({
  required String id,
  required double quantity,
  double unitPrice = 100.0,
}) {
  return InvoiceLineItem(
    id: id,
    invoiceId: 'inv-1',
    sortOrder: 0,
    description: 'Work item',
    quantity: quantity,
    unitPrice: unitPrice,
    total: quantity * unitPrice,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('InvoiceWizardState Total Hours (DEV-77)', () {
    test('totalDurationMinutes returns 0 when no entries selected', () {
      const state = InvoiceWizardState();
      expect(state.totalDurationMinutes, equals(0));
      expect(state.totalHours, equals(0.0));
    });

    test('totalDurationMinutes correctly sums duration of multiple entries', () {
      final entries = [
        _createEntry(id: '1', durationMinutes: 120), // 2h
        _createEntry(id: '2', durationMinutes: 90), // 1h 30m
        _createEntry(id: '3', durationMinutes: 45), // 45m
      ];

      final state = InvoiceWizardState(selectedEntries: entries);

      expect(state.totalDurationMinutes, equals(255));
      expect(state.totalHours, closeTo(4.25, 0.001));
      expect(formatDuration(state.totalDurationMinutes), equals('4h 15m'));
    });

    test('handles entries with null durationMinutes gracefully', () {
      final entries = [
        _createEntry(id: '1', durationMinutes: 60),
        _createEntry(id: '2', durationMinutes: null),
        _createEntry(id: '3', durationMinutes: 30),
      ];

      final state = InvoiceWizardState(selectedEntries: entries);

      expect(state.totalDurationMinutes, equals(90));
      expect(state.totalHours, equals(1.5));
      expect(formatDuration(state.totalDurationMinutes), equals('1h 30m'));
    });

    test('subtotal calculates correctly with duration and manual items', () {
      final entries = [
        _createEntry(id: '1', durationMinutes: 120, hourlyRate: 50.0), // $100
        _createEntry(id: '2', durationMinutes: 60, hourlyRate: 80.0), // $80
      ];
      const manualItems = [
        ManualLineItem(
          description: 'Setup fee',
          quantity: 1,
          unitPrice: 50.0,
        ),
      ];

      final state = InvoiceWizardState(
        selectedEntries: entries,
        manualLineItems: manualItems,
      );

      // (2h * 50) + (1h * 80) + 50 = 230
      expect(state.subtotal, equals(230.0));
      expect(state.totalHours, equals(3.0));
    });
  });

  group('Invoice Detail Total Hours (DEV-77)', () {
    test('sums line item quantities to compute total invoice hours', () {
      final lineItems = [
        _createLineItem(id: 'li-1', quantity: 7.5),
        _createLineItem(id: 'li-2', quantity: 8.0),
        _createLineItem(id: 'li-3', quantity: 4.25),
      ];

      final totalHours = lineItems.fold<double>(
        0.0,
        (sum, item) => sum + item.quantity,
      );

      expect(totalHours, equals(19.75));
      final totalMinutes = (totalHours * 60).round();
      expect(totalMinutes, equals(1185));
      expect(formatDuration(totalMinutes), equals('19h 45m'));
    });
  });
}
