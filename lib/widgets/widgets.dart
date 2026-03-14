// lib/widgets/widgets.dart
// Reusable small widgets.

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

// ── Asset thumbnail ───────────────────────────────────────────────────────────

class AssetThumb extends StatelessWidget {
  final AssetEntity asset;
  final double size;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AssetThumb({
    super.key,
    required this.asset,
    this.size = 80,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AssetEntityImage(
            asset,
            isOriginal: false,
            thumbnailSize: ThumbnailSize.square(size.toInt()),
            fit: BoxFit.cover,
          ),
          if (selected)
            Container(
              color: Colors.blue.withOpacity(0.40),
              alignment: Alignment.topRight,
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.check_circle,
                  color: Colors.white, size: 20),
            ),
        ],
      ),
    );
  }
}

// ── Confirm dialog ────────────────────────────────────────────────────────────

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ── Tag chip picker dialog ────────────────────────────────────────────────────

class TagPickerDialog extends StatefulWidget {
  final List<({int id, String name})> allTags;
  final Set<int> initialSelected;

  const TagPickerDialog({
    super.key,
    required this.allTags,
    required this.initialSelected,
  });

  @override
  State<TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<TagPickerDialog> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Tags'),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: widget.allTags.map((tag) {
            final isSelected = _selected.contains(tag.id);
            return FilterChip(
              label: Text(tag.name),
              selected: isSelected,
              onSelected: (v) {
                setState(() {
                  v ? _selected.add(tag.id) : _selected.remove(tag.id);
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
