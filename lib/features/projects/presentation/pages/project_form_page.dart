import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../../core/database/app_database.dart';
import '../providers/project_providers.dart';

class ProjectFormPage extends ConsumerStatefulWidget {
  final String clientId;
  final Project? project;

  const ProjectFormPage({
    super.key,
    required this.clientId,
    this.project,
  });

  @override
  ConsumerState<ProjectFormPage> createState() => _ProjectFormPageState();
}

class _ProjectFormPageState extends ConsumerState<ProjectFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _githubRepoCtrl;
  late Color _color;
  late bool _isActive;
  bool _saving = false;

  bool get _isEditing => widget.project != null;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descriptionCtrl = TextEditingController(text: p?.description ?? '');
    _rateCtrl = TextEditingController(
        text: p?.hourlyRateOverride?.toString() ?? '');
    _githubRepoCtrl = TextEditingController(text: p?.githubRepo ?? '');
    _color = Color(p?.color ?? 0xFF2196F3);
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _rateCtrl.dispose();
    _githubRepoCtrl.dispose();
    super.dispose();
  }

  void _pickColor() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: _color,
            onColorChanged: (color) {
              setState(() => _color = color);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final notifier = ref.read(projectNotifierProvider.notifier);
      final rate = double.tryParse(_rateCtrl.text);

      final githubRepo = _githubRepoCtrl.text.trim().isEmpty
          ? null
          : _githubRepoCtrl.text.trim();

      if (_isEditing) {
        await notifier.updateProject(
          widget.project!.id,
          widget.clientId,
          ProjectsCompanion(
            name: Value(_nameCtrl.text.trim()),
            description: Value(_descriptionCtrl.text.trim().isEmpty
                ? null
                : _descriptionCtrl.text.trim()),
            hourlyRateOverride: Value(rate),
            githubRepo: Value(githubRepo),
            color: Value(_color.toARGB32()),
            isActive: Value(_isActive),
          ),
        );
      } else {
        await notifier.addProject(
          clientId: widget.clientId,
          name: _nameCtrl.text.trim(),
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          hourlyRateOverride: rate,
          githubRepo: githubRepo,
          color: _color.toARGB32(),
        );
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archive() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Project'),
        content: Text(
            'Archive "${widget.project!.name}"? It will be hidden from active lists.'),
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
    if (confirm == true && mounted) {
      await ref
          .read(projectNotifierProvider.notifier)
          .archiveProject(widget.project!.id, widget.clientId);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Project' : 'Add Project'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Archive',
              onPressed: _archive,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Project Name *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
              autofocus: !_isEditing,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionCtrl,
              decoration:
                  const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _rateCtrl,
              decoration: const InputDecoration(
                labelText: 'Hourly Rate Override',
                hintText: 'Uses client/default if empty',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _githubRepoCtrl,
              decoration: const InputDecoration(
                labelText: 'GitHub Repo',
                hintText: 'owner/repo or full GitHub URL',
                prefixIcon: Icon(Icons.code),
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Color'),
              trailing: GestureDetector(
                onTap: _pickColor,
                child: CircleAvatar(
                  backgroundColor: _color,
                  radius: 20,
                ),
              ),
            ),
            if (_isEditing)
              SwitchListTile(
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save Changes' : 'Add Project'),
            ),
          ],
        ),
      ),
    );
  }
}
