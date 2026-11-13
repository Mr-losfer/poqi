/// 统一媒体模型：所有插件最终都要收敛到这一组结构。
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.poster,
    this.year,
    this.score,
    this.remarks,
    this.area,
    this.kind,
    this.tags = const [],
    this.sourceId,
    this.sourceName,
    this.extra = const {},
  });

  /// 站点内的唯一标识（通常是详情页路径或站点原始 id）。
  final String id;
  final String title;
  final String? poster;
  final String? year;
  final String? score;
  final String? remarks;
  final String? area;
  final String? kind;
  final List<String> tags;

  /// 聚合检索时用于回填"来自哪个站点"。
  final String? sourceId;
  final String? sourceName;

  /// 插件自定义字段，用于透传给详情/播放。
  final Map<String, dynamic> extra;

  MediaItem copyWith({
    String? id,
    String? title,
    String? poster,
    String? year,
    String? score,
    String? remarks,
    String? area,
    String? kind,
    List<String>? tags,
    String? sourceId,
    String? sourceName,
    Map<String, dynamic>? extra,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      year: year ?? this.year,
      score: score ?? this.score,
      remarks: remarks ?? this.remarks,
      area: area ?? this.area,
      kind: kind ?? this.kind,
      tags: tags ?? this.tags,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (poster != null) 'poster': poster,
        if (year != null) 'year': year,
        if (score != null) 'score': score,
        if (remarks != null) 'remarks': remarks,
        if (area != null) 'area': area,
        if (kind != null) 'kind': kind,
        if (tags.isNotEmpty) 'tags': tags,
        if (sourceId != null) 'sourceId': sourceId,
        if (sourceName != null) 'sourceName': sourceName,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        poster: j['poster'] as String?,
        year: j['year'] as String?,
        score: j['score'] as String?,
        remarks: j['remarks'] as String?,
        area: j['area'] as String?,
        kind: j['kind'] as String?,
        tags: (j['tags'] as List?)?.map((e) => '$e').toList() ?? const [],
        sourceId: j['sourceId'] as String?,
        sourceName: j['sourceName'] as String?,
        extra: (j['extra'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

class Episode {
  const Episode({required this.name, required this.url, this.index = 0});

  final String name;
  final String url;
  final int index;

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'index': index};

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        name: '${j['name'] ?? ''}',
        url: '${j['url'] ?? ''}',
        index: (j['index'] as num?)?.toInt() ?? 0,
      );
}

/// 播放线路（同一部剧的多条源）。
class PlayLine {
  const PlayLine({required this.name, required this.episodes});

  final String name;
  final List<Episode> episodes;

  Map<String, dynamic> toJson() => {
        'name': name,
        'episodes': episodes.map((e) => e.toJson()).toList(),
      };

  factory PlayLine.fromJson(Map<String, dynamic> j) => PlayLine(
        name: '${j['name'] ?? '线路'}',
        episodes: (j['episodes'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Episode.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class MediaDetail {
  const MediaDetail({
    required this.item,
    this.intro,
    this.director,
    this.actors = const [],
    this.lines = const [],
    this.fetchedAt,
  });

  final MediaItem item;
  final String? intro;
  final String? director;
  final List<String> actors;
  final List<PlayLine> lines;
  final DateTime? fetchedAt;

  int get episodeCount => lines.fold(0, (a, l) => a + l.episodes.length);

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        if (intro != null) 'intro': intro,
        if (director != null) 'director': director,
        if (actors.isNotEmpty) 'actors': actors,
        if (lines.isNotEmpty) 'lines': lines.map((e) => e.toJson()).toList(),
      };
}

class MediaPage {
  const MediaPage({required this.items, this.page = 1, this.hasMore = false});

  final List<MediaItem> items;
  final int page;
  final bool hasMore;

  static const empty = MediaPage(items: []);
}

/// 分类筛选项（地区/类型/年份…）。
class FilterGroup {
  const FilterGroup({required this.key, required this.label, required this.values});

  final String key;
  final String label;
  final List<String> values;

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'values': values};

  factory FilterGroup.fromJson(Map<String, dynamic> j) => FilterGroup(
        key: '${j['key'] ?? ''}',
        label: '${j['label'] ?? ''}',
        values: (j['values'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}

class PlayTarget {
  const PlayTarget({
    required this.siteId,
    required this.siteName,
    required this.item,
    required this.line,
    required this.episode,
    required this.lineIndex,
    required this.episodeIndex,
  });

  final String siteId;
  final String siteName;
  final MediaItem item;
  final PlayLine line;
  final Episode episode;
  final int lineIndex;
  final int episodeIndex;
}

/// 解析后的播放地址。
class PlaySource {
  const PlaySource({
    required this.url,
    this.headers = const {},
    this.kind = PlayKind.auto,
    this.lineName,
    this.title,
  });

  final String url;
  final Map<String, String> headers;
  final PlayKind kind;
  final String? lineName;
  final String? title;
}

enum PlayKind { auto, hls, mp4, flv, unknown }
