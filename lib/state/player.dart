import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/net/pq_http.dart';
import '../domain/models/media.dart';
import '../domain/models/site.dart';
import 'providers.dart';

enum PlaybackMode { idle, resolving, ready, simulated, failed }

class PlayAttempt {
  const PlayAttempt({
    required this.siteName,
    required this.episodeName,
    required this.ok,
    this.message,
  });

  final String siteName;
  final String episodeName;
  final bool ok;
  final String? message;
}

class PlayerState {
  const PlayerState({
    this.site,
    this.item,
    this.detail,
    this.lineIndex = 0,
    this.episodeIndex = 0,
    this.source,
    this.mode = PlaybackMode.idle,
    this.error,
    this.attempts = const [],
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
    this.fallbackNote,
  });

  final SiteBinding? site;
  final MediaItem? item;
  final MediaDetail? detail;
  final int lineIndex;
  final int episodeIndex;
  final PlaySource? source;
  final PlaybackMode mode;
  final String? error;
  final List<PlayAttempt> attempts;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double speed;
  final String? fallbackNote;

  PlayLine? get line =>
      detail == null || detail!.lines.isEmpty ? null : detail!.lines[lineIndex.clamp(0, detail!.lines.length - 1)];

  Episode? get episode {
    final l = line;
    if (l == null || l.episodes.isEmpty) return null;
    return l.episodes[episodeIndex.clamp(0, l.episodes.length - 1)];
  }

  bool get isSimulated => mode == PlaybackMode.simulated;
  bool get hasSource => source != null && source!.url.isNotEmpty;

  PlayerState copyWith({
    SiteBinding? site,
    MediaItem? item,
    MediaDetail? detail,
    int? lineIndex,
    int? episodeIndex,
    PlaySource? source,
    PlaybackMode? mode,
    String? error,
    List<PlayAttempt>? attempts,
    bool? playing,
    Duration? position,
    Duration? duration,
    double? speed,
    String? fallbackNote,
  }) {
    return PlayerState(
      site: site ?? this.site,
      item: item ?? this.item,
      detail: detail ?? this.detail,
      lineIndex: lineIndex ?? this.lineIndex,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      source: source ?? this.source,
      mode: mode ?? this.mode,
      error: error,
      attempts: attempts ?? this.attempts,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      fallbackNote: fallbackNote ?? this.fallbackNote,
    );
  }
}

final playerProvider = NotifierProvider<PlayerController, PlayerState>(
  PlayerController.new,
);

class PlayerController extends Notifier<PlayerState> {
  Timer? _clock;
  final List<PlayAttempt> _attempts = [];

  @override
  PlayerState build() {
    ref.onDispose(() => _clock?.cancel());
    return const PlayerState();
  }

  Future<void> open({
    required SiteBinding site,
    required MediaItem item,
    int lineIndex = 0,
    int episodeIndex = 0,
  }) async {
    _clock?.cancel();
    _attempts.clear();
    state = PlayerState(
      site: site,
      item: item,
      mode: PlaybackMode.resolving,
      lineIndex: lineIndex,
      episodeIndex: episodeIndex,
    );

    final backend = ref.read(backendProvider);
    MediaDetail? detail;
    try {
      detail = await backend.detailOf(site, item.id);
    } catch (e) {
      detail = null;
      state = state.copyWith(error: '详情加载失败：$e');
    }

    state = state.copyWith(detail: detail);
    if (detail == null || detail.lines.isEmpty) {
      await _fallback(item, reason: '该站点没有可用剧集');
      return;
    }
    await _play(lineIndex, episodeIndex);
  }

  Future<void> selectEpisode(int line, int ep) async {
    if (state.detail == null) return;
    state = state.copyWith(lineIndex: line, episodeIndex: ep, position: Duration.zero);
    await _play(line, ep);
  }

  Future<void> nextEpisode() async {
    final l = state.line;
    if (l == null) return;
    if (state.episodeIndex + 1 < l.episodes.length) {
      await selectEpisode(state.lineIndex, state.episodeIndex + 1);
    }
  }

  Future<void> prevEpisode() async {
    if (state.episodeIndex > 0) {
      await selectEpisode(state.lineIndex, state.episodeIndex - 1);
    }
  }

  Future<void> _play(int lineIndex, int episodeIndex) async {
    final site = state.site;
    final detail = state.detail;
    if (site == null || detail == null) return;

    final line = detail.lines[lineIndex.clamp(0, detail.lines.length - 1)];
    if (line.episodes.isEmpty) {
      await _fallback(state.item!, reason: '剧集列表为空');
      return;
    }
    final ep = line.episodes[episodeIndex.clamp(0, line.episodes.length - 1)];

    state = state.copyWith(
      mode: PlaybackMode.resolving,
      lineIndex: lineIndex,
      episodeIndex: episodeIndex,
      error: null,
    );

    final runner = ref.read(backendProvider).runnerOf(site);
    try {
      if (runner == null) throw PqHttpException('插件缺失');
      final source = await runner.play(ep.url);
      _attempts.add(PlayAttempt(
        siteName: site.name,
        episodeName: ep.name,
        ok: true,
      ));
      final simulated = source.url.startsWith('demo://');
      state = state.copyWith(
        source: source,
        mode: simulated ? PlaybackMode.simulated : PlaybackMode.ready,
        attempts: List.of(_attempts),
        playing: true,
        duration: simulated ? const Duration(minutes: 45) : Duration.zero,
        position: Duration.zero,
      );
      if (simulated) _startClock();
    } catch (e) {
      _attempts.add(PlayAttempt(
        siteName: site.name,
        episodeName: ep.name,
        ok: false,
        message: '$e',
      ));
      state = state.copyWith(attempts: List.of(_attempts));
      await _fallback(state.item!, reason: '当前线路播放失败');
    }
  }

  /// 播放失败时，用片名到其它站点循环找同一集。
  Future<void> _fallback(MediaItem item, {required String reason}) async {
    state = state.copyWith(
      mode: PlaybackMode.resolving,
      fallbackNote: '正在其它站点寻找《${item.title}》…',
    );
    final backend = ref.read(backendProvider);
    final targetEp = state.episodeIndex;

    List<MediaItem> candidates;
    try {
      candidates = await backend.otherSources(item, limit: 5);
    } catch (_) {
      candidates = const [];
    }

    for (final cand in candidates) {
      final site = backend.sites().where((s) => s.id == cand.sourceId).firstOrNull;
      if (site == null) continue;
      try {
        final detail = await backend.detailOf(site, cand.id);
        if (detail == null || detail.lines.isEmpty) continue;
        final runner = backend.runnerOf(site);
        if (runner == null) continue;
        final line = detail.lines.first;
        if (line.episodes.isEmpty) continue;
        final ep = line.episodes[targetEp.clamp(0, line.episodes.length - 1)];
        final source = await runner.play(ep.url);
        _attempts.add(PlayAttempt(
          siteName: site.name,
          episodeName: ep.name,
          ok: true,
          message: '自动切换',
        ));
        final simulated = source.url.startsWith('demo://');
        state = state.copyWith(
          site: site,
          detail: detail,
          item: cand,
          lineIndex: 0,
          episodeIndex: targetEp,
          source: source,
          mode: simulated ? PlaybackMode.simulated : PlaybackMode.ready,
          attempts: List.of(_attempts),
          fallbackNote: '已自动切换到「${site.name}」',
          playing: true,
          duration: simulated ? const Duration(minutes: 45) : Duration.zero,
          position: Duration.zero,
        );
        if (simulated) _startClock();
        return;
      } catch (e) {
        _attempts.add(PlayAttempt(
          siteName: site.name,
          episodeName: '第 ${targetEp + 1} 集',
          ok: false,
          message: '$e',
        ));
      }
    }

    state = state.copyWith(
      mode: PlaybackMode.failed,
      error: '$reason，且未找到其它可用片源',
      attempts: List.of(_attempts),
      playing: false,
    );
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.playing) return;
      final next = state.position + Duration(seconds: (1 * state.speed).round());
      if (next >= state.duration) {
        state = state.copyWith(position: state.duration, playing: false);
        _clock?.cancel();
        nextEpisode();
        return;
      }
      state = state.copyWith(position: next);
    });
  }

  void togglePlay() {
    if (state.mode == PlaybackMode.failed) return;
    state = state.copyWith(playing: !state.playing);
  }

  void seek(Duration p) {
    final clamped = p < Duration.zero
        ? Duration.zero
        : (p > state.duration && state.duration > Duration.zero ? state.duration : p);
    state = state.copyWith(position: clamped);
  }

  void setSpeed(double speed) => state = state.copyWith(speed: speed);

  Future<void> retry() async {
    if (state.site != null && state.item != null) {
      await open(
        site: state.site!,
        item: state.item!,
        lineIndex: state.lineIndex,
        episodeIndex: state.episodeIndex,
      );
    }
  }

  Future<void> saveProgress() async {
    final site = state.site;
    final item = state.item;
    final line = state.line;
    final ep = state.episode;
    if (site == null || item == null || line == null || ep == null) return;
    await ref.read(backendProvider).recordPlay(
          site: site,
          item: item,
          line: line,
          episode: ep,
          lineIndex: state.lineIndex,
          positionSec: state.position.inSeconds,
          durationSec: state.duration.inSeconds,
        );
    ref.read(historyProvider.notifier).reload();
  }

  void reset() {
    _clock?.cancel();
    _attempts.clear();
    state = const PlayerState();
  }
}
