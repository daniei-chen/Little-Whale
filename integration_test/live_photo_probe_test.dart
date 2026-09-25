// 探测：微博 / 快手 / 知乎 的真实数据里，有没有「动图」相关的字段。
//
// 这三个平台的"动图"是否存在，我不确定 —— 与其猜，不如把真实数据打出来看。
// 只要数据里出现 livePhoto / stream / video 这类每图一个视频的结构，
// 那就是有动图；没有就不要硬做。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/local/engine.dart';

Future<void> mount(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocalEngineHost())));
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (LocalEngine.instance.isReady) break;
  }
}

String js(String code) =>
    '(function(){ try { $code } catch(e) { return JSON.stringify({error:String(e)}); } })()';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('微博：数据里有没有 LivePhoto 字段', (tester) async {
    await mount(tester);
    final e = LocalEngine.instance;
    await e.setUserAgent(LocalEngine.desktopUa);

    // 微博的接口要在页面里用同步 XHR 打（带 Cookie）
    await e.evaluate('https://m.weibo.cn/detail/5337608997570566',
        'String(window.location.href)',
        settle: const Duration(seconds: 8));

    final r = await e.evalCurrent(js(r'''
      var x = new XMLHttpRequest();
      x.open('GET', 'https://m.weibo.cn/statuses/show?id=5337608997570566', false);
      x.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
      x.setRequestHeader('Accept', 'application/json');
      x.send();
      var t = x.responseText || '';
      var out = { len: t.length };
      try {
        var j = JSON.parse(t);
        var d = j.data || j;
        out.topKeys = Object.keys(d).slice(0, 40);
        out.picCount = (d.pics || []).length;
        if (d.pics && d.pics.length) {
          out.pic0Keys = Object.keys(d.pics[0]);
          out.pic0 = JSON.stringify(d.pics[0]).slice(0, 700);
        }
        // 找动图相关字段
        out.hasLive = t.indexOf('live') > -1 || t.indexOf('Live') > -1;
        out.hasLivePhoto = t.indexOf('livePhoto') > -1 || t.indexOf('live_photo') > -1;
        out.hasStream = t.indexOf('stream') > -1;
        out.hasVideo = t.indexOf('video') > -1;
        out.pageInfo = d.page_info ? JSON.stringify(d.page_info).slice(0, 400) : '(无)';
        // pics 里每一项的字段名汇总
        var keys = {};
        (d.pics || []).forEach(function (p) {
          Object.keys(p).forEach(function (k) { keys[k] = (keys[k] || 0) + 1; });
        });
        out.allPicKeys = keys;
      } catch (err) { out.parseErr = String(err); out.head = t.slice(0, 300); }
      return JSON.stringify(out);
    '''));

    final s = r.toString();
    for (var i = 0; i < s.length; i += 500) {
      // ignore: avoid_print
      print('[微博探] ${s.substring(i, i + 500 > s.length ? s.length : i + 500)}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('快手：图集作品里每张图有没有视频', (tester) async {
    await mount(tester);
    final e = LocalEngine.instance;
    await e.setUserAgent(LocalEngine.mobileUa);

    await e.evaluate('https://v.kuaishou.com/JjikGmiZ', 'String(window.location.href)',
        settle: const Duration(seconds: 10));

    final r = await e.evalCurrent(js(r'''
      var out = { href: String(location.href).slice(0, 110) };
      var html = document.documentElement.outerHTML || '';
      out.hasLivePhoto = html.indexOf('livePhoto') > -1;
      out.hasLive = html.indexOf('live') > -1;
      out.hasAtlas = html.indexOf('atlas') > -1;
      out.hasPhotoVideo = html.indexOf('photoVideo') > -1 || html.indexOf('photo_video') > -1;
      // 找所有 mp4 线索
      var m = html.match(/https?:[^"'\s\\]{10,220}\.mp4[^"'\s\\]{0,80}/g) || [];
      out.mp4Count = m.length;
      out.mp40 = m.length ? m[0].slice(0, 150) : '';
      // 找图集字段
      var a = html.match(/"atlas"[^}]{0,300}/);
      out.atlasCtx = a ? a[0].slice(0, 300) : '(无)';
      var lp = html.match(/"livePhoto"[^,}]{0,200}/);
      out.liveCtx = lp ? lp[0].slice(0, 200) : '(无)';
      return JSON.stringify(out);
    '''));

    final s = r.toString();
    for (var i = 0; i < s.length; i += 500) {
      // ignore: avoid_print
      print('[快手探] ${s.substring(i, i + 500 > s.length ? s.length : i + 500)}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('知乎：专栏里有没有动图/视频字段', (tester) async {
    await mount(tester);
    final e = LocalEngine.instance;
    await e.setUserAgent(LocalEngine.desktopUa);

    await e.evaluate('https://zhuanlan.zhihu.com/p/28852607',
        'String(window.location.href)',
        settle: const Duration(seconds: 10));

    final r = await e.evalCurrent(js(r'''
      var out = {};
      var html = document.documentElement.outerHTML || '';
      out.hasLivePhoto = html.indexOf('livePhoto') > -1 || html.indexOf('live_photo') > -1;
      out.hasVideo = html.indexOf('"video"') > -1;
      out.videoTags = document.querySelectorAll('video').length;
      // 图里的 gif
      var gifs = 0;
      document.querySelectorAll('img').forEach(function (i) {
        var s = i.currentSrc || i.src || '';
        if (/\.gif/i.test(s)) gifs++;
      });
      out.gifImgs = gifs;
      // 页面上有没有 gif 地址
      var m = html.match(/https?:[^"'\s\\]{10,200}\.gif[^"'\s\\]{0,60}/g) || [];
      out.gifUrls = m.length;
      out.gif0 = m.length ? m[0].slice(0, 140) : '';
      // 知乎视频
      var v = document.querySelectorAll('video');
      out.videoSrcs = [];
      for (var i = 0; i < v.length && i < 3; i++) {
        out.videoSrcs.push(String(v[i].currentSrc || v[i].src || '').slice(0, 140));
      }
      return JSON.stringify(out);
    '''));

    final s = r.toString();
    for (var i = 0; i < s.length; i += 500) {
      // ignore: avoid_print
      print('[知乎探] ${s.substring(i, i + 500 > s.length ? s.length : i + 500)}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
