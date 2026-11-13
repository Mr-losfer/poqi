/// 收藏 / 播放历史 / 搜索热词，都是本地优先的数据。
class FavoriteEntry {
  const FavoriteEntry({
    required this.siteId,
    required this.itemId,
    required this.title,
    this.poster,
    this.year,
    this.remarks,
    required this.addedAt,
  });

  final String siteId;
  final String itemId;
  final String title;
  final String? poster;
  final String? year;
  final String? remarks;
  final DateTime addedAt;

  String get key => '$siteId::$itemId';

  Map<String, dynamic> toJson() => {
        'siteId': siteId,
        'itemId': itemId,
        'title': title,
        if (poster != null) 'poster': poster,
        if (year != null) 'year': year,
        if (remarks != null) 'remarks': remarks,
        'addedAt': addedAt.toIso8601String(),
      };

  factory FavoriteEntry.fromJson(Map<String, dynamic> j) => FavoriteEntry(
        siteId: '${j['siteId'] ?? ''}',
        itemId: '${j['itemId'] ?? ''}',
        title: '${j['title'] ?? ''}',
        poster: j['poster'] as String?,
        year: j['year'] as String?,
        remarks: j['remarks'] as String?,
        addedAt: DateTime.tryParse('${j['addedAt'] ?? ''}') ?? DateTime(2024),
      );
}

class HistoryEntry {
  const HistoryEntry({
    required this.siteId,
    required this.siteName,
    required this.itemId,
    required this.title,
    required this.lineIndex,
    required this.episodeIndex,
    required this.episodeName,
    required this.updatedAt,
    this.poster,
    this.positionSec = 0,
    this.durationSec = 0,
    this.lineName,
  });

  final String siteId;
  final String siteName;
  final String itemId;
  final String title;
  final String? poster;
  final int lineIndex;
  final int episodeIndex;
  final String episodeName;
  final String? lineName;
  final int positionSec;
  final int durationSec;
  final DateTime updatedAt;

  String get key => '$siteId::$itemId';

  double get progress =>
      durationSec <= 0 ? 0 : (positionSec / durationSec).clamp(0.0, 1.0);

  HistoryEntry copyWith({
    int? lineIndex,
    int? episodeIndex,
    String? episodeName,
    String? lineName,
    int? positionSec,
    int? durationSec,
    DateTime? updatedAt,
  }) {
    return HistoryEntry(
      siteId: siteId,
      siteName: siteName,
      itemId: itemId,
      title: title,
      poster: poster,
      lineIndex: lineIndex ?? this.lineIndex,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      episodeName: episodeName ?? this.episodeName,
      lineName: lineName ?? this.lineName,
      positionSec: positionSec ?? this.positionSec,
      durationSec: durationSec ?? this.durationSec,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'siteId': siteId,
        'siteName': siteName,
        'itemId': itemId,
        'title': title,
        if (poster != null) 'poster': poster,
        'lineIndex': lineIndex,
        'episodeIndex': episodeIndex,
        'episodeName': episodeName,
        if (lineName != null) 'lineName': lineName,
        'positionSec': positionSec,
        'durationSec': durationSec,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        siteId: '${j['siteId'] ?? ''}',
        siteName: '${j['siteName'] ?? ''}',
        itemId: '${j['itemId'] ?? ''}',
        title: '${j['title'] ?? ''}',
        poster: j['poster'] as String?,
        lineIndex: (j['lineIndex'] as num?)?.toInt() ?? 0,
        episodeIndex: (j['episodeIndex'] as num?)?.toInt() ?? 0,
        episodeName: '${j['episodeName'] ?? ''}',
        lineName: j['lineName'] as String?,
        positionSec: (j['positionSec'] as num?)?.toInt() ?? 0,
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse('${j['updatedAt'] ?? ''}') ?? DateTime(2024),
      );
}
