import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/states.dart';
import '../../state/home_search.dart';
import '../media/nav.dart';
import '../media/widgets.dart';

/// 热门建议词：给出可点击的起点，避免空白输入框。
const _hotWords = <String>['长夜将尽', '星屑旅团', '人间烟火档案', '雾中灯塔', '山海之间', '暗涌'];

class SearchPage extends StatelessWidget {
  const SearchPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  Widget build(BuildContext context) => _SearchBody(initialQuery: initialQuery);
}

class _SearchBody extends ConsumerStatefulWidget {
  const _SearchBody({this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends ConsumerState<_SearchBody> {
  late final TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialQuery ?? '').trim();
    final existing = ref.read(searchProvider).keyword;
    // 没有新关键词时沿用上一次的检索，保证输入框与结果一致。
    _controller = TextEditingController(text: initial.isNotEmpty ? initial : existing);
    _hasText = _controller.text.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
    if (initial.isNotEmpty && initial != existing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(searchProvider.notifier).search(initial);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _SearchBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = (widget.initialQuery ?? '').trim();
    final prev = (oldWidget.initialQuery ?? '').trim();
    if (next.isNotEmpty && next != prev) {
      _controller.text = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(searchProvider.notifier).search(next);
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _submit(String raw) {
    final q = raw.trim();
    if (q.isEmpty) {
      ref.read(searchProvider.notifier).clear();
      return;
    }
    ref.read(searchProvider.notifier).search(q);
  }

  void _runWord(String word) {
    _controller.text = word;
    _controller.selection = TextSelection.collapsed(offset: word.length);
    ref.read(searchProvider.notifier).search(word);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _clear() {
    _controller.clear();
    ref.read(searchProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final state = ref.watch(searchProvider);
    final compact = PqAdaptive.isCompact(context);

    return Scaffold(
      backgroundColor: p.canvas,
      body: PqBackdrop(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: PqContent(
                  maxWidth: 1320,
                  child: _head(context, p, compact),
                ),
              ),
              SliverToBoxAdapter(
                child: PqContent(maxWidth: 1320, child: _status(p, state)),
              ),
              SliverToBoxAdapter(
                child: PqContent(
                  maxWidth: 1320,
                  child: PqAnimatedSwap(
                    child: KeyedSubtree(
                      key: ValueKey(_phaseOf(state)),
                      child: _body(context, p, state),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: PqContent(maxWidth: 1320, child: _footer(p, state)),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: 40 + MediaQuery.paddingOf(context).bottom),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _phaseOf(SearchState state) {
    if (state.keyword.isEmpty) return 'idle';
    if (state.running && state.results.isEmpty) return 'searching';
    if (state.results.isEmpty) return 'empty';
    return 'grid-${state.keyword}';
  }

  Widget _head(BuildContext context, PqPalette p, bool compact) {
    return Padding(
      padding: EdgeInsets.only(top: compact ? 12 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PqIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: '返回',
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PqSearchField(
                  controller: _controller,
                  autofocus: true,
                  hint: '搜索影片、演员、站点…',
                  onSubmit: _submit,
                  showShortcut: !compact,
                ),
              ),
              const SizedBox(width: 4),
              _ClearButton(enabled: _hasText, onTap: _clear),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '热门',
                style: PqType.eyebrow.copyWith(color: p.textFaint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final word in _hotWords)
                      _HotChip(label: word, onTap: () => _runWord(word)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _status(PqPalette p, SearchState state) {
    final hasKeyword = state.keyword.isNotEmpty;
    if (!hasKeyword) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.running)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(minHeight: 2),
            ),
          if (state.running) const SizedBox(height: 14),
          if (state.sites.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final site in state.sites) _SiteChip(status: site),
              ],
            ),
          if (state.running && state.results.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '已到达 ${state.results.length} 条，仍在继续…',
              style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(BuildContext context, PqPalette p, SearchState state) {
    if (state.keyword.isEmpty) {
      return const PqEmptyState(
        compact: true,
        icon: Icons.travel_explore_rounded,
        title: '从一个关键词开始',
        message: '输入片名、演员或站点，Poqi 会同时向所有已启用站点检索。',
      );
    }

    if (state.running && state.results.isEmpty) {
      return PqLoadingLine(label: '正在向 ${state.sites.length} 个站点检索…');
    }

    if (state.results.isEmpty) {
      return PqEmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到「${state.keyword}」',
        message: '换个关键词试试，或到插件页确认站点已启用并且声明了搜索端点。',
        action: FilledButton(
          onPressed: () => context.go('/plugins'),
          child: const Text('检查站点'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: MediaGrid(
        items: state.results,
        onTap: (item) => openDetail(context, item),
      ),
    );
  }

  Widget _footer(PqPalette p, SearchState state) {
    if (state.results.isEmpty) return const SizedBox.shrink();
    final sources = <String>{
      for (final item in state.results)
        if (item.sourceId != null && item.sourceId!.isNotEmpty) item.sourceId!,
    }.length;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: p.lineSoft, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${state.results.length} 个结果 · 来自 $sources 个站点',
                  style: PqType.bodySmall.copyWith(color: p.textMuted, fontSize: 12),
                ),
              ),
              Text(
                '用时 ${_elapsed(state.elapsedMs)}',
                style: PqType.mono.copyWith(fontSize: 11, color: p.textFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _elapsed(int ms) {
    if (ms <= 0) return '0ms';
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms}ms';
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return TextButton(
      onPressed: enabled ? onTap : null,
      style: TextButton.styleFrom(
        foregroundColor: p.textMuted,
        disabledForegroundColor: p.textFaint.withOpacity(0.45),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('清除'),
    );
  }
}

class _HotChip extends StatelessWidget {
  const _HotChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return PqPressable(
      onTap: onTap,
      borderRadius: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.lineSoft, width: 0.9),
        ),
        child: Text(
          label,
          style: PqType.label.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: p.textMuted,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// 单站点状态：状态点颜色区分 pending / running / done / failed。
class _SiteChip extends StatelessWidget {
  const _SiteChip({required this.status});

  final SiteSearchStatus status;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final color = switch (status.state) {
      SiteQueryState.done => p.sage,
      SiteQueryState.failed => p.danger,
      SiteQueryState.running => p.accent,
      SiteQueryState.pending => p.textFaint,
    };
    final detail = switch (status.state) {
      SiteQueryState.done =>
        status.count > 0 ? '${status.count} 条 · ${status.ms}ms' : '无结果',
      SiteQueryState.failed => '失败',
      SiteQueryState.running => '查询中',
      SiteQueryState.pending => '等待',
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: status.state == SiteQueryState.failed
              ? p.danger.withOpacity(0.32)
              : p.lineSoft,
          width: 0.9,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.state == SiteQueryState.failed)
            Icon(Icons.priority_high_rounded, size: 12, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          const SizedBox(width: 6),
          Text(
            status.siteName,
            style: PqType.label.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: p.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            detail,
            style: PqType.mono.copyWith(fontSize: 10, height: 1.2, color: color),
          ),
        ],
      ),
    );

    final message = status.message;
    if (message == null || message.isEmpty) return chip;
    return Tooltip(message: message, child: chip);
  }
}
