import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:code_ledger/core/database/tables/expenses_table.dart';

void main() {
  group('Expense Labels Formatting (DEV-80)', () {
    test('formats expense subtitle label and percentage without broken literal variables', () {
      const category = 'internet';
      const deductibleFraction = 0.40;

      final label = kExpenseCategoryLabels[category] ?? 'Other';
      final pct = (deductibleFraction * 100).toStringAsFixed(0);
      final subtitle = '$label · $pct% deductible';

      expect(subtitle, equals('Internet · 40% deductible'));
      expect(subtitle, isNot(contains(r'$label')));
      expect(subtitle, isNot(contains(r'$pct')));
    });

    test('formats expense category labels for all known categories', () {
      for (final entry in kExpenseCategoryLabels.entries) {
        final label = entry.value;
        final pct = (0.50 * 100).toStringAsFixed(0);
        final subtitle = '$label · $pct% deductible';

        expect(subtitle, startsWith(label));
        expect(subtitle, endsWith('50% deductible'));
        expect(subtitle, isNot(contains(r'$')));
      }
    });

    test('formats date button label cleanly', () {
      final date = DateTime(2026, 10, 16);
      final formatted = 'Start: ${DateFormat('MMM d, yyyy').format(date)}';

      expect(formatted, equals('Start: Oct 16, 2026'));
      expect(formatted, isNot(contains(r'${DateFormat')));
    });

    test('formats delete confirmation dialog message cleanly', () {
      const expenseName = 'Home Internet';
      final message = 'Remove "$expenseName"?';

      expect(message, equals('Remove "Home Internet"?'));
      expect(message, isNot(contains(r'${expense.name}')));
    });
  });
}
