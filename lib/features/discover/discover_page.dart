import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/states.dart';
import '../../data/backend.dart';
import '../../domain/models/media.dart';
import '../../state/providers.dart';
import '../media/nav.dart';
import '../media/widgets.dart';
import '../shell/pq_shell.dart';

const _kinds = <String>['全部', '电影', '剧集', '动漫', '综艺', '纪录片'];

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key, this.initialKind});

  final String? initialKind;

  @override
  Widget build(BuildContext context) => _DiscoverBody(initialKind: initialKind);
}

/// 分类页：一次筛选，向所有已启用站点并发取分类结果。
class _DiscoverBody extends ConsumerStatefulWidget {
  const _DiscoverBody({this.initialKind});

  final String? initialKind;

  @override
  ConsumerState<_DiscoverBody> createState() => _DiscoverBodyState();
}

class _DiscoverBodyState extends ConsumerState<_DiscoverBody> {
  late int _index;
  bool _loading = true;
  List<MediaItem> _items = const [];
  List<String> _failed = const [];
  int _attempted = 0;
  int _round = 0;

  @override
  void initState() {
    super.initState();
    final raw = widget.initialKind;
    final i = raw == null || raw.isEmpty ? -1 : _kinds.indexOf(raw);
    _index = i < 0 ? 0 : i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant _DiscoverBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final raw = widget.initialKind;
    final next = raw == null || raw.isEmpty ? 0 : _kinds.indexOf(raw).clamp(0, _kinds.length - 1);
    if (next != _index) {
      _index = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final round = ++_round;
    final kind = _index == 0 ? null : _kinds[_index];
    final sites = ref.read(sitesProvider).where((s) => s.enabled).toList();
    final factory = ref.read(runnerFactoryProvider);

    setState(() {
      _loading = true;
      _failed = const [];
    });

    final failures = <String>[];
    var attempted = 0;

    final chunks = await Future.wait(sites.map((site) async {
      final runner = factory(site);
      if (runner == null) {
        failures.add(site.name);
        attempted++;
        return const <MediaItem>[];
      }
      // 未声明分类端点的站点不算失败，直接跳过。
      if (!runner.plugin.supportsCategory) return const <MediaItem>[];
      attempted++;
      try {
        final page = await runner.category(kind: kind);
        return page.items;
      } catch (_) {
        failures.add(site.name);
        return const <MediaItem>[];
      }
    }));

    if (!mounted || round != _round) return;

    final merged = <MediaItem>[];
    for (final list in chunks) {
      merged.addAll(list);
    }

    setState(() {
      _loading = false;
      _items = PoqiBackend.dedupe(merged);
      _failed = failures;
      _attempted = attempted;
    });
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _load();
  }

  bool get _allFailed =>
      _attempted > 0 && _items.isEmpty && _failed.length >= _attempted;

  int get _sourceCount {
    final ids = <String>{};
    for (final item in _items) {
      final id = item.sourceId;
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids.length;
  }

  String get _phase {
    if (_loading) return 'loading';
    if (_allFailed) return 'error';
    if (_items.isEmpty) return 'empty';
    return 'grid-$_index';
  }

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final top = compact ? MediaQuery.paddingOf(context).top + 10 : 18.0;

    return PqBackdrop(
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: PqContent(
              child: Padding(
                padding: EdgeInsets.only(top: top),
                child: PqPageHeader(
                  eyebrow: 'LIBRARY',
                  title: '分类',
                  subtitle: '跨站点浏览，一处筛选，全部源生效',
                  actions: [
                    PqIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: '重新聚合',
                      onTap: _loading ? null : _load,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: PqContent(child: _filterBar(context, p, compact)),
          ),
          SliverToBoxAdapter(
            child: PqContent(
              child: PqAnimatedSwap(
                child: KeyedSubtree(
                  key: ValueKey(_phase),
                  child: _phaseView(context, p),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: PqContent(child: _footer(p))),
          SliverToBoxAdapter(
            child: SizedBox(height: 40 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(BuildContext context, PqPalette p, bool compact) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: PqSegmented(
                items: _kinds,
                index: _index,
                compact: compact,
                onChanged: _select,
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 16),
            Text(
              _loading ? '聚合中' : '${_items.length} 部',
              style: PqType.eyebrow.copyWith(color: p.textFaint, letterSpacing: 1.2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _phaseView(BuildContext context, PqPalette p) {
    if (_loading) {
      return LayoutBuilder(
        builder: (context, c) {
          final cols = PqAdaptive.columnsFor(c.maxWidth);
          return PqPosterGridSkeleton(count: cols * 2, columns: cols);
        },
      );
    }

    if (_allFailed) {
      return PqErrorState(
        message: '${_failed.join('、')} 都没有返回内容，可能是网络或站点配置的问题。',
        onRetry: _load,
      );
    }

    if (_items.isEmpty) {
      return PqEmptyState(
        icon: Icons.video_library_outlined,
        title: _attempted == 0 ? '还没有可用的分类源' : '这一类暂时没有内容',
        message: _attempted == 0
            ? '去「插件」页启用站点，并确认插件声明了分类端点。'
            : '换个类型试试，或到插件页检查站点是否正常。',
        action: FilledButton(
          onPressed: () => context.go('/plugins'),
          child: const Text('前往插件工坊'),
        ),
      );
    }

    return MediaGrid(
      items: _items,
      onTap: (item) => openDetail(context, item),
    );
  }

  Widget _footer(PqPalette p) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: p.lineSoft, height: 1),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '共 ${_items.length} 部 · 来自 $_sourceCount 个站点',
                style: PqType.bodySmall.copyWith(color: p.textMuted, fontSize: 12),
              ),
              if (_failed.isNotEmpty)
                Text(
                  '${_failed.join('、')} 本次未响应，已跳过',
                  style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
