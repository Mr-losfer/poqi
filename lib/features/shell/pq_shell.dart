import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/logo.dart';
import '../../core/ui/primitives.dart';
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

/// 自适应外壳，全部使用 Material 3 标准导航组件：
///
/// - compact：底部 [NavigationBar]
/// - medium ：[NavigationRail]（仅图标，带标签提示）
/// - expanded：[NavigationDrawer] 常驻侧栏
///
/// 顶栏统一为 [AppBar]，搜索、主题切换放在 actions 里。
class PqShell extends ConsumerWidget {
  const PqShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _go(int i) => navigationShell.goBranch(
        i,
        initialLocation: i == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = PqAdaptive.of(context);

    if (form == PqFormFactor.compact) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final item in navItems)
              NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon),
                label: item.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _PqTopBar(compact: form == PqFormFactor.medium),
      body: Row(
        children: [
          if (form == PqFormFactor.medium)
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.none,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: PqLogo(size: 24, showWordmark: false),
              ),
              destinations: [
                for (final item in navItems)
                  NavigationRailDestination(
                    icon: Tooltip(message: item.label, child: Icon(item.icon)),
                    selectedIcon: Tooltip(message: item.label, child: Icon(item.activeIcon)),
                    label: Text(item.label),
                  ),
              ],
            )
          else
            SizedBox(
              width: 300,
              child: NavigationDrawer(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _go,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(28, 20, 16, 8),
                    child: PqLogo(size: 30),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 16, 16),
                    child: Text(
                      '把散落的影像，收进一只盒子。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  for (final item in navItems)
                    NavigationDrawerDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.activeIcon),
                      label: Text(item.label),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(28, 20, 28, 0),
                    child: Divider(),
                  ),
                ],
              ),
            ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

/// 顶栏：AppBar + 内联搜索。
class _PqTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const _PqTopBar({this.compact = false});

  final bool compact;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _search(BuildContext context, String q) {
    final keyword = q.trim();
    if (keyword.isEmpty) {
      context.go('/search');
    } else {
      context.go('/search?q=${Uri.encodeQueryComponent(keyword)}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);

    return AppBar(
      titleSpacing: 16,
      title: compact ? const PqLogo(size: 24) : Text('Poqi', style: theme.textTheme.titleLarge),
      actions: [
        const _SiteSwitcher(),
        const SizedBox(width: 8),
        if (!compact)
          SizedBox(
            width: 320,
            child: PqSearchField(
              hint: '搜索全部站点…',
              onSubmit: (q) => _search(context, q),
              showShortcut: true,
            ),
          )
        else
          IconButton(
            tooltip: '搜索',
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.search),
          ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: settings.themeMode == ThemeMode.dark ? '切换到浅色' : '切换到深色',
          onPressed: () => ref.read(settingsProvider.notifier).toggleTheme(),
          icon: Icon(
            settings.themeMode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// 顶栏的站点切换器：把「聚合全部站点」和「只看某一个站」做成一个入口。
///
/// 选择结果写入 [selectedSiteProvider]，首页、分类、搜索三处同时生效。
class _SiteSwitcher extends ConsumerWidget {
  const _SiteSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sites = ref.watch(enabledSitesProvider);
    final current = ref.watch(selectedSiteNameProvider);
    final compact = PqAdaptive.isCompact(context);

    if (sites.isEmpty) return const SizedBox.shrink();
    final label = current?.name ?? '全部站点';

    void pick(String? id) {
      ref.read(selectedSiteProvider.notifier).state = id;
    }

    return MenuAnchor(
      style: MenuStyle(
        maximumSize: const WidgetStatePropertyAll(Size(320, 420)),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(
            current == null ? Icons.check : Icons.apps_outlined,
            size: 18,
          ),
          onPressed: () => pick(null),
          child: const Text('全部站点'),
        ),
        const Divider(height: 1),
        for (final s in sites)
          MenuItemButton(
            leadingIcon: Icon(
              s.id == current?.id ? Icons.check : Icons.dns_outlined,
              size: 18,
            ),
            onPressed: () => pick(s.id),
            child: Text(s.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();

        if (compact) {
          return IconButton(
            tooltip: '切换站点：$label',
            onPressed: toggle,
            icon: Badge(
              isLabelVisible: current != null,
              child: const Icon(Icons.dns_outlined),
            ),
          );
        }
        return Tooltip(
          message: '切换站点',
          child: FilledButton.tonalIcon(
            onPressed: toggle,
            icon: const Icon(Icons.dns_outlined, size: 18),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 页面标题区：eyebrow（可选）+ 标题 + 说明 + 右侧动作。
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
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
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      eyebrow!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Text(title, style: theme.textTheme.headlineMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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

/// 页面通用容器：限宽居中 + 统一留白。
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

/// 首次挂载淡入，避免路由切换时的生硬跳变。
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
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}
