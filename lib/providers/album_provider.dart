// lib/providers/album_provider.dart
// Manages albums list and per-album operations.

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/models.dart';

class AlbumProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  List<AlbumModel> _albums = [];
  List<AlbumModel> get albums => List.unmodifiable(_albums);

  // Per-album tag IDs cache: albumId → List<tagId>
  final Map<int, List<int>> _albumTagIds = {};

  // Per-album asset IDs cache: albumId → List<assetId>
  final Map<int, List<String>> _albumAssetIds = {};

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _albums = await _db.getAllAlbums();
    // Warm the tag-ID cache for ALL albums in one query so the view
    // can filter by tags synchronously (no FutureBuilder needed).
    final bulk = await _db.getAllAlbumTagIds();
    _albumTagIds
      ..clear()
      ..addAll(bulk);
    _loading = false;
    notifyListeners();
  }

  Future<AlbumModel> addAlbum(AlbumModel album,
      {List<int> tagIds = const [],
      List<String> assetIds = const []}) async {
    final saved = await _db.insertAlbum(album);
    if (tagIds.isNotEmpty) {
      await _db.setTagsForAlbum(saved.id!, tagIds);
    }
    if (assetIds.isNotEmpty) {
      await _db.addImagesToAlbum(saved.id!, assetIds);
    }
    _albums = [..._albums, saved]..sort((a, b) => a.name.compareTo(b.name));
    _albumTagIds[saved.id!] = tagIds;
    _albumAssetIds[saved.id!] = assetIds;
    notifyListeners();
    return saved;
  }

  Future<void> updateAlbum(AlbumModel album, {List<int>? tagIds}) async {
    await _db.updateAlbum(album);
    if (tagIds != null) {
      await _db.setTagsForAlbum(album.id!, tagIds);
      _albumTagIds[album.id!] = tagIds;
    }
    final idx = _albums.indexWhere((a) => a.id == album.id);
    if (idx != -1) {
      _albums = List.from(_albums)..[idx] = album;
      _albums.sort((a, b) => a.name.compareTo(b.name));
    }
    notifyListeners();
  }

  Future<void> deleteAlbum(int id) async {
    await _db.deleteAlbum(id);
    _albums = _albums.where((a) => a.id != id).toList();
    _albumTagIds.remove(id);
    _albumAssetIds.remove(id);
    notifyListeners();
  }

  Future<List<int>> getTagIds(int albumId) async {
    if (!_albumTagIds.containsKey(albumId)) {
      _albumTagIds[albumId] = await _db.getTagIdsForAlbum(albumId);
    }
    return _albumTagIds[albumId]!;
  }

  /// Returns tag IDs for [albumId] from the in-memory cache (populated by
  /// [load]). Returns an empty list if the album has no cached entry yet.
  List<int> getTagIdsSync(int albumId) => _albumTagIds[albumId] ?? [];

  Future<List<String>> getAssetIds(int albumId) async {
    if (!_albumAssetIds.containsKey(albumId)) {
      _albumAssetIds[albumId] = await _db.getAssetIdsForAlbum(albumId);
    }
    return _albumAssetIds[albumId]!;
  }

  Future<void> addImagesToAlbum(int albumId, List<String> assetIds) async {
    await _db.addImagesToAlbum(albumId, assetIds);
    _albumAssetIds.remove(albumId); // invalidate cache
    notifyListeners();
  }

  Future<void> removeImageFromAlbum(int albumId, String assetId) async {
    await _db.removeImageFromAlbum(albumId, assetId);
    _albumAssetIds[albumId]?.remove(assetId);
    notifyListeners();
  }

  AlbumModel? getById(int id) {
    try {
      return _albums.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }
}
