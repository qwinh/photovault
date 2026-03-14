// lib/providers/image_provider.dart
// Loads all device images via photo_manager, applies in-memory filters/sort.

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../db/database_helper.dart';

enum SortOrder { dateDesc, dateAsc, nameAsc, nameDesc }

class ImageFilterState {
  final int? albumIdFilter;       // show only images in this album
  final bool onlyFavoriteAlbums;  // show only images in any favorite album
  final int? minWidth;
  final int? minHeight;
  final SortOrder sortOrder;

  const ImageFilterState({
    this.albumIdFilter,
    this.onlyFavoriteAlbums = false,
    this.minWidth,
    this.minHeight,
    this.sortOrder = SortOrder.dateDesc,
  });

  ImageFilterState copyWith({
    Object? albumIdFilter = _sentinel,
    bool? onlyFavoriteAlbums,
    Object? minWidth = _sentinel,
    Object? minHeight = _sentinel,
    SortOrder? sortOrder,
  }) {
    return ImageFilterState(
      albumIdFilter: albumIdFilter == _sentinel
          ? this.albumIdFilter
          : albumIdFilter as int?,
      onlyFavoriteAlbums: onlyFavoriteAlbums ?? this.onlyFavoriteAlbums,
      minWidth: minWidth == _sentinel ? this.minWidth : minWidth as int?,
      minHeight: minHeight == _sentinel ? this.minHeight : minHeight as int?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

const _sentinel = Object();

class DeviceImageProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  List<AssetEntity> _all = [];
  List<AssetEntity> _filtered = [];
  List<AssetEntity> get filtered => List.unmodifiable(_filtered);
  List<AssetEntity> get all => List.unmodifiable(_all);

  ImageFilterState _filterState = const ImageFilterState();
  ImageFilterState get filterState => _filterState;

  bool _loading = false;
  bool get loading => _loading;

  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;

  // Asset IDs for album filter and favorite filter (refreshed on demand)
  Set<String> _albumFilterAssetIds = {};
  Set<String> _favoriteAssetIds = {};

  Future<void> requestPermissionAndLoad() async {
    final result = await PhotoManager.requestPermissionExtend();
    // hasAccess covers: authorized, limited (Android 14 partial), restricted.
    // isAuth alone misses `limited` which is the common state on Android 14+
    // when the user taps "Allow selected photos" or "Allow all photos".
    _permissionGranted = result.hasAccess;
    if (_permissionGranted) {
      await loadAll();
    } else {
      // Permission permanently denied or not yet granted — open OS Settings
      // so the user can manually enable it. Without this the button does nothing
      // visible after the first rejection.
      await PhotoManager.openSetting();
      notifyListeners();
    }
  }

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isNotEmpty) {
      _all = await albums.first.getAssetListRange(
        start: 0,
        end: await albums.first.assetCountAsync,
      );
    } else {
      _all = [];
    }

    _loading = false;
    await _applyFilters();
  }

  Future<void> setFilter(ImageFilterState state) async {
    _filterState = state;
    await _applyFilters();
  }

  Future<void> refreshForAlbumFilter(int albumId) async {
    _albumFilterAssetIds = (await _db.getAssetIdsForAlbum(albumId)).toSet();
    await _applyFilters();
  }

  Future<void> refreshFavoriteFilter() async {
    _favoriteAssetIds = await _db.getFavoriteAlbumAssetIds();
    await _applyFilters();
  }

  Future<void> _applyFilters() async {
    // Refresh DB-backed filter sets when needed
    if (_filterState.albumIdFilter != null) {
      _albumFilterAssetIds =
          (await _db.getAssetIdsForAlbum(_filterState.albumIdFilter!)).toSet();
    }
    if (_filterState.onlyFavoriteAlbums) {
      _favoriteAssetIds = await _db.getFavoriteAlbumAssetIds();
    }

    List<AssetEntity> result = List.of(_all);

    // Filter by album membership
    if (_filterState.albumIdFilter != null) {
      result =
          result.where((a) => _albumFilterAssetIds.contains(a.id)).toList();
    }

    // Filter by favorite albums
    if (_filterState.onlyFavoriteAlbums) {
      result = result.where((a) => _favoriteAssetIds.contains(a.id)).toList();
    }

    // Filter by dimensions
    if (_filterState.minWidth != null) {
      result =
          result.where((a) => a.width >= _filterState.minWidth!).toList();
    }
    if (_filterState.minHeight != null) {
      result =
          result.where((a) => a.height >= _filterState.minHeight!).toList();
    }

    // Sort
    switch (_filterState.sortOrder) {
      case SortOrder.dateDesc:
        result.sort((a, b) =>
            (b.createDateTime).compareTo(a.createDateTime));
        break;
      case SortOrder.dateAsc:
        result.sort((a, b) =>
            (a.createDateTime).compareTo(b.createDateTime));
        break;
      case SortOrder.nameAsc:
        result.sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
        break;
      case SortOrder.nameDesc:
        result.sort((a, b) => (b.title ?? '').compareTo(a.title ?? ''));
        break;
    }

    _filtered = result;
    notifyListeners();
  }

  /// Invalidates cached filter sets so next filter apply re-fetches from DB.
  void invalidateFilterCache() {
    _albumFilterAssetIds = {};
    _favoriteAssetIds = {};
  }
}
