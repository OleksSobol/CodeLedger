import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../providers/client_providers.dart';

class ClientListTile extends ConsumerWidget {
  final Client client;

  const ClientListTile({super.key, required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(clientSummaryProvider(client.id));

    return Card(
      child: ListTile(
        title: Text(client.name),
        subtitle: summaryAsync.when(
          loading: () => const Text('Loading...'),
          error: (_, _) => null,
          data: (summary) {
            final parts = <String>[];
            if (summary.uninvoicedHours > 0) {
              parts.add(
                  '${summary.uninvoicedHours.toStringAsFixed(1)}h uninvoiced');
            }
            if (summary.totalBilled > 0) {
              parts.add(
                  '${formatCurrency(summary.totalBilled, currency: client.currency)} billed');
            }
            if (parts.isEmpty) return const Text('No activity yet');
            return Text(parts.join(' · '));
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/clients/${client.id}'),
      ),
    );
  }
}
