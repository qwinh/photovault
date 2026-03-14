// lib/models/models.dart
// Central data models for PhotoVault.

class AlbumModel {
  final int? id;
  final String name;
  final String description;
  final bool isFavorite;

  const AlbumModel({
    this.id,
    required this.name,
    this.description = '',
    this.isFavorite = false,
  });

  AlbumModel copyWith({
    int? id,
    String? name,
    String? description,
    bool? isFavorite,
  }) {
    return AlbumModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'is_favorite': isFavorite ? 1 : 0,
      };

  factory AlbumModel.fromMap(Map<String, dynamic> m) => AlbumModel(
        id: m['id'] as int?,
        name: m['name'] as String,
        description: m['description'] as String? ?? '',
        isFavorite: (m['is_favorite'] as int? ?? 0) == 1,
      );
}

class TagModel {
  final int? id;
  final String name;
  final String description;

  const TagModel({this.id, required this.name, this.description = ''});

  TagModel copyWith({int? id, String? name, String? description}) => TagModel(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
      };

  factory TagModel.fromMap(Map<String, dynamic> m) => TagModel(
        id: m['id'] as int?,
        name: m['name'] as String,
        description: m['description'] as String? ?? '',
      );
}

/// Represents a device image (from photo_manager) stored/linked in the DB.
/// The [assetId] is the AssetEntity.id from photo_manager.
class ImageRecord {
  final String assetId;
  // We keep a local path for display when asset is available.
  // The assetId is the primary key stored in SQLite.

  const ImageRecord({required this.assetId});
}
