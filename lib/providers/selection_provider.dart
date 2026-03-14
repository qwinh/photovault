// lib/providers/selection_provider.dart
// Manages the global selected-images pool (persisted in SQLite).

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../db/database_helper.dart';

class SelectionProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  /// Ordered list of selected asset IDs (persisted).
  List<String> _assetIds = [];
  List<String> get assetIds => List.unmodifiable(_assetIds);

  /// Resolved AssetEntity objects (populated lazily/on demand).
  List<AssetEntity> _entities = [];
  List<AssetEntity> get entities => List.unmodifiable(_entities);

  bool get isEmpty => _assetIds.isEmpty;
  int get count => _assetIds.length;

  bool isSelected(String assetId) => _assetIds.contains(assetId);

  Future<void> load() async {
    _assetIds = await _db.getSelectedAssetIds();
    await _resolveEntities();
    notifyListeners();
  }

  Future<void> toggle(String assetId) async {
    if (_assetIds.contains(assetId)) {
      await _db.removeFromSelected(assetId);
      _assetIds = List.from(_assetIds)..remove(assetId);
    } else {
      await _db.addToSelected(assetId);
      _assetIds = List.from(_assetIds)..add(assetId);
    }
    await _resolveEntities();
    notifyListeners();
  }

  Future<void> removeOne(String assetId) async {
    await _db.removeFromSelected(assetId);
    _assetIds = List.from(_assetIds)..remove(assetId);
    _entities = _entities.where((e) => e.id != assetId).toList();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _db.clearSelected();
    _assetIds = [];
    _entities = [];
    notifyListeners();
  }

  /// Reorder in-memory only; call [persistOrder] to save.
  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final idsCopy = List<String>.from(_assetIds);
    final entCopy = List<AssetEntity>.from(_entities);
    final id = idsCopy.removeAt(oldIndex);
    idsCopy.insert(newIndex, id);
    if (oldIndex < entCopy.length) {
      final ent = entCopy.removeAt(oldIndex);
      entCopy.insert(newIndex, ent);
    }
    _assetIds = idsCopy;
    _entities = entCopy;
    notifyListeners();
  }

  Future<void> persistOrder() async {
    await _db.setSelectedOrder(_assetIds);
  }

  Future<void> _resolveEntities() async {
    final resolved = <AssetEntity>[];
    for (final id in _assetIds) {
      final entity = await AssetEntity.fromId(id);
      if (entity != null) resolved.add(entity);
    }
    _entities = resolved;
  }
}
