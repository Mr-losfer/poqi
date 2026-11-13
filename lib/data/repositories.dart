import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/models/library.dart';
import '../domain/models/plugin.dart';
import '../domain/models/settings.dart';
import '../domain/models/site.dart';
import '../domain/plugin/builtin.dart';
import '../domain/plugin/diff.dart';
import 'store.dart';

const _uuid = Uuid();

/// 一次插件保存产生的版本记录（含差量补丁）。
class PluginRevision {
  const PluginRevision({
    required this.seq,
    required this.pluginId,
    required this.savedAt,
    required this.message,
    required this.patch,
    required this.snapshot,
    this.added = 0,
    this.removed = 0,
    this.full = false,
  });

  /// 递增序号，从 1 开始。
  final int seq;
  final String pluginId;
  final DateTime savedAt;
  final String message;

  /// 与上一版的 unified diff；首版为全量（[full] = true）。
  final String patch;
  final String snapshot;
  final int added;
  final int removed;
  final bool full;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'pluginId': pluginId,
        'savedAt': savedAt.toIso8601String(),
        'message': message,
        'patch': patch,
        'snapshot': snapshot,
        'added': added,
        'removed': removed,
        'full': full,
      };

  factory PluginRevision.fromJson(Map<String, dynamic> j) => PluginRevision(
        seq: (j['seq'] as num?)?.toInt() ?? 1,
        pluginId: '${j['pluginId'] ?? ''}',
        savedAt: DateTime.tryParse('${j['savedAt'] ?? ''}') ?? DateTime(2024),
        message: '${j['message'] ?? ''}',
        patch: '${j['patch'] ?? ''}',
        snapshot: '${j['snapshot'] ?? ''}',
        added: (j['added'] as num?)?.toInt() ?? 0,
        removed: (j['removed'] as num?)?.toInt() ?? 0,
        full: j['full'] == true,
      );
}

class PluginRepository {
  PluginRepository(this._store);

  final JsonStore _store;

  List<PluginManifest> _custom() =>
      _store.getList(StoreKeys.plugins).map(PluginManifest.fromJson).toList();

  /// 全部插件：内置打底，同 id 的自定义版本覆盖内置。
  List<PluginManifest> all() {
    final map = <String, PluginManifest>{};
    for (final p in builtinPlugins()) {
      map[p.id] = p;
    }
    for (final p in _custom()) {
      map[p.id] = p;
    }
    final list = map.values.toList()
      ..sort((a, b) {
        if (a.builtin != b.builtin) return a.builtin ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return list;
  }

  PluginManifest? byId(String id) {
    for (final p in all()) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> save(PluginManifest plugin, {String message = ''}) async {
    final list = _store.getList(StoreKeys.plugins);
    final idx = list.indexWhere((e) => '${e['id']}' == plugin.id);
    final payload = plugin.toJson();

    final previous = idx >= 0
        ? jsonEncode(list[idx])
        : (builtinPlugins().where((e) => e.id == plugin.id).isNotEmpty
            ? builtinPlugins().firstWhere((e) => e.id == plugin.id).toJsonString()
            : '');

    if (idx >= 0) {
      list[idx] = payload;
    } else {
      list.add(payload);
    }
    await _store.setList(StoreKeys.plugins, list);
    await _appendRevision(plugin.id, previous, plugin.toJsonString(), message);
  }

  Future<void> delete(String id) async {
    final list = _store.getList(StoreKeys.plugins)
      ..removeWhere((e) => '${e['id']}' == id);
    await _store.setList(StoreKeys.plugins, list);
    final revs = _store.getMap(StoreKeys.revisions) ?? {};
    revs.remove(id);
    await _store.setMap(StoreKeys.revisions, revs);
  }

  Future<void> restoreBuiltin(String id) async {
    final list = _store.getList(StoreKeys.plugins)
      ..removeWhere((e) => '${e['id']}' == id);
    await _store.setList(StoreKeys.plugins, list);
  }

  // ---------------- 版本与补丁 ----------------

  List<PluginRevision> revisions(String pluginId) {
    final all = _store.getMap(StoreKeys.revisions) ?? {};
    final raw = all[pluginId];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => PluginRevision.fromJson(e.cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => b.seq.compareTo(a.seq));
  }

  Future<void> _appendRevision(
    String pluginId,
    String before,
    String after,
    String message,
  ) async {
    final all = _store.getMap(StoreKeys.revisions) ?? {};
    final raw = all[pluginId] is List ? (all[pluginId] as List) : <dynamic>[];
    final existing = raw
        .whereType<Map>()
        .map((e) => PluginRevision.fromJson(e.cast<String, dynamic>()))
        .toList();

    final isFirst = existing.isEmpty;
    final patch = isFirst ? '' : UnifiedDiff.generate(before, after);
    final stats = UnifiedDiff.stats(before, after);

    final rev = PluginRevision(
      seq: (existing.isEmpty ? 0 : existing.map((e) => e.seq).reduce((a, b) => a > b ? a : b)) + 1,
      pluginId: pluginId,
      savedAt: DateTime.now(),
      message: message.trim().isEmpty
          ? (isFirst ? '初始版本（全量）' : '保存修改')
          : message.trim(),
      patch: isFirst ? UnifiedDiff.generate('', after) : patch,
      snapshot: after,
      added: stats.added,
      removed: stats.removed,
      full: isFirst,
    );

    final list = [rev.toJson(), ...raw.whereType<Map>()].take(40).toList();
    all[pluginId] = list;
    await _store.setMap(StoreKeys.revisions, all);
  }

  /// 应用到指定历史版本；返回新的插件对象（不自动保存）。
  PluginManifest materialize(String pluginId, int seq) {
    for (final r in revisions(pluginId)) {
      if (r.seq == seq) {
        return PluginManifest.fromJsonString(r.snapshot);
      }
    }
    throw StateError('找不到版本 v$seq');
  }

  /// 生成两个版本之间的补丁文本，供"复制给 AI"或归档。
  String patchBetween(String pluginId, int fromSeq, int toSeq) {
    final revs = revisions(pluginId);
    final from = revs.where((e) => e.seq == fromSeq).firstOrNull;
    final to = revs.where((e) => e.seq == toSeq).firstOrNull;
    if (from == null || to == null) throw StateError('版本不存在');
    return UnifiedDiff.generate(from.snapshot, to.snapshot);
  }

  Future<PluginRevision> applyPatchToLatest(
    String pluginId,
    String patch, {
    String message = '应用补丁',
  }) async {
    final plugin = byId(pluginId);
    if (plugin == null) throw StateError('插件不存在');
    final source = plugin.toJsonString();
    final result = UnifiedDiff.apply(source, patch);
    final next = PluginManifest.fromJsonString(result);
    await save(next, message: message);
    return revisions(pluginId).first;
  }
}

class SiteRepository {
  SiteRepository(this._store);

  final JsonStore _store;

  List<SiteBinding> all() {
    final raw = _store.getList(StoreKeys.sites);
    if (raw.isEmpty) return const [];
    final list = raw.map(SiteBinding.fromJson).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  Future<void> seedIfEmpty() async {
    if (_store.getList(StoreKeys.sites).isNotEmpty) return;
    await _store.setList(
      StoreKeys.sites,
      seedSites().map((e) => e.toJson()).toList(),
    );
  }

  Future<void> save(SiteBinding site) async {
    final list = _store.getList(StoreKeys.sites);
    final idx = list.indexWhere((e) => '${e['id']}' == site.id);
    final payload = site.copyWith(updatedAt: DateTime.now()).toJson();
    if (idx >= 0) {
      list[idx] = payload;
    } else {
      list.add(payload);
    }
    await _store.setList(StoreKeys.sites, list);
  }

  Future<void> delete(String id) async {
    final list = _store.getList(StoreKeys.sites)..removeWhere((e) => '${e['id']}' == id);
    await _store.setList(StoreKeys.sites, list);
  }

  Future<void> reorder(List<String> ids) async {
    final list = _store.getList(StoreKeys.sites);
    for (var i = 0; i < ids.length; i++) {
      final idx = list.indexWhere((e) => '${e['id']}' == ids[i]);
      if (idx >= 0) {
        list[idx] = {...list[idx], 'order': i};
      }
    }
    await _store.setList(StoreKeys.sites, list);
  }

  Future<void> updateHealth(
    String id, {
    required bool ok,
    required int latencyMs,
    String? message,
  }) async {
    final list = _store.getList(StoreKeys.sites);
    final idx = list.indexWhere((e) => '${e['id']}' == id);
    if (idx < 0) return;
    list[idx] = {
      ...list[idx],
      'lastCheckAt': DateTime.now().toIso8601String(),
      'lastCheckOk': ok,
      'latencyMs': latencyMs,
      if (message != null) 'lastCheckMessage': message,
    };
    await _store.setList(StoreKeys.sites, list);
  }

  String newId() => 'site_${_uuid.v4().substring(0, 8)}';
}

class LibraryRepository {
  LibraryRepository(this._store);

  final JsonStore _store;

  List<FavoriteEntry> favorites() =>
      _store.getList(StoreKeys.favorites).map(FavoriteEntry.fromJson).toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  bool isFavorite(String siteId, String itemId) =>
      favorites().any((e) => e.siteId == siteId && e.itemId == itemId);

  Future<bool> toggleFavorite(FavoriteEntry entry) async {
    final list = _store.getList(StoreKeys.favorites);
    final idx = list.indexWhere(
      (e) => '${e['siteId']}' == entry.siteId && '${e['itemId']}' == entry.itemId,
    );
    if (idx >= 0) {
      list.removeAt(idx);
      await _store.setList(StoreKeys.favorites, list);
      return false;
    }
    list.insert(0, entry.toJson());
    await _store.setList(StoreKeys.favorites, list);
    return true;
  }

  Future<void> removeFavorite(String siteId, String itemId) async {
    final list = _store.getList(StoreKeys.favorites)
      ..removeWhere((e) => '${e['siteId']}' == siteId && '${e['itemId']}' == itemId);
    await _store.setList(StoreKeys.favorites, list);
  }

  List<HistoryEntry> history() =>
      _store.getList(StoreKeys.history).map(HistoryEntry.fromJson).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> upsertHistory(HistoryEntry entry) async {
    final list = _store.getList(StoreKeys.history);
    final idx = list.indexWhere(
      (e) => '${e['siteId']}' == entry.siteId && '${e['itemId']}' == entry.itemId,
    );
    if (idx >= 0) {
      list[idx] = entry.toJson();
    } else {
      list.insert(0, entry.toJson());
    }
    // 最多保留 200 条
    final trimmed = list.take(200).toList();
    await _store.setList(StoreKeys.history, trimmed);
  }

  Future<void> removeHistory(String siteId, String itemId) async {
    final list = _store.getList(StoreKeys.history)
      ..removeWhere((e) => '${e['siteId']}' == siteId && '${e['itemId']}' == itemId);
    await _store.setList(StoreKeys.history, list);
  }

  Future<void> clearHistory() => _store.setList(StoreKeys.history, const []);

  Future<void> replaceAll({
    required List<FavoriteEntry> favorites,
    required List<HistoryEntry> history,
  }) async {
    await _store.setList(StoreKeys.favorites, favorites.map((e) => e.toJson()).toList());
    await _store.setList(StoreKeys.history, history.map((e) => e.toJson()).toList());
  }
}

class SettingsRepository {
  SettingsRepository(this._store);

  final JsonStore _store;

  AppSettings load() {
    final raw = _store.getMap(StoreKeys.settings);
    if (raw == null) return const AppSettings();
    return AppSettings.fromJson(raw);
  }

  Future<void> save(AppSettings settings) =>
      _store.setMap(StoreKeys.settings, settings.toJson());

  Future<String> deviceId() async {
    var id = _store.getString(StoreKeys.deviceId);
    if (id == null || id.isEmpty) {
      id = 'dev_${_uuid.v4().substring(0, 12)}';
      await _store.setString(StoreKeys.deviceId, id);
    }
    return id;
  }
}
