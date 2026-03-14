// lib/views/image_view.dart
// Full-screen viewer. Swipe left/right to navigate the list from the
// previous context (passed via FilteredListNotifier or album).
// Shows filename, dimensions, date on tap.
// Toggle selection from the global pool.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';

import '../providers/selection_provider.dart';
import '../views/images_view.dart';

class ImageView extends StatefulWidget {
  final int initialIndex;

  const ImageView({super.key, required this.initialIndex});

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  late PageController _pageCtrl;
  List<AssetEntity> _assets = [];
  int _currentIndex = 0;
  bool _showInfo = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Get the list from the shared notifier (set by ImagesView or AlbumView)
      final list = context.read<FilteredListNotifier>().list;
      if (list.isNotEmpty && list.first is AssetEntity) {
        setState(() => _assets = list.cast<AssetEntity>());
      }
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  AssetEntity? get _current =>
      _assets.isEmpty ? null : _assets[_currentIndex];

  @override
  Widget build(BuildContext context) {
    final selProv = context.watch<SelectionProvider>();
    final asset = _current;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          // Info toggle
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => setState(() => _showInfo = !_showInfo),
          ),
          // Selection toggle
          if (asset != null)
            IconButton(
              icon: Icon(
                selProv.isSelected(asset.id)
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                color: selProv.isSelected(asset.id)
                    ? Colors.blue
                    : Colors.white,
              ),
              tooltip: selProv.isSelected(asset.id)
                  ? 'Remove from selection'
                  : 'Add to selection',
              onPressed: () => selProv.toggle(asset.id),
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: _assets.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                // ── Page view for swipe navigation ──────────────────────
                PageView.builder(
                  controller: _pageCtrl,
                  itemCount: _assets.length,
                  onPageChanged: (i) =>
                      setState(() => _currentIndex = i),
                  itemBuilder: (ctx, i) {
                    return InteractiveViewer(
                      child: Center(
                        child: AssetEntityImage(
                          _assets[i],
                          isOriginal: true,
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                ),

                // ── Info overlay ────────────────────────────────────────
                if (_showInfo && asset != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _InfoPanel(asset: asset),
                  ),
              ],
            ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final AssetEntity asset;
  const _InfoPanel({required this.asset});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy-MM-dd HH:mm')
        .format(asset.createDateTime);

    return Container(
      color: Colors.black.withOpacity(0.75),
      padding:
          const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('File: ${asset.title ?? 'Unknown'}'),
            Text('Dimensions: ${asset.width} × ${asset.height}'),
            Text('Date: $date'),
          ],
        ),
      ),
    );
  }
}
