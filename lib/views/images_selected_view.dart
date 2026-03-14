// lib/views/images_selected_view.dart
// Shows the global selected images pool.
// Drag-and-drop to reorder (in-memory only; persisted on save).
// Actions: remove one, clear all, add to existing album, create new album.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';

import '../providers/album_provider.dart';
import '../providers/selection_provider.dart';
import '../services/notification_service.dart';
import '../widgets/widgets.dart';

class ImagesSelectedView extends StatelessWidget {
  const ImagesSelectedView({super.key});

  @override
  Widget build(BuildContext context) {
    final selProv = context.watch<SelectionProvider>();
    final entities = selProv.entities;

    return Scaffold(
      appBar: AppBar(
        title: Text('Selected (${selProv.count})'),
        actions: [
          if (selProv.count > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear all',
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Clear Selection',
                  message: 'Remove all ${selProv.count} images from selection?',
                  confirmLabel: 'Clear',
                );
                if (ok) await selProv.clearAll();
              },
            ),
        ],
      ),
      body: entities.isEmpty
          ? const Center(
              child: Text('No images selected.\nLong-press photos to select.',
                  textAlign: TextAlign.center))
          : Column(
              children: [
                // ── Action buttons ─────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.photo_album_outlined),
                          label: const Text('Add to album'),
                          onPressed: () =>
                              _showAddToAlbumDialog(context, selProv),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('New album'),
                          onPressed: () => context.push('/albums/add'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // ── Reorderable grid ───────────────────────────────────────
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(4),
                    buildDefaultDragHandles: false,
                    itemCount: entities.length,
                    onReorder: (oldIdx, newIdx) {
                      selProv.reorder(oldIdx, newIdx);
                      // Persist new order
                      selProv.persistOrder();
                    },
                    itemBuilder: (ctx, i) {
                      final e = entities[i];
                      return SizedBox(
                        key: ValueKey(e.id),
                        height: 88,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 72,
                              height: 72,
                              child: AssetEntityImage(
                                e,
                                isOriginal: false,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          title: Text(
                            e.title ?? 'Image ${i + 1}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                              '${e.width} × ${e.height}',
                              style: const TextStyle(fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () =>
                                    selProv.removeOne(e.id),
                              ),
                              // Drag handle
                              ReorderableDragStartListener(
                                index: i,
                                child: const Icon(Icons.drag_handle),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _showAddToAlbumDialog(
      BuildContext context, SelectionProvider selProv) async {
    final ap = context.read<AlbumProvider>();
    if (ap.albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No albums yet. Create one first.')));
      return;
    }

    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to album'),
        children: ap.albums
            .map((a) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, a.id),
                  child: Text(a.name),
                ))
            .toList(),
      ),
    );

    if (chosen == null) return;

    final assetIds = selProv.assetIds;
    await ap.addImagesToAlbum(chosen, assetIds);
    await selProv.clearAll();

    final albumName = ap.getById(chosen)?.name ?? '';
    await NotificationService.instance
        .show('Images added', 'Added to "$albumName".');

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${assetIds.length} image(s) to "$albumName"')));
    }
  }
}
