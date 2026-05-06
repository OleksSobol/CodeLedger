import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/time_entry_providers.dart';

class TagFilterBar extends ConsumerWidget {
  const TagFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTagsAsync = ref.watch(allTagsProvider);
    final selectedTags = ref.watch(tagFilterProvider);

    final tags = allTagsAsync.value ?? {};
    if (tags.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (selectedTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: const Text('Clear'),
                onPressed: () =>
                    ref.read(tagFilterProvider.notifier).set({}),
              ),
            ),
          ...tags.map((tag) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(tag),
                  selected: selectedTags.contains(tag),
                  onSelected: (selected) {
                    final current =
                        Set<String>.from(ref.read(tagFilterProvider));
                    selected ? current.add(tag) : current.remove(tag);
                    ref.read(tagFilterProvider.notifier).set(current);
                  },
                ),
              )),
        ],
      ),
    );
  }
}
