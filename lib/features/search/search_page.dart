import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(searchProvider);
    final compact = PqAdaptive.isCompact(context);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: PqBackdrop(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: PqContent(
                  maxWidth: 1320,
                  child: _head(context, compact),
                ),
              ),
              SliverToBoxAdapter(
                child: PqContent(maxWidth: 1320, child: _status(context, state)),
              ),
              SliverToBoxAdapter(
                child: PqContent(
                  maxWidth: 1320,
                  child: PqAnimatedSwap(
                    child: KeyedSubtree(
                      key: ValueKey(_phaseOf(state)),
                      child: _body(context, state),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: PqContent(maxWidth: 1320, child: _footer(context, state)),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: 32 + MediaQuery.paddingOf(context).bottom),
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

  Widget _head(BuildContext context, bool compact) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(top: compact ? 8 : 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SearchBar(
                  controller: _controller,
                  autoFocus: true,
                  hintText: '搜索影片、演员、站点…',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_hasText)
                      IconButton(
                        tooltip: '清除',
                        onPressed: _clear,
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
                  side: const WidgetStatePropertyAll(BorderSide.none),
                  textStyle: WidgetStatePropertyAll(theme.textTheme.bodyLarge),
                  constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
                  onSubmitted: _submit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '热门',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in _hotWords)
                ActionChip(
                  label: Text(word),
                  onPressed: () => _runWord(word),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _status(BuildContext context, SearchState state) {
    final theme = Theme.of(context);
    if (state.keyword.isEmpty) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.running)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 4),
            ),
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(BuildContext context, SearchState state) {
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
      padding: const EdgeInsets.only(top: 16),
      child: MediaGrid(
        items: state.results,
        onTap: (item) => openDetail(context, item),
      ),
    );
  }

  Widget _footer(BuildContext context, SearchState state) {
    final theme = Theme.of(context);
    if (state.results.isEmpty) return const SizedBox.shrink();
    final sources = <String>{
      for (final item in state.results)
        if (item.sourceId != null && item.sourceId!.isNotEmpty) item.sourceId!,
    }.length;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${state.results.length} 个结果 · 来自 $sources 个站点',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '用时 ${_elapsed(state.elapsedMs)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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

/// 单站点状态：状态信息用 ActionChip 的 leading 图标表达。
class _SiteChip extends StatelessWidget {
  const _SiteChip({required this.status});

  final SiteSearchStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (IconData icon, Color color, String detail) = switch (status.state) {
      SiteQueryState.done => (
          Icons.check_circle_outline,
          scheme.tertiary,
          status.count > 0 ? '${status.count} 条 · ${status.ms}ms' : '无结果',
        ),
      SiteQueryState.failed => (
          Icons.error_outline,
          scheme.error,
          '失败',
        ),
      SiteQueryState.running => (
          Icons.hourglass_empty,
          scheme.primary,
          '查询中',
        ),
      SiteQueryState.pending => (
          Icons.schedule,
          scheme.onSurfaceVariant,
          '等待',
        ),
    };

    final chip = ActionChip(
      onPressed: null,
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        '${status.siteName} · $detail',
        style: theme.textTheme.labelMedium?.copyWith(color: color),
      ),
      visualDensity: VisualDensity.compact,
    );

    final message = status.message;
    if (message == null || message.isEmpty) return chip;
    return Tooltip(message: message, child: chip);
  }
}
