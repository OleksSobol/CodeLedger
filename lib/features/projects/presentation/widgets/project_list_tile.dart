import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/database/app_database.dart';

class ProjectListTile extends StatelessWidget {
  final Project project;
  final String clientId;

  const ProjectListTile({
    super.key,
    required this.project,
    required this.clientId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(project.color),
          radius: 16,
        ),
        title: Text(project.name),
        subtitle: project.description != null
            ? Text(project.description!,
                maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!project.isActive)
              Chip(
                label: const Text('Inactive'),
                labelStyle: Theme.of(context).textTheme.labelSmall,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => context.push(
            '/clients/$clientId/projects/${project.id}/edit',
            extra: project),
      ),
    );
  }
}
