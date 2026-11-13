import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/ui/adaptive.dart';
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
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return Consumer(builder: (ctx, ref, _) {
          final theme = Theme.of(ctx);
          final current = ref.watch(playerProvider);
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text('选集', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                for (var li = 0; li < detail.lines.length; li++) ...[
                  Text(
                    detail.lines[li].name,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var ei = 0; ei < detail.lines[li].episodes.length; ei++)
                        ChoiceChip(
                          label: Text(detail.lines[li].episodes[ei].name),
                          selected:
                              current.lineIndex == li && current.episodeIndex == ei,
                          onSelected: (_) {
                            Navigator.pop(ctx);
                            _videoUrl = null;
                            ref.read(playerProvider.notifier).selectEpisode(li, ei);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          );
        });
      },
    );
  }

  void _showDiagnostics(BuildContext context) {
    final ps = ref.read(playerProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('播放诊断', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '播放失败时会自动到其它站点寻找同一集。下面是本次尝试记录。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              if (ps.attempts.isEmpty)
                Text(
                  '暂无记录',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < ps.attempts.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            ps.attempts[i].ok
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: ps.attempts[i].ok ? scheme.tertiary : scheme.error,
                          ),
                          title: Text(
                            '${ps.attempts[i].siteName} · ${ps.attempts[i].episodeName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: ps.attempts[i].message == null
                              ? null
                              : Text(
                                  ps.attempts[i].message!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ps.attempts[i].ok
                                        ? scheme.onSurfaceVariant
                                        : scheme.error,
                                  ),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (ps.source != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText(
                        ps.source!.url,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
    final theme = Theme.of(context);
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
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            if (state.attempts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                state.attempts.map((e) => e.siteName).join(' → '),
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.white54),
              ),
            ],
          ],
        ),
      );
    } else {
      // 模拟放映：没有真实视频流时的海报舞台
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
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.black45,
                  child: Icon(Icons.play_arrow, size: 32, color: Colors.white),
                ),
                if (state.playing)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Icon(Icons.graphic_eq, size: 20, color: Colors.white70),
                  ),
                const SizedBox(height: 14),
                Text(
                  state.episode?.name ?? '演示片源',
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  '内置演示源 · 无真实视频流',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
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
            const Icon(Icons.videocam_off_outlined, size: 34, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              '该设备无法解码此片源',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              '可以换一条线路或其它站点再试',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return ColoredBox(
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

class _FailedCard extends StatelessWidget {
  const _FailedCard({required this.state});

  final PlayerState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.portable_wifi_off_outlined, size: 30, color: scheme.error),
              const SizedBox(height: 12),
              Text('这一集暂时放不出来', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                state.error ?? '所有站点都没有返回可用的播放地址',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => context.pop(),
                child: const Text('返回详情'),
              ),
            ],
          ),
        ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;
    final progress = (position.inMilliseconds / total).clamp(0.0, 1.0);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => onBack(),
                      icon: const Icon(Icons.arrow_back),
                      color: Colors.white,
                      tooltip: '返回',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.item?.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: Colors.white),
                          ),
                          Text(
                            [
                              state.site?.name ?? '',
                              state.line?.name ?? '',
                              state.episode?.name ?? '',
                            ].where((e) => e.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    if (state.mode == PlaybackMode.simulated)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: PqTag('演示片源'),
                      ),
                    IconButton(
                      onPressed: onDiagnostics,
                      icon: const Icon(Icons.monitor_heart_outlined),
                      color: Colors.white70,
                      tooltip: '播放诊断',
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            // 中央播放键
            if (!playing && state.mode != PlaybackMode.failed)
              IconButton.filled(
                onPressed: onToggle,
                icon: const Icon(Icons.play_arrow),
                iconSize: 36,
                tooltip: '播放',
                style: IconButton.styleFrom(
                  minimumSize: const Size(68, 68),
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                ),
              ),
            if (state.mode == PlaybackMode.failed)
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            const Spacer(),
            Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Column(
                  children: [
                    _Scrubber(
                      scheme: scheme,
                      progress: progress,
                      onSeek: (f) => onSeek(
                        Duration(milliseconds: (total * f).round()),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: onToggle,
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          color: Colors.white,
                          tooltip: playing ? '暂停' : '播放',
                        ),
                        IconButton(
                          onPressed: onPrev,
                          icon: const Icon(Icons.skip_previous),
                          color: Colors.white70,
                          tooltip: '上一集',
                        ),
                        IconButton(
                          onPressed: onNext,
                          icon: const Icon(Icons.skip_next),
                          color: Colors.white70,
                          tooltip: '下一集',
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_fmt(position)} / ${duration.inSeconds == 0 ? '--:--' : _fmt(duration)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            color: Colors.white70,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: onEpisodes,
                          icon: const Icon(Icons.list, size: 18),
                          label: const Text('选集'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        PopupMenuButton<double>(
                          tooltip: '倍速',
                          icon: const Icon(Icons.speed, color: Colors.white70),
                          onSelected: onSpeed,
                          itemBuilder: (context) => [
                            for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                              CheckedPopupMenuItem<double>(
                                value: s,
                                checked: s == state.speed,
                                child: Text('${s}x'),
                              ),
                          ],
                        ),
                        IconButton(
                          onPressed: onFullscreen,
                          icon: Icon(
                            immersive
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                          color: Colors.white70,
                          tooltip: '全屏',
                        ),
                      ],
                    ),
                  ],
                ),
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
  const _Scrubber({
    required this.scheme,
    required this.progress,
    required this.onSeek,
  });

  final ColorScheme scheme;
  final double progress;
  final ValueChanged<double> onSeek;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.progress).clamp(0.0, 1.0);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        activeTrackColor: widget.scheme.primary,
        inactiveTrackColor: Colors.white24,
        thumbColor: widget.scheme.primary,
        overlayColor: widget.scheme.primary.withOpacity(0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
        value: value,
        onChanged: (v) => setState(() => _dragging = v),
        onChangeEnd: (v) {
          widget.onSeek(v);
          setState(() => _dragging = null);
        },
      ),
    );
  }
}
