import 'library.dart';
import 'plugin.dart';
import 'site.dart';

/// 局域网内发现到的设备。
class SyncPeer {
  const SyncPeer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.platform = '',
    this.version = '',
    this.lastSeen,
    this.rttMs,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String platform;
  final String version;
  final DateTime? lastSeen;
  final int? rttMs;

  String get endpoint => 'http://$host:$port';

  SyncPeer copyWith({DateTime? lastSeen, int? rttMs}) => SyncPeer(
        id: id,
        name: name,
        host: host,
        port: port,
        platform: platform,
        version: version,
        lastSeen: lastSeen ?? this.lastSeen,
        rttMs: rttMs ?? this.rttMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'platform': platform,
        'version': version,
      };

  factory SyncPeer.fromJson(Map<String, dynamic> j) => SyncPeer(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        host: '${j['host'] ?? ''}',
        port: (j['port'] as num?)?.toInt() ?? 8766,
        platform: '${j['platform'] ?? ''}',
        version: '${j['version'] ?? ''}',
      );
}

/// 可同步的数据快照（也是导入/导出的格式）。
class SyncSnapshot {
  const SyncSnapshot({
    required this.deviceId,
    required this.deviceName,
    required this.exportedAt,
    this.plugins = const [],
    this.sites = const [],
    this.favorites = const [],
    this.history = const [],
    this.version = 1,
  });

  final int version;
  final String deviceId;
  final String deviceName;
  final DateTime exportedAt;
  final List<PluginManifest> plugins;
  final List<SiteBinding> sites;
  final List<FavoriteEntry> favorites;
  final List<HistoryEntry> history;

  int get total =>
      plugins.length + sites.length + favorites.length + history.length;

  Map<String, dynamic> toJson() => {
        'version': version,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'exportedAt': exportedAt.toIso8601String(),
        'plugins': plugins.map((e) => e.toJson()).toList(),
        'sites': sites.map((e) => e.toJson()).toList(),
        'favorites': favorites.map((e) => e.toJson()).toList(),
        'history': history.map((e) => e.toJson()).toList(),
      };

  factory SyncSnapshot.fromJson(Map<String, dynamic> j) => SyncSnapshot(
        version: (j['version'] as num?)?.toInt() ?? 1,
        deviceId: '${j['deviceId'] ?? ''}',
        deviceName: '${j['deviceName'] ?? ''}',
        exportedAt: DateTime.tryParse('${j['exportedAt'] ?? ''}') ?? DateTime.now(),
        plugins: (j['plugins'] as List?)
                ?.whereType<Map>()
                .map((e) => PluginManifest.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
        sites: (j['sites'] as List?)
                ?.whereType<Map>()
                .map((e) => SiteBinding.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
        favorites: (j['favorites'] as List?)
                ?.whereType<Map>()
                .map((e) => FavoriteEntry.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
        history: (j['history'] as List?)
                ?.whereType<Map>()
                .map((e) => HistoryEntry.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}

/// 合并统计，用于同步完成后的对账展示。
class SyncReport {
  const SyncReport({
    this.pluginsAdded = 0,
    this.pluginsUpdated = 0,
    this.sitesAdded = 0,
    this.sitesUpdated = 0,
    this.favoritesMerged = 0,
    this.historyMerged = 0,
    this.skipped = 0,
  });

  final int pluginsAdded;
  final int pluginsUpdated;
  final int sitesAdded;
  final int sitesUpdated;
  final int favoritesMerged;
  final int historyMerged;
  final int skipped;

  int get total =>
      pluginsAdded +
      pluginsUpdated +
      sitesAdded +
      sitesUpdated +
      favoritesMerged +
      historyMerged;

  SyncReport operator +(SyncReport o) => SyncReport(
        pluginsAdded: pluginsAdded + o.pluginsAdded,
        pluginsUpdated: pluginsUpdated + o.pluginsUpdated,
        sitesAdded: sitesAdded + o.sitesAdded,
        sitesUpdated: sitesUpdated + o.sitesUpdated,
        favoritesMerged: favoritesMerged + o.favoritesMerged,
        historyMerged: historyMerged + o.historyMerged,
        skipped: skipped + o.skipped,
      );

  Map<String, dynamic> toJson() => {
        'pluginsAdded': pluginsAdded,
        'pluginsUpdated': pluginsUpdated,
        'sitesAdded': sitesAdded,
        'sitesUpdated': sitesUpdated,
        'favoritesMerged': favoritesMerged,
        'historyMerged': historyMerged,
        'skipped': skipped,
      };
}
