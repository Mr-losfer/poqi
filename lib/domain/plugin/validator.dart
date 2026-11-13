import '../models/plugin.dart';
import 'expr.dart';

/// 插件清单静态校验：写插件时即时反馈，避免"保存后才发现规则不通"。
class PluginValidator {
  const PluginValidator();

  List<PluginIssue> validate(PluginManifest p) {
    final issues = <PluginIssue>[];

    if (p.id.trim().isEmpty) {
      issues.add(const PluginIssue(IssueLevel.error, '插件 id 不能为空', path: 'id'));
    } else if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$').hasMatch(p.id)) {
      issues.add(const PluginIssue(
        IssueLevel.error,
        'id 需为 3–64 位小写字母、数字、点、下划线或短横线',
        path: 'id',
      ));
    }
    if (p.name.trim().isEmpty) {
      issues.add(const PluginIssue(IssueLevel.error, 'name 不能为空', path: 'name'));
    }
    if (!RegExp(r'^\d+\.\d+\.\d+').hasMatch(p.version)) {
      issues.add(const PluginIssue(
        IssueLevel.warning,
        'version 建议使用语义化版本，如 1.0.0',
        path: 'version',
      ));
    }
    if (p.engine == PluginEngine.http && p.baseUrl.trim().isEmpty) {
      issues.add(const PluginIssue(
        IssueLevel.error,
        'HTTP 插件必须声明 baseUrl',
        path: 'baseUrl',
      ));
    }
    if (p.endpoints.isEmpty) {
      issues.add(const PluginIssue(IssueLevel.error, '至少需要一个端点', path: 'endpoints'));
    }
    if (!p.endpoints.containsKey('home')) {
      issues.add(const PluginIssue(
        IssueLevel.warning,
        '缺少 home 端点，首页将不会展示该站点内容',
        path: 'endpoints.home',
      ));
    }
    if (!p.endpoints.containsKey('search')) {
      issues.add(const PluginIssue(
        IssueLevel.info,
        '未声明 search，全站聚合搜索会跳过该站点',
        path: 'endpoints.search',
      ));
    }

    final keys = <String>{};
    for (var i = 0; i < p.config.length; i++) {
      final f = p.config[i];
      final path = 'config[$i]';
      if (f.key.trim().isEmpty) {
        issues.add(PluginIssue(IssueLevel.error, '配置项缺少 key', path: path));
        continue;
      }
      if (!keys.add(f.key)) {
        issues.add(PluginIssue(IssueLevel.error, '配置 key 重复：${f.key}', path: path));
      }
      if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(f.key)) {
        issues.add(PluginIssue(
          IssueLevel.error,
          '配置 key 需为合法标识符（字母/下划线开头）：${f.key}',
          path: path,
        ));
      }
      if (f.type == ConfigFieldType.select && f.options.isEmpty) {
        issues.add(PluginIssue(IssueLevel.error, 'select 类型必须提供 options', path: path));
      }
      if (f.required && (f.defaultValue ?? '').isEmpty) {
        issues.add(PluginIssue(
          IssueLevel.info,
          '必填项 ${f.label} 没有默认值，添加站点时需用户填写',
          path: path,
        ));
      }
    }

    p.vars.forEach((name, spec) {
      final path = 'vars.$name';
      if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) {
        issues.add(PluginIssue(IssueLevel.error, '变量名不合法：$name', path: path));
      }
      issues.addAll(_checkExpr(spec.expr, path));
      if (spec.ttlSeconds > 0 && spec.ttlSeconds < 30) {
        issues.add(PluginIssue(
          IssueLevel.warning,
          '变量 $name 的 TTL 短于 30 秒，可能导致频繁刷新',
          path: path,
        ));
      }
    });

    p.endpoints.forEach((name, ep) {
      final path = 'endpoints.$name';
      if (!const {'home', 'category', 'search', 'detail', 'play'}.contains(name)) {
        issues.add(PluginIssue(
          IssueLevel.warning,
          '未知端点名 "$name"，只支持 home/category/search/detail/play',
          path: path,
        ));
      }
      issues.addAll(_checkTemplate(ep.request.path, '$path.request.path'));
      ep.request.headers.forEach((k, v) {
        issues.addAll(_checkTemplate(v, '$path.request.headers.$k'));
      });
      ep.request.query.forEach((k, v) {
        issues.addAll(_checkTemplate(v, '$path.request.query.$k'));
      });

      final parse = ep.parse;
      if (parse != null) {
        issues.addAll(_checkParse(
          parse,
          '$path.parse',
          requireIdentity: name != 'play',
        ));
      } else if (name != 'play') {
        issues.add(PluginIssue(
          IssueLevel.error,
          '端点 $name 缺少 parse，无法解析响应',
          path: path,
        ));
      }

      if (parse?.format == ParseFormat.regex && (parse?.pattern ?? '').isEmpty) {
        issues.add(PluginIssue(IssueLevel.error, 'regex 缺少 pattern', path: '$path.parse'));
      }
      if (name == 'detail' && parse != null && parse.episodes == null) {
        issues.add(PluginIssue(
          IssueLevel.warning,
          'detail 未声明 episodes，播放页可能没有剧集可选',
          path: '$path.parse.episodes',
        ));
      }
    });

    if (p.engine == PluginEngine.http && p.headers.isEmpty) {
      issues.add(const PluginIssue(
        IssueLevel.info,
        '建议声明 UA / Referer，部分站点会校验',
        path: 'headers',
      ));
    }

    return issues;
  }

  List<PluginIssue> _checkParse(
    ParseSpec parse,
    String path, {
    bool requireIdentity = true,
  }) {
    final out = <PluginIssue>[];
    if (parse.format == ParseFormat.html && (parse.root ?? '').trim().isEmpty) {
      out.add(PluginIssue(IssueLevel.error, 'HTML 解析必须提供 root 选择器', path: path));
    }
    if (parse.fields.isEmpty) {
      out.add(PluginIssue(IssueLevel.error, 'fields 不能为空', path: '$path.fields'));
    }
    for (final key in const ['title', 'id']) {
      if (requireIdentity &&
          !parse.fields.containsKey(key) &&
          parse.format != ParseFormat.regex) {
        out.add(PluginIssue(
          IssueLevel.error,
          'fields 缺少必需字段 "$key"',
          path: '$path.fields',
        ));
      }
    }
    parse.fields.forEach((k, v) {
      out.addAll(_checkExpr(v, '$path.fields.$k'));
    });
    if (parse.episodes != null) {
      out.addAll(_checkParse(parse.episodes!, '$path.episodes', requireIdentity: false));
    }
    return out;
  }

  List<PluginIssue> _checkExpr(String source, String path) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return [PluginIssue(IssueLevel.error, '表达式为空', path: path)];
    }
    if (trimmed.contains('{{')) {
      return _checkTemplate(trimmed, path);
    }
    try {
      PExpr.validate(trimmed);
      return const [];
    } on ExprException catch (e) {
      return [PluginIssue(IssueLevel.error, '表达式语法错误：${e.message}', path: path)];
    }
  }

  List<PluginIssue> _checkTemplate(String source, String path) {
    final out = <PluginIssue>[];
    final re = RegExp(r'\{\{([\s\S]*?)\}\}');
    for (final m in re.allMatches(source)) {
      out.addAll(_checkExpr(m.group(1)!, path));
    }
    return out;
  }

  /// 用于编辑器底部状态条的一行摘要。
  static String summarize(List<PluginIssue> issues) {
    if (issues.isEmpty) return '校验通过';
    final e = issues.where((i) => i.level == IssueLevel.error).length;
    final w = issues.where((i) => i.level == IssueLevel.warning).length;
    final i = issues.where((i) => i.level == IssueLevel.info).length;
    final parts = <String>[];
    if (e > 0) parts.add('$e 个错误');
    if (w > 0) parts.add('$w 个警告');
    if (i > 0) parts.add('$i 条建议');
    return parts.join(' · ');
  }
}

/// 单个站点配置完整性检查。
List<String> missingRequiredConfig(PluginManifest p, Map<String, String> config) {
  final missing = <String>[];
  for (final f in p.config) {
    if (!f.required) continue;
    final v = config[f.key];
    if (v == null || v.trim().isEmpty) missing.add(f.label);
  }
  return missing;
}
