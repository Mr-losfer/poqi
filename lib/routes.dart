import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/ui/primitives.dart';
import 'features/connect/connect_page.dart';
import 'features/detail/detail_page.dart';
import 'features/discover/discover_page.dart';
import 'features/docs/docs_page.dart';
import 'features/home/home_page.dart';
import 'features/player/player_page.dart';
import 'features/plugins/plugin_detail_page.dart';
import 'features/plugins/plugin_editor_page.dart';
import 'features/plugins/plugins_page.dart';
import 'features/search/search_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shell/pq_shell.dart';
import 'features/sites/site_editor_page.dart';

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    child: child,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => PqShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => const NoTransitionPage(child: HomePage()),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/discover',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DiscoverPage(initialKind: state.uri.queryParameters['kind']),
            ),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/plugins',
            pageBuilder: (context, state) => const NoTransitionPage(child: PluginsPage()),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/connect',
            pageBuilder: (context, state) => const NoTransitionPage(child: ConnectPage()),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(child: SettingsPage()),
          ),
        ]),
      ],
    ),
    GoRoute(
      path: '/search',
      pageBuilder: (context, state) => _fadePage(
        state,
        SearchPage(initialQuery: state.uri.queryParameters['q']),
      ),
    ),
    GoRoute(
      path: '/detail/:siteId/:itemId',
      pageBuilder: (context, state) => _fadePage(
        state,
        DetailPage(
          siteId: state.pathParameters['siteId']!,
          itemId: state.pathParameters['itemId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/play',
      pageBuilder: (context, state) => _fadePage(state, const PlayerPage()),
    ),
    GoRoute(
      path: '/plugin/:id',
      pageBuilder: (context, state) => _fadePage(
        state,
        PluginDetailPage(pluginId: state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/plugin/:id/edit',
      pageBuilder: (context, state) => _fadePage(
        state,
        PluginEditorPage(pluginId: state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/site/new',
      pageBuilder: (context, state) => _fadePage(
        state,
        SiteEditorPage(presetPluginId: state.uri.queryParameters['plugin']),
      ),
    ),
    GoRoute(
      path: '/site/:id/edit',
      pageBuilder: (context, state) => _fadePage(
        state,
        SiteEditorPage(siteId: state.pathParameters['id']),
      ),
    ),
    GoRoute(
      path: '/docs',
      pageBuilder: (context, state) => _fadePage(state, const DocsPage()),
    ),
  ],
  errorBuilder: (context, state) => _NotFound(location: state.uri.toString()),
);

class _NotFound extends StatelessWidget {
  const _NotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('404'),
            const SizedBox(height: 8),
            Text(location, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            PqBackButton(),
          ],
        ),
      ),
    );
  }
}
