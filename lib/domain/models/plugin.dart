import 'dart:convert';

import 'media.dart';

/// 插件规范版本。规则变更时递增，并保持向后兼容的迁移。
const int kPluginSpecVersion = 1;

enum PluginEngine {
  /// 通过 HTTP 抓取 + 声明式解析。
  http,

  /// 通过 HTTP 抓取 + 内嵌 JavaScript 变换。
  ///
  /// 比声明式灵活得多：可以在脚本里做条件判断、字符串清洗、
  /// 正则提取、多线路拆分，适合结构不规整的站点。
  js,

  /// 内置演示引擎，随包分发，用于离线体验与规则演示。
  demo;

  static PluginEngine parse(String? v) {
    switch (v) {
      case 'demo':
        return PluginEngine.demo;
      case 'js':
        return PluginEngine.js;
      default:
        return PluginEngine.http;
    }
  }

  String get label => switch (this) {
        PluginEngine.http => 'HTTP',
        PluginEngine.js => 'JavaScript',
        PluginEngine.demo => '演示',
      };
}

enum ConfigFieldType {
  text,
  password,
  number,
  boolean,
  select;

  static ConfigFieldType parse(String? v) => switch (v) {
        'password' => ConfigFieldType.password,
        'number' => ConfigFieldType.number,
        'boolean' => ConfigFieldType.boolean,
        'select' => ConfigFieldType.select,
        _ => ConfigFieldType.text,
      };
}

/// 站点级配置项：插件作者声明，用户为每个站点单独填写。
class ConfigField {
  const ConfigField({
    required this.key,
    required this.label,
    this.type = ConfigFieldType.text,
    this.required = false,
    this.secret = false,
    this.hint,
    this.help,
    this.defaultValue,
    this.options = const [],
    this.refreshSeconds,
  });

  final String key;
  final String label;
  final ConfigFieldType type;
  final bool required;

  /// 敏感值：在列表中打码展示。
  final bool secret;
  final String? hint;
  final String? help;
  final String? defaultValue;
  final List<String> options;

  /// 建议的刷新周期（秒），供"定时更换 token/cookie"场景使用。
  final int? refreshSeconds;

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        if (required) 'required': true,
        if (secret) 'secret': true,
        if (hint != null) 'hint': hint,
        if (help != null) 'help': help,
        if (defaultValue != null) 'default': defaultValue,
        if (options.isNotEmpty) 'options': options,
        if (refreshSeconds != null) 'refreshSeconds': refreshSeconds,
      };

  factory ConfigField.fromJson(Map<String, dynamic> j) => ConfigField(
        key: '${j['key'] ?? ''}',
        label: '${j['label'] ?? j['key'] ?? ''}',
        type: ConfigFieldType.parse(j['type'] as String?),
        required: j['required'] == true,
        secret: j['secret'] == true,
        hint: j['hint'] as String?,
        help: j['help'] as String?,
        defaultValue: j['default']?.toString(),
        options: (j['options'] as List?)?.map((e) => '$e').toList() ?? const [],
        refreshSeconds: (j['refreshSeconds'] as num?)?.toInt(),
      );
}

/// 运行时变量：可调用 HTTP 获取 token，按 TTL 缓存。
class VarSpec {
  const VarSpec({
    required this.expr,
    this.ttlSeconds = 0,
  });

  final String expr;
  final int ttlSeconds;

  Map<String, dynamic> toJson() => {
        'expr': expr,
        if (ttlSeconds > 0) 'ttl': ttlSeconds,
      };

  factory VarSpec.fromJson(Map<String, dynamic> j) => VarSpec(
        expr: '${j['expr'] ?? ''}',
        ttlSeconds: (j['ttl'] as num?)?.toInt() ?? 0,
      );
}

class RequestSpec {
  const RequestSpec({
    this.method = 'GET',
    this.path = '',
    this.headers = const {},
    this.query = const {},
    this.body,
    this.timeoutMs = 15000,
  });

  final String method;

  /// 支持 `{{ }}` 模板，变量来自 cfg / vars / page / keyword / id。
  final String path;
  final Map<String, String> headers;
  final Map<String, String> query;
  final Object? body;
  final int timeoutMs;

  Map<String, dynamic> toJson() => {
        'method': method,
        'path': path,
        if (headers.isNotEmpty) 'headers': headers,
        if (query.isNotEmpty) 'query': query,
        if (body != null) 'body': body,
        'timeoutMs': timeoutMs,
      };

  factory RequestSpec.fromJson(Map<String, dynamic> j) => RequestSpec(
        method: '${j['method'] ?? 'GET'}',
        path: '${j['path'] ?? ''}',
        headers: (j['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
        query: (j['query'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
        body: j['body'],
        timeoutMs: (j['timeoutMs'] as num?)?.toInt() ?? 15000,
      );
}

enum ParseFormat { json, html, regex, split }

class ParseSpec {
  const ParseSpec({
    required this.format,
    this.root,
    this.fields = const {},
    this.episodes,
    this.pattern,
    this.group = 1,
    this.from,
    this.lineNames,
    this.lineSep = r'$$$',
    this.itemSep = '#',
    this.pairSep = r'$',
  });

  final ParseFormat format;

  /// json: 形如 `data.list`；html: CSS 选择器；regex: 不适用。
  final String? root;

  /// 字段名 → 表达式。
  final Map<String, String> fields;

  /// 详情页剧集解析（root 为每个剧集节点）。
  final ParseSpec? episodes;

  /// regex 模式。
  final String? pattern;
  final int group;

  /// split 模式：对详情记录求值得到 `a$url#b$url` 形式的剧集串。
  final String? from;

  /// split 模式：线路名串，通常取 `vod_play_from`。
  final String? lineNames;
  final String lineSep;
  final String itemSep;
  final String pairSep;

  Map<String, dynamic> toJson() => {
        'format': format.name,
        if (root != null) 'root': root,
        if (fields.isNotEmpty) 'fields': fields,
        if (episodes != null) 'episodes': episodes!.toJson(),
        if (pattern != null) 'pattern': pattern,
        if (group != 1) 'group': group,
        if (from != null) 'from': from,
        if (lineNames != null) 'lineNames': lineNames,
        if (lineSep != r'$$$') 'lineSep': lineSep,
        if (itemSep != '#') 'itemSep': itemSep,
        if (pairSep != r'$') 'pairSep': pairSep,
      };

  factory ParseSpec.fromJson(Map<String, dynamic> j) => ParseSpec(
        format: switch ('${j['format'] ?? 'json'}') {
          'html' => ParseFormat.html,
          'regex' => ParseFormat.regex,
          'split' => ParseFormat.split,
          _ => ParseFormat.json,
        },
        root: j['root'] as String?,
        fields: (j['fields'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
        episodes: j['episodes'] is Map
            ? ParseSpec.fromJson((j['episodes'] as Map).cast<String, dynamic>())
            : null,
        pattern: j['pattern'] as String?,
        group: (j['group'] as num?)?.toInt() ?? 1,
        from: j['from'] as String?,
        lineNames: j['lineNames'] as String?,
        lineSep: '${j['lineSep'] ?? r'$$$'}',
        itemSep: '${j['itemSep'] ?? '#'}',
        pairSep: '${j['pairSep'] ?? r'$'}',
      );
}

class EndpointSpec {
  const EndpointSpec({
    this.request = const RequestSpec(),
    this.parse,
    this.js,
    this.filters = const [],
    this.pageStart = 1,
    this.pageSize,
  });

  final RequestSpec request;
  final ParseSpec? parse;

  /// `engine: js` 时调用的脚本函数名（如 `home` / `detail`）。
  ///
  /// 缺省时按端点名推断，所以大多数插件不用写这一项。
  final String? js;

  final List<FilterGroup> filters;
  final int pageStart;
  final int? pageSize;

  /// 该端点实际调用的 JS 函数名。
  String jsFunctionFor(String endpoint) => (js == null || js!.isEmpty) ? endpoint : js!;

  Map<String, dynamic> toJson() => {
        'request': request.toJson(),
        if (parse != null) 'parse': parse!.toJson(),
        if (js != null && js!.isNotEmpty) 'js': js,
        if (filters.isNotEmpty) 'filters': filters.map((e) => e.toJson()).toList(),
        if (pageStart != 1) 'pageStart': pageStart,
        if (pageSize != null) 'pageSize': pageSize,
      };

  factory EndpointSpec.fromJson(Map<String, dynamic> j) => EndpointSpec(
        request: j['request'] is Map
            ? RequestSpec.fromJson((j['request'] as Map).cast<String, dynamic>())
            : const RequestSpec(),
        parse: j['parse'] is Map
            ? ParseSpec.fromJson((j['parse'] as Map).cast<String, dynamic>())
            : null,
        js: j['js'] as String?,
        filters: (j['filters'] as List?)
                ?.whereType<Map>()
                .map((e) => FilterGroup.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
        pageStart: (j['pageStart'] as num?)?.toInt() ?? 1,
        pageSize: (j['pageSize'] as num?)?.toInt(),
      );
}

/// 插件清单 —— Poqi 插件规范 v1 的根对象。
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.spec = kPluginSpecVersion,
    this.author = '',
    this.description = '',
    this.homepage = '',
    this.icon = '',
    this.engine = PluginEngine.http,
    this.script = '',
    this.baseUrl = '',
    this.headers = const {},
    this.config = const [],
    this.vars = const {},
    this.endpoints = const {},
    this.notes = '',
    this.builtin = false,
  });

  final int spec;
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String homepage;
  final String? icon;
  final PluginEngine engine;

  /// `engine: js` 时的完整脚本（可含多个端点函数）。
  final String script;

  final String baseUrl;
  final Map<String, String> headers;
  final List<ConfigField> config;
  final Map<String, VarSpec> vars;
  final Map<String, EndpointSpec> endpoints;
  final String notes;

  /// 随包分发的插件（不可删除，但可复制后修改）。
  final bool builtin;

  bool get supportsSearch => endpoints.containsKey('search');
  bool get supportsCategory => endpoints.containsKey('category');
  bool get hasDetail => endpoints.containsKey('detail');

  ConfigField? configField(String key) {
    for (final f in config) {
      if (f.key == key) return f;
    }
    return null;
  }

  PluginManifest copyWith({
    String? id,
    String? name,
    String? version,
    String? author,
    String? description,
    String? homepage,
    String? icon,
    PluginEngine? engine,
    String? script,
    String? baseUrl,
    Map<String, String>? headers,
    List<ConfigField>? config,
    Map<String, VarSpec>? vars,
    Map<String, EndpointSpec>? endpoints,
    String? notes,
    bool? builtin,
  }) {
    return PluginManifest(
      spec: spec,
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      homepage: homepage ?? this.homepage,
      icon: icon ?? this.icon,
      engine: engine ?? this.engine,
      script: script ?? this.script,
      baseUrl: baseUrl ?? this.baseUrl,
      headers: headers ?? this.headers,
      config: config ?? this.config,
      vars: vars ?? this.vars,
      endpoints: endpoints ?? this.endpoints,
      notes: notes ?? this.notes,
      builtin: builtin ?? this.builtin,
    );
  }

  Map<String, dynamic> toJson() => {
        'spec': spec,
        'id': id,
        'name': name,
        'version': version,
        if (author.isNotEmpty) 'author': author,
        if (description.isNotEmpty) 'description': description,
        if (homepage.isNotEmpty) 'homepage': homepage,
        if (icon != null && icon!.isNotEmpty) 'icon': icon,
        'engine': engine.name,
        if (script.isNotEmpty) 'script': script,
        'baseUrl': baseUrl,
        if (headers.isNotEmpty) 'headers': headers,
        if (config.isNotEmpty) 'config': config.map((e) => e.toJson()).toList(),
        if (vars.isNotEmpty) 'vars': vars.map((k, v) => MapEntry(k, v.toJson())),
        'endpoints': endpoints.map((k, v) => MapEntry(k, v.toJson())),
        if (notes.isNotEmpty) 'notes': notes,
      };

  String toJsonString({bool pretty = true}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  factory PluginManifest.fromJson(Map<String, dynamic> j) {
    return PluginManifest(
      spec: (j['spec'] as num?)?.toInt() ?? kPluginSpecVersion,
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      version: '${j['version'] ?? '1.0.0'}',
      author: '${j['author'] ?? ''}',
      description: '${j['description'] ?? ''}',
      homepage: '${j['homepage'] ?? ''}',
      icon: j['icon'] as String?,
      engine: PluginEngine.parse(j['engine'] as String?),
      script: '${j['script'] ?? ''}',
      baseUrl: '${j['baseUrl'] ?? ''}',
      headers: (j['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
      config: (j['config'] as List?)
              ?.whereType<Map>()
              .map((e) => ConfigField.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const [],
      vars: (j['vars'] as Map?)?.map(
            (k, v) => MapEntry(
              '$k',
              VarSpec.fromJson((v as Map).cast<String, dynamic>()),
            ),
          ) ??
          const {},
      endpoints: (j['endpoints'] as Map?)?.map(
            (k, v) => MapEntry(
              '$k',
              EndpointSpec.fromJson((v as Map).cast<String, dynamic>()),
            ),
          ) ??
          const {},
      notes: '${j['notes'] ?? ''}',
    );
  }

  factory PluginManifest.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('插件根节点必须是 JSON 对象');
    return PluginManifest.fromJson(decoded.cast<String, dynamic>());
  }
}

/// 校验结果。
class PluginIssue {
  const PluginIssue(this.level, this.message, {this.path});

  final IssueLevel level;
  final String message;
  final String? path;

  bool get isError => level == IssueLevel.error;

  @override
  String toString() => '${level.name}: ${path ?? ''} $message';
}

enum IssueLevel { error, warning, info }
