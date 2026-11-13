import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/release.dart';
import '../../domain/models/settings.dart';

class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    this.viaProxy = true,
    this.speedBps = 0,
  });

  final int received;
  final int total;
  final bool viaProxy;
  final double speedBps;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 内置更新器。
///
/// 检查顺序：
///   1. GitHub Releases API（api.github.com，可直连）
///   2. 仓库内 version.json（走 gh-proxy 加速）
///
/// 下载顺序：
///   1. `https://gh-proxy.com/https://github.com/...`（主代理）
///   2. `https://github.com/...`（直连兜底）
class UpdateService {
  UpdateService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              headers: {'Accept': 'application/vnd.github+json'},
            ));

  final Dio _dio;

  static const proxyPrefix = 'https://gh-proxy.com/';

  /// 未取到发布页链接时的兜底地址，与设置里的默认仓库保持同源。
  static String get _repoSlug => const AppSettings().repoSlug;

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 检查更新，返回结构化结果（不抛异常）。
  Future<UpdateCheckOutcome> check(AppSettings settings, {String? current}) async {
    final cur = current ?? await currentVersion();
    final api = await _fromGitHubApi(settings);
    if (api != null) {
      if (api.version.isEmpty) return UpdateCheckOutcome(current: cur, message: '发布信息缺少版本号');
      if (compareVersions(api.version, cur) > 0) {
        return UpdateCheckOutcome(release: api, current: cur);
      }
      return UpdateCheckOutcome(current: cur);
    }
    final manifest = await _fromManifest(settings);
    if (manifest == null) {
      return UpdateCheckOutcome(current: cur, message: 'GitHub API 与备用清单均不可达');
    }
    if (compareVersions(manifest.version, cur) > 0) {
      return UpdateCheckOutcome(release: manifest, current: cur);
    }
    return UpdateCheckOutcome(current: cur);
  }

  Future<ReleaseInfo?> _fromGitHubApi(AppSettings settings) async {
    final url = 'https://api.github.com/repos/${settings.repoOwner}/${settings.repoName}/releases/latest';
    try {
      final resp = await _dio.get<dynamic>(url);
      final data = resp.data;
      if (data is! Map) return null;
      return ReleaseInfo(
        version: '${data['tag_name'] ?? data['name'] ?? ''}'
            .replaceAll(RegExp(r'^[vV]'), ''),
        tag: '${data['tag_name'] ?? ''}',
        notes: '${data['body'] ?? ''}',
        publishedAt: DateTime.tryParse('${data['published_at'] ?? ''}'),
        htmlUrl: '${data['html_url'] ?? ''}',
        assets: (data['assets'] as List?)
                ?.whereType<Map>()
                .map((e) => ReleaseAsset(
                      name: '${e['name'] ?? ''}',
                      url: '${e['browser_download_url'] ?? ''}',
                      size: (e['size'] as num?)?.toInt() ?? 0,
                    ))
                .toList() ??
            const [],
      );
    } catch (e) {
      debugPrint('GitHub API 检查失败: $e');
      return null;
    }
  }

  Future<ReleaseInfo?> _fromManifest(AppSettings settings) async {
    final candidates = [
      '${proxyPrefix}https://raw.githubusercontent.com/${settings.repoOwner}/${settings.repoName}/main/version.json',
      'https://raw.githubusercontent.com/${settings.repoOwner}/${settings.repoName}/main/version.json',
    ];
    for (final url in candidates) {
      try {
        final resp = await _dio.get<dynamic>(url);
        final data = resp.data;
        if (data is Map) {
          return ReleaseInfo(
            version: '${data['version'] ?? ''}'.replaceAll(RegExp(r'^[vV]'), ''),
            tag: '${data['tag'] ?? data['version'] ?? ''}',
            notes: '${data['notes'] ?? ''}',
            htmlUrl: '${data['htmlUrl'] ?? ''}',
            assets: (data['assets'] as List?)
                    ?.whereType<Map>()
                    .map((e) => ReleaseAsset.fromJson(e.cast<String, dynamic>()))
                    .toList() ??
                const [],
          );
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// 下载更新包：主代理 → 直连兜底。
  Future<File> download(
    ReleaseInfo release, {
    required bool preferProxy,
    void Function(DownloadProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (kIsWeb) throw UpdateException('网页版请直接前往发布页下载');

    final asset = release.assetFor('.apk') ??
        release.assetFor('.zip') ??
        release.assetFor('.exe') ??
        (release.assets.isNotEmpty ? release.assets.first : null);
    if (asset == null) throw UpdateException('该版本没有可下载的安装包');

    final direct = asset.url.isNotEmpty
        ? asset.url
        : 'https://github.com/${release.htmlUrl.split('/releases')[0].split('github.com/').last}'
            '/releases/download/${release.tag}/${asset.name}';
    final proxied = '$proxyPrefix$direct';

    final urls = preferProxy ? [proxied, direct] : [direct, proxied];
    Object? lastError;

    for (var i = 0; i < urls.length; i++) {
      final viaProxy = urls[i] == proxied;
      try {
        return await _downloadFrom(
          urls[i],
          asset.name,
          viaProxy: viaProxy,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      } catch (e) {
        lastError = e;
        debugPrint('下载失败（${viaProxy ? '代理' : '直连'}）: $e');
      }
    }
    throw UpdateException('下载失败：${lastError ?? '未知错误'}');
  }

  Future<File> _downloadFrom(
    String url,
    String name, {
    required bool viaProxy,
    void Function(DownloadProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/updates/$name');
    await file.parent.create(recursive: true);

    final started = DateTime.now();
    final resp = await _dio.download(
      url,
      file.path,
      cancelToken: cancelToken,
      deleteOnError: true,
      options: Options(receiveTimeout: const Duration(minutes: 10)),
      onReceiveProgress: (received, total) {
        final elapsed = DateTime.now().difference(started).inMilliseconds;
        final speed = elapsed <= 0 ? 0.0 : received * 1000 / elapsed;
        onProgress?.call(DownloadProgress(
          received: received,
          total: total,
          viaProxy: viaProxy,
          speedBps: speed,
        ));
      },
    );
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw UpdateException('HTTP ${resp.statusCode}');
    }
    if (!await file.exists() || await file.length() < 1024) {
      throw UpdateException('下载内容异常（文件过小）');
    }
    return file;
  }

  Future<void> install(File file) async {
    if (kIsWeb) {
      await launchUrl(Uri.parse('https://github.com/${_repoSlug}/releases'),
          mode: LaunchMode.externalApplication);
      return;
    }
    if (Platform.isAndroid) {
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw UpdateException('无法拉起安装器：${result.message}');
      }
      return;
    }
    await OpenFilex.open(file.path);
  }

  Future<void> openReleasePage(String url) async {
    final target = url.isNotEmpty ? url : 'https://github.com/$_repoSlug/releases';
    await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
  }
}

/// 让调用方区分"已是最新"与"检查失败"。
class UpdateCheckOutcome {
  const UpdateCheckOutcome({this.release, this.current, this.message});

  final ReleaseInfo? release;
  final String? current;
  final String? message;

  bool get hasUpdate => release != null;
  bool get failed => message != null;
}
