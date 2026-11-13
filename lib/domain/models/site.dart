/// 站点 = 插件 + 该站点的独立配置。
///
/// 一个插件可被多个站点复用（同一套站点逻辑，不同域名/密钥）。
class SiteBinding {
  const SiteBinding({
    required this.id,
    required this.pluginId,
    required this.name,
    this.baseUrl = '',
    this.enabled = true,
    this.order = 0,
    this.config = const {},
    this.notes = '',
    this.createdAt,
    this.updatedAt,
    this.lastCheckAt,
    this.lastCheckOk,
    this.lastCheckMessage,
    this.latencyMs,
  });

  final String id;
  final String pluginId;

  /// 站点显示名（可以不同于插件名，例如"XX 影视 · 备用"）。
  final String name;
  final String baseUrl;
  final bool enabled;
  final int order;

  /// 配置项 key → 值（含 token / cookie 等敏感项）。
  final Map<String, String> config;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastCheckAt;
  final bool? lastCheckOk;
  final String? lastCheckMessage;
  final int? latencyMs;

  SiteBinding copyWith({
    String? id,
    String? pluginId,
    String? name,
    String? baseUrl,
    bool? enabled,
    int? order,
    Map<String, String>? config,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastCheckAt,
    bool? lastCheckOk,
    String? lastCheckMessage,
    int? latencyMs,
  }) {
    return SiteBinding(
      id: id ?? this.id,
      pluginId: pluginId ?? this.pluginId,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      config: config ?? this.config,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      lastCheckOk: lastCheckOk ?? this.lastCheckOk,
      lastCheckMessage: lastCheckMessage ?? this.lastCheckMessage,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pluginId': pluginId,
        'name': name,
        'baseUrl': baseUrl,
        'enabled': enabled,
        'order': order,
        'config': config,
        if (notes.isNotEmpty) 'notes': notes,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (lastCheckAt != null) 'lastCheckAt': lastCheckAt!.toIso8601String(),
        if (lastCheckOk != null) 'lastCheckOk': lastCheckOk,
        if (lastCheckMessage != null) 'lastCheckMessage': lastCheckMessage,
        if (latencyMs != null) 'latencyMs': latencyMs,
      };

  factory SiteBinding.fromJson(Map<String, dynamic> j) => SiteBinding(
        id: '${j['id'] ?? ''}',
        pluginId: '${j['pluginId'] ?? ''}',
        name: '${j['name'] ?? ''}',
        baseUrl: '${j['baseUrl'] ?? ''}',
        enabled: j['enabled'] != false,
        order: (j['order'] as num?)?.toInt() ?? 0,
        config: (j['config'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
        notes: '${j['notes'] ?? ''}',
        createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}'),
        updatedAt: DateTime.tryParse('${j['updatedAt'] ?? ''}'),
        lastCheckAt: DateTime.tryParse('${j['lastCheckAt'] ?? ''}'),
        lastCheckOk: j['lastCheckOk'] as bool?,
        lastCheckMessage: j['lastCheckMessage'] as String?,
        latencyMs: (j['latencyMs'] as num?)?.toInt(),
      );
}

/// 站点健康状态（由连通性测试写入）。
enum SiteHealth { unknown, ok, degraded, failed }

SiteHealth healthOf(SiteBinding s) {
  if (!s.enabled) return SiteHealth.unknown;
  final ok = s.lastCheckOk;
  if (ok == null) return SiteHealth.unknown;
  if (ok) {
    final l = s.latencyMs ?? 0;
    return l > 2500 ? SiteHealth.degraded : SiteHealth.ok;
  }
  return SiteHealth.failed;
}
