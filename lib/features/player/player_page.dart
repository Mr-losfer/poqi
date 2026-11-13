import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/poster.dart';
import '../../core/ui/primitives.dart';
import '../../state/player.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  VideoPlayerController? _video;
  String? _videoUrl;
  bool _videoFailed = false;

  bool _controlsVisible = true;
  bool _immersive = false;
  Timer? _hideTimer;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _armHideTimer();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.read(playerProvider.notifier).saveProgress();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _video?.dispose();
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (ref.read(playerProvider).playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _armHideTimer();
  }

  Future<void> _syncVideo(PlayerState ps) async {
    final url = ps.source?.url ?? '';
    final live = ps.mode == PlaybackMode.ready && (url.startsWith('http'));
    if (!live) {
      if (_video != null) {
        await _video!.dispose();
        _video = null;
        _videoUrl = null;
      }
      return;
    }
    if (_videoUrl == url && _video != null) return;

    await _video?.dispose();
    _video = null;
    _videoUrl = url;
    _videoFailed = false;
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: ps.source?.headers ?? const {},
      );
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _video = controller);
    } catch (_) {
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  Future<void> _toggleFullscreen() async {
    if (PqAdaptive.isCompact(context)) {
      final next = !_immersive;
      setState(() => _immersive = next);
      if (next) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    } else {
      setState(() => _immersive = !_immersive);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final ps = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    // 只在新片源出现时初始化播放器
    if (ps.mode == PlaybackMode.ready && ps.source?.url != _videoUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncVideo(ps));
    }

    final live = _video?.value.isInitialized == true;
    final duration = live ? _video!.value.duration : ps.duration;
    final position = live ? _video!.value.position : ps.position;
    final playing = live ? _video!.value.isPlaying : ps.playing;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) notifier.saveProgress();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Stage(
                state: ps,
                video: live ? _video : null,
                videoFailed: _videoFailed,
              ),
              // 控制层
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: _Controls(
                    state: ps,
                    position: position,
                    duration: duration,
                    playing: playing,
                    immersive: _immersive,
                    onBack: () async {
                      await notifier.saveProgress();
                      if (mounted) context.pop();
                    },
                    onToggle: () {
                      if (live) {
                        final v = _video!;
                        v.value.isPlaying ? v.pause() : v.play();
                        setState(() {});
                      }
                      notifier.togglePlay();
                      _armHideTimer();
                    },
                    onSeek: (d) {
                      if (live) {
                        _video!.seekTo(d);
                        setState(() {});
                      }
                      notifier.seek(d);
                    },
                    onPrev: () async {
                      await notifier.prevEpisode();
                      _videoUrl = null;
                    },
                    onNext: () async {
                      await notifier.nextEpisode();
                      _videoUrl = null;
                    },
                    onSpeed: (s) {
                      notifier.setSpeed(s);
                      _video?.setPlaybackSpeed(s);
                    },
                    onFullscreen: _toggleFullscreen,
                    onEpisodes: () => _showEpisodes(context),
                    onDiagnostics: () => _showDiagnostics(context),
                    onRetry: () {
                      _videoUrl = null;
                      _videoFailed = false;
                      notifier.retry();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEpisodes(BuildContext context) {
    final ps = ref.read(playerProvider);
    final detail = ps.detail;
    if (detail == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PqPalette.of(context).surfaceHigh,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Consumer(builder: (ctx, ref, _) {
          final current = ref.watch(playerProvider);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            maxChildSize: 0.9,
            minChildSize: 0.3,
            builder: (ctx, scroll) {
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: PqPalette.of(ctx).line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('选集', style: PqType.h2),
                  const SizedBox(height: 12),
                  for (var li = 0; li < detail.lines.length; li++) ...[
                    Text(
                      detail.lines[li].name,
                      style: PqType.label.copyWith(
                        color: PqPalette.of(ctx).textFaint,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var ei = 0; ei < detail.lines[li].episodes.length; ei++)
                          Builder(builder: (context) {
                            final active =
                                current.lineIndex == li && current.episodeIndex == ei;
                            final pp = PqPalette.of(context);
                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                _videoUrl = null;
                                ref.read(playerProvider.notifier).selectEpisode(li, ei);
                              },
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 64),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: active
                                      ? pp.accent.withOpacity(0.16)
                                      : pp.surfaceHigh,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: active
                                        ? pp.accent.withOpacity(0.55)
                                        : pp.lineSoft,
                                    width: 0.9,
                                  ),
                                ),
                                child: Text(
                                  detail.lines[li].episodes[ei].name,
                                  textAlign: TextAlign.center,
                                  style: PqType.label.copyWith(
                                    fontSize: 12,
                                    color: active ? pp.accent : pp.textMuted,
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              );
            },
          );
        });
      },
    );
  }

  void _showDiagnostics(BuildContext context) {
    final ps = ref.read(playerProvider);
    final p = PqPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surfaceHigh,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('播放诊断', style: PqType.h2),
            const SizedBox(height: 6),
            Text(
              '播放失败时会自动到其它站点寻找同一集。下面是本次尝试记录。',
              style: PqType.bodySmall.copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 16),
            if (ps.attempts.isEmpty)
              Text('暂无记录', style: PqType.bodySmall.copyWith(color: p.textFaint))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: ps.attempts.length,
                  separatorBuilder: (_, __) => Divider(color: p.lineSoft),
                  itemBuilder: (context, i) {
                    final a = ps.attempts[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Icon(
                            a.ok ? Icons.check_circle_outline : Icons.error_outline,
                            size: 16,
                            color: a.ok ? p.sage : p.danger,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${a.siteName} · ${a.episodeName}',
                                  style: PqType.bodySmall.copyWith(color: p.text, fontSize: 12.5),
                                ),
                                if (a.message != null)
                                  Text(
                                    a.message!,
                                    style: PqType.bodySmall.copyWith(
                                      color: p.textFaint,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            if (ps.source != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.canvas,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.lineSoft),
                ),
                child: Text(
                  ps.source!.url,
                  style: PqType.mono.copyWith(fontSize: 11, color: p.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.state, this.video, this.videoFailed = false});

  final PlayerState state;
  final VideoPlayerController? video;
  final bool videoFailed;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;

    Widget content;
    if (video != null) {
      content = Center(
        child: AspectRatio(
          aspectRatio: video!.value.aspectRatio == 0 ? 16 / 9 : video!.value.aspectRatio,
          child: VideoPlayer(video!),
        ),
      );
    } else if (state.mode == PlaybackMode.failed) {
      content = Center(child: _FailedCard(state: state));
    } else if (state.mode == PlaybackMode.resolving || state.mode == PlaybackMode.idle) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 16),
            Text(
              state.fallbackNote ?? '正在解析片源…',
              style: PqType.bodySmall.copyWith(color: p.textMuted),
            ),
            if (state.attempts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                state.attempts.map((e) => e.siteName).join(' → '),
                style: PqType.eyebrow.copyWith(color: p.textFaint),
              ),
            ],
          ],
        ),
      );
    } else {
      // 模拟放映：没有真实视频流时的放映室氛围
      content = Stack(
        fit: StackFit.expand,
        children: [
          PosterArt(
            title: state.item?.title ?? 'Poqi',
            seed: '${state.site?.id}-${state.item?.title}',
            radius: 0,
            glyphSize: 0.55,
            dim: 0.35,
          ),
          const _Scanlines(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.35),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Icon(
                    state.playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                    color: Colors.white.withOpacity(0.9),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  state.episode?.name ?? '演示片源',
                  style: PqType.title.copyWith(color: Colors.white.withOpacity(0.9)),
                ),
                const SizedBox(height: 4),
                Text(
                  '内置演示源 · 无真实视频流',
                  style: PqType.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (videoFailed && state.mode == PlaybackMode.ready) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 34, color: p.textMuted),
            const SizedBox(height: 12),
            Text('该设备无法解码此片源', style: PqType.title),
            const SizedBox(height: 6),
            Text(
              '可以换一条线路或其它站点再试',
              style: PqType.bodySmall.copyWith(color: p.textFaint),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: w > 1100 ? 1180 : w,
            maxHeight: h,
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _Scanlines extends StatefulWidget {
  const _Scanlines();

  @override
  State<_Scanlines> createState() => _ScanlinesState();
}

class _ScanlinesState extends State<_Scanlines> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ScanlinePainter(_c.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1;
    for (var i = 0; i < 22; i++) {
      final y = size.height * i / 22;
      paint.color = Colors.white.withOpacity(0.018 + (i % 3) * 0.006);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // 缓慢移动的光带
    final y = size.height * t;
    final rect = Rect.fromLTWH(0, y - 60, size.width, 120);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0),
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter old) => old.t != t;
}

class _FailedCard extends StatelessWidget {
  const _FailedCard({required this.state});

  final PlayerState state;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: p.surfaceHigh.withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.portable_wifi_off_rounded, size: 30, color: p.danger),
          const SizedBox(height: 12),
          Text('这一集暂时放不出来', style: PqType.h2.copyWith(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            state.error ?? '所有站点都没有返回可用的播放地址',
            textAlign: TextAlign.center,
            style: PqType.bodySmall.copyWith(color: p.textMuted, height: 1.6),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('返回详情'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.position,
    required this.duration,
    required this.playing,
    required this.immersive,
    required this.onBack,
    required this.onToggle,
    required this.onSeek,
    required this.onPrev,
    required this.onNext,
    required this.onSpeed,
    required this.onFullscreen,
    required this.onEpisodes,
    required this.onDiagnostics,
    required this.onRetry,
  });

  final PlayerState state;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool immersive;
  final Future<void> Function() onBack;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<double> onSpeed;
  final VoidCallback onFullscreen;
  final VoidCallback onEpisodes;
  final VoidCallback onDiagnostics;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final total = duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;
    final progress = (position.inMilliseconds / total).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.55),
            Colors.black.withOpacity(0.0),
            Colors.black.withOpacity(0.0),
            Colors.black.withOpacity(0.78),
          ],
          stops: const [0, 0.24, 0.6, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
              child: Row(
                children: [
                  PqIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => onBack(),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.item?.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PqType.title.copyWith(color: Colors.white),
                        ),
                        Text(
                          [
                            state.site?.name ?? '',
                            state.line?.name ?? '',
                            state.episode?.name ?? '',
                          ].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PqType.bodySmall.copyWith(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.mode == PlaybackMode.simulated)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withOpacity(0.14)),
                      ),
                      child: Text(
                        '演示片源',
                        style: PqType.label.copyWith(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: onDiagnostics,
                    icon: const Icon(Icons.monitor_heart_outlined, size: 18),
                    color: Colors.white.withOpacity(0.7),
                    tooltip: '播放诊断',
                  ),
                ],
              ),
            ),
            const Spacer(),
            // 中央播放键
            if (!playing && state.mode != PlaybackMode.failed)
              GestureDetector(
                onTap: onToggle,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.accent,
                    boxShadow: [
                      BoxShadow(
                        color: p.accent.withOpacity(0.35),
                        blurRadius: 32,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(Icons.play_arrow_rounded, size: 36, color: p.onAccent),
                ),
              ),
            if (state.mode == PlaybackMode.failed)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新尝试'),
              ),
            const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 0, compact ? 12 : 20, 10),
              child: Column(
                children: [
                  _Scrubber(
                    progress: progress,
                    onSeek: (f) => onSeek(
                      Duration(milliseconds: (total * f).round()),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      IconButton(
                        onPressed: onToggle,
                        icon: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 24,
                        ),
                        color: Colors.white,
                        tooltip: playing ? '暂停' : '播放',
                      ),
                      IconButton(
                        onPressed: onPrev,
                        icon: const Icon(Icons.skip_previous_rounded, size: 21),
                        color: Colors.white.withOpacity(0.8),
                        tooltip: '上一集',
                      ),
                      IconButton(
                        onPressed: onNext,
                        icon: const Icon(Icons.skip_next_rounded, size: 21),
                        color: Colors.white.withOpacity(0.8),
                        tooltip: '下一集',
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_fmt(position)} / ${duration.inSeconds == 0 ? '--:--' : _fmt(duration)}',
                        style: PqType.mono.copyWith(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      if (!compact) ...[
                        _GhostButton(
                          label: '选集',
                          icon: Icons.list_rounded,
                          onTap: onEpisodes,
                        ),
                        const SizedBox(width: 8),
                        _SpeedMenu(speed: state.speed, onChanged: onSpeed),
                        const SizedBox(width: 8),
                      ] else
                        _GhostButton(
                          label: '选集',
                          icon: Icons.list_rounded,
                          onTap: onEpisodes,
                        ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: onFullscreen,
                        icon: Icon(
                          immersive
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          size: 21,
                        ),
                        color: Colors.white.withOpacity(0.8),
                        tooltip: '全屏',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.progress, required this.onSeek});

  final double progress;
  final ValueChanged<double> onSeek;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final value = _dragging ?? widget.progress;
    return LayoutBuilder(
      builder: (context, c) {
        void seek(double dx) {
          final f = (dx / c.maxWidth).clamp(0.0, 1.0);
          setState(() => _dragging = f);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seek(d.localPosition.dx),
          onTapUp: (d) {
            widget.onSeek((d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0));
            setState(() => _dragging = null);
          },
          onHorizontalDragStart: (d) => seek(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
          onHorizontalDragEnd: (_) {
            widget.onSeek(value);
            setState(() => _dragging = null);
          },
          child: SizedBox(
            height: 22,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment(value.clamp(0.0, 1.0) * 2 - 1, 0),
                  child: Container(
                    width: _dragging != null ? 13 : 9,
                    height: _dragging != null ? 13 : 9,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: PqType.label.copyWith(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withOpacity(0.78),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}

class _SpeedMenu extends StatelessWidget {
  const _SpeedMenu({required this.speed, required this.onChanged});

  final double speed;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: '倍速',
      color: PqPalette.of(context).surfaceHigher,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          PopupMenuItem(
            value: s,
            child: Text(
              '${s}x',
              style: PqType.bodySmall.copyWith(
                color: s == speed ? PqPalette.of(context).accent : null,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.speed_rounded, size: 16, color: Colors.white.withOpacity(0.78)),
            const SizedBox(width: 5),
            Text(
              '${speed}x',
              style: PqType.label.copyWith(fontSize: 12, color: Colors.white.withOpacity(0.78)),
            ),
          ],
        ),
      ),
    );
  }
}
