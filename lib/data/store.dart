import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 极简持久层：所有结构都存为 JSON 字符串。
///
/// 选择 SharedPreferences 而不是数据库：插件/站点/书签都是小体量文档，
/// 同构支持 Android / Web / Windows / Linux，便于整包导出与局域网同步。
class JsonStore {
  JsonStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<JsonStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return JsonStore(prefs);
  }

  Map<String, dynamic>? getMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map ? v.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// 返回**可变**列表。
  ///
  /// 这里曾经返回 `const []`，而所有调用方都是「取出 → add/remove → 写回」，
  /// 于是任何 key 尚未写入过的首次保存都会抛
  /// `Unsupported operation: Cannot add to an unmodifiable list`。
  /// 表现为「新建插件点了没反应」（async 抛错无人接）与 MCP 写入失败。
  List<Map<String, dynamic>> getList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final v = jsonDecode(raw);
      if (v is! List) return <Map<String, dynamic>>[];
      return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  String? getString(String key) => _prefs.getString(key);

  Future<void> setMap(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  Future<void> setList(String key, List<Map<String, dynamic>> value) =>
      _prefs.setString(key, jsonEncode(value));

  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  bool? getBool(String key) => _prefs.getBool(key);

  Set<String> keys() => _prefs.getKeys();

  Future<void> clear() => _prefs.clear();
}

class StoreKeys {
  const StoreKeys._();

  static const plugins = 'pq.plugins.v1';
  static const sites = 'pq.sites.v1';
  static const favorites = 'pq.favorites.v1';
  static const history = 'pq.history.v1';
  static const settings = 'pq.settings.v1';
  static const revisions = 'pq.revisions.v1';
  static const install = 'pq.install.v1';
  static const deviceId = 'pq.device.id';
  static const deviceName = 'pq.device.name';
}
