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

const base = 'https://example.com/api.php/provide/vod/';
const siteBase = 'https://example.com';

// ---------------------------------------------------------------------------
console.log('内置 CMS 插件脚本');

check('home 返回两条，字段映射正确', () => {
  const out = home({ json: listBody, base: siteBase, page: 1 });
  eq(out.length, 2);
  eq(out[0].id, '42', 'id 要转成字符串');
  eq(out[0].title, '长夜将尽');
  eq(out[0].poster, 'https://example.com/upload/42.jpg', '相对海报要补全');
  eq(out[0].year, '2026');
  eq(out[0].area, '内地');
  eq(out[0].remarks, '更新至 3 集');
  eq(out[0].score, '8.9');
  eq(out[0].kind, '剧集');
  eq(out[0].intro, '一场关于时间的实验', '简介要去标签');
  eq(out[1].poster, 'https://cdn.example.com/43.jpg', '绝对地址不要动');
});

check('category / search 与 home 共用映射', () => {
  eq(category({ json: listBody, base: siteBase }).length, 2);
  eq(search({ json: listBody, base: siteBase, keyword: '长夜' }).length, 2);
});

check('空响应安全返回空数组', () => {
  eq(home({ json: null, base: siteBase }), []);
  eq(home({ json: { code: 0, list: [] }, base: siteBase }), []);
  eq(detail({ json: {}, base: siteBase, id: '99' }).id, '99', '详情缺数据时用请求 id 兜底');
});

check('detail 解析出简介、导演、演员、两条线路', () => {
  const d = detail({ json: detailBody, base: siteBase, id: '42' });
  eq(d.id, '42');
  eq(d.title, '长夜将尽');
  eq(d.intro, '简介第一段第二段');
  eq(d.director, '陈叙');
  eq(d.actors, ['林恒', '周宛', '李迟'], '中英文逗号与斜杠都要能切');
  eq(d.lines.length, 2, '两条线路');
  eq(d.lines[0].name, '量子');
  eq(d.lines[0].episodes.length, 3);
  eq(d.lines[0].episodes[0].name, '第01集');
  eq(d.lines[0].episodes[0].url, 'https://x.example.com/1.m3u8');
  eq(d.lines[1].name, '非凡');
  eq(d.lines[1].episodes.length, 2);
  eq(d.lines[1].episodes[0].url, 'https://example.com/y/1.m3u8', '相对地址要补全');
});

check('剧集串异常时不崩', () => {
  const d1 = detail({ json: { list: [{ vod_id: 1, vod_name: 'x', vod_play_url: '' }] }, base: siteBase, id: '1' });
  eq(d1.lines, []);
  const d2 = detail({
    json: { list: [{ vod_id: 2, vod_name: 'y', vod_play_from: 'A', vod_play_url: '第1集$http://a/1#第2集$http://a/2$$$第1集$http://b/1' }] },
    base: siteBase,
    id: '2',
  });
  eq(d2.lines.length, 2, '线路名少于组数时补默认名');
  eq(d2.lines[1].name, '线路2');
  const d3 = detail({
    json: { list: [{ vod_id: 3, vod_name: 'z', vod_play_url: 'http://a/1#http://a/2' }] },
    base: siteBase,
    id: '3',
  });
  eq(d3.lines[0].episodes[0].name, '第1集', '没有 $ 时自动编号');
});

check('play 直接回显剧集地址', () => {
  eq(play({ id: 'https://x.example.com/1.m3u8' }).url, 'https://x.example.com/1.m3u8');
  eq(play({ id: '' }).url, '');
});

check('脚本声明的函数齐全', () => {
  for (const fn of ['home', 'category', 'search', 'detail', 'play']) {
    assert(typeof globalThis[fn] === 'function', '缺少函数 ' + fn);
  }
});

// ---------------------------------------------------------------------------
console.log('\nCSS 选择器（HTML 站点会用到）');
const html = `<div class="box"><ul><li class="v"><a href="/p/1" title="甲">甲<span>HD</span></a></li>
<li class="v"><a href="/p/2">乙</a></li></ul><img data-original="/i/1.jpg"></div>`;

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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
