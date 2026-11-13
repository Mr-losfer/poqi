import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design/pq_theme.dart';
import 'routes.dart';
import 'state/connect.dart';
import 'state/providers.dart';

class PoqiApp extends ConsumerStatefulWidget {
  const PoqiApp({super.key});

  @override
  ConsumerState<PoqiApp> createState() => _PoqiAppState();
}

class _PoqiAppState extends ConsumerState<PoqiApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = ref.read(settingsProvider);
      // 启动时按设置拉起局域网服务，并做一次静默更新检查。
      await ref.read(connectProvider.notifier).bootstrap();
      if (settings.autoCheckUpdate) {
        await ref.read(connectProvider.notifier).checkUpdate(silent: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: 'Poqi',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: PqTheme.build(dark: false),
      darkTheme: PqTheme.build(dark: true),
      themeMode: settings.themeMode,
      scrollBehavior: const PqScrollBehavior(),
      builder: (context, child) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale.clamp(0.9, 1.25)),
          ),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                  appRouter.push('/search'),
              const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                  appRouter.push('/search'),
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (appRouter.canPop()) appRouter.pop();
              },
            },
            child: Focus(
              autofocus: true,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

/// 桌面端允许鼠标拖拽滚动，并始终显示细滚动条。
class PqScrollBehavior extends MaterialScrollBehavior {
  const PqScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.fuchsia) {
      return const ClampingScrollPhysics();
    }
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}
