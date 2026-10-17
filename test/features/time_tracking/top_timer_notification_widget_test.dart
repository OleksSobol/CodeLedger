import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:code_ledger/core/database/app_database.dart';
import 'package:code_ledger/core/providers/database_provider.dart';
import 'package:code_ledger/core/providers/repository_providers.dart';
import 'package:code_ledger/core/providers/theme_provider.dart';
import 'package:code_ledger/features/clients/presentation/providers/client_providers.dart';
import 'package:code_ledger/features/time_tracking/presentation/providers/time_entry_providers.dart';
import 'package:code_ledger/features/time_tracking/presentation/widgets/top_timer_notification_widget.dart';

AppDatabase _openTestDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('TopTimerNotificationWidget (DEV-75)', () {
    testWidgets('renders SizedBox.shrink when no running timer', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runningEntriesProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TopTimerNotificationWidget(),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(InkWell), findsNothing);
      expect(find.byIcon(Icons.stop), findsNothing);
    });

    testWidgets('renders timer, client name, and clock-out button when timer is on', (tester) async {
      final now = DateTime.now();
      final startTime = now.subtract(const Duration(minutes: 25, seconds: 12));

      final testEntry = TimeEntry(
        id: 'running-1',
        clientId: 'client-123',
        startTime: startTime,
        hourlyRateSnapshot: 100.0,
        description: 'Building notifications widget',
        isManual: false,
        isInvoiced: false,
        createdAt: startTime,
        updatedAt: startTime,
      );

      final testClient = Client(
        id: 'client-123',
        name: 'Acme Studios',
        currency: 'USD',
        isArchived: false,
        createdAt: startTime,
        updatedAt: startTime,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runningEntriesProvider.overrideWith((ref) => Stream.value([testEntry])),
            clientByIdProvider('client-123').overrideWith((ref) => Future.value(testClient)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TopTimerNotificationWidget(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Should show client and description
      expect(find.textContaining('Acme Studios'), findsOneWidget);
      expect(find.textContaining('Building notifications widget'), findsOneWidget);

      // Should show clock-out button
      expect(find.byIcon(Icons.stop), findsOneWidget);
    });
  });
}
