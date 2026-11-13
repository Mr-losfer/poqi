/// Poqi JS 插件运行时（纯 ES5，零依赖）。
///
/// **这里是唯一事实源**：`tool/js_runtime_test.js` 会从本文件提取脚本，
/// 用 Node 跑一遍 HTML 解析 / CSS 选择器 / 工具函数，再交给 Dart 内嵌执行。
/// 改这里之后请跑 `node tool/js_runtime_test.js`。
///
/// 之所以内嵌成 Dart 字符串而不是 asset：插件执行是同步的，
/// 走 `rootBundle` 会把一次求值变成异步，平白增加复杂度。
library;

const String pqRuntimeJs = r'''
/* -------------------------------------------------------------------------
 * Poqi JS 插件运行时（纯 ES5，无依赖）
 *
 * 插件脚本里可以直接用 `pq.*`：
 *   pq.http.get(url, opts)        发 GET，返回响应文本（同步写法）
 *   pq.http.json(url, opts)       GET + JSON.parse
 *   pq.http.post(url, body, opts) POST，body 可以是对象（自动 JSON）
 *   pq.http.request({url,...})    返回 {ok,status,headers,body,url,error}
 *   pq.get(obj, 'a.b.0.c', def)   安全取值
 *   pq.text(node) / pq.ownText    取文本
 *   pq.attr(node, 'href')         取属性
 *   pq.html(node) / pq.outer      取 HTML
 *   pq.select(html, 'css')        第一个匹配（返回节点）
 *   pq.selectAll(html, 'css')     全部匹配
 *   pq.css(html, 'css')           匹配到的文本数组（最常用）
 *   pq.cssAttr(html, 'css', 'href')
 *   pq.abs(base, '/a.jpg')        补全相对地址
 *   pq.clean(html)                去标签 + 解实体
 *   pq.matchAll(str, re, group)   全局正则
 *   pq.first(str, re, group)      首个正则
 *   pq.num('8.9分') -> 8.9
 *   pq.uniq / pq.trim / pq.pad / pq.query / pq.json / pq.log
 *
 * 网络说明：脚本是同步求值的，网络是异步的。宿主用「先记账、后重放」
 * 把两者接起来 —— `pq.http.get()` 在脚本里就是同步返回字符串。
 * 细节见 js_bridge.dart。
 *
 * CSS 选择器支持：
 *   tag  .class  #id  *  [attr]  [attr=v]  [attr*=v]  [attr^=v]  [attr$=v]
 *   后代 (空格)  子代 (>)  逗号分组
 * ------------------------------------------------------------------------- */

var pq = (function () {
  var VOID_TAGS = {
    area: 1, base: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1, input: 1,
    link: 1, meta: 1, param: 1, source: 1, track: 1, wbr: 1
  };
  var RAW_TAGS = { script: 1, style: 1, textarea: 1, title: 1 };

  var ENTITIES = {
    amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ',
    ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’', hellip: '…',
    mdash: '—', ndash: '–', middot: '·', times: '×', copy: '©'
  };

  function decodeEntities(s) {
    if (!s || s.indexOf('&') < 0) return s || '';
    return s.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, function (m, code) {
      if (code.charAt(0) === '#') {
        var hex = code.charAt(1) === 'x' || code.charAt(1) === 'X';
        var n = parseInt(hex ? code.slice(2) : code.slice(1), hex ? 16 : 10);
        if (!isNaN(n) && n > 0 && n < 0x10ffff) {
          try { return String.fromCodePoint(n); } catch (e) { return m; }
        }
        return m;
      }
      var hit = ENTITIES[code.toLowerCase()];
      return hit === undefined ? m : hit;
    });
  }

  function makeNode(tag, attrs, parent) {
    return { tag: tag, attrs: attrs || {}, children: [], parent: parent || null };
  }

  // ---------------------------------------------------------------- 解析 HTML
  function parseHtml(html) {
    var root = makeNode('#root', {}, null);
    var stack = [root];
    var i = 0;
    var len = html.length;

    function top() { return stack[stack.length - 1]; }

    while (i < len) {
      var lt = html.indexOf('<', i);
      if (lt < 0) {
        top().children.push(html.slice(i));
        break;
      }
      if (lt > i) top().children.push(html.slice(i, lt));

      // 注释 / doctype / CDATA
      if (html.substr(lt, 4) === '<!--') {
        var endC = html.indexOf('-->', lt + 4);
        i = endC < 0 ? len : endC + 3;
        continue;
      }
      if (html.charAt(lt + 1) === '!' || html.charAt(lt + 1) === '?') {
        var endD = html.indexOf('>', lt);
        i = endD < 0 ? len : endD + 1;
        continue;
      }

      var gt = html.indexOf('>', lt);
      if (gt < 0) { top().children.push(html.slice(lt)); break; }
      var raw = html.slice(lt + 1, gt);

      // 闭合标签
      if (raw.charAt(0) === '/') {
        var closeName = raw.slice(1).trim().toLowerCase();
        for (var k = stack.length - 1; k > 0; k--) {
          if (stack[k].tag === closeName) {
            stack.length = k;
            break;
          }
        }
        i = gt + 1;
        continue;
      }

      // 开标签
      var selfClose = raw.charAt(raw.length - 1) === '/';
      if (selfClose) raw = raw.slice(0, -1);
      var m = raw.match(/^([a-zA-Z][^\s/>]*)/);
      if (!m) { i = gt + 1; continue; }
      var tag = m[1].toLowerCase();
      var attrs = {};
      var rest = raw.slice(m[1].length);
      var attrRe = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
      var am;
      while ((am = attrRe.exec(rest)) !== null) {
        var v = am[2] !== undefined ? am[2] : (am[3] !== undefined ? am[3] : (am[4] !== undefined ? am[4] : ''));
        attrs[am[1].toLowerCase()] = decodeEntities(v);
      }

      var node = makeNode(tag, attrs, top());
      top().children.push(node);
      i = gt + 1;

      if (RAW_TAGS[tag]) {
        var close = html.toLowerCase().indexOf('</' + tag, i);
        var textEnd = close < 0 ? len : close;
        var rawText = html.slice(i, textEnd);
        if (rawText) node.children.push(rawText);
        if (close < 0) { i = len; } else {
          var g2 = html.indexOf('>', close);
          i = g2 < 0 ? len : g2 + 1;
        }
        continue;
      }

      if (!selfClose && !VOID_TAGS[tag]) stack.push(node);
    }
    return root;
  }

  // ------------------------------------------------------------ 选择器解析
  function parseSelector(sel) {
    // 返回 [{chain:[{tag,id,classes,attrs,comb}], }]
    var groups = [];
    var parts = sel.split(',');
    for (var p = 0; p < parts.length; p++) {
      var text = parts[p].trim();
      if (!text) continue;
      var buf = '';
      var depth = 0;
      var list = [];
      // comb 记录"当前 token 与它前面那个 token"的关系，所以遇到 > 时
      // 要把它留给下一个 token，而不是回写到上一个。
      var pendingComb = ' ';
      for (var i = 0; i < text.length; i++) {
        var ch = text.charAt(i);
        if (ch === '[') depth++;
        if (ch === ']') depth--;
        if (depth === 0 && (ch === ' ' || ch === '>')) {
          if (buf) {
            list.push({ text: buf, comb: pendingComb });
            buf = '';
            pendingComb = ' ';
          }
          if (ch === '>') pendingComb = '>';
          continue;
        }
        buf += ch;
      }
      if (buf) list.push({ text: buf, comb: pendingComb });
      if (!list.length) continue;

      var chain = [];
      for (var j = 0; j < list.length; j++) {
        chain.push(parseSimple(list[j].text, j === 0 ? '' : list[j].comb));
      }
      groups.push(chain);
    }
    return groups;
  }

  function parseSimple(text, comb) {
    var out = { tag: null, id: null, classes: [], attrs: [], comb: comb };
    var i = 0;
    var m = text.match(/^([a-zA-Z*][-a-zA-Z0-9_]*)/);
    if (m) { out.tag = m[1] === '*' ? null : m[1].toLowerCase(); i = m[1].length; }
    while (i < text.length) {
      var ch = text.charAt(i);
      if (ch === '.' || ch === '#') {
        var re = ch === '.' ? /^\.([-a-zA-Z0-9_]+)/ : /^#([-a-zA-Z0-9_]+)/;
        var mm = text.slice(i).match(re);
        if (!mm) { i++; continue; }
        if (ch === '.') out.classes.push(mm[1]); else out.id = mm[1];
        i += mm[0].length;
      } else if (ch === '[') {
        var close = text.indexOf(']', i);
        if (close < 0) break;
        var body = text.slice(i + 1, close);
        var am = body.match(/^([-a-zA-Z0-9_:]+)\s*(?:([*^$]?=)\s*(.*))?$/);
        if (am) {
          var val = am[3];
          if (val !== undefined) {
            val = val.trim();
            if ((val.charAt(0) === '"' && val.charAt(val.length - 1) === '"') ||
                (val.charAt(0) === "'" && val.charAt(val.length - 1) === "'")) {
              val = val.slice(1, -1);
            }
          }
          out.attrs.push({ name: am[1].toLowerCase(), op: am[2] || null, value: val });
        }
        i = close + 1;
      } else {
        i++;
      }
    }
    return out;
  }

  function matchSimple(node, simple) {
    if (!node || !node.tag || node.tag === '#root') return false;
    if (simple.tag && node.tag !== simple.tag) return false;
    if (simple.id && node.attrs.id !== simple.id) return false;
    for (var c = 0; c < simple.classes.length; c++) {
      var cls = ' ' + (node.attrs['class'] || '') + ' ';
      if (cls.indexOf(' ' + simple.classes[c] + ' ') < 0) return false;
    }
    for (var a = 0; a < simple.attrs.length; a++) {
      var want = simple.attrs[a];
      var actual = node.attrs[want.name];
      if (actual === undefined) return false;
      if (want.op === null) continue;
      if (want.op === '=' && actual !== want.value) return false;
      if (want.op === '*=' && actual.indexOf(want.value) < 0) return false;
      if (want.op === '^=' && actual.indexOf(want.value) !== 0) return false;
      if (want.op === '$=' && actual.slice(-want.value.length) !== want.value) return false;
    }
    return true;
  }

  function matchChain(node, chain, idx) {
    if (!matchSimple(node, chain[idx])) return false;
    if (idx === 0) return true;
    var comb = chain[idx].comb;
    var parent = node.parent;
    if (comb === '>') {
      return parent ? matchChain(parent, chain, idx - 1) : false;
    }
    while (parent) {
      if (matchChain(parent, chain, idx - 1)) return true;
      parent = parent.parent;
    }
    return false;
  }

  function walk(node, fn) {
    for (var i = 0; i < node.children.length; i++) {
      var child = node.children[i];
      if (typeof child === 'string') continue;
      fn(child);
      walk(child, fn);
    }
  }

  function rootOf(input) {
    if (typeof input === 'string') return parseHtml(input);
    if (input && input.tag) return input;
    return parseHtml(String(input || ''));
  }

  function selectAll(input, sel) {
    var root = rootOf(input);
    var groups = parseSelector(sel);
    var out = [];
    walk(root, function (node) {
      for (var g = 0; g < groups.length; g++) {
        var chain = groups[g];
        if (matchChain(node, chain, chain.length - 1)) { out.push(node); return; }
      }
    });
    return out;
  }

  function select(input, sel) {
    var all = selectAll(input, sel);
    return all.length ? all[0] : null;
  }

  // ------------------------------------------------------------------ 取值
  function textOf(node) {
    if (node === null || node === undefined) return '';
    if (typeof node === 'string') return node;
    if (typeof node === 'number') return String(node);
    var out = '';
    for (var i = 0; i < node.children.length; i++) {
      var c = node.children[i];
      out += typeof c === 'string' ? c : textOf(c);
    }
    return decodeEntities(out);
  }

  function ownText(node) {
    if (!node) return '';
    if (typeof node === 'string') return node;
    var out = '';
    for (var i = 0; i < node.children.length; i++) {
      var c = node.children[i];
      if (typeof c === 'string') out += c;
    }
    return decodeEntities(out);
  }

  function attrOf(node, name) {
    if (!node || !node.attrs) return '';
    var v = node.attrs[String(name).toLowerCase()];
    return v === undefined ? '' : v;
  }

  function innerHtml(node) {
    if (!node) return '';
    var out = '';
    for (var i = 0; i < node.children.length; i++) {
      var c = node.children[i];
      out += typeof c === 'string' ? c : outerHtml(c);
    }
    return out;
  }

  function outerHtml(node) {
    if (typeof node === 'string') return node;
    if (!node || !node.tag) return '';
    var s = '<' + node.tag;
    for (var k in node.attrs) {
      if (Object.prototype.hasOwnProperty.call(node.attrs, k)) {
        s += ' ' + k + '="' + String(node.attrs[k]).replace(/"/g, '&quot;') + '"';
      }
    }
    s += '>';
    s += innerHtml(node);
    s += '</' + node.tag + '>';
    return s;
  }

  function get(obj, path, def) {
    if (obj === null || obj === undefined) return def;
    if (!path) return obj;
    var parts = String(path).split('.');
    var cur = obj;
    for (var i = 0; i < parts.length; i++) {
      if (cur === null || cur === undefined) return def;
      var key = parts[i];
      if (key === '') continue;
      cur = cur[key];
    }
    return cur === undefined || cur === null ? def : cur;
  }

  function clean(s) {
    if (!s) return '';
    return decodeEntities(String(s).replace(/<[^>]*>/g, '')).replace(/\s+/g, ' ').trim();
  }

  function trim(s) { return s === null || s === undefined ? '' : String(s).replace(/^\s+|\s+$/g, ''); }

  function num(s) {
    if (s === null || s === undefined) return 0;
    var m = String(s).match(/-?\d+(\.\d+)?/);
    return m ? parseFloat(m[0]) : 0;
  }

  function abs(base, url) {
    if (!url) return '';
    var u = String(url).trim();
    if (!u) return '';
    if (/^(https?:|data:|blob:)/i.test(u)) return u;
    var b = String(base || '').replace(/\/+$/, '');
    if (u.indexOf('//') === 0) return 'https:' + u;
    if (u.charAt(0) === '/') {
      var m = b.match(/^(https?:\/\/[^\/]+)/i);
      return (m ? m[1] : '') + u;
    }
    return b + '/' + u.replace(/^\.\//, '');
  }

  function matchAll(str, re, group) {
    if (!str) return [];
    var rx = re instanceof RegExp ? re : new RegExp(re, 'g');
    var flags = rx.flags || '';
    if (flags.indexOf('g') < 0) rx = new RegExp(rx.source, flags + 'g');
    var out = [];
    var m;
    var guard = 0;
    while ((m = rx.exec(str)) !== null) {
      out.push(group === undefined ? m[1] !== undefined ? m[1] : m[0] : (m[group] !== undefined ? m[group] : ''));
      if (m.index === rx.lastIndex) rx.lastIndex++;
      if (++guard > 5000) break;
    }
    return out;
  }

  function first(str, re, group) {
    if (!str) return '';
    var rx = re instanceof RegExp ? new RegExp(re.source, (re.flags || '').replace('g', '')) : new RegExp(re);
    var m = rx.exec(str);
    if (!m) return '';
    if (group === undefined) return m[1] !== undefined ? m[1] : m[0];
    return m[group] === undefined ? '' : m[group];
  }

  function uniq(arr) {
    var seen = {};
    var out = [];
    for (var i = 0; i < (arr || []).length; i++) {
      var k = String(arr[i]);
      if (!seen[k]) { seen[k] = 1; out.push(arr[i]); }
    }
    return out;
  }

  function map(list, fn) {
    var out = [];
    for (var i = 0; i < (list || []).length; i++) out.push(fn(list[i], i));
    return out;
  }

  function pad(n, width) {
    var s = String(n);
    while (s.length < width) s = '0' + s;
    return s;
  }

  // ------------------------------------------------------------------ HTTP
  // 真正的请求由宿主（Dart）发出，脚本侧看到的是「同步」返回。
  // 机制：命中 __poqiCache 直接给结果；没命中就记录到 __poqiPending 并
  // 抛出 __POQI_NEED__，宿主请求完成后带着缓存把脚本整体重跑一遍。
  function gctx() {
    return (typeof globalThis !== 'undefined' ? globalThis : this).__poqiCtx || {};
  }

  function toBody(v) {
    if (v === null || v === undefined) return null;
    if (typeof v === 'string') return v;
    if (typeof v === 'object') return JSON.stringify(v);
    return String(v);
  }

  function dispatch(url, method, body, opts) {
    var o = opts || {};
    var target = trim(String(url === null || url === undefined ? '' : url));
    if (!target) throw new Error('pq.http：url 不能为空');
    if (!/^(https?:)?\/\//i.test(target)) target = abs(gctx().base || '', target);
    var res = (typeof globalThis !== 'undefined' ? globalThis : this).__poqiFetch({
      url: target,
      method: String(method || 'GET').toUpperCase(),
      headers: o.headers || {},
      body: toBody(body),
      timeoutMs: o.timeout || 20000
    });
    return {
      ok: res.ok === true,
      status: res.status || 0,
      url: res.url || target,
      headers: res.headers || {},
      body: res.body === null || res.body === undefined ? '' : String(res.body),
      error: res.error || ''
    };
  }

  function parseJsonText(t) {
    if (!t) return null;
    try { return JSON.parse(String(t)); } catch (e) { return null; }
  }

  var http = {
    request: function (opts) {
      var o = opts || {};
      return dispatch(o.url, o.method || 'GET', o.body, o);
    },
    get: function (url, opts) {
      return dispatch(url, 'GET', null, opts).body;
    },
    post: function (url, body, opts) {
      return dispatch(url, 'POST', body, opts).body;
    },
    put: function (url, body, opts) {
      return dispatch(url, 'PUT', body, opts).body;
    },
    del: function (url, opts) {
      return dispatch(url, 'DELETE', null, opts).body;
    },
    json: function (url, opts) {
      return parseJsonText(dispatch(url, 'GET', null, opts).body);
    },
    postJson: function (url, body, opts) {
      var o = opts || {};
      var headers = {};
      var k;
      if (o.headers) {
        for (k in o.headers) {
          if (Object.prototype.hasOwnProperty.call(o.headers, k)) headers[k] = o.headers[k];
        }
      }
      var hasCt = false;
      for (k in headers) {
        if (Object.prototype.hasOwnProperty.call(headers, k) && k.toLowerCase() === 'content-type') hasCt = true;
      }
      if (!hasCt) headers['Content-Type'] = 'application/json';
      return parseJsonText(dispatch(
        url,
        'POST',
        typeof body === 'string' ? body : JSON.stringify(body),
        { headers: headers, timeout: o.timeout }
      ).body);
    }
  };

  function query(obj) {
    var out = [];
    for (var k in obj) {
      if (!Object.prototype.hasOwnProperty.call(obj, k)) continue;
      var v = obj[k];
      if (v === null || v === undefined || v === '') continue;
      out.push(encodeURIComponent(k) + '=' + encodeURIComponent(String(v)));
    }
    return out.join('&');
  }

  function log() {
    var g = typeof globalThis !== 'undefined' ? globalThis : this;
    if (!g.__poqiLogs) g.__poqiLogs = [];
    var parts = [];
    for (var i = 0; i < arguments.length; i++) {
      var a = arguments[i];
      if (typeof a === 'string') {
        parts.push(a);
      } else {
        try { parts.push(JSON.stringify(a)); } catch (e) { parts.push(String(a)); }
      }
    }
    g.__poqiLogs.push(parts.join(' '));
    if (g.__poqiLogs.length > 200) g.__poqiLogs.shift();
  }

  function now() {
    var t = gctx().now;
    return typeof t === 'number' ? t : Date.now();
  }

  return {
    parseHtml: parseHtml,
    select: select,
    selectAll: selectAll,
    text: textOf,
    ownText: ownText,
    attr: attrOf,
    html: innerHtml,
    outer: outerHtml,
    css: function (input, sel) { return map(selectAll(input, sel), textOf).map(trim); },
    cssAttr: function (input, sel, name) { return map(selectAll(input, sel), function (n) { return attrOf(n, name); }); },
    get: get,
    clean: clean,
    trim: trim,
    num: num,
    abs: abs,
    matchAll: matchAll,
    first: first,
    uniq: uniq,
    map: map,
    pad: pad,
    decode: decodeEntities,
    http: http,
    json: parseJsonText,
    query: query,
    log: log,
    now: now
  };
})();

// --------------------------------------------------------------- HTTP 桥
// __poqiCache 跨轮保留（宿主只在请求成功后才写入），
// __poqiPending 每轮清空，用来判断「这一轮有没有发起新请求」。
(function () {
  var g = typeof globalThis !== 'undefined' ? globalThis : this;
  if (!g.__poqiCache) g.__poqiCache = {};
  if (!g.__poqiPending) g.__poqiPending = [];
  if (!g.__poqiLogs) g.__poqiLogs = [];
})();

function __poqiHttpKey(method, url, body) {
  return String(method || 'GET').toUpperCase() + ' ' + String(url || '') + ' ' +
    (body === null || body === undefined ? '' : String(body));
}

function __poqiFetch(req) {
  var g = typeof globalThis !== 'undefined' ? globalThis : this;
  var method = String(req.method || 'GET').toUpperCase();
  var body = req.body === null || req.body === undefined ? '' : String(req.body);
  var key = __poqiHttpKey(method, req.url, body);
  var hit = g.__poqiCache[key];
  if (hit) return hit;

  var record = {
    url: String(req.url || ''),
    method: method,
    headers: req.headers || {},
    body: body,
    timeoutMs: req.timeoutMs || 20000
  };
  g.__poqiPending.push(record);
  // encodeURIComponent 把 JSON 压成不含空白的 ASCII，宿主从报错首行即可还原。
  throw new Error('__POQI_NEED__' + encodeURIComponent(JSON.stringify(record)));
}

// ---------------------------------------------------------- 脚本装载 / 收集
// 每次重放都重新执行一遍脚本，所以要先清掉上一轮的残留：
//   * __poqiBase 是「首次装载前的全局键快照」，内置函数都在里面，绝不动；
//   * 不在 base 里的键一律视为脚本产物，装载后收进 __poqi[pluginId]。
function __poqiPrepare(id) {
  var g = typeof globalThis !== 'undefined' ? globalThis : this;
  if (!g.__poqiBase) {
    var seed = {};
    var all = Object.keys(g);
    for (var s = 0; s < all.length; s++) seed[all[s]] = 1;
    g.__poqiBase = seed;
  }
  var base = g.__poqiBase;
  var keys = Object.keys(g);
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i];
    if (base[k]) continue;
    if (k.indexOf('__poqi') === 0) continue;   // 宿主自己的内部状态
    if (k === 'pq') continue;                  // 运行时本体
    try { delete g[k]; } catch (e) {
      try { g[k] = undefined; } catch (e2) {}
    }
  }
  g.__poqi = g.__poqi || {};
  g.__poqi[id] = {};
  return 0;
}

function __poqiCollect(id) {
  var g = typeof globalThis !== 'undefined' ? globalThis : this;
  var base = g.__poqiBase || {};
  var bag = {};
  var keys = Object.keys(g);
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i];
    if (base[k]) continue;
    if (k.indexOf('__poqi') === 0) continue;
    if (k === 'pq') continue;
    if (typeof g[k] === 'function') bag[k] = g[k];
    try { delete g[k]; } catch (e) {
      try { g[k] = undefined; } catch (e2) {}
    }
  }
  g.__poqi = g.__poqi || {};
  g.__poqi[id] = bag;
  return 0;
}

// ------------------------------------------------------------------ 派发
function __poqiCall(name, ctx) {
  var fn = (typeof globalThis !== 'undefined' ? globalThis : this)[name];
  if (typeof fn !== 'function') {
    throw new Error('插件脚本缺少函数 ' + name + '()');
  }
  var out = fn(ctx);
  return out === undefined ? null : out;
}

if (typeof globalThis !== 'undefined') {
  globalThis.pq = pq;
  globalThis.__poqiCall = __poqiCall;
  globalThis.__poqiFetch = __poqiFetch;
  globalThis.__poqiHttpKey = __poqiHttpKey;
} else {
  this.pq = pq;
  this.__poqiCall = __poqiCall;
  this.__poqiFetch = __poqiFetch;
  this.__poqiHttpKey = __poqiHttpKey;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    pq: pq,
    __poqiCall: __poqiCall,
    __poqiFetch: __poqiFetch,
    __poqiHttpKey: __poqiHttpKey
  };
}

''';
