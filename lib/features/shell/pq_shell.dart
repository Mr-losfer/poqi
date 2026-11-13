import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/logo.dart';
import '../../core/ui/primitives.dart';
import '../../state/connect.dart';
import '../../state/providers.dart';

class PqNavItem {
  const PqNavItem(this.label, this.icon, this.activeIcon, this.path);

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
}

const navItems = <PqNavItem>[
  PqNavItem('首页', Icons.home_outlined, Icons.home_rounded, '/home'),
  PqNavItem('分类', Icons.grid_view_outlined, Icons.grid_view_rounded, '/discover'),
  PqNavItem('插件', Icons.extension_outlined, Icons.extension_rounded, '/plugins'),
  PqNavItem('连接', Icons.wifi_tethering_outlined, Icons.wifi_tethering_rounded, '/connect'),
  PqNavItem('设置', Icons.tune_outlined, Icons.tune_rounded, '/settings'),
];

/// 自适应外壳：手机底部导航、平板窄栏、桌面展开侧栏 + 顶栏。
class PqShell extends ConsumerWidget {
  const PqShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PqPalette.of(context);
    final form = PqAdaptive.of(context);
    final compact = form == PqFormFactor.compact;

    if (compact) {
      return Scaffold(
        backgroundColor: p.canvas,
        body: navigationShell,
        bottomNavigationBar: _BottomNav(navigationShell: navigationShell),
      );
    }

    final railWidth = form == PqFormFactor.medium ? 84.0 : 236.0;
    return Scaffold(
      backgroundColor: p.canvas,
      body: Row(
        children: [
          _SideNav(
            width: railWidth,
            collapsed: form == PqFormFactor.medium,
            currentIndex: navigationShell.currentIndex,
            onSelect: (i) => navigationShell.goBranch(
              i,
              initialLocation: i == navigationShell.currentIndex,
            ),
          ),
          VerticalDivider(width: 1, color: p.lineSoft),
          Expanded(
            child: Column(
              children: [
                _TopBar(compactHeight: form == PqFormFactor.medium),
                Divider(height: 1, color: p.lineSoft),
                Expanded(child: navigationShell),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.lineSoft, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < navItems.length; i++)
                Expanded(
                  child: _BottomItem(
                    item: navItems[i],
                    selected: navigationShell.currentIndex == i,
                    onTap: () => navigationShell.goBranch(
                      i,
                      initialLocation: i == navigationShell.currentIndex,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PqNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? p.accent.withOpacity(0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              selected ? item.activeIcon : item.icon,
              size: 21,
              color: selected ? p.accent : p.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: PqType.eyebrow.copyWith(
              fontSize: 9.5,
              letterSpacing: 0.6,
              color: selected ? p.accent : p.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideNav extends ConsumerWidget {
  const _SideNav({
    required this.width,
    required this.collapsed,
    required this.currentIndex,
    required this.onSelect,
  });

  final double width;
  final bool collapsed;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PqPalette.of(context);
    final connect = ref.watch(connectProvider);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(collapsed ? 0 : 22, 22, collapsed ? 0 : 18, 26),
            child: collapsed
                ? const Center(child: PqLogo(size: 26, showWordmark: false))
                : Row(
                    children: [
                      const PqLogo(size: 26),
                      const Spacer(),
                      Tooltip(
                        message: 'v1.0.0',
                        child: Text(
                          '1.0',
                          style: PqType.eyebrow.copyWith(color: p.textFaint),
                        ),
                      ),
                    ],
                  ),
          ),
          for (var i = 0; i < navItems.length; i++)
            _SideItem(
              item: navItems[i],
              collapsed: collapsed,
              active: currentIndex == i,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.fromLTRB(collapsed ? 12 : 18, 0, collapsed ? 12 : 18, 18),
            child: collapsed
                ? Center(
                    child: Tooltip(
                      message: connect.mcpRunning ? 'MCP 在线' : 'MCP 未开启',
                      child: Icon(
                        Icons.hub_outlined,
                        size: 16,
                        color: connect.mcpRunning ? p.sage : p.textFaint,
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.lineSoft),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: connect.mcpRunning ? p.sage : p.textFaint,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            connect.mcpRunning ? 'MCP · ${connect.mcpPort}' : '局域网未连接',
                            style: PqType.bodySmall.copyWith(fontSize: 11, color: p.textMuted),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 14, color: p.textFaint),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 侧栏项：用 InheritedShell 定位当前分支。
class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.item,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  final PqNavItem item;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 14, vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            decoration: BoxDecoration(
              color: active ? p.accent.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? p.accent.withOpacity(0.24) : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  active ? item.activeIcon : item.icon,
                  size: 19,
                  color: active ? p.accent : p.textMuted,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Text(
                    item.label,
                    style: PqType.label.copyWith(
                      fontSize: 13,
                      color: active ? p.text : p.textMuted,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (active)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerStatefulWidget {
  const _TopBar({this.compactHeight = false});

  final bool compactHeight;

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  void _search(String q) {
    final keyword = q.trim();
    if (keyword.isEmpty) {
      context.go('/search');
    } else {
      context.go('/search?q=${Uri.encodeQueryComponent(keyword)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final settings = ref.watch(settingsProvider);
    return SizedBox(
      height: 62,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: PqAdaptive.gutter(context)),
        child: Row(
          children: [
            if (!widget.compactHeight)
              Text(
                '把散落的影像，收进一只盒子。',
                style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 12),
              ),
            const Spacer(),
            SizedBox(
              width: widget.compactHeight ? 300 : 380,
              child: PqSearchField(
                hint: '搜索全站影视…',
                onSubmit: _search,
                showShortcut: !widget.compactHeight,
              ),
            ),
            const SizedBox(width: 6),
            PqIconButton(
              icon: settings.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              tooltip: '切换主题',
              onTap: () => ref.read(settingsProvider.notifier).toggleTheme(),
            ),
            PqIconButton(
              icon: Icons.extension_outlined,
              tooltip: '插件工坊',
              onTap: () => context.go('/plugins'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部滚动渐显的标题栏（页面内使用）。
class PqPageHeader extends StatelessWidget {
  const PqPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.actions = const [],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      eyebrow!.toUpperCase(),
                      style: PqType.eyebrow.copyWith(color: p.accent.withOpacity(0.9)),
                    ),
                  ),
                Text(title, style: PqType.h1.copyWith(fontSize: 26, letterSpacing: -0.6)),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    style: PqType.bodySmall.copyWith(color: p.textMuted, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 页面通用容器：紧凑端带安全区与返回键。
class PqPage extends StatelessWidget {
  const PqPage({
    super.key,
    required this.child,
    this.padded = true,
    this.maxWidth = PqTokens.maxContent,
  });

  final Widget child;
  final bool padded;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return PqFadeUpOnce(
      child: PqContent(
        maxWidth: maxWidth,
        padding: padded,
        child: child,
      ),
    );
  }
}

class PqFadeUpOnce extends StatefulWidget {
  const PqFadeUpOnce({super.key, required this.child});

  final Widget child;

  @override
  State<PqFadeUpOnce> createState() => _PqFadeUpOnceState();
}

class _PqFadeUpOnceState extends State<PqFadeUpOnce> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _show ? Offset.zero : const Offset(0, 0.012),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
