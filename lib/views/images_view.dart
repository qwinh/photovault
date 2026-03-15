// lib/views/images_view.dart
// Displays all device images in a grid.
// Supports filtering (include/exclude albums, favorite albums, dimensions) and sorting.
// Long-press to enter multi-select; pan to add more to selection.
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

  // ── Drag-to-select state ──────────────────────────────────────────────────
  final _gridKey = GlobalKey();
  final _scrollController = ScrollController();
  final Set<int> _dragVisited = {};
  bool? _dragSelecting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ip.DeviceImageProvider>().requestPermissionAndLoad();
      context.read<SelectionProvider>().load();
    });
    _lifecycleListener = AppLifecycleListener(onResume: _onAppResumed);
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
    _scrollController.dispose();
    super.dispose();
  }

  void _enterSelectionMode() => setState(() => _selectionMode = true);
  void _exitSelectionMode() => setState(() => _selectionMode = false);

  // ── Drag-to-select helpers ────────────────────────────────────────────────

  int _indexAt(Offset localPos, int itemCount, double gridWidth) {
    final cols = (gridWidth / 120).floor().clamp(3, 6);
    const spacing = 2.0;
    const padding = 2.0;
    final cellSize = (gridWidth - padding * 2 - spacing * (cols - 1)) / cols;

    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final adjustedY = localPos.dy + scrollOffset - padding;
    final adjustedX = localPos.dx - padding;

    if (adjustedX < 0 || adjustedY < 0) return -1;

    final col = (adjustedX / (cellSize + spacing)).floor();
    final row = (adjustedY / (cellSize + spacing)).floor();
    if (col >= cols) return -1;

    final idx = row * cols + col;
    return (idx >= 0 && idx < itemCount) ? idx : -1;
  }

  void _onDragStart(
      DragStartDetails details, int itemCount, double gridWidth) {
    if (!_selectionMode) return;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final idx = _indexAt(local, itemCount, gridWidth);
    if (idx == -1) return;

    final selProv = context.read<SelectionProvider>();
    final assets = context.read<ip.DeviceImageProvider>().filtered;
    _dragVisited.clear();
    _dragVisited.add(idx);
    _dragSelecting = !selProv.isSelected(assets[idx].id);
    if (_dragSelecting!) {
      selProv.select(assets[idx].id);
    } else {
      selProv.deselect(assets[idx].id);
    }
  }

  void _onDragUpdate(
      DragUpdateDetails details, int itemCount, double gridWidth) {
    if (!_selectionMode || _dragSelecting == null) return;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final idx = _indexAt(local, itemCount, gridWidth);
    if (idx == -1 || _dragVisited.contains(idx)) return;

    _dragVisited.add(idx);
    final assets = context.read<ip.DeviceImageProvider>().filtered;
    final selProv = context.read<SelectionProvider>();
    if (_dragSelecting!) {
      selProv.select(assets[idx].id);
    } else {
      selProv.deselect(assets[idx].id);
    }
  }

  void _onDragEnd(DragEndDetails _) {
    _dragVisited.clear();
    _dragSelecting = null;
  }

  @override
  Widget build(BuildContext context) {
    final imgProv = context.watch<ip.DeviceImageProvider>();
    final selProv = context.watch<SelectionProvider>();
    final selCount = selProv.count;

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
            // Show a badge on the filter icon when any filter is active.
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Filters & Sort',
                  onPressed: () => _showFilterSheet(context, imgProv),
                ),
                if (imgProv.filterState.hasAlbumFilter ||
                    imgProv.filterState.minWidth != null ||
                    imgProv.filterState.minHeight != null)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      body: imgProv.loading
          ? const Center(child: CircularProgressIndicator())
          : !imgProv.permissionGranted
              ? _PermissionPrompt(
                  onRequest: imgProv.requestPermissionAndLoad)
              : RefreshIndicator(
                  onRefresh: () =>
                      context.read<ip.DeviceImageProvider>().loadAll(),
                  child: imgProv.filtered.isEmpty
                      ? const SingleChildScrollView(
                          physics: AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: 300,
                            child: Center(child: Text('No photos found.')),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (ctx, constraints) {
                            final gridWidth = constraints.maxWidth;
                            final itemCount = imgProv.filtered.length;
                            return GestureDetector(
                              onPanStart: _selectionMode
                                  ? (d) =>
                                      _onDragStart(d, itemCount, gridWidth)
                                  : null,
                              onPanUpdate: _selectionMode
                                  ? (d) =>
                                      _onDragUpdate(d, itemCount, gridWidth)
                                  : null,
                              onPanEnd: _selectionMode ? _onDragEnd : null,
                              child: GridView.builder(
                                key: _gridKey,
                                controller: _scrollController,
                                physics: _selectionMode
                                    ? const NeverScrollableScrollPhysics()
                                    : const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(2),
                                gridDelegate: _adaptiveGrid(gridWidth),
                                itemCount: itemCount,
                                itemBuilder: (ctx, i) {
                                  final asset = imgProv.filtered[i];
                                  final isSelected =
                                      selProv.isSelected(asset.id);

                                  return GestureDetector(
                                    onTap: () {
                                      if (_selectionMode) {
                                        selProv.toggle(asset.id);
                                      } else {
                                        context
                                            .read<FilteredListNotifier>()
                                            .setList(imgProv.filtered);
                                        context.push('/images/view/$i');
                                      }
                                    },
                                    onLongPress: () {
                                      _enterSelectionMode();
                                      selProv.select(asset.id);
                                    },
                                    child: AssetThumb(
                                      asset: asset,
                                      selected: isSelected,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
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

  void _toggleInclude(int albumId) {
    final next = Set<int>.from(_state.includeAlbumIds);
    if (next.contains(albumId)) {
      next.remove(albumId);
    } else {
      next.add(albumId);
      // An album cannot be in both lists simultaneously.
      final excl = Set<int>.from(_state.excludeAlbumIds)..remove(albumId);
      _state = _state.copyWith(includeAlbumIds: next, excludeAlbumIds: excl);
      setState(() {});
      return;
    }
    setState(() => _state = _state.copyWith(includeAlbumIds: next));
  }

  void _toggleExclude(int albumId) {
    final next = Set<int>.from(_state.excludeAlbumIds);
    if (next.contains(albumId)) {
      next.remove(albumId);
    } else {
      next.add(albumId);
      // An album cannot be in both lists simultaneously.
      final incl = Set<int>.from(_state.includeAlbumIds)..remove(albumId);
      _state = _state.copyWith(excludeAlbumIds: next, includeAlbumIds: incl);
      setState(() {});
      return;
    }
    setState(() => _state = _state.copyWith(excludeAlbumIds: next));
  }

  @override
  Widget build(BuildContext context) {
    final albums = context.read<AlbumProvider>().albums;
    final theme = Theme.of(context);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Text('Filter & Sort', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),

            // ── In these albums (include) ────────────────────────────────────
            Text('Show only — in these albums',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            if (albums.isEmpty)
              const Text('No albums yet.',
                  style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: albums.map((a) {
                  final included = _state.includeAlbumIds.contains(a.id);
                  return FilterChip(
                    label: Text(a.name),
                    selected: included,
                    onSelected: (_) => _toggleInclude(a.id!),
                    selectedColor:
                        theme.colorScheme.primaryContainer,
                    checkmarkColor:
                        theme.colorScheme.onPrimaryContainer,
                  );
                }).toList(),
              ),
            const SizedBox(height: 14),

            // ── Not in these albums (exclude) ────────────────────────────────
            Text('Hide — in these albums',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            if (albums.isEmpty)
              const Text('No albums yet.',
                  style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: albums.map((a) {
                  final excluded = _state.excludeAlbumIds.contains(a.id);
                  return FilterChip(
                    label: Text(a.name),
                    selected: excluded,
                    onSelected: (_) => _toggleExclude(a.id!),
                    selectedColor: theme.colorScheme.errorContainer,
                    checkmarkColor: theme.colorScheme.onErrorContainer,
                  );
                }).toList(),
              ),
            const SizedBox(height: 8),

            // ── Favorite albums only ─────────────────────────────────────────
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('In favorite albums only'),
              value: _state.onlyFavoriteAlbums,
              onChanged: (v) => setState(
                  () => _state = _state.copyWith(onlyFavoriteAlbums: v)),
            ),

            // ── Min dimensions ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minWCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Min width (px)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minHCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Min height (px)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Sort ─────────────────────────────────────────────────────────
            Text('Sort', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
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
            const SizedBox(height: 20),

            // ── Actions ──────────────────────────────────────────────────────
            FilledButton(
              onPressed: () {
                final w = int.tryParse(_minWCtrl.text);
                final h = int.tryParse(_minHCtrl.text);
                widget.onApply(_state.copyWith(minWidth: w, minHeight: h));
              },
              child: const Text('Apply'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () =>
                  widget.onApply(const ip.ImageFilterState()),
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