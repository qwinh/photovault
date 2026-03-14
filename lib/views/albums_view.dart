// lib/views/albums_view.dart
// Shows all albums as list tiles.
// Long press → multi-select mode.
// Swipe left-to-right → edit, right-to-left → delete.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/album_provider.dart';
import '../providers/tag_provider.dart';
import '../services/notification_service.dart';
import '../widgets/widgets.dart';

class AlbumsView extends StatefulWidget {
  const AlbumsView({super.key});

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<int> _selectedIds = {};
  bool _selectionMode = false;
  bool _favOnly = false;

  // Tag filter: all tags whose IDs are in this set must be on the album (AND).
  Set<int> _tagFilter = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlbumProvider>().load();
      context.read<TagProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AlbumModel> _applyFilters(List<AlbumModel> albums, AlbumProvider ap) {
    return albums.where((a) {
      // Name search
      if (_searchQuery.isNotEmpty &&
          !a.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      // Favorites-only toggle
      if (_favOnly && !a.isFavorite) return false;
      // Tag AND filter: every selected tag must be on the album.
      if (_tagFilter.isNotEmpty) {
        final albumTagIds = ap.getTagIdsSync(a.id!).toSet();
        if (!_tagFilter.every(albumTagIds.contains)) return false;
      }
      return true;
    }).toList();
  }

  void _enterSelectionMode(int id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _bulkDelete() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Delete Albums',
      message: 'Delete ${_selectedIds.length} album(s)?',
    );
    if (!confirmed) return;
    final ap = context.read<AlbumProvider>();
    for (final id in List.of(_selectedIds)) {
      await ap.deleteAlbum(id);
    }
    _exitSelectionMode();
    await NotificationService.instance.show(
        'Albums deleted', '${_selectedIds.length} album(s) removed.');
  }

  Future<void> _bulkToggleFavorite() async {
    final ap = context.read<AlbumProvider>();
    for (final id in _selectedIds) {
      final album = ap.getById(id);
      if (album != null) {
        await ap.updateAlbum(album.copyWith(isFavorite: !album.isFavorite));
      }
    }
    _exitSelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.watch<AlbumProvider>();
    final tp = context.watch<TagProvider>();
    final filtered = _applyFilters(ap.albums, ap);

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : const Text('Albums'),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.favorite),
                  tooltip: 'Toggle favorite',
                  onPressed: _bulkToggleFavorite,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete',
                  onPressed: _bulkDelete,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectionMode,
                ),
              ]
            : [
                // Favorites toggle
                IconButton(
                  icon: Icon(
                    _favOnly ? Icons.favorite : Icons.favorite_border,
                    color: _favOnly ? Colors.pink : null,
                  ),
                  tooltip: _favOnly ? 'Show all albums' : 'Favorites only',
                  onPressed: () => setState(() => _favOnly = !_favOnly),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New album',
                  onPressed: () => context.push('/albums/add'),
                ),
              ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search albums…',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // Tag filter chips
          if (tp.tags.isNotEmpty)
            _TagFilterBar(
              tags: tp.tags,
              selected: _tagFilter,
              onChanged: (s) => setState(() => _tagFilter = s),
            ),
          // Album list
          Expanded(
            child: ap.loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(child: Text('No albums yet.'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final album = filtered[i];
                          final isSelected =
                              _selectedIds.contains(album.id);
                          return _AlbumTile(
                            album: album,
                            selectionMode: _selectionMode,
                            isSelected: isSelected,
                            onTap: () {
                              if (_selectionMode) {
                                setState(() {
                                  isSelected
                                      ? _selectedIds.remove(album.id)
                                      : _selectedIds.add(album.id!);
                                });
                              } else {
                                context.push('/albums/${album.id}');
                              }
                            },
                            onLongPress: () =>
                                _enterSelectionMode(album.id!),
                            onEdit: () => context.push(
                                '/albums/${album.id}?edit=true'),
                            onDelete: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Delete Album',
                                message:
                                    'Delete "${album.name}"?',
                              );
                              if (ok) {
                                await context
                                    .read<AlbumProvider>()
                                    .deleteAlbum(album.id!);
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

// ── Album list tile with swipe actions ────────────────────────────────────────

class _AlbumTile extends StatelessWidget {
  final AlbumModel album;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AlbumTile({
    required this.album,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ap = context.read<AlbumProvider>();

    return Dismissible(
      key: ValueKey('album_${album.id}'),
      background: Container(
        color: Colors.blue,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onEdit();
          return false;
        } else {
          return confirmDialog(
            context,
            title: 'Delete Album',
            message: 'Delete "${album.name}"?',
          );
        }
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        selected: isSelected,
        leading: _AlbumThumb(albumId: album.id!, provider: ap),
        title: Text(album.name),
        subtitle: album.description.isNotEmpty
            ? Text(album.description,
                maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (album.isFavorite)
              const Icon(Icons.favorite, color: Colors.pink, size: 18),
            if (selectionMode)
              Icon(isSelected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked),
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

/// Shows the first image of the album as a square thumbnail.
class _AlbumThumb extends StatefulWidget {
  final int albumId;
  final AlbumProvider provider;
  const _AlbumThumb({required this.albumId, required this.provider});

  @override
  State<_AlbumThumb> createState() => _AlbumThumbState();
}

class _AlbumThumbState extends State<_AlbumThumb> {
  AssetEntity? _first;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await widget.provider.getAssetIds(widget.albumId);
    if (ids.isNotEmpty) {
      final entity = await AssetEntity.fromId(ids.first);
      if (mounted) setState(() => _first = entity);
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
          width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_first == null) {
      return Container(
        width: 48,
        height: 48,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: const Icon(Icons.photo),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 48,
        height: 48,
        child: AssetThumb(asset: _first!, size: 48),
      ),
    );
  }
}

// ── Tag filter bar ─────────────────────────────────────────────────────────────

class _TagFilterBar extends StatelessWidget {
  final List<TagModel> tags;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  const _TagFilterBar({
    required this.tags,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: tags.map((t) {
          final active = selected.contains(t.id);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(t.name),
              selected: active,
              onSelected: (v) {
                final copy = Set<int>.from(selected);
                v ? copy.add(t.id!) : copy.remove(t.id);
                onChanged(copy);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
