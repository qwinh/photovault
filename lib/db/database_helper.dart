// lib/db/database_helper.dart
// Manages the SQLite database using sqflite.
// Tables: albums, tags, album_tags (junction), album_images (junction),
//         selected_images (persisted selection pool).

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

class DatabaseHelper {
  static const _dbName = 'photovault.db';
  static const _dbVersion = 2;

  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE albums (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        description TEXT    NOT NULL DEFAULT '',
        is_favorite INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL UNIQUE,
        description TEXT    NOT NULL DEFAULT ''
      )
    ''');

    // Junction: which tags belong to which album
    await db.execute('''
      CREATE TABLE album_tags (
        album_id INTEGER NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
        tag_id   INTEGER NOT NULL REFERENCES tags(id)   ON DELETE CASCADE,
        PRIMARY KEY (album_id, tag_id)
      )
    ''');

    // Junction: which device-image asset IDs belong to which album
    await db.execute('''
      CREATE TABLE album_images (
        album_id INTEGER NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
        asset_id TEXT    NOT NULL,
        sort_idx INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (album_id, asset_id)
      )
    ''');

    // Globally selected images pool (persisted across sessions)
    await db.execute('''
      CREATE TABLE selected_images (
        asset_id TEXT    PRIMARY KEY NOT NULL,
        sort_idx INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add UNIQUE constraint to tags.name via a table rebuild (SQLite does
      // not support ADD CONSTRAINT on existing tables).
      await db.execute(
          'CREATE TABLE tags_new (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, description TEXT NOT NULL DEFAULT \'\')');
      // Copy rows; on conflict keep the first occurrence (lowest id).
      await db.execute(
          'INSERT OR IGNORE INTO tags_new (id, name, description) SELECT id, name, description FROM tags ORDER BY id ASC');
      await db.execute('DROP TABLE tags');
      await db.execute('ALTER TABLE tags_new RENAME TO tags');
    }
  }

  // ── Albums ──────────────────────────────────────────────────────────────────

  Future<List<AlbumModel>> getAllAlbums() async {
    final db = await database;
    final rows = await db.query('albums', orderBy: 'name ASC');
    return rows.map(AlbumModel.fromMap).toList();
  }

  Future<AlbumModel> insertAlbum(AlbumModel album) async {
    final db = await database;
    final id = await db.insert('albums', album.toMap());
    return album.copyWith(id: id);
  }

  Future<void> updateAlbum(AlbumModel album) async {
    final db = await database;
    await db.update('albums', album.toMap(),
        where: 'id = ?', whereArgs: [album.id]);
  }

  Future<void> deleteAlbum(int id) async {
    final db = await database;
    await db.delete('albums', where: 'id = ?', whereArgs: [id]);
  }

  // ── Tags ────────────────────────────────────────────────────────────────────

  Future<List<TagModel>> getAllTags() async {
    final db = await database;
    final rows = await db.query('tags', orderBy: 'name ASC');
    return rows.map(TagModel.fromMap).toList();
  }

  /// Returns true if a tag with [name] already exists, optionally
  /// excluding [excludeId] (used when renaming an existing tag).
  Future<bool> tagNameExists(String name, {int? excludeId}) async {
    final db = await database;
    final rows = await db.query(
      'tags',
      columns: ['id'],
      where: excludeId != null
          ? 'LOWER(name) = LOWER(?) AND id != ?'
          : 'LOWER(name) = LOWER(?)',
      whereArgs: excludeId != null ? [name, excludeId] : [name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<TagModel> insertTag(TagModel tag) async {
    final db = await database;
    final id = await db.insert('tags', tag.toMap());
    return tag.copyWith(id: id);
  }

  Future<void> updateTag(TagModel tag) async {
    final db = await database;
    await db.update('tags', tag.toMap(), where: 'id = ?', whereArgs: [tag.id]);
  }

  Future<void> deleteTag(int id) async {
    final db = await database;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  // Returns a map of tagId → usageCount (number of albums using the tag)
  Future<Map<int, int>> getTagUsageCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT tag_id, COUNT(*) as cnt FROM album_tags GROUP BY tag_id');
    return {
      for (final r in rows) r['tag_id'] as int: r['cnt'] as int,
    };
  }

  // ── Album ↔ Tags ────────────────────────────────────────────────────────────

  Future<List<int>> getTagIdsForAlbum(int albumId) async {
    final db = await database;
    final rows = await db.query('album_tags',
        columns: ['tag_id'], where: 'album_id = ?', whereArgs: [albumId]);
    return rows.map((r) => r['tag_id'] as int).toList();
  }

  /// Fetches every album's tag IDs in a single query.
  /// Returns a map of albumId → List<tagId>.
  Future<Map<int, List<int>>> getAllAlbumTagIds() async {
    final db = await database;
    final rows =
        await db.query('album_tags', columns: ['album_id', 'tag_id']);
    final result = <int, List<int>>{};
    for (final r in rows) {
      final albumId = r['album_id'] as int;
      final tagId = r['tag_id'] as int;
      result.putIfAbsent(albumId, () => []).add(tagId);
    }
    return result;
  }

  Future<void> setTagsForAlbum(int albumId, List<int> tagIds) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('album_tags',
          where: 'album_id = ?', whereArgs: [albumId]);
      for (final tid in tagIds) {
        await txn.insert('album_tags', {'album_id': albumId, 'tag_id': tid},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  // ── Album ↔ Images ──────────────────────────────────────────────────────────

  Future<List<String>> getAssetIdsForAlbum(int albumId) async {
    final db = await database;
    final rows = await db.query('album_images',
        columns: ['asset_id'],
        where: 'album_id = ?',
        whereArgs: [albumId],
        orderBy: 'sort_idx ASC');
    return rows.map((r) => r['asset_id'] as String).toList();
  }

  Future<void> addImagesToAlbum(int albumId, List<String> assetIds) async {
    final db = await database;
    await db.transaction((txn) async {
      final existing = await txn.query('album_images',
          columns: ['asset_id'],
          where: 'album_id = ?',
          whereArgs: [albumId]);
      final existingIds = existing.map((r) => r['asset_id'] as String).toSet();
      int idx = existingIds.length;
      for (final aid in assetIds) {
        if (!existingIds.contains(aid)) {
          await txn.insert('album_images',
              {'album_id': albumId, 'asset_id': aid, 'sort_idx': idx++},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  Future<void> removeImageFromAlbum(int albumId, String assetId) async {
    final db = await database;
    await db.delete('album_images',
        where: 'album_id = ? AND asset_id = ?', whereArgs: [albumId, assetId]);
  }

  /// Returns all unique asset IDs that belong to at least one album.
  Future<Set<String>> getAllAlbumAssetIds() async {
    final db = await database;
    final rows =
        await db.query('album_images', columns: ['asset_id'], distinct: true);
    return rows.map((r) => r['asset_id'] as String).toSet();
  }

  /// Returns all unique asset IDs belonging to favorite albums.
  Future<Set<String>> getFavoriteAlbumAssetIds() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT ai.asset_id
      FROM album_images ai
      JOIN albums a ON a.id = ai.album_id
      WHERE a.is_favorite = 1
    ''');
    return rows.map((r) => r['asset_id'] as String).toSet();
  }

  /// Returns all unique asset IDs belonging to any of the given album IDs.
  /// Returns an empty set if [albumIds] is empty.
  Future<Set<String>> getAssetIdsForAlbums(Set<int> albumIds) async {
    if (albumIds.isEmpty) return {};
    final db = await database;
    final placeholders = List.filled(albumIds.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT DISTINCT asset_id FROM album_images WHERE album_id IN ($placeholders)',
      albumIds.toList(),
    );
    return rows.map((r) => r['asset_id'] as String).toSet();
  }

  // ── Selected Images pool ────────────────────────────────────────────────────

  Future<List<String>> getSelectedAssetIds() async {
    final db = await database;
    final rows = await db.query('selected_images', orderBy: 'sort_idx ASC');
    return rows.map((r) => r['asset_id'] as String).toList();
  }

  Future<void> addToSelected(String assetId) async {
    final db = await database;
    final rows = await db
        .rawQuery('SELECT MAX(sort_idx) as m FROM selected_images');
    final maxIdx = (rows.first['m'] as int?) ?? -1;
    await db.insert(
        'selected_images', {'asset_id': assetId, 'sort_idx': maxIdx + 1},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeFromSelected(String assetId) async {
    final db = await database;
    await db.delete('selected_images',
        where: 'asset_id = ?', whereArgs: [assetId]);
  }

  Future<void> clearSelected() async {
    final db = await database;
    await db.delete('selected_images');
  }

  Future<void> setSelectedOrder(List<String> orderedAssetIds) async {
    final db = await database;
    await db.transaction((txn) async {
      for (int i = 0; i < orderedAssetIds.length; i++) {
        await txn.update('selected_images', {'sort_idx': i},
            where: 'asset_id = ?', whereArgs: [orderedAssetIds[i]]);
      }
    });
  }
}