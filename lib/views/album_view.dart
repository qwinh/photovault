// lib/views/album_view.dart
// Shows album details: name, description, favorite, tags, and a grid of images.
// Supports inline editing (toggle with edit icon).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/album_provider.dart';
import '../providers/tag_provider.dart';
import '../services/notification_service.dart';
import '../views/images_view.dart';
import '../widgets/widgets.dart';

class AlbumView extends StatefulWidget {
  final int albumId;
  final bool startInEditMode;

  const AlbumView({
    super.key,
    required this.albumId,
    this.startInEditMode = false,
  });

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> {
  bool _editMode = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  bool _isFavorite = false;

  List<AssetEntity> _entities = [];
  List<int> _tagIds = [];
  bool _loading = true;

  final Set<String> _selectedAssetIds = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _editMode = widget.startInEditMode;
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ap = context.read<AlbumProvider>();
    final album = ap.getById(widget.albumId);
    if (album == null) return;

    _nameCtrl.text = album.name;
    _descCtrl.text = album.description;
    _isFavorite = album.isFavorite;

    final assetIds = await ap.getAssetIds(widget.albumId);
    final tagIds = await ap.getTagIds(widget.albumId);

    final entities = <AssetEntity>[];
    for (final id in assetIds) {
      final e = await AssetEntity.fromId(id);
      if (e != null) entities.add(e);
    }

    if (mounted) {
      setState(() {
        _entities = entities;
        _tagIds = tagIds;
        _loading = false;
      });
    }
  }

  Future<void> _saveEdits() async {
    final ap = context.read<AlbumProvider>();
    final album = ap.getById(widget.albumId);
    if (album == null) return;

    await ap.updateAlbum(
      album.copyWith(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        isFavorite: _isFavorite,
      ),
      tagIds: _tagIds,
    );

    if (mounted) {
      setState(() => _editMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Album updated')));
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

  Future<void> _removeSelectedImages() async {
    final ap = context.read<AlbumProvider>();
    for (final aid in _selectedAssetIds) {
      await ap.removeImageFromAlbum(widget.albumId, aid);
    }
    setState(() {
      _entities =
          _entities.where((e) => !_selectedAssetIds.contains(e.id)).toList();
      _selectedAssetIds.clear();
      _selectionMode = false;
    });
    await NotificationService.instance
        .show('Images removed', 'Removed from album.');
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.watch<AlbumProvider>();
    final tp = context.watch<TagProvider>();
    final album = ap.getById(widget.albumId);

    if (album == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Album')),
        body: const Center(child: Text('Album not found.')),
      );
    }

    final tagNames = _tagIds
        .map((id) => tp.getById(id)?.name)
        .whereType<String>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: _editMode
            ? const Text('Edit Album')
            : Text(album.name),
        actions: _selectionMode
            ? [
                IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _removeSelectedImages),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                          _selectionMode = false;
                          _selectedAssetIds.clear();
                        })),
              ]
            : [
                if (_editMode)
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _saveEdits,
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => setState(() => _editMode = true),
                  ),
              ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _editMode
                        ? _EditForm(
                            nameCtrl: _nameCtrl,
                            descCtrl: _descCtrl,
                            isFavorite: _isFavorite,
                            tagNames: tagNames,
                            onFavoriteToggle: (v) =>
                                setState(() => _isFavorite = v),
                            onPickTags: _pickTagsDialog,
                          )
                        : _ReadOnlyInfo(
                            album: album,
                            tagNames: tagNames,
                          ),
                  ),
                ),
                if (_entities.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.all(8),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final e = _entities[i];
                          final selected =
                              _selectedAssetIds.contains(e.id);
                          return AssetThumb(
                            asset: e,
                            selected: selected,
                            onTap: () {
                              if (_selectionMode) {
                                setState(() {
                                  selected
                                      ? _selectedAssetIds.remove(e.id)
                                      : _selectedAssetIds.add(e.id);
                                });
                              } else {
                                // Pass image list to ImageView via shared notifier
                                context.read<FilteredListNotifier>()
                                    .setList(_entities);
                                context.push('/images/view/$i');
                              }
                            },
                            onLongPress: () => setState(() {
                              _selectionMode = true;
                              _selectedAssetIds.add(e.id);
                            }),
                          );
                        },
                        childCount: _entities.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 120,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                    ),
                  )
                else
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No images in this album yet.'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ReadOnlyInfo extends StatelessWidget {
  final AlbumModel album;
  final List<String> tagNames;

  const _ReadOnlyInfo({required this.album, required this.tagNames});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(album.name,
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            if (album.isFavorite)
              const Icon(Icons.favorite, color: Colors.pink),
          ],
        ),
        if (album.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(album.description),
        ],
        if (tagNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children:
                tagNames.map((n) => Chip(label: Text(n))).toList(),
          ),
        ],
      ],
    );
  }
}

class _EditForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final bool isFavorite;
  final List<String> tagNames;
  final ValueChanged<bool> onFavoriteToggle;
  final VoidCallback onPickTags;

  const _EditForm({
    required this.nameCtrl,
    required this.descCtrl,
    required this.isFavorite,
    required this.tagNames,
    required this.onFavoriteToggle,
    required this.onPickTags,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: descCtrl,
          decoration: const InputDecoration(labelText: 'Description'),
          maxLines: 2,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Favorite'),
          value: isFavorite,
          onChanged: onFavoriteToggle,
        ),
        Row(
          children: [
            const Text('Tags: '),
            Expanded(
              child: tagNames.isEmpty
                  ? const Text('None', style: TextStyle(color: Colors.grey))
                  : Wrap(
                      spacing: 4,
                      children: tagNames
                          .map((n) => Chip(label: Text(n)))
                          .toList(),
                    ),
            ),
            TextButton.icon(
              onPressed: onPickTags,
              icon: const Icon(Icons.label),
              label: const Text('Edit'),
            ),
          ],
        ),
      ],
    );
  }
}


