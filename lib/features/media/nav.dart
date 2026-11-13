import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/media.dart';
import '../../domain/models/site.dart';
import '../../state/player.dart';
import '../../state/providers.dart';

SiteBinding? siteOf(WidgetRef ref, String? siteId) {
  if (siteId == null) return null;
  for (final s in ref.read(sitesProvider)) {
    if (s.id == siteId) return s;
  }
  return null;
}

void openDetail(BuildContext context, MediaItem item) {
  if (item.sourceId == null) return;
  context.push('/detail/${item.sourceId}/${Uri.encodeComponent(item.id)}');
}

Future<void> openPlay(BuildContext context, WidgetRef ref, MediaItem item) async {
  final site = siteOf(ref, item.sourceId);
  if (site == null) return;
  await ref.read(playerProvider.notifier).open(site: site, item: item);
  if (context.mounted) context.push('/play');
}
