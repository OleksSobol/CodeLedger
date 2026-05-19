import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../time_tracking/presentation/providers/time_entry_providers.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/active_timer_card.dart';
import '../widgets/context_header.dart';
import '../widgets/financial_summary_row.dart';
import '../widgets/quick_actions_row.dart';
import '../widgets/recent_activity_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final isWide = MediaQuery.sizeOf(context).width >= 600;

    Widget body = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(runningEntryProvider);
        ref.invalidate(recentEntriesProvider);
        ref.invalidate(monthlyIncomeProvider);
        ref.invalidate(outstandingInvoicesProvider);
        ref.invalidate(overdueInvoicesProvider);
        ref.invalidate(uninvoicedByClientProvider);
        ref.invalidate(weeklyHoursProvider);
        await Future.delayed(const Duration(milliseconds: 300));
      },
      child: CustomScrollView(
          slivers: [
            // 1. Context Header (SliverAppBar with greeting)
            const ContextHeader(),

            // 2. Hero Timer
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    Spacing.md, Spacing.md, Spacing.md, 0),
                child: ActiveTimerCard(),
              ),
            ),

            // 3. Quick Actions
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    Spacing.md, Spacing.md, Spacing.md, 0),
                child: QuickActionsRow(),
              ),
            ),

            // 4. Financial Tiles — section header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.md, Spacing.lg, Spacing.md, Spacing.sm),
                child: Text(
                  'Overview',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: FinancialSummaryRow()),

            // 5. Activity Timeline — section header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.md, Spacing.lg, Spacing.md, Spacing.sm),
                child: Text(
                  'Recent Activity',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const RecentActivitySliver(),

            // Bottom padding for FAB clearance
            const SliverToBoxAdapter(
              child: SizedBox(height: Spacing.xl + 80),
            ),
          ],
        ),
    );

    if (isWide) {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: body,
        ),
      );
    }

    return Scaffold(body: body);
  }
}
