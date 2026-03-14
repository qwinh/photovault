// lib/views/images_view.dart
// Displays all device images in a grid.
// Supports filtering (album, favorite albums, dimensions) and sorting.
// Long-press to enter multi-select; swipe horizontally to add more to selection.
// Selected images go to the global SelectionProvider pool.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/album_provider.dart';
import '../providers/image_provider.dart' as ip;
import '../providers/selection_provider.dart';
import '../router/app_router.dart';
import '../widgets/widgets.dart';

class ImagesView extends StatefulWidget {
  const ImagesView({super.key});

  @override
  State<ImagesView> createState() => _ImagesViewState();
}

class _ImagesViewState extends State<ImagesView> {
  bool _selectionMode = false;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ip.DeviceImageProvider>().requestPermissionAndLoad();
      context.read<SelectionProvider>().load();
    });
    // Listen for app resume so we can re-check permission after returning
    // from the OS Settings page.
    _lifecycleListener = AppLifecycleListener(
      onResume: _onAppResumed,
    );
  }

  void _onAppResumed() {
    final imageProvider = context.read<ip.DeviceImageProvider>();
    if (!imageProvider.permissionGranted) {
      imageProvider.requestPermissionAndLoad();
    } else if (imageProvider.all.isEmpty) {
      imageProvider.loadAll();
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _enterSelectionMode() {
    setState(() => _selectionMode = true);
  }

  void _exitSelectionMode() {
    setState(() => _selectionMode = false);
  }

  @override
  Widget build(BuildContext context) {
    final imgProv = context.watch<ip.DeviceImageProvider>();
    final selProv = context.watch<SelectionProvider>();
    final selCount = selProv.count;

    // Keep badge in sync
    context.read<SelectionCountNotifier>().update(selCount);

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('$selCount selected')
            : const Text('Photos'),
        actions: [
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _exitSelectionMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filters & Sort',
              onPressed: () => _showFilterSheet(context, imgProv),
            ),
          ],
        ],
      ),
      body: imgProv.loading
          ? const Center(child: CircularProgressIndicator())
          : !imgProv.permissionGranted
              ? _PermissionPrompt(
                  onRequest: imgProv.requestPermissionAndLoad)
              : imgProv.filtered.isEmpty
                  ? const Center(child: Text('No photos found.'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(2),
                      gridDelegate:
                          _adaptiveGrid(MediaQuery.of(context).size.width),
                      itemCount: imgProv.filtered.length,
                      itemBuilder: (ctx, i) {
                        final asset = imgProv.filtered[i];
                        final isSelected = selProv.isSelected(asset.id);

                        return GestureDetector(
                          onTap: () {
                            if (_selectionMode) {
                              selProv.toggle(asset.id);
                            } else {
                              // Pass filtered list via provider for swipe nav
                              context
                                  .read<FilteredListNotifier>()
                                  .setList(imgProv.filtered);
                              context.push('/images/view/$i');
                            }
                          },
                          onLongPress: () {
                            _enterSelectionMode();
                            selProv.toggle(asset.id);
                          },
                          child: AssetThumb(
                            asset: asset,
                            selected: isSelected,
                          ),
                        );
                      },
                    ),
    );
  }

  SliverGridDelegateWithFixedCrossAxisCount _adaptiveGrid(double width) {
    final cols = (width / 120).floor().clamp(3, 6);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      crossAxisSpacing: 2,
      mainAxisSpacing: 2,
    );
  }

  void _showFilterSheet(
      BuildContext context, ip.DeviceImageProvider imgProv) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        current: imgProv.filterState,
        onApply: (state) {
          imgProv.setFilter(state);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ── Filter / sort bottom sheet ────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final ip.ImageFilterState current;
  final ValueChanged<ip.ImageFilterState> onApply;

  const _FilterSheet({required this.current, required this.onApply});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ip.ImageFilterState _state;
  final _minWCtrl = TextEditingController();
  final _minHCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _state = widget.current;
    _minWCtrl.text = _state.minWidth?.toString() ?? '';
    _minHCtrl.text = _state.minHeight?.toString() ?? '';
  }

  @override
  void dispose() {
    _minWCtrl.dispose();
    _minHCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.read<AlbumProvider>();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Filter & Sort',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            // Album filter
            DropdownButtonFormField<int?>(
              decoration:
                  const InputDecoration(labelText: 'Filter by album'),
              value: _state.albumIdFilter,
              items: [
                const DropdownMenuItem(value: null, child: Text('All albums')),
                ...ap.albums.map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name),
                    )),
              ],
              onChanged: (v) =>
                  setState(() => _state = _state.copyWith(albumIdFilter: v)),
            ),
            const SizedBox(height: 8),

            // Favorite albums only
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('In favorite albums only'),
              value: _state.onlyFavoriteAlbums,
              onChanged: (v) =>
                  setState(() => _state = _state.copyWith(onlyFavoriteAlbums: v)),
            ),

            // Min dimensions
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minWCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Min width (px)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minHCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Min height (px)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Sort
            Text('Sort', style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: ip.SortOrder.values.map((s) {
                return ChoiceChip(
                  label: Text(_sortLabel(s)),
                  selected: _state.sortOrder == s,
                  onSelected: (_) =>
                      setState(() => _state = _state.copyWith(sortOrder: s)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            FilledButton(
              onPressed: () {
                final w = int.tryParse(_minWCtrl.text);
                final h = int.tryParse(_minHCtrl.text);
                widget.onApply(_state.copyWith(minWidth: w, minHeight: h));
              },
              child: const Text('Apply'),
            ),
            TextButton(
              onPressed: () => widget.onApply(const ip.ImageFilterState()),
              child: const Text('Reset filters'),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(ip.SortOrder s) => switch (s) {
        ip.SortOrder.dateDesc => 'Newest first',
        ip.SortOrder.dateAsc => 'Oldest first',
        ip.SortOrder.nameAsc => 'Name A–Z',
        ip.SortOrder.nameDesc => 'Name Z–A',
      };
}

// ── Permission prompt ─────────────────────────────────────────────────────────

class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onRequest;
  const _PermissionPrompt({required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'PhotoVault needs access to your photos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRequest,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Provider to share the current filtered list with ImageView for swipe nav.
class FilteredListNotifier extends ChangeNotifier {
  List<dynamic> _list = [];
  List<dynamic> get list => _list;

  void setList(List<dynamic> list) {
    _list = list;
    notifyListeners();
  }
}
