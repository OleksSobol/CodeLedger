import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/time_entry_providers.dart';
import '../../../clients/presentation/providers/client_providers.dart';

class CompanyFilterBar extends ConsumerWidget {
  const CompanyFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(activeClientsProvider);
    final selectedIds = ref.watch(clientIdFilterProvider);

    final clients = clientsAsync.value ?? [];
    if (clients.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: const Text('All'),
                onPressed: () =>
                    ref.read(clientIdFilterProvider.notifier).set({}),
              ),
            ),
          ...clients.map((client) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(client.name),
                  selected: selectedIds.contains(client.id),
                  onSelected: (selected) {
                    final current =
                        Set<String>.from(ref.read(clientIdFilterProvider));
                    selected
                        ? current.add(client.id)
                        : current.remove(client.id);
                    ref.read(clientIdFilterProvider.notifier).set(current);
                  },
                ),
              )),
        ],
      ),
    );
  }
}
