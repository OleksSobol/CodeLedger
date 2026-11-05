import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;

import 'package:code_ledger/core/database/app_database.dart';
import 'package:code_ledger/core/database/daos/expense_transaction_dao.dart';
import 'package:code_ledger/core/database/tables/expense_categories_table.dart';
import 'package:code_ledger/core/repositories/drift/drift_expense_transaction_repository.dart';

AppDatabase _openTestDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('Quick-Capture Deductible Basis Calculation (DEV-101)', () {
    test('calculates 100% business use deductible basis accurately', () {
      const amount = 149.99;
      const pct = 100;
      final deductible = double.parse(
        (amount * (pct / 100.0)).toStringAsFixed(2),
      );

      expect(deductible, equals(149.99));
    });

    test('calculates 80% business use deductible basis accurately', () {
      const amount = 200.00;
      const pct = 80;
      final deductible = double.parse(
        (amount * (pct / 100.0)).toStringAsFixed(2),
      );

      expect(deductible, equals(160.00));
    });

    test('calculates 50% business use deductible basis with proper rounding', () {
      const amount = 89.99;
      const pct = 50;
      final deductible = double.parse(
        (amount * (pct / 100.0)).toStringAsFixed(2),
      );

      expect(deductible, equals(44.99));
    });

    test('clamps percentage to 0-100%', () {
      const amount = 100.00;
      final pctOver = 120.clamp(0, 100);
      final pctUnder = (-10).clamp(0, 100);

      expect(pctOver, equals(100));
      expect(pctUnder, equals(0));

      final dedOver = double.parse(
        (amount * (pctOver / 100.0)).toStringAsFixed(2),
      );
      final dedUnder = double.parse(
        (amount * (pctUnder / 100.0)).toStringAsFixed(2),
      );

      expect(dedOver, equals(100.00));
      expect(dedUnder, equals(0.00));
    });
  });

  group('Schedule C Default Categories (DEV-101)', () {
    test('contains all IRS Schedule C mapped seed categories', () {
      final names = kDefaultExpenseCategories.map((c) => c.name).toList();
      final lines =
          kDefaultExpenseCategories.map((c) => c.irsScheduleCLine).toList();

      expect(names, contains('Office Expenses'));
      expect(names, contains('Supplies & Materials'));
      expect(names, contains('Hardware & Tech (< \$2,500)'));
      expect(names, contains('Software & Hosting'));
      expect(names, contains('Travel & Transport'));

      expect(lines.any((l) => l.contains('Line 18')), isTrue);
      expect(lines.any((l) => l.contains('Line 22')), isTrue);
      expect(lines.any((l) => l.contains('Line 27a')), isTrue);
      expect(lines.any((l) => l.contains('Line 24a')), isTrue);
    });
  });

  group('DriftExpenseTransactionRepository (DEV-101)', () {
    late AppDatabase db;
    late DriftExpenseTransactionRepository repo;

    setUp(() async {
      db = _openTestDb();
      repo = DriftExpenseTransactionRepository(ExpenseTransactionDao(db));
    });

    tearDown(() => db.close());

    test('seeds Schedule C categories on database creation', () async {
      final categories = await repo.getAllCategories();
      expect(categories, isNotEmpty);
      expect(categories.length, equals(kDefaultExpenseCategories.length));

      final office = categories.firstWhere((c) => c.name == 'Office Expenses');
      expect(office.irsScheduleCLine, contains('Line 18'));
    });

    test('inserts, joins with category, and deletes an expense transaction', () async {
      final categories = await repo.getAllCategories();
      final category = categories.first;

      const txId = 'test-tx-1';
      final now = DateTime(2026, 11, 5);

      await repo.insertTransaction(
        ExpenseTransactionsCompanion.insert(
          id: txId,
          title: 'Keychron Q1 Pro',
          vendor: const Value('Keychron'),
          amount: 199.99,
          date: now,
          categoryId: category.id,
          businessUsePct: const Value(80),
          deductibleAmount: const Value(159.99),
          receiptPath: const Value('/path/to/receipt.jpg'),
        ),
      );

      final all = await repo.getAllWithCategory();
      expect(all.length, equals(1));
      expect(all.first.transaction.title, equals('Keychron Q1 Pro'));
      expect(all.first.transaction.vendor, equals('Keychron'));
      expect(all.first.transaction.amount, equals(199.99));
      expect(all.first.category.name, equals(category.name));
      expect(all.first.deductibleAmount, equals(159.99));

      // Test watch stream
      final streamed = await repo.watchAllWithCategory().first;
      expect(streamed.length, equals(1));

      // Test delete
      final deletedCount = await repo.deleteTransaction(txId);
      expect(deletedCount, equals(1));

      final afterDelete = await repo.getAllWithCategory();
      expect(afterDelete, isEmpty);
    });
  });
}

