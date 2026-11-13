import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/backend.dart';
import 'data/net/pq_http.dart';
import 'data/repositories.dart';
import 'data/store.dart';
import 'domain/plugin/runner.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await JsonStore.open();
  final settingsRepo = SettingsRepository(store);
  final pluginRepo = PluginRepository(store);
  final siteRepo = SiteRepository(store);
  final libraryRepo = LibraryRepository(store);

  await siteRepo.seedIfEmpty();

  final settings = settingsRepo.load();
  final deviceId = await settingsRepo.deviceId();
  final deviceName =
      settings.deviceName.isEmpty ? _defaultDeviceName() : settings.deviceName;

  final backend = PoqiBackend(
    store: store,
    pluginRepo: pluginRepo,
    siteRepo: siteRepo,
    libraryRepo: libraryRepo,
    settingsRepo: settingsRepo,
    http: PqHttp(),
    varCache: VarCache(),
    settings: settings,
    deviceId: deviceId,
    deviceName: deviceName,
  );

  runApp(
    ProviderScope(
      overrides: [backendProvider.overrideWithValue(backend)],
      child: const PoqiApp(),
    ),
  );
}

String _defaultDeviceName() {
  const names = ['放映厅', '沙发', '投影仪', '书房', '客厅', '小剧场'];
  final i = DateTime.now().millisecond % names.length;
  return 'Poqi ${names[i]}';
}
