import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../providers/client_providers.dart';
import '../../../projects/presentation/widgets/project_list_tile.dart';
import '../../../projects/presentation/providers/project_providers.dart';

class ClientDetailPage extends ConsumerWidget {
  final String clientId;

  const ClientDetailPage({super.key, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(clientSummaryProvider(clientId));
    final projectsAsync = ref.watch(projectsForClientProvider(clientId));

    return summaryAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (summary) {
        final client = summary.client;
        return Scaffold(
          appBar: AppBar(
            title: Text(client.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => context.push(
                    '/clients/${client.id}/edit', extra: client),
              ),
              PopupMenuButton(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive Client'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete Client'),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'archive') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Archive Client'),
                        content: Text(
                            'Archive "${client.name}"? They will be hidden from active lists.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Archive'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await ref
                          .read(clientNotifierProvider.notifier)
                          .archiveClient(client.id);
                      if (context.mounted) context.pop();
                    }
                  } else if (value == 'delete') {
                    final notifier =
                        ref.read(clientNotifierProvider.notifier);
                    final hasRecords =
                        await notifier.hasLinkedRecords(client.id);

                    if (!context.mounted) return;

                    if (hasRecords) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Cannot delete: client has time entries or invoices. Archive instead.'),
                        ),
                      );
                      return;
                    }

                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Client'),
                        content: Text(
                            'Permanently delete "${client.name}"? This cannot be undone.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await notifier.deleteClient(client.id);
                      if (context.mounted) context.pop();
                    }
                  }
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () =>
                context.push('/clients/${client.id}/projects/add'),
            tooltip: 'Add Project',
            child: const Icon(Icons.add),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              // Summary cards
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _SummaryCard(
                      label: 'Uninvoiced',
                      value: formatDecimalHours(
                          (summary.uninvoicedHours * 60).round()),
                      subtitle: 'hours',
                      context: context,
                    ),
                    const SizedBox(width: 8),
                    _SummaryCard(
                      label: 'Billed',
                      value: formatCurrency(summary.totalBilled,
                          currency: client.currency),
                      context: context,
                    ),
                    const SizedBox(width: 8),
                    _SummaryCard(
                      label: 'Paid',
                      value: formatCurrency(summary.totalPaid,
                          currency: client.currency),
                      context: context,
                    ),
                  ],
                ),
              ),

              // Contact info
              if (client.contactName != null ||
                  client.email != null ||
                  client.phone != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Contact',
                            style:
                                Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        if (client.contactName != null)
                          Text(client.contactName!),
                        if (client.email != null) Text(client.email!),
                        if (client.phone != null) Text(client.phone!),
                      ],
                    ),
                  ),
                ),

              // Billing info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Billing',
                          style:
                              Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _InfoRow(
                          'Rate',
                          client.hourlyRate != null
                              ? '${formatCurrency(client.hourlyRate!, currency: client.currency)}/hr'
                              : 'Using default'),
                      if (client.taxRate != null)
                        _InfoRow('Tax Rate', '${client.taxRate}%'),
                      if (client.paymentTermsOverride != null)
                        _InfoRow('Terms', client.paymentTermsOverride!),
                    ],
                  ),
                ),
              ),

              // Projects
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Projects',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              projectsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error loading projects: $e'),
                ),
                data: (projects) {
                  if (projects.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 32),
                      child: Center(
                        child: Text('No projects yet. Tap + to add one.'),
                      ),
                    );
                  }
                  return Column(
                    children: projects
                        .map((p) => ProjectListTile(
                            project: p, clientId: clientId))
                        .toList(),
                  );
                },
              ),

              // Notes
              if (client.notes != null && client.notes!.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notes',
                            style:
                                Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text(client.notes!),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final BuildContext context;

  const _SummaryCard({
    required this.label,
    required this.value,
    this.subtitle,
    required this.context,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
