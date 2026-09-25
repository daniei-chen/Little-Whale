// 小鲸鱼 App · 测试
//
// 分三层：
//   1. 纯函数 / 数据契约 —— 不需要设备，最快
//   2. 页面渲染 —— 用 Widget 测试把三个页面真正画出来并断言关键元素
//   3. 直连下载的 URL 解析 —— 这是「省服务器流量」那条路径的核心

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flashsave/main.dart';
import 'package:flashsave/local/types.dart';
import 'package:flashsave/local/registry.dart';
import 'package:flashsave/config.dart';
import 'package:flashsave/data/platforms.dart';
import 'package:flashsave/data/local_store.dart';
import 'package:flashsave/models/parse_result.dart';
import 'package:flashsave/services/download_service.dart';
import 'package:flashsave/widgets/net_image.dart';
import 'package:flashsave/services/update_service.dart';
import 'package:flashsave/state/app_state.dart';

/// 构造一条和后端返回结构一致的结果
ParseResult mockVideo({String title = '测试视频标题'}) => ParseResult.fromJson({
      'id': 'douyin_123',
      'platform': 'douyin',
      'platformName': '抖音',
      'platformColor': '#161823',
      'platformSoft': 'rgba(22, 24, 35, 0.07)',
      'type': 'video',
      'title': title,
      'author': '@测试作者',
      'authorInitial': '测',
      'duration': '00:13',
      'resolution': 'normal_1080_0',
      'size': '8.6 MB',
      'publishTime': '2026-09-07',
      'music': '@测试原声',
      'noWatermarkUrl': 'http://10.0.2.2:8787/media?u=aHR0cHM6Ly9hL2IubXA0&r=aHR0cHM6Ly92LmRvdXlpbi5jb20v',
      'watermarkUrl': 'http://10.0.2.2:8787/media?u=aHR0cHM6Ly9hL2MubXA0',
      'sourceUrl': 'https://v.douyin.com/abc/',
      'parsedAt': DateTime.now().millisecondsSinceEpoch,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 单例把 SharedPreferences 实例缓存住了，必须清掉，
    // 否则后续测试里的 setMockInitialValues 不生效。
    LocalStore.instance.resetCacheForTests();

    // 单例状态在测试之间会残留，这里重置
    AppState.instance.rawText = '';
    AppState.instance.result = null;
    AppState.instance.error = null;
    AppState.instance.parsing = false;
    AppState.instance.tabIndex = 0;
    AppState.instance.detected = null;
    AppState.instance.history = const [];
  });

  /// 造好本地数据再引导 AppState（顺序很重要：先 mock 再 bootstrap）
  Future<void> seedAndBoot(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    LocalStore.instance.resetCacheForTests();
    await AppState.instance.bootstrap();
  }

  /* ================================================================
   * 一、纯函数与数据契约
   * ================================================================ */

  group('链接提取与平台识别', () {
    test('从分享文案里提取链接', () {
      expect(extractUrl('7.15 复制打开抖音 https://v.douyin.com/abc/ 看看'),
          'https://v.douyin.com/abc/');
      // 结尾的中文标点不能被吞进 URL
      expect(extractUrl('看看这个 https://b23.tv/xyz。'), 'https://b23.tv/xyz');
      expect(extractUrl('没有链接的一段话'), isNull);
      expect(extractUrl(null), isNull);
    });

    test('六个平台都能识别', () {
      expect(detectPlatform('https://v.douyin.com/abc/')?.key, 'douyin');
      expect(detectPlatform('https://xhslink.com/a/b')?.key, 'xhs');
      expect(detectPlatform('https://www.bilibili.com/video/BV1xx')?.key, 'bilibili');
      expect(detectPlatform('https://m.weibo.cn/detail/123456')?.key, 'weibo');
      expect(detectPlatform('https://v.kuaishou.com/abc')?.key, 'kuaishou');
      expect(detectPlatform('https://zhuanlan.zhihu.com/p/123')?.key, 'zhihu');

      // 明确**不做**的平台，识别不出来才是对的 ——
      // 不能假装支持，然后在解析时才失败。
      expect(detectPlatform('https://www.toutiao.com/article/123/'), isNull);
      expect(detectPlatform('https://v.youku.com/v_show/id_x.html'), isNull);
    });
  });

  group('相对时间格式化', () {
    test('各档位', () {
      final now = DateTime(2026, 9, 24, 22, 0);
      String rel(Duration d) =>
          formatRelative(now.subtract(d).millisecondsSinceEpoch, now: now);

      expect(rel(const Duration(seconds: 10)), '刚刚');
      expect(rel(const Duration(minutes: 5)), '5 分钟前');
      expect(rel(const Duration(hours: 3)), '3 小时前');
      expect(rel(const Duration(days: 1)), '昨天 22:00');
      expect(rel(const Duration(days: 3)), '09-21 22:00');
      expect(rel(const Duration(days: 30)), '2026-08-25');
    });
  });

  group('解析结果契约', () {
    test('视频字段与颜色解析', () {
      final r = mockVideo();
      expect(r.isVideo, isTrue);
      expect(r.platformName, '抖音');
      expect(r.platformColorValue, 0xFF161823);
      // rgba(22,24,35,0.07) → alpha ≈ 18
      expect((r.platformSoftValue >> 24) & 0xFF, closeTo(18, 2));
      expect((r.platformSoftValue >> 16) & 0xFF, 22);
    });

    test('清晰度展示值：内部标识要变成人能读的形式', () {
      expect(mockVideo().resolutionLabel, '1080P');           // normal_1080_0
      expect(
        ParseResult.fromJson({'id': 'x', 'platform': 'bilibili', 'type': 'video',
          'title': 't', 'resolution': '720P'}).resolutionLabel,
        '720P',
      );
      expect(
        ParseResult.fromJson({'id': 'x', 'platform': 'bilibili', 'type': 'video',
          'title': 't', 'resolution': ''}).resolutionLabel,
        '',
      );
      // 识别不出来就原样返回，不瞎猜
      expect(
        ParseResult.fromJson({'id': 'x', 'platform': 'bilibili', 'type': 'video',
          'title': 't', 'resolution': '未知清晰度'}).resolutionLabel,
        '未知清晰度',
      );
    });

    test('图文结果与序列化往返', () {
      final r = ParseResult.fromJson({
        'id': 'xhs_1', 'platform': 'xhs', 'platformName': '小红书', 'type': 'images',
        'title': '图文笔记',
        'images': [
          {'url': 'https://x/1.jpg', 'thumb': 'https://x/1t.jpg', 'index': 0},
          {'url': 'https://x/2.jpg', 'index': 1},
        ],
        'imageCount': 2,
      });
      expect(r.isImages, isTrue);
      expect(r.images.length, 2);

      final back = ParseResult.decode(r.encode());
      expect(back.images.length, 2);
      expect(back.images[1].url, 'https://x/2.jpg');
      expect(back.title, '图文笔记');
    });
  });

  group('文件后缀要按真实容器判断', () {
    test('QuickTime 头识别为 .mov —— 小红书会把 mov 报成 video/mp4', () {
      // 小红书原始视频对象的真实文件头：ftypqt
      const qt = [0, 0, 0, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74, 0x20, 0x20];
      expect(DownloadService.extFromMagicBytes(qt), '.mov');
    });

    test('标准 MP4 头（ftypisom）识别为 .mp4', () {
      const mp4 = [0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D];
      expect(DownloadService.extFromMagicBytes(mp4), '.mp4');
    });

    test('常见图片头也要认出来', () {
      expect(DownloadService.extFromMagicBytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]), '.jpg');
      expect(DownloadService.extFromMagicBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]), '.png');
      expect(DownloadService.extFromMagicBytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0, 0, 0, 0, 0]), '.gif');
    });

    test('认不出来时返回 null，交给上层兜底', () {
      expect(DownloadService.extFromMagicBytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]), isNull);
    });
  });

  group('版本号与更新检查', () {
    // config.dart 里的版本号要手动跟 pubspec 对齐（为了少一个依赖），
    // 这条测试就是防止改了一处忘了另一处。
    test('config.dart 的版本号必须和 pubspec.yaml 一致', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*([0-9.]+)\+(\d+)', multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull, reason: 'pubspec.yaml 里应当有 version: x.y.z+n');

      expect(kAppVersion, m!.group(1),
          reason: 'config.dart 的 kAppVersion 与 pubspec 不一致');
      expect(kAppBuild, int.parse(m.group(2)!),
          reason: 'config.dart 的 kAppBuild 与 pubspec 不一致');
    });

    test('更新清单能正确解析，脏数据不会当成新版本', () {
      final ok = UpdateInfo.fromJson({
        'build': 5,
        'version': '1.1.0',
        'url': 'https://example.com/app.apk',
        'notes': '新增快手、知乎',
        'force': false,
      });
      expect(ok, isNotNull);
      expect(ok!.build, 5);
      expect(ok.version, '1.1.0');
      expect(ok.force, isFalse);

      // 缺 build、根本不是 Map —— 都必须返回 null 而不是崩
      expect(UpdateInfo.fromJson({'version': '1.1.0'}), isNull);
      expect(UpdateInfo.fromJson('垃圾数据'), isNull);
      expect(UpdateInfo.fromJson(null), isNull);

      // 缺 url：**测试环境没有注入 DOWNLOAD_PAGE**，所以下载地址是空的，
      // 等于「有新版却点不动」，应当当脏数据丢掉。
      // （真机上有注入，这条会走另一条分支 —— 见下面那条测试）
      expect(UpdateInfo.fromJson({'build': 5}), isNull);
    });
  });
  group('平台列表一致性（防止界面和解析器脱节）', () {
    // 这组测试是有来历的：快手/微博/知乎做完后，首页那排平台标签还是
    // 写死的旧列表，用户装上后以为只支持三个平台。
    // 所以把「界面列表」和「能解析的平台」绑在一起断言，让它们不能再脱节。
    test('界面上展示的平台数 = 解析器支持的平台数 = 6', () {
      expect(kPlatforms.length, 6);
      expect(LocalRegistry.all.length, 6);
    });

    test('两个列表的 key 必须一一对应', () {
      final uiKeys = kPlatforms.map((p) => p.key).toSet();
      final parseKeys = LocalRegistry.all.map((p) => p.key).toSet();
      expect(uiKeys, parseKeys,
          reason: '界面显示的平台必须都能解析，能解析的也必须都显示出来');
    });

    test('六个平台的真实分享文案都能被识别出来', () {
      const samples = {
        'douyin': '4.17 复制打开抖音，看看【某人的作品】 https://v.douyin.com/ABCdef123/ 11/01',
        'xhs': '爱学习的小狗有出息 https://xhslink.cn/o/1AejNnW65yA 复制一下',
        'bilibili': '【标题】 https://b23.tv/AbCdEf',
        'weibo': '分享一下 https://m.weibo.cn/detail/5337608997570566',
        'kuaishou': '看看这个 https://v.kuaishou.com/JjikGmiZ',
        'zhihu': '这篇不错 https://zhuanlan.zhihu.com/p/28852607',
      };

      for (final entry in samples.entries) {
        expect(extractUrl(entry.value), isNotNull,
            reason: '要能从这段文案里把链接抠出来：${entry.value}');
        expect(detectPlatform(entry.value)?.key, entry.key,
            reason: '这段文案应当被识别为 ${entry.key}：${entry.value}');
      }
    });
  });
  group('图片多选与单张保存', () {
    test('默认全选，可单张切换、可全不选', () async {
      await seedAndBoot({});
      final s = AppState.instance;

      s.result = ParseResult.fromLocal(
        'douyin', '抖音', 'images', '测试图集',
        referer: 'https://www.douyin.com/',
        images: const [
          {'url': 'https://a/1.jpg', 'width': 100, 'height': 100},
          {'url': 'https://a/2.jpg', 'width': 100, 'height': 100},
          {'url': 'https://a/3.jpg', 'width': 100, 'height': 100},
        ],
      );
      s.pickAll();

      expect(s.pickedCount, 3);
      expect(s.allPicked, isTrue);

      s.togglePick(1); // 取消第 2 张
      expect(s.pickedCount, 2);
      expect(s.isPicked(1), isFalse);
      expect(s.allPicked, isFalse);

      s.pickNone();
      expect(s.pickedCount, 0);
      expect(s.allPicked, isFalse);

      s.pickAll();
      expect(s.pickedCount, 3);
      expect(s.allPicked, isTrue);
    });

    test('一张都没勾时保存会被拦住，而不是静默失败', () async {
      await seedAndBoot({});
      final s = AppState.instance;
      s.result = ParseResult.fromLocal(
        'douyin', '抖音', 'images', '测试图集',
        images: const [
          {'url': 'https://a/1.jpg'},
        ],
      );
      s.pickNone();

      final outcome = await s.saveAllImages();
      expect(outcome.saved, isFalse);
      expect(outcome.message, contains('选'));
    });

    test('单张保存：下标越界要报错，不能崩', () async {
      await seedAndBoot({});
      final s = AppState.instance;
      s.result = ParseResult.fromLocal(
        'douyin', '抖音', 'images', '测试图集',
        images: const [
          {'url': 'https://a/1.jpg'},
        ],
      );

      final bad = await s.saveSingleImage(5);
      expect(bad.saved, isFalse);
      expect(bad.message, contains('不存在'));
    });
  });

  group('直连下载：从代理地址里拆原始直链', () {
    test('能解出 u（目标直链）与 r（Referer）', () {
      final target = DownloadService.parseProxyUrl(
        'https://api.example.com/media?u=aHR0cHM6Ly9jZG4uY29tL3ZpZGVvLm1wNA'
        '&e=1758700000&s=deadbeef&r=aHR0cHM6Ly93d3cuYmlsaWJpbGkuY29tLw'
        '&name=%E6%B5%8B%E8%AF%95L.mp4',
      );
      expect(target, isNotNull);
      expect(target!.rawUrl, 'https://cdn.com/video.mp4');
      expect(target.referer, 'https://www.bilibili.com/');
      expect(target.fileName, '测试L.mp4');
      expect(target.proxyUrl, contains('/media?'));
    });

    test('base64url 的无填充形式也要能解（后端就是这么编的）', () {
      // 'https://a/b.mp4' 的 base64url（去掉了 padding）
      final t = DownloadService.parseProxyUrl(
          'http://h/media?u=aHR0cHM6Ly9hL2IubXA0&r=aHR0cHM6Ly92LmRvdXlpbi5jb20v');
      expect(t!.rawUrl, 'https://a/b.mp4');
      expect(t.referer, 'https://v.douyin.com/');
    });

    test('不是代理地址时返回 null，不会瞎解', () {
      expect(DownloadService.parseProxyUrl('https://cdn.com/raw.mp4'), isNull);
      expect(DownloadService.parseProxyUrl(''), isNull);
    });
  });

  /* ================================================================
   * 三、进 App 自动识别剪贴板
   *
   * 这功能最容易做成「骚扰用户」，所以四条守卫都要单独锁住：
   * 开关关着不读、不是链接不读、不是支持的平台不读、同一条不重复解析。
   * ================================================================ */

  testWidgets('自动识别剪贴板：开关关闭时不处理', (tester) async {
    String clip = 'https://v.douyin.com/abc/';
    mockClipboard(tester, () => clip);

    final s = AppState.instance;
    await s.updateSettings(s.settings.copyWith(autoPaste: false));

    expect(await s.tryAutoParseFromClipboard(), isFalse);
    expect(s.rawText, '');
  });

  testWidgets('自动识别剪贴板：不是链接 / 不是支持的平台，都不打扰用户', (tester) async {
    String clip = '';
    mockClipboard(tester, () => clip);

    final s = AppState.instance;
    await s.updateSettings(s.settings.copyWith(autoPaste: true));

    // 一段没有链接的文案
    clip = '这是一段普通的复制内容，没有链接';
    expect(await s.tryAutoParseFromClipboard(), isFalse);
    expect(s.rawText, '');

    // 明确不做的平台不该被识别（头条已确认不做）
    clip = 'https://www.toutiao.com/article/123456/';
    expect(await s.tryAutoParseFromClipboard(), isFalse);
    expect(s.rawText, '');
  });

  testWidgets('自动识别剪贴板：支持的平台会填充；同一条只解析一次', (tester) async {
    String clip = '7.15 复制打开抖音，看看 https://v.douyin.com/abc/ 的作品';
    mockClipboard(tester, () => clip);

    final s = AppState.instance;
    // 把它指向一个必然「立刻连接被拒」的地址，别让测试真去连后端。
    // 另外必须套 runAsync：testWidgets 默认跑在 FakeAsync 里，
    // 真实的网络 IO 在那里永远不会完成，会挂到超时。
    await s.updateSettings(
      s.settings.copyWith(autoPaste: true),
    );

    await tester.runAsync(() async {
      expect(await s.tryAutoParseFromClipboard(), isTrue);
    });
    expect(s.rawText, contains('https://v.douyin.com/abc/'));

    // 同一条再来一次：不重复解析
    await tester.runAsync(() async {
      expect(await s.tryAutoParseFromClipboard(), isFalse);
    });

    // 换一条新的：应当再次触发
    clip = '看看这个 https://www.bilibili.com/video/BV1xx411c7mD';
    await tester.runAsync(() async {
      expect(await s.tryAutoParseFromClipboard(), isTrue);
    });
    expect(s.rawText, contains('BV1xx411c7mD'));
  });

  testWidgets('自动识别剪贴板：用户手打过内容就不覆盖', (tester) async {
    String clip = 'https://v.douyin.com/abc/';
    mockClipboard(tester, () => clip);

    final s = AppState.instance;
    await s.updateSettings(s.settings.copyWith(autoPaste: true));

    // 模拟用户手动输入了别的东西
    s.forgetAutoFill();
    s.setText('用户自己敲的半截链接 https://v.douyin.com/USER/');

    // 剪贴板里是另一条，但输入框已由用户掌控 → 不覆盖
    clip = 'https://v.douyin.com/CLIPBOARD/';
    expect(await s.tryAutoParseFromClipboard(), isFalse);
    expect(s.rawText, contains('USER'));
  });
  /* ================================================================
   * 二、三个页面的渲染
   * ================================================================ */

  testWidgets('首页：品牌卡 / 输入区 / 主按钮 / 三步 / 须知 都在', (tester) async {
    await pumpApp(tester);

    expect(find.text('小鲸鱼'), findsWidgets);
    expect(find.text('分享链接'), findsOneWidget);
    expect(find.text('开始解析'), findsOneWidget);
    expect(find.text('一键粘贴'), findsOneWidget);
    expect(find.text('三步搞定'), findsOneWidget);
    expect(find.text('使用须知'), findsOneWidget);
    for (final p in kPlatforms) {
      expect(find.text(p.name), findsWidgets);
    }
    // 六个平台都要出现在首页标签里 —— 这条是防「解析支持了但界面没更新」
    expect(kPlatforms.length, 6);
    expect(find.text('快手'), findsWidgets);
    expect(find.text('微博'), findsWidgets);
    expect(find.text('知乎'), findsWidgets);
  });

  testWidgets('首页：注入解析结果后能画出结果卡', (tester) async {
    AppState.instance.setText('https://v.douyin.com/abc/');
    AppState.instance.result = mockVideo(title: '一条真实的测试标题');
    AppState.instance.detected = detectPlatform('https://v.douyin.com/abc/');

    await pumpApp(tester);

    expect(find.text('一条真实的测试标题'), findsOneWidget);
    expect(find.text('@测试作者'), findsOneWidget);
    expect(find.text('解析成功'), findsOneWidget);
    expect(find.text('重新解析'), findsOneWidget);
    expect(find.text('00:13'), findsOneWidget);
    expect(find.text('1080P'), findsOneWidget);        // 不是 normal_1080_0
    expect(find.text('保存到相册'), findsOneWidget);
    // 只提供原片，不再有「带水印版本」这个选项
    expect(find.text('原片 · 无水印'), findsOneWidget);
    expect(find.text('复制标题'), findsOneWidget);
    expect(find.text('复制直链'), findsOneWidget);
  });

  testWidgets('记录页：空状态 / 有数据两种形态', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('记录'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('还没有解析记录'), findsOneWidget);
    expect(find.text('去解析'), findsOneWidget);
  });

  testWidgets('记录页：渲染历史条目（标题 / 平台 / 相对时间）', (tester) async {
    final item = mockVideo(title: '记录页里的一条视频');
    await seedAndBoot({
      'fs_history': [item.encode()],
      'fs_stat': jsonEncode({
        'total': 7,
        'today': 2,
        'date': DateTime.now().toIso8601String().substring(0, 10),
      }),
    });

    await pumpApp(tester);
    await tester.tap(find.text('记录'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('记录页里的一条视频'), findsOneWidget);
    expect(find.text('抖音'), findsWidgets);
    expect(find.text('最近 1 条'), findsOneWidget);
    expect(find.text('清空记录'), findsOneWidget);
    expect(find.textContaining('长按可删除'), findsOneWidget);
  });

  testWidgets('我的页：统计 / 分组 / 设置项 / 开关', (tester) async {
    await seedAndBoot({
      'fs_stat': jsonEncode({
        'total': 12,
        'today': 3,
        'date': DateTime.now().toIso8601String().substring(0, 10),
      }),
    });

    await pumpApp(tester);
    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('小鲸鱼用户'), findsOneWidget);
    expect(find.text('累计解析'), findsOneWidget);
    expect(find.text('今日解析'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    expect(find.text('常用'), findsOneWidget);
    expect(find.text('解析偏好'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);

    expect(find.text('解析记录'), findsOneWidget);
    expect(find.text('使用教程'), findsOneWidget);
    expect(find.text('进 App 自动识别剪贴板'), findsOneWidget);
    expect(find.text('动图存成视频'), findsOneWidget);
    // 服务器那套已经整体移除，不该再出现在任何地方
    expect(find.text('解析方式'), findsNothing);
    expect(find.text('服务器'), findsNothing);
    expect(find.text('解析服务'), findsNothing);
    expect(find.text('关于小鲸鱼'), findsOneWidget);
  });

  testWidgets('「我的」页不再有服务器相关的设置项', (tester) async {
    await seedAndBoot({});
    await tester.pumpWidget(const FlashSaveApp());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 300));

    // 解析方式二选一、直连下载开关、解析服务地址 —— 全部移除
    expect(find.text('本地解析'), findsNothing);
    expect(find.text('服务器解析'), findsNothing);
    expect(find.textContaining('直连下载'), findsNothing);
    expect(find.text('解析服务'), findsNothing);

    // 但偏好开关还在，而且加了动图这项
    expect(find.text('进 App 自动识别剪贴板'), findsOneWidget);
    expect(find.text('动图存成视频'), findsOneWidget);
  });

  testWidgets('三个 tab 都能来回切', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('解析偏好'), findsOneWidget);

    await tester.tap(find.text('记录'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('去解析'), findsWidgets);

    await tester.tap(find.text('解析').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('开始解析'), findsOneWidget);
  });
  group('本轮新增代码的单元测试', () {
    // ---------------------------------------------------------------
    // 更新清单解析（含安装包大小）
    // ---------------------------------------------------------------
    test('更新清单：能解析 size，缺 size 也不崩', () {
      final withSize = UpdateInfo.fromJson({
        'build': 9,
        'version': '1.0.0',
        'url': 'https://example.com/a.apk',
        'size': 20971520,
      });
      expect(withSize, isNotNull);
      expect(withSize!.size, 20971520);

      // 老清单没有 size —— 不能因此判定为脏数据
      final noSize = UpdateInfo.fromJson({
        'build': 9,
        'version': '1.0.0',
        'url': 'https://example.com/a.apk',
      });
      expect(noSize, isNotNull);
      expect(noSize!.size, 0, reason: '缺 size 时应当是 0，而不是拒绝这条更新');
    });

    // ---------------------------------------------------------------
    // 图片按显示尺寸解码
    // ---------------------------------------------------------------
    test('imageCacheWidth：随像素密度缩放，且有上下限', () {
      // 只验证边界：真实 DPR 由运行环境决定，测试里不方便伪造
      final w = imageCacheWidth(150);
      expect(w, greaterThanOrEqualTo(64), reason: '不能小于 64');
      expect(w, lessThanOrEqualTo(720), reason: '不能大于 720（列表缩略图没必要更大）');

      // 极端小的请求也要被夹到下限
      expect(imageCacheWidth(1), 64);
      // 极端大的请求要被夹到上限
      expect(imageCacheWidth(100000), 720);
    });

    // ---------------------------------------------------------------
    // 动图字段在模型之间不能丢
    // ---------------------------------------------------------------
    test('LocalImage 的动图字段能正确往返 JSON', () {
      const live = LocalImage(
        url: 'https://example.com/a.jpg',
        width: 100,
        height: 200,
        videoUrl: 'https://example.com/a.mp4',
        durationSec: 3,
      );
      expect(live.isLive, isTrue);

      final back = LocalImage(
        url: live.toJson()['url'] as String,
        width: live.toJson()['width'] as int,
        height: live.toJson()['height'] as int,
        videoUrl: (live.toJson()['videoUrl'] ?? '') as String,
        durationSec: (live.toJson()['durationSec'] ?? 0) as int,
      );
      expect(back.videoUrl, live.videoUrl);
      expect(back.durationSec, live.durationSec);
      expect(back.isLive, isTrue);
    });

    test('普通图片不会被误判成动图', () {
      const plain = LocalImage(url: 'https://example.com/a.jpg');
      expect(plain.isLive, isFalse);
      expect(plain.toJson().containsKey('videoUrl'), isFalse,
          reason: '非动图不该写出空的 videoUrl 字段');
    });
  });
}

/// 拦截剪贴板平台通道，让测试能控制「剪贴板里有什么」。
///
/// 真机上读剪贴板要 App 有窗口焦点，测试环境没有真实剪贴板，
/// 所以直接 mock 掉这个 method channel。
void mockClipboard(WidgetTester tester, String Function() read) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      switch (call.method) {
        case 'Clipboard.getData':
          return <String, dynamic>{'text': read()};
        case 'Clipboard.setData':
          return null;
        case 'HapticFeedback.vibrate':
          return null;
        default:
          return null;
      }
    },
  );
}

/// 把整个 App 渲染出来，并**等冷启动的剪贴板检测跑完**。
///
/// AppShell 在首帧后会延迟 350ms 去读剪贴板（Android 10+ 要求 App 先拿到窗口焦点）。
/// 测试里如果只 pump 300ms 就结束，会报 "A Timer is still pending"。
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const FlashSaveApp());
  await tester.pump(const Duration(milliseconds: 900));
}
