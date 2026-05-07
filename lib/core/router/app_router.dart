import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'shell_scaffold.dart';
import '../database/app_database.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/clients/presentation/pages/clients_list_page.dart';
import '../../features/clients/presentation/pages/client_detail_page.dart';
import '../../features/clients/presentation/pages/client_form_page.dart';
import '../../features/projects/presentation/pages/project_form_page.dart';
import '../../features/time_tracking/presentation/pages/time_tracking_page.dart';
import '../../features/time_tracking/presentation/pages/clock_in_page.dart';
import '../../features/time_tracking/presentation/pages/manual_entry_page.dart';
import '../../features/time_tracking/presentation/pages/edit_time_entry_page.dart';
import '../../features/invoices/presentation/pages/invoices_list_page.dart';
import '../../features/invoices/presentation/pages/invoice_detail_page.dart';
import '../../features/invoices/presentation/pages/invoice_wizard_page.dart';
import '../../features/invoices/presentation/pages/manual_invoice_page.dart';
import '../../features/invoices/presentation/pages/edit_draft_invoice_page.dart';
import '../../features/invoices/presentation/pages/add_time_to_invoice_page.dart';
import '../../features/invoices/presentation/pages/send_invoices_page.dart';
import '../../features/reports/presentation/pages/reports_page.dart';
import '../../features/backup/presentation/pages/backup_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/invoices/presentation/pages/template_list_page.dart';
import '../../features/invoices/presentation/pages/template_designer_page.dart';
import '../../features/time_tracking/presentation/pages/time_entry_layout_page.dart';
import '../../features/settings/presentation/pages/accounts_settings_page.dart';
import '../../features/reports/presentation/pages/wa_excise_report_page.dart';
import '../../features/github/presentation/pages/github_sync_preview_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _timeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'time');
final _invoicesNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'invoices');
final _settingsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'settings');

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          ShellScaffold(navigationShell: navigationShell),
      branches: [
        // Branch 0: Home / Dashboard
        StatefulShellBranch(
          navigatorKey: _homeNavigatorKey,
          routes: [
            GoRoute(
              path: '/',
              name: 'dashboard',
              builder: (context, state) => const DashboardPage(),
            ),
          ],
        ),

        // Branch 1: Time Tracking (list only — clock-in/manual/edit push full-screen)
        StatefulShellBranch(
          navigatorKey: _timeNavigatorKey,
          routes: [
            GoRoute(
              path: '/time-tracking',
              name: 'timeTracking',
              builder: (context, state) => const TimeTrackingPage(),
            ),
          ],
        ),

        // Branch 2: Invoices (list only — wizard & detail push full-screen)
        StatefulShellBranch(
          navigatorKey: _invoicesNavigatorKey,
          routes: [
            GoRoute(
              path: '/invoices',
              name: 'invoices',
              builder: (context, state) => const InvoicesListPage(),
            ),
          ],
        ),

        // Branch 3: Settings
        StatefulShellBranch(
          navigatorKey: _settingsNavigatorKey,
          routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),

    // Full-screen routes (pushed on root navigator, no bottom nav)

    // Time tracking sub-pages
    GoRoute(
      path: '/time-tracking/clock-in',
      name: 'clockIn',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ClockInPage(),
    ),
    GoRoute(
      path: '/time-tracking/manual',
      name: 'manualEntry',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ManualEntryPage(),
    ),
    GoRoute(
      path: '/time-tracking/edit',
      name: 'editTimeEntry',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final entry = state.extra as TimeEntry;
        return EditTimeEntryPage(entry: entry);
      },
    ),

    // Manual invoice entry
    GoRoute(
      path: '/invoices/manual',
      name: 'invoiceManual',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ManualInvoicePage(),
    ),

    // Dedicated send-invoices routine (drafts ready to email)
    GoRoute(
      path: '/invoices/send',
      name: 'invoiceSend',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SendInvoicesPage(),
    ),

    // Edit draft invoice
    GoRoute(
      path: '/invoices/:invoiceId/edit',
      name: 'invoiceEditDraft',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final invoice = state.extra as Invoice;
        return EditDraftInvoicePage(invoice: invoice);
      },
    ),

    // Append more time entries to a draft invoice
    GoRoute(
      path: '/invoices/:invoiceId/add-time',
      name: 'invoiceAddTime',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final invoice = state.extra as Invoice;
        return AddTimeToInvoicePage(invoice: invoice);
      },
    ),

    // Invoice wizard (single page with internal PageView steps)
    GoRoute(
      path: '/invoices/create',
      name: 'invoiceCreate',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const InvoiceWizardPage(),
    ),
    GoRoute(
      path: '/invoices/:invoiceId',
      name: 'invoiceDetail',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final invoiceId =
            int.parse(state.pathParameters['invoiceId']!);
        return InvoiceDetailPage(invoiceId: invoiceId);
      },
    ),

    GoRoute(
      path: '/profile',
      name: 'profile',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ProfilePage(),
    ),
    GoRoute(
      path: '/clients',
      name: 'clients',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ClientsListPage(),
      routes: [
        GoRoute(
          path: 'add',
          name: 'clientAdd',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) => const ClientFormPage(),
        ),
        GoRoute(
          path: ':clientId',
          name: 'clientDetail',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) {
            final clientId =
                int.parse(state.pathParameters['clientId']!);
            return ClientDetailPage(clientId: clientId);
          },
          routes: [
            GoRoute(
              path: 'edit',
              name: 'clientEdit',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) {
                final client = state.extra as dynamic;
                return ClientFormPage(client: client);
              },
            ),
            GoRoute(
              path: 'projects/add',
              name: 'projectAdd',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) {
                final clientId =
                    int.parse(state.pathParameters['clientId']!);
                return ProjectFormPage(clientId: clientId);
              },
            ),
            GoRoute(
              path: 'projects/:projectId/edit',
              name: 'projectEdit',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) {
                final clientId =
                    int.parse(state.pathParameters['clientId']!);
                final project = state.extra as dynamic;
                return ProjectFormPage(
                    clientId: clientId, project: project);
              },
            ),
          ],
        ),
      ],
    ),
    // Invoice template designer
    GoRoute(
      path: '/settings/accounts',
      name: 'accounts',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AccountsSettingsPage(),
    ),
    GoRoute(
      path: '/settings/entry-layout',
      name: 'entryLayout',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const TimeEntryLayoutPage(),
    ),
    GoRoute(
      path: '/settings/templates',
      name: 'templateList',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const TemplateListPage(),
    ),
    GoRoute(
      path: '/settings/templates/edit',
      name: 'templateDesigner',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final template = state.extra as InvoiceTemplate;
        return TemplateDesignerPage(template: template);
      },
    ),

    GoRoute(
      path: '/reports',
      name: 'reports',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ReportsPage(),
    ),
    GoRoute(
      path: '/reports/wa-excise',
      name: 'waExcise',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const WaExciseReportPage(),
    ),
    GoRoute(
      path: '/backup',
      name: 'backup',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BackupPage(),
    ),
    GoRoute(
      path: '/github-sync',
      name: 'githubSync',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, DateTime>;
        return GitHubSyncPreviewPage(
          start: extra['start']!,
          end: extra['end']!,
        );
      },
    ),
  ],
);
