// lib/views/tags_view.dart
// Shows all tags in a list.
// Inline editing: tap edit icon → text fields appear in the tile.
// Add: FAB expands an inline form at the top.
// Delete: trash icon with confirmation.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/tag_provider.dart';
import '../widgets/widgets.dart';

class TagsView extends StatefulWidget {
  const TagsView({super.key});

  @override
  State<TagsView> createState() => _TagsViewState();
}

class _TagsViewState extends State<TagsView> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Which tag ID is currently being edited inline (-1 = none)
  int? _editingId;
  final _editNameCtrl = TextEditingController();
  final _editDescCtrl = TextEditingController();

  // Whether the inline "add" form is visible
  bool _showAddForm = false;
  final _addNameCtrl = TextEditingController();
  final _addDescCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TagProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _editNameCtrl.dispose();
    _editDescCtrl.dispose();
    _addNameCtrl.dispose();
    _addDescCtrl.dispose();
    super.dispose();
  }

  void _startEdit(TagModel tag) {
    _editNameCtrl.text = tag.name;
    _editDescCtrl.text = tag.description;
    setState(() => _editingId = tag.id);
  }

  Future<void> _saveEdit(TagModel tag) async {
    final name = _editNameCtrl.text.trim();
    if (name.isEmpty) return;
    await context.read<TagProvider>().updateTag(
          tag.copyWith(
              name: name, description: _editDescCtrl.text.trim()),
        );
    setState(() => _editingId = null);
  }

  Future<void> _addTag() async {
    final name = _addNameCtrl.text.trim();
    if (name.isEmpty) return;
    await context.read<TagProvider>().addTag(
          TagModel(name: name, description: _addDescCtrl.text.trim()),
        );
    _addNameCtrl.clear();
    _addDescCtrl.clear();
    setState(() => _showAddForm = false);
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<TagProvider>();
    final tags = tp.tags
        .where((t) =>
            _query.isEmpty ||
            t.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _showAddForm = !_showAddForm),
        child: Icon(_showAddForm ? Icons.close : Icons.add),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: 'Search tags…',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),

          // Inline add form
          if (_showAddForm) _AddTagForm(
            nameCtrl: _addNameCtrl,
            descCtrl: _addDescCtrl,
            onAdd: _addTag,
          ),

          // Tag list
          Expanded(
            child: tags.isEmpty
                ? const Center(child: Text('No tags yet.'))
                : ListView.builder(
                    itemCount: tags.length,
                    itemBuilder: (ctx, i) {
                      final tag = tags[i];
                      final isEditing = _editingId == tag.id;
                      final usage = tp.usageCount(tag.id!);

                      return isEditing
                          ? _EditingTile(
                              nameCtrl: _editNameCtrl,
                              descCtrl: _editDescCtrl,
                              onSave: () => _saveEdit(tag),
                              onCancel: () =>
                                  setState(() => _editingId = null),
                            )
                          : _TagTile(
                              tag: tag,
                              usageCount: usage,
                              onEdit: () => _startEdit(tag),
                              onDelete: () async {
                                final ok = await confirmDialog(
                                  context,
                                  title: 'Delete Tag',
                                  message:
                                      'Delete tag "${tag.name}"?',
                                );
                                if (ok) {
                                  await context
                                      .read<TagProvider>()
                                      .deleteTag(tag.id!);
                                }
                              },
                            );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Read-only tag tile ─────────────────────────────────────────────────────────

class _TagTile extends StatelessWidget {
  final TagModel tag;
  final int usageCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TagTile({
    required this.tag,
    required this.usageCount,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.label_outline),
      title: Text(tag.name),
      subtitle: tag.description.isNotEmpty
          ? Text(tag.description,
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Usage count badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$usageCount',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete),
        ],
      ),
    );
  }
}

// ── Inline editing tile ────────────────────────────────────────────────────────

class _EditingTile extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _EditingTile({
    required this.nameCtrl,
    required this.descCtrl,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Tag name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: onSave, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Inline add form ────────────────────────────────────────────────────────────

class _AddTagForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final VoidCallback onAdd;

  const _AddTagForm({
    required this.nameCtrl,
    required this.descCtrl,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'New tag name *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 6),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Tag'),
            ),
          ],
        ),
      ),
    );
  }
}
