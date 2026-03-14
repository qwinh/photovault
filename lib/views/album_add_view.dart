// lib/views/album_add_view.dart
// Create a new album. If navigated from ImagesSelectedView, the selected
// images pool is pre-filled. Commits create the album and clear the pool.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/album_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/tag_provider.dart';
import '../services/notification_service.dart';
import '../widgets/widgets.dart';

class AlbumAddView extends StatefulWidget {
  const AlbumAddView({super.key});

  @override
  State<AlbumAddView> createState() => _AlbumAddViewState();
}

class _AlbumAddViewState extends State<AlbumAddView> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isFavorite = false;
  List<int> _tagIds = [];

  // Images that will go into the new album (taken from selection pool)
  List<AssetEntity> _previewEntities = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Mirror the current selection pool as preview
      final sp = context.read<SelectionProvider>();
      setState(() => _previewEntities = List.of(sp.entities));
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Album name is required.')));
      return;
    }

    setState(() => _submitting = true);

    final ap = context.read<AlbumProvider>();
    final sp = context.read<SelectionProvider>();

    final assetIds = _previewEntities.map((e) => e.id).toList();

    await ap.addAlbum(
      AlbumModel(
          name: name,
          description: _descCtrl.text.trim(),
          isFavorite: _isFavorite),
      tagIds: _tagIds,
      assetIds: assetIds,
    );

    // Clear the global selection pool after committing
    await sp.clearAll();

    await NotificationService.instance.show('Album created', '"$name" created.');

    if (mounted) {
      context.pop();
    }
  }

  Future<void> _pickTagsDialog() async {
    final tp = context.read<TagProvider>();
    final result = await showDialog<List<int>>(
      context: context,
      builder: (_) => TagPickerDialog(
        allTags: tp.tags.map((t) => (id: t.id!, name: t.name)).toList(),
        initialSelected: _tagIds.toSet(),
      ),
    );
    if (result != null) setState(() => _tagIds = result);
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<TagProvider>();
    final tagNames = _tagIds
        .map((id) => tp.getById(id)?.name)
        .whereType<String>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Album'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: const Text('Create'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Form fields ──────────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Album name *',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mark as favorite'),
            value: _isFavorite,
            onChanged: (v) => setState(() => _isFavorite = v),
          ),

          // ── Tags ─────────────────────────────────────────────────────────
          Row(
            children: [
              const Text('Tags:',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Expanded(
                child: tagNames.isEmpty
                    ? const Text('None',
                        style: TextStyle(color: Colors.grey))
                    : Wrap(
                        spacing: 4,
                        children:
                            tagNames.map((n) => Chip(label: Text(n))).toList(),
                      ),
              ),
              TextButton.icon(
                onPressed: _pickTagsDialog,
                icon: const Icon(Icons.label_outline),
                label: const Text('Edit'),
              ),
            ],
          ),

          const Divider(height: 32),

          // ── Image preview grid ───────────────────────────────────────────
          Row(
            children: [
              Text(
                'Images (${_previewEntities.length})',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  // Navigate to images view; user selects more there.
                  // The selection pool persists so they come back with
                  // updated pool.
                  context.push('/images');
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add more'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_previewEntities.isEmpty)
            Container(
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('No images selected',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _previewEntities.length,
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 100,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (_, i) {
                final e = _previewEntities[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AssetThumb(
                      asset: e,
                      onTap: () => setState(
                          () => _previewEntities.removeAt(i)),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _previewEntities.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
