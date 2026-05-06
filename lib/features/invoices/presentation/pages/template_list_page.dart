import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/spacing.dart';
import '../providers/template_providers.dart';

class TemplateListPage extends ConsumerWidget {
  const TemplateListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(allTemplatesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Template',
            onPressed: () => _createNew(context, ref),
          ),
        ],
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (templates) {
          if (templates.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.palette_outlined,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: Spacing.md),
                  Text('No templates',
                      style: theme.textTheme.titleMedium),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(Spacing.md),
            itemCount: templates.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: Spacing.sm),
            itemBuilder: (context, index) {
              final t = templates[index];
              return _TemplateCard(template: t);
            },
          );
        },
      ),
    );
  }

  Future<void> _createNew(BuildContext context, WidgetRef ref) async {
    final templates = ref.read(allTemplatesProvider).value ?? [];
    final source = templates.firstWhere(
      (t) => t.isDefault,
      orElse: () => templates.first,
    );

    final id = await ref
        .read(templateNotifierProvider.notifier)
        .duplicateTemplate(source, 'Custom Template');

    if (context.mounted) {
      final dao = ref.read(invoiceTemplateDaoProvider);
      final newTemplate = await dao.getById(id);
      if (newTemplate != null && context.mounted) {
        context.pushNamed('templateDesigner', extra: newTemplate);
      }
    }
  }
}

class _TemplateCard extends ConsumerWidget {
  final InvoiceTemplate template;

  const _TemplateCard({required this.template});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.pushNamed('templateDesigner', extra: template),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              // Color swatches
              Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(template.primaryColor),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Color(template.accentColor),
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(6)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: Spacing.md),

              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          template.name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (template.isDefault) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.star,
                              size: 16,
                              color: theme.colorScheme.primary),
                        ],
                        if (!template.isBuiltIn) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Custom',
                              style:
                                  theme.textTheme.labelSmall?.copyWith(
                                color: theme
                                    .colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (template.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        template.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Chevron
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
