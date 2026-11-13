import 'package:flutter/material.dart';

/// 全局设置。
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.deviceName = '',
    this.pairCode = '2468',
    this.mcpEnabled = false,
    this.mcpPort = 8765,
    this.syncEnabled = false,
    this.syncPort = 8766,
    this.autoCheckUpdate = true,
    this.preferProxy = true,
    this.repoOwner = 'losfer',
    this.repoName = 'poqi',
    this.searchConcurrency = 4,
    this.aggregateTimeoutMs = 12000,
    this.preferSourceIds = const [],
    this.lastUpdateCheck,
    this.skippedVersion,
    this.onboarded = false,
  });

  final ThemeMode themeMode;
  final String deviceName;

  /// 局域网配对码：同一 Wi-Fi 下的设备填同一个码即可互相同步。
  final String pairCode;

  /// 局域网 MCP 服务（HTTP/JSON-RPC）。
  final bool mcpEnabled;
  final int mcpPort;

  /// 局域网同步服务（发现 + 推送/拉取）。
  final bool syncEnabled;
  final int syncPort;

  final bool autoCheckUpdate;
  final bool preferProxy;
  final String repoOwner;
  final String repoName;
  final int searchConcurrency;
  final int aggregateTimeoutMs;

  /// 聚合播放时优先尝试的站点顺序。
  final List<String> preferSourceIds;

  final DateTime? lastUpdateCheck;
  final String? skippedVersion;
  final bool onboarded;

  String get repoSlug => '$repoOwner/$repoName';

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? deviceName,
    String? pairCode,
    bool? mcpEnabled,
    int? mcpPort,
    bool? syncEnabled,
    int? syncPort,
    bool? autoCheckUpdate,
    bool? preferProxy,
    String? repoOwner,
    String? repoName,
    int? searchConcurrency,
    int? aggregateTimeoutMs,
    List<String>? preferSourceIds,
    DateTime? lastUpdateCheck,
    String? skippedVersion,
    bool? onboarded,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      deviceName: deviceName ?? this.deviceName,
      pairCode: pairCode ?? this.pairCode,
      mcpEnabled: mcpEnabled ?? this.mcpEnabled,
      mcpPort: mcpPort ?? this.mcpPort,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncPort: syncPort ?? this.syncPort,
      autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
      preferProxy: preferProxy ?? this.preferProxy,
      repoOwner: repoOwner ?? this.repoOwner,
      repoName: repoName ?? this.repoName,
      searchConcurrency: searchConcurrency ?? this.searchConcurrency,
      aggregateTimeoutMs: aggregateTimeoutMs ?? this.aggregateTimeoutMs,
      preferSourceIds: preferSourceIds ?? this.preferSourceIds,
      lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
      skippedVersion: skippedVersion ?? this.skippedVersion,
      onboarded: onboarded ?? this.onboarded,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'deviceName': deviceName,
        'pairCode': pairCode,
        'mcpEnabled': mcpEnabled,
        'mcpPort': mcpPort,
        'syncEnabled': syncEnabled,
        'syncPort': syncPort,
        'autoCheckUpdate': autoCheckUpdate,
        'preferProxy': preferProxy,
        'repoOwner': repoOwner,
        'repoName': repoName,
        'searchConcurrency': searchConcurrency,
        'aggregateTimeoutMs': aggregateTimeoutMs,
        'preferSourceIds': preferSourceIds,
        if (lastUpdateCheck != null) 'lastUpdateCheck': lastUpdateCheck!.toIso8601String(),
        if (skippedVersion != null) 'skippedVersion': skippedVersion,
        'onboarded': onboarded,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: switch ('${j['themeMode'] ?? 'dark'}') {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        },
        deviceName: '${j['deviceName'] ?? ''}',
        pairCode: '${j['pairCode'] ?? '2468'}',
        mcpEnabled: j['mcpEnabled'] == true,
        mcpPort: (j['mcpPort'] as num?)?.toInt() ?? 8765,
        syncEnabled: j['syncEnabled'] == true,
        syncPort: (j['syncPort'] as num?)?.toInt() ?? 8766,
        autoCheckUpdate: j['autoCheckUpdate'] != false,
        preferProxy: j['preferProxy'] != false,
        repoOwner: '${j['repoOwner'] ?? 'losfer'}',
        repoName: '${j['repoName'] ?? 'poqi'}',
        searchConcurrency: (j['searchConcurrency'] as num?)?.toInt() ?? 4,
        aggregateTimeoutMs: (j['aggregateTimeoutMs'] as num?)?.toInt() ?? 12000,
        preferSourceIds:
            (j['preferSourceIds'] as List?)?.map((e) => '$e').toList() ?? const [],
        lastUpdateCheck: DateTime.tryParse('${j['lastUpdateCheck'] ?? ''}'),
        skippedVersion: j['skippedVersion'] as String?,
        onboarded: j['onboarded'] == true,
      );
}
