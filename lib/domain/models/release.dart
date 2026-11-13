/// 版本与更新。
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    this.size = 0,
    this.sha256,
  });

  final String name;
  final String url;
  final int size;
  final String? sha256;

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'size': size,
        if (sha256 != null) 'sha256': sha256,
      };

  factory ReleaseAsset.fromJson(Map<String, dynamic> j) => ReleaseAsset(
        name: '${j['name'] ?? ''}',
        url: '${j['url'] ?? ''}',
        size: (j['size'] as num?)?.toInt() ?? 0,
        sha256: j['sha256'] as String?,
      );
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tag,
    this.notes = '',
    this.publishedAt,
    this.htmlUrl = '',
    this.assets = const [],
    this.channel = 'stable',
  });

  final String version;
  final String tag;
  final String notes;
  final DateTime? publishedAt;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
  final String channel;

  ReleaseAsset? assetFor(String suffix) {
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith(suffix.toLowerCase())) return a;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'tag': tag,
        if (notes.isNotEmpty) 'notes': notes,
        if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
        if (htmlUrl.isNotEmpty) 'htmlUrl': htmlUrl,
        if (assets.isNotEmpty) 'assets': assets.map((e) => e.toJson()).toList(),
        'channel': channel,
      };

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) => ReleaseInfo(
        version: '${j['version'] ?? j['tag'] ?? ''}',
        tag: '${j['tag'] ?? j['version'] ?? ''}',
        notes: '${j['notes'] ?? j['body'] ?? ''}',
        publishedAt: DateTime.tryParse('${j['publishedAt'] ?? j['published_at'] ?? ''}'),
        htmlUrl: '${j['htmlUrl'] ?? j['html_url'] ?? ''}',
        assets: (j['assets'] as List?)
                ?.whereType<Map>()
                .map((e) => ReleaseAsset.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
        channel: '${j['channel'] ?? 'stable'}',
      );
}

/// 语义化版本比较：返回 >0 表示 a 更新。
int compareVersions(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

List<int> _parts(String v) {
  final clean = v.trim().replaceAll(RegExp(r'^[vV]'), '').split('+').first;
  return clean
      .split('.')
      .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
}

enum UpdateCheckResult { upToDate, available, failed }
