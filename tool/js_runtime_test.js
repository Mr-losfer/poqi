#!/usr/bin/env node
/* eslint-disable */
/**
 * JS 插件运行时的离线验证。
 *
 * Flutter 侧用 flutter_js（QuickJS）执行插件，但 `flutter test` 跑在 Dart VM 上，
 * 加载不了原生库，所以这层逻辑没法进单元测试。折中办法：
 *   * JS 运行时与内置插件脚本都以字符串形式存在 Dart 源码里；
 *   * 本脚本把它们抽出来，用 Node 跑同一份代码，验证解析正确性。
 *
 * 用法：node tool/js_runtime_test.js
 * 退出码非 0 表示失败，可直接挂到 CI 的 android job 里（Node 是预装的）。
 */

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function read(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}

/** 从 Dart 的 r'''...''' 里取出字面量内容。 */
function extractRawString(source, marker) {
  const start = source.indexOf(marker);
  if (start < 0) throw new Error('找不到标记：' + marker);
  const open = source.indexOf("r'''", start);
  if (open < 0) throw new Error('标记后面没有 r\'\'\'：' + marker);
  const contentStart = open + 4;
  const end = source.indexOf("'''", contentStart);
  if (end < 0) throw new Error('r\'\'\' 没有闭合：' + marker);
  return source.slice(contentStart, end);
}

/** 从 Dart 的 r"""...""" 里取出字面量内容。 */
function extractRawTripleDouble(source, marker) {
  const start = source.indexOf(marker);
  if (start < 0) throw new Error('找不到标记：' + marker);
  const open = source.indexOf('r"""', start);
  if (open < 0) throw new Error('标记后面没有 r"""：' + marker);
  const contentStart = open + 4;
  const end = source.indexOf('"""', contentStart);
  if (end < 0) throw new Error('r""" 没有闭合：' + marker);
  return source.slice(contentStart, end);
}

const runtimeJs = extractRawString(read('lib/domain/plugin/js/pq_runtime.dart'), 'const String pqRuntimeJs');
const cmsScript = extractRawTripleDouble(read('lib/domain/plugin/builtin.dart'), 'const _cmsV10Script');

vm.runInThisContext(runtimeJs);
vm.runInThisContext(cmsScript);

let pass = 0;
let fail = 0;

function check(name, fn) {
  try {
    fn();
    pass++;
    console.log('  ok   ' + name);
  } catch (e) {
    fail++;
    console.log('  FAIL ' + name + '\n       ' + e.message);
  }
}

function eq(actual, expect, hint) {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expect);
  if (a !== b) {
    throw new Error((hint ? hint + '\n       ' : '') + 'got ' + a + '\n       want ' + b);
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

// ---------------------------------------------------------------------------
// 真实苹果CMS v10 响应样本
// ---------------------------------------------------------------------------
const listBody = {
  code: 1,
  msg: '数据列表',
  page: 1,
  pagecount: 9,
  limit: '20',
  total: 168,
  list: [
    {
      vod_id: 42,
      vod_name: '长夜将尽',
      vod_pic: '/upload/42.jpg',
      vod_year: '2026',
      vod_area: '内地',
      vod_remarks: '更新至 3 集',
      vod_score: '8.9',
      type_name: '剧集',
      vod_blurb: '一场关于<em>时间</em>的实验',
    },
    {
      vod_id: 43,
      vod_name: '雾中灯塔',
      vod_pic: 'https://cdn.example.com/43.jpg',
      vod_year: '2025',
      vod_area: '港台',
      vod_remarks: 'HD',
      vod_score: '7.1',
      type_name: '电影',
    },
  ],
};

const detailBody = {
  code: 1,
  list: [
    {
      vod_id: 42,
      vod_name: '长夜将尽',
      vod_pic: '/upload/42.jpg',
      vod_content: '<p>简介第一段</p><p>第二段</p>',
      vod_director: '陈叙',
      vod_actor: '林恒,周宛/李迟',
      vod_year: '2026',
      vod_area: '内地',
      vod_remarks: '更新至 3 集',
      vod_score: '8.9',
      type_name: '剧集',
      vod_play_from: '量子$$$非凡',
      vod_play_url:
        '第01集$https://x.example.com/1.m3u8#第02集$https://x.example.com/2.m3u8' +
        '#第03集$https://x.example.com/3.m3u8$$$第01集$/y/1.m3u8#第02集$/y/2.m3u8',
    },
  ],
};

// ---------------------------------------------------------------------------
// 装载一个插件脚本：运行时 + 预置的 HTTP 缓存 + 上下文
// ---------------------------------------------------------------------------
function runtimeCacheKey(method, url, body) {
  return String(method || 'GET').toUpperCase() + ' ' + String(url || '') + ' ' +
    (body === null || body === undefined ? '' : String(body));
}

function ok(body, url) {
  return {
    ok: true,
    status: 200,
    body: typeof body === 'string' ? body : JSON.stringify(body),
    headers: { 'content-type': 'application/json' },
    url: url || '',
    error: '',
  };
}

function loadPlugin(rawScript, opts) {
  opts = opts || {};
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(runtimeJs, sandbox);
  if (opts.cache) sandbox.__poqiCache = opts.cache;
  if (opts.ctx) sandbox.__poqiCtx = opts.ctx;
  if (rawScript) vm.runInContext(rawScript, sandbox);
  return sandbox;
}

// ---------------------------------------------------------------------------
console.log('内置 CMS 插件脚本');

const api = 'https://example.com/api.php/provide/vod/';
const siteBase = 'https://example.com';

function cmsOpts(query, body, ctxExtra) {
  const url = api + '?' + query;
  return {
    cache: { [runtimeCacheKey('GET', url, '')]: ok(body, url) },
    ctx: Object.assign({ base: siteBase, cfg: { api } }, ctxExtra || {}),
  };
}

check('home 自己发请求，返回两条并映射字段', () => {
  const box = loadPlugin(cmsScript, cmsOpts('ac=list&pg=1', listBody));
  const out = box.home({ base: siteBase, cfg: { api }, page: 1 });
  eq(out.list.length, 2);
  eq(out.list[0].id, '42', 'id 要转成字符串');
  eq(out.list[0].title, '长夜将尽');
  eq(out.list[0].year, '2026');
  eq(out.list[0].area, '内地');
  eq(out.list[0].remarks, '更新至 3 集');
  eq(out.list[0].score, '8.9');
  eq(out.list[0].kind, '剧集');
  eq(out.list[0].intro, '一场关于时间的实验', '简介要去标签');
  eq(out.list[1].poster, 'https://cdn.example.com/43.jpg', '绝对地址不要动');
  eq(out.hasMore, false, '20 条以下认为没有下一页');
});

check('category / search 走不同参数', () => {
  const catUrl = api + '?ac=list&t=1&pg=2';
  const cat = loadPlugin(cmsScript, {
    cache: { [runtimeCacheKey('GET', catUrl, '')]: ok(listBody, catUrl) },
    ctx: { base: siteBase, cfg: { api } },
  });
  eq(cat.category({ base: siteBase, cfg: { api }, page: 2, category: '1' }).list.length, 2);

  const searchUrl = api + '?ac=detail&wd=%E9%95%BF%E5%A4%9C&pg=1';
  const sea = loadPlugin(cmsScript, {
    cache: { [runtimeCacheKey('GET', searchUrl, '')]: ok(listBody, searchUrl) },
    ctx: { base: siteBase, cfg: { api } },
  });
  eq(sea.search({ base: siteBase, cfg: { api }, page: 1, keyword: '长夜' }).list.length, 2);
});

check('detail 解析出简介、导演、演员、两条线路', () => {
  const url = api + '?ac=detail&ids=42';
  const box = loadPlugin(cmsScript, {
    cache: { [runtimeCacheKey('GET', url, '')]: ok(detailBody, url) },
    ctx: { base: siteBase, cfg: { api } },
  });
  const d = box.detail({ base: siteBase, cfg: { api }, id: '42' });
  eq(d.id, '42');
  eq(d.title, '长夜将尽');
  eq(d.intro, '简介第一段第二段');
  eq(d.director, '陈叙');
  eq(d.actors, ['林恒', '周宛', '李迟'], '中英文逗号与斜杠都要能切');
  eq(d.lines.length, 2, '两条线路');
  eq(d.lines[0].name, '量子');
  eq(d.lines[0].episodes.length, 3);
  eq(d.lines[0].episodes[0].url, 'https://x.example.com/1.m3u8');
  eq(d.lines[1].name, '非凡');
  eq(d.lines[1].episodes[0].url, 'https://example.com/y/1.m3u8', '相对地址要补全');
});

check('剧集串异常时不崩', () => {
  const url = api + '?ac=detail&ids=1';
  const box = loadPlugin(cmsScript, {
    cache: {
      [runtimeCacheKey('GET', url, '')]: ok({ list: [{ vod_id: 1, vod_name: 'x', vod_play_url: '' }] }, url),
    },
    ctx: { base: siteBase, cfg: { api } },
  });
  eq(box.detail({ base: siteBase, cfg: { api }, id: '1' }).lines, []);
});

check('play 直接回显剧集地址', () => {
  const box = loadPlugin(cmsScript, { ctx: { base: siteBase, cfg: { api } } });
  eq(box.play({ id: 'https://x.example.com/1.m3u8' }).url, 'https://x.example.com/1.m3u8');
  eq(box.play({ id: '' }).url, '');
});

check('没配接口地址时给出可读错误', () => {
  const box = loadPlugin(cmsScript, { ctx: { base: siteBase, cfg: { api: '' } } });
  let msg = '';
  try {
    box.home({ base: siteBase, cfg: { api: '' }, page: 1 });
  } catch (e) {
    msg = e.message;
  }
  assert(msg.indexOf('接口地址') >= 0, '应该提示填接口地址，实际：' + msg);
});

check('请求未命中时抛 __POQI_NEED__，宿主能从消息里还原请求', () => {
  const box = loadPlugin(cmsScript, { ctx: { base: siteBase, cfg: { api } } });
  let msg = '';
  try {
    box.home({ base: siteBase, cfg: { api }, page: 1 });
  } catch (e) {
    msg = e.message;
  }
  const marker = '__POQI_NEED__';
  const idx = msg.indexOf(marker);
  assert(idx >= 0, '没有拿到中断信号：' + msg);
  const token = msg.slice(idx + marker.length).trim().split(/\s+/)[0];
  const req = JSON.parse(decodeURIComponent(token));
  eq(req.url, api + '?ac=list&pg=1');
  eq(req.method, 'GET');
});

check('接口返回非 JSON 时报错而不是静默返回空', () => {
  const url = api + '?ac=list&pg=1';
  const box = loadPlugin(cmsScript, {
    cache: { [runtimeCacheKey('GET', url, '')]: ok('<html>403</html>', url) },
    ctx: { base: siteBase, cfg: { api } },
  });
  let msg = '';
  try {
    box.home({ base: siteBase, cfg: { api }, page: 1 });
  } catch (e) {
    msg = e.message;
  }
  assert(msg.indexOf('JSON') >= 0, '应该提示不是 JSON，实际：' + msg);
});

check('脚本声明的函数齐全', () => {
  const box = loadPlugin(cmsScript, { ctx: { base: siteBase, cfg: { api } } });
  for (const fn of ['home', 'category', 'search', 'detail', 'play']) {
    assert(typeof box[fn] === 'function', '缺少函数 ' + fn);
  }
  eq(box.plugin.id, 'poqi.cms.v10');
  eq(box.plugin.config.length, 2);
});

// ---------------------------------------------------------------------------
console.log('\nTVBox 插件脚本');

const tvboxScript = extractRawTripleDouble(read('lib/domain/plugin/builtin.dart'), 'const _tvboxScript');

check('默认挑第一个 type=1 的站点', () => {
  const iface = 'https://example.com/tvbox.json';
  const target = 'https://b.example.com/api.php/provide/vod/';
  const box = loadPlugin(tvboxScript, {
    cache: {
      [runtimeCacheKey('GET', iface, '')]: ok({
        sites: [
          { key: 'csp_a', name: 'A站', type: 3, api: 'https://a/api' },
          { key: 'csp_b', name: 'B站', type: 1, api: target },
        ],
      }, iface),
      [runtimeCacheKey('GET', target + '?ac=list&pg=1', '')]: ok(listBody, target),
    },
    ctx: { base: '', cfg: { interface: iface, siteKey: '' } },
  });
  const out = box.home({ base: '', cfg: { interface: iface, siteKey: '' }, page: 1 });
  eq(out.list.length, 2);
  eq(out.list[0].title, '长夜将尽');
});

check('siteKey 可以按 name 精确指定', () => {
  const iface = 'https://example.com/tvbox.json';
  const target = 'https://c.example.com/api/';
  const box = loadPlugin(tvboxScript, {
    cache: {
      [runtimeCacheKey('GET', iface, '')]: ok({
        sites: [
          { key: 'csp_b', name: 'B站', type: 1, api: 'https://b/api' },
          { key: 'csp_c', name: 'C站', type: 1, api: target },
        ],
      }, iface),
      [runtimeCacheKey('GET', target + '?ac=list&pg=1', '')]: ok(listBody, target),
    },
    ctx: { base: '', cfg: { interface: iface, siteKey: 'C站' } },
  });
  eq(box.home({ base: '', cfg: { interface: iface, siteKey: 'C站' }, page: 1 }).list.length, 2);
});

check('找不到站点时提示清楚', () => {
  const iface = 'https://example.com/tvbox.json';
  const box = loadPlugin(tvboxScript, {
    cache: {
      [runtimeCacheKey('GET', iface, '')]: ok({ sites: [{ key: 'x', name: 'X', type: 3 }] }, iface),
    },
    ctx: { base: '', cfg: { interface: iface, siteKey: '' } },
  });
  let msg = '';
  try {
    box.home({ base: '', cfg: { interface: iface, siteKey: '' }, page: 1 });
  } catch (e) {
    msg = e.message;
  }
  assert(msg.indexOf('type=1') >= 0, '应该提示没有 type=1 的站点，实际：' + msg);
});

// ---------------------------------------------------------------------------
console.log('\npq 工具');

const util = loadPlugin('');

check('pq.query 拼装并跳过空值', () => {
  eq(util.pq.query({ ac: 'list', pg: 2, t: '', u: null }), 'ac=list&pg=2');
  eq(util.pq.query({ wd: '长 夜' }), 'wd=%E9%95%BF%20%E5%A4%9C');
});

check('pq.http.request 返回完整结构', () => {
  const url = 'https://x.example.com/a';
  const box = loadPlugin('', {
    cache: { [runtimeCacheKey('GET', url, '')]: ok('hello', url) },
    ctx: { base: 'https://x.example.com' },
  });
  const r = box.pq.http.request({ url: '/a' });
  eq(r.ok, true);
  eq(r.status, 200);
  eq(r.body, 'hello');
  eq(r.url, url);
});

check('相对地址按 p.base 补全', () => {
  const url = 'https://x.example.com/api/list';
  const box = loadPlugin('', {
    cache: { [runtimeCacheKey('GET', url, '')]: ok('[]', url) },
    ctx: { base: 'https://x.example.com' },
  });
  eq(box.pq.http.get('/api/list'), '[]');
});

// ---------------------------------------------------------------------------
console.log('\n新建插件模板');

check('HTML 模板能加载且函数齐全', () => {
  const tpl = extractRawTripleDouble(read('lib/features/plugins/plugins_page.dart'), 'const String _templateHtml');
  const box = loadPlugin(tpl, { ctx: { base: 'https://example.com', cfg: {} } });
  eq(box.plugin.id, 'custom.mysite');
  eq(box.plugin.name, '我的站点');
  for (const fn of ['home', 'category', 'search', 'detail', 'play']) {
    assert(typeof box[fn] === 'function', '缺少函数 ' + fn);
  }
});

check('JSON 模板能加载且声明了 api 配置', () => {
  const tpl = extractRawTripleDouble(read('lib/features/plugins/plugins_page.dart'), 'const String _templateJson');
  const box = loadPlugin(tpl, { ctx: { base: 'https://example.com', cfg: {} } });
  eq(box.plugin.config[0].key, 'api');
  eq(box.plugin.config[0].required, true);
});

// ---------------------------------------------------------------------------
console.log('\nCSS 选择器（HTML 站点会用到）');
const html = `<div class="box"><ul><li class="v"><a href="/p/1" title="甲">甲<span>HD</span></a></li>
<li class="v"><a href="/p/2">乙</a></li></ul><img data-original="/i/1.jpg"></div>`;
const pq = util.pq;

check('后代选择器取到 2 条', () => {
  eq(pq.selectAll(html, 'ul li a').length, 2);
  eq(pq.css(html, 'ul li a'), ['甲HD', '乙']);
  eq(pq.cssAttr(html, 'ul li a', 'href'), ['/p/1', '/p/2']);
  eq(pq.cssAttr(html, 'img', 'data-original'), ['/i/1.jpg']);
});

check('子代与属性选择器', () => {
  eq(pq.selectAll(html, 'div > ul').length, 1);
  eq(pq.selectAll(html, 'div > li').length, 0);
  eq(pq.selectAll(html, 'a[href^="/p/"]').length, 2);
  eq(pq.selectAll(html, 'a[title]').length, 1);
});

// ---------------------------------------------------------------------------
console.log('\n重放联调（模拟宿主补数据后重跑脚本）');

function runReplay(box, fnName, ctx, fetchFn, maxRounds) {
  const limit = maxRounds || 8;
  box.__poqiCtx = ctx;
  for (let i = 0; i < limit; i++) {
    box.__poqiPending = [];
    try {
      const out = box[fnName](ctx);
      if (!box.__poqiPending.length) return out;
      // 脚本把中断信号吞掉了：仍需补数据后重跑
      const p0 = box.__poqiPending[0];
      box.__poqiCache[runtimeCacheKey(p0.method, p0.url, p0.body)] = fetchFn(p0);
    } catch (e) {
      const msg = String((e && e.message) || e);
      const idx = msg.indexOf('__POQI_NEED__');
      if (idx < 0) throw e;
      const token = msg.slice(idx + '__POQI_NEED__'.length).trim().split(/\s+/)[0];
      const req = JSON.parse(decodeURIComponent(token));
      box.__poqiCache[runtimeCacheKey(req.method, req.url, req.body)] = fetchFn(req);
    }
  }
  throw new Error('超过轮数上限');
}

check('两次串联请求能在两轮内完成', () => {
  const script = `
var plugin = { id: 'x', name: 'x' };
function home(p) {
  var a = pq.http.get('https://a/1');
  var b = pq.http.get('https://a/2');
  return { list: [{ id: a + b, title: 'ok' }] };
}`;
  const box = loadPlugin(script, { ctx: { base: '' } });
  const seen = [];
  const out = runReplay(box, 'home', { base: '' }, (r) => {
    seen.push(r.url);
    const body = r.url.endsWith('/1') ? 'A' : 'B';
    return { ok: true, status: 200, body: body, headers: {}, url: r.url, error: '' };
  });
  eq(out.list[0].id, 'AB');
  eq(seen, ['https://a/1', 'https://a/2']);
});

check('脚本自己 try/catch 吞掉中断信号时，宿主仍能补数据', () => {
  const script = `
var plugin = { id: 'y', name: 'y' };
function home(p) {
  var body = '';
  try { body = pq.http.get('https://a/9'); } catch (e) { body = ''; }
  return { list: body ? [{ id: '1', title: body }] : [] };
}`;
  const box = loadPlugin(script, { ctx: { base: '' } });
  let hits = 0;
  const out = runReplay(box, 'home', { base: '' }, (r) => {
    hits++;
    return { ok: true, status: 200, body: 'RESCUED', headers: {}, url: r.url, error: '' };
  });
  eq(hits, 1);
  eq(out.list.length, 1);
  eq(out.list[0].title, 'RESCUED');
});

check('重跑不会让上一次的函数残留（同名函数不会串味）', () => {
  const a = loadPlugin(`
var plugin = { id: 'a', name: 'a' };
function home(p) { return 'A'; }`, {});
  const first = a.home({ base: '' });
  // 模拟 __poqiPrepare：清理上一轮脚本产物
  a.__poqiBase = a.__poqiBase || {};
  Object.keys(a).forEach((k) => {
    if (k.indexOf('__poqi') === 0 || k === 'pq' || k === 'console') return;
    if (a.__poqiBase[k]) return;
    try { delete a[k]; } catch (e) {}
  });
  vm.runInContext("var plugin = { id: 'b', name: 'b' }; function home(p) { return 'B'; }", a);
  eq(first, 'A');
  eq(a.home({ base: '' }), 'B');
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
