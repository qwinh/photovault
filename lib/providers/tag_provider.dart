// lib/providers/tag_provider.dart

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/models.dart';

/// Thrown when an insert or update would produce a duplicate tag name.
class DuplicateTagNameException implements Exception {
  final String name;
  const DuplicateTagNameException(this.name);
}

class TagProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  List<TagModel> _tags = [];
  List<TagModel> get tags => List.unmodifiable(_tags);

  Map<int, int> _usageCounts = {};
  int usageCount(int tagId) => _usageCounts[tagId] ?? 0;

  Future<void> load() async {
    _tags = await _db.getAllTags();
    _usageCounts = await _db.getTagUsageCounts();
    notifyListeners();
  }

  /// Throws [DuplicateTagNameException] if a tag with the same name exists.
  Future<TagModel> addTag(TagModel tag) async {
    if (await _db.tagNameExists(tag.name)) {
      throw DuplicateTagNameException(tag.name);
    }
    final saved = await _db.insertTag(tag);
    _tags = [..._tags, saved]..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return saved;
  }

  /// Throws [DuplicateTagNameException] if another tag already has this name.
  Future<void> updateTag(TagModel tag) async {
    if (await _db.tagNameExists(tag.name, excludeId: tag.id)) {
      throw DuplicateTagNameException(tag.name);
    }
    await _db.updateTag(tag);
    final idx = _tags.indexWhere((t) => t.id == tag.id);
    if (idx != -1) {
      _tags = List.from(_tags)..[idx] = tag;
      _tags.sort((a, b) => a.name.compareTo(b.name));
    }
    notifyListeners();
  }

  Future<void> deleteTag(int id) async {
    await _db.deleteTag(id);
    _tags = _tags.where((t) => t.id != id).toList();
    _usageCounts.remove(id);
    notifyListeners();
  }

  TagModel? getById(int id) {
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshUsageCounts() async {
    _usageCounts = await _db.getTagUsageCounts();
    notifyListeners();
  }
}