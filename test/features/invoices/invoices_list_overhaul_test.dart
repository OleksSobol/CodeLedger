import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:code_ledger/core/database/app_database.dart';
import 'package:code_ledger/features/invoices/presentation/pages/invoices_list_page.dart';
import 'package:code_ledger/features/invoices/presentation/providers/invoice_providers.dart';
import 'package:code_ledger/features/clients/presentation/providers/client_providers.dart';

Invoice _makeInvoice({
  required String id,
  required String invoiceNumber,
  required String clientId,
  required String status,
  required DateTime issueDate,
  required DateTime dueDate,
  required double total,
  double amountPaid = 0.0,
  DateTime? paidDate,
}) {
  return Invoice(
    id: id,
    invoiceNumber: invoiceNumber,
    clientId: clientId,
    status: status,
    issueDate: issueDate,
    dueDate: dueDate,
    paidDate: paidDate,
    subtotal: total * 0.9,
    taxRate: 10.0,
    taxLabel: 'Sales Tax',
    taxAmount: total * 0.1,
    lateFeeAmount: 0.0,
    total: total,
    amountPaid: amountPaid,
    currency: 'USD',
    templateType: 'standard',
    createdAt: issueDate,
    updatedAt: issueDate,
  );
}

void main() {
  group('DEV-79 Invoice Overhaul Unit Tests', () {
    test('InvoiceMetricsSummary.fromInvoices accurately calculates summary metrics', () {
      final now = DateTime.now();
      final invoices = [
        // Draft
        _makeInvoice(
          id: '1',
          invoiceNumber: 'INV-001',
          clientId: 'c1',
          status: 'draft',
          issueDate: now,
          dueDate: now.add(const Duration(days: 30)),
          total: 1000.0,
        ),
        // Sent (not overdue)
        _makeInvoice(
          id: '2',
          invoiceNumber: 'INV-002',
          clientId: 'c1',
          status: 'sent',
          issueDate: now,
          dueDate: now.add(const Duration(days: 15)),
          total: 2500.0,
        ),
        // Sent (overdue by 5 days)
        _makeInvoice(
          id: '3',
          invoiceNumber: 'INV-003',
          clientId: 'c2',
          status: 'sent',
          issueDate: now.subtract(const Duration(days: 35)),
          dueDate: now.subtract(const Duration(days: 5)),
          total: 1500.0,
        ),
        // Paid
        _makeInvoice(
          id: '4',
          invoiceNumber: 'INV-004',
          clientId: 'c2',
          status: 'paid',
          issueDate: now.subtract(const Duration(days: 40)),
          dueDate: now.subtract(const Duration(days: 10)),
          paidDate: now.subtract(const Duration(days: 12)),
          total: 3000.0,
          amountPaid: 3000.0,
        ),
        // Archived (should be excluded from metrics)
        _makeInvoice(
          id: '5',
          invoiceNumber: 'INV-005',
          clientId: 'c1',
          status: 'archived',
          issueDate: now.subtract(const Duration(days: 60)),
          dueDate: now.subtract(const Duration(days: 30)),
          total: 500.0,
        ),
      ];

      final summary = InvoiceMetricsSummary.fromInvoices(invoices);

      // Draft count
      expect(summary.draftCount, equals(1));

      // Outstanding = 2500 (inv-2) + 1500 (inv-3) = 4000
      expect(summary.totalOutstanding, equals(4000.0));
      expect(summary.outstandingCount, equals(2));

      // Overdue = 1500 (inv-3)
      expect(summary.totalOverdue, equals(1500.0));
      expect(summary.overdueCount, equals(1));

      // Paid = 3000 (inv-4)
      expect(summary.totalPaid, equals(3000.0));
      expect(summary.paidCount, equals(1));
    });

    testWidgets('Invoice search and sort logic filters and sorts properly', (tester) async {
      final now = DateTime.now();
      final clients = [
        Client(
          id: 'c1',
          name: 'Acme Corporation',
          currency: 'USD',
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        ),
        Client(
          id: 'c2',
          name: 'Beta Global',
          currency: 'USD',
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final invoices = [
        _makeInvoice(
          id: '1',
          invoiceNumber: 'INV-100',
          clientId: 'c1',
          status: 'draft',
          issueDate: DateTime(2026, 1, 1),
          dueDate: DateTime(2026, 1, 31),
          total: 2000.0,
        ),
        _makeInvoice(
          id: '2',
          invoiceNumber: 'INV-200',
          clientId: 'c2',
          status: 'sent',
          issueDate: DateTime(2026, 2, 1),
          dueDate: DateTime(2026, 2, 28),
          total: 5000.0,
        ),
        _makeInvoice(
          id: '3',
          invoiceNumber: 'INV-300',
          clientId: 'c1',
          status: 'paid',
          issueDate: DateTime(2026, 3, 1),
          dueDate: DateTime(2026, 3, 31),
          total: 1000.0,
        ),
      ];

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allInvoicesProvider.overrideWith((ref) => Stream.value(invoices)),
            allClientsProvider.overrideWith((ref) => Stream.value(clients)),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              ref.watch(filteredInvoicesProvider);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all non-archived are returned initially
      final initial = capturedRef.read(filteredInvoicesProvider).value!;
      expect(initial.length, equals(3));

      // Search by invoice number
      capturedRef.read(invoiceSearchQueryProvider.notifier).set('200');
      await tester.pump();
      final searchByNum = capturedRef.read(filteredInvoicesProvider).value!;
      expect(searchByNum.length, equals(1));
      expect(searchByNum.first.invoiceNumber, equals('INV-200'));

      // Search by client name
      capturedRef.read(invoiceSearchQueryProvider.notifier).set('Beta');
      await tester.pump();
      final searchByClient = capturedRef.read(filteredInvoicesProvider).value!;
      expect(searchByClient.length, equals(1));
      expect(searchByClient.first.invoiceNumber, equals('INV-200'));

      // Clear search and test status filter
      capturedRef.read(invoiceSearchQueryProvider.notifier).clear();
      capturedRef.read(invoiceStatusFilterProvider.notifier).set('draft');
      await tester.pump();
      final draftOnly = capturedRef.read(filteredInvoicesProvider).value!;
      expect(draftOnly.length, equals(1));
      expect(draftOnly.first.status, equals('draft'));

      // Test sort by amount high to low
      capturedRef.read(invoiceStatusFilterProvider.notifier).set(null);
      capturedRef.read(invoiceSortOrderProvider.notifier).set(InvoiceSortOrder.amountHigh);
      await tester.pump();
      final sortedByAmount = capturedRef.read(filteredInvoicesProvider).value!;
      expect(sortedByAmount.map((i) => i.total).toList(), equals([5000.0, 2000.0, 1000.0]));
    });
  });

  group('DEV-79 InvoicesListPage Widget Tests', () {
    testWidgets('renders financial metrics header, search bar, filter chips with counts, and cards', (tester) async {
      final now = DateTime.now();
      final clients = [
        Client(
          id: 'c1',
          name: 'Starlight Tech',
          currency: 'USD',
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final invoices = [
        _makeInvoice(
          id: '1',
          invoiceNumber: 'INV-042',
          clientId: 'c1',
          status: 'sent',
          issueDate: now,
          dueDate: now.add(const Duration(days: 14)),
          total: 1200.0,
        ),
        _makeInvoice(
          id: '2',
          invoiceNumber: 'INV-043',
          clientId: 'c1',
          status: 'paid',
          issueDate: now.subtract(const Duration(days: 20)),
          dueDate: now.subtract(const Duration(days: 5)),
          paidDate: now.subtract(const Duration(days: 6)),
          total: 800.0,
          amountPaid: 800.0,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allInvoicesProvider.overrideWith((ref) => Stream.value(invoices)),
            allClientsProvider.overrideWith((ref) => Stream.value(clients)),
            clientByIdProvider('c1').overrideWith((ref) => Future.value(clients.first)),
          ],
          child: const MaterialApp(
            home: InvoicesListPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check AppBar
      expect(find.text('Invoices'), findsOneWidget);

      // Check Metrics Header Cards
      expect(find.text('Outstanding'), findsOneWidget);
      expect(find.text('\$1,200.00'), findsNWidgets(2));
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Paid'), findsWidgets);

      // Check Search TextField
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search invoices or clients...'), findsOneWidget);

      // Check Filter Chips with Counts
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Sent (1)'), findsOneWidget);
      expect(find.text('Paid (1)'), findsOneWidget);

      // Check Invoices rendered in cards
      expect(find.text('INV-042'), findsOneWidget);
      expect(find.text('INV-043'), findsOneWidget);
      expect(find.text('Starlight Tech'), findsWidgets);

      // Check quick action buttons
      expect(find.text('Record Payment'), findsOneWidget);
      expect(find.text('View PDF'), findsOneWidget);
    });

    testWidgets('shows empty search state when query matches nothing', (tester) async {
      final now = DateTime.now();
      final clients = [
        Client(
          id: 'c1',
          name: 'Acme Corp',
          currency: 'USD',
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final invoices = [
        _makeInvoice(
          id: '1',
          invoiceNumber: 'INV-100',
          clientId: 'c1',
          status: 'draft',
          issueDate: now,
          dueDate: now.add(const Duration(days: 30)),
          total: 1000.0,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allInvoicesProvider.overrideWith((ref) => Stream.value(invoices)),
            allClientsProvider.overrideWith((ref) => Stream.value(clients)),
            clientByIdProvider('c1').overrideWith((ref) => Future.value(clients.first)),
          ],
          child: const MaterialApp(
            home: InvoicesListPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search query that doesn't match
      await tester.enterText(find.byType(TextField), 'NonexistentClientXYZ');
      await tester.pumpAndSettle();

      expect(find.text('No invoices matching "NonexistentClientXYZ"'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);

      // Tap Clear Search button
      await tester.tap(find.text('Clear Search'));
      await tester.pumpAndSettle();

      // Invoice reappears
      expect(find.text('INV-100'), findsOneWidget);
    });
  });
}
