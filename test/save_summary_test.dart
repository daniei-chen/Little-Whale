// 保存失败时的明细摘要。
//
// 【为什么值得测】图文作品一次存 9 张，失败 2 张时旧代码只报
// 「成功 7 张，失败 2 张」—— 用户不知道该重试哪几张，只能整条重来。
// 现在会带上「第几张：为什么」，而序号要和保存出来的文件名 `标题_3` 对得上，
// 否则用户按序号去相册里找，会发现对不上。
//
// 摘要还要控制长度：Toast 一行放不下几十个字。

import 'package:flutter_test/flutter_test.dart';

import 'package:flashsave/state/app_state.dart';

void main() {
  group('失败明细摘要', () {
    test('单条失败：原样带上', () {
      final s = AppState.summarizeFailures(['第 3 张：链接已过期']);
      expect(s, '第 3 张：链接已过期');
    });

    test('两条失败：都带上，用分号隔开', () {
      final s = AppState.summarizeFailures(['第 3 张：链接已过期', '第 8 张：403']);
      expect(s, contains('第 3 张'));
      expect(s, contains('第 8 张'));
      expect(s, contains('；'));
    });

    test('超过两条：只显示前两条，并注明还剩几条', () {
      final s = AppState.summarizeFailures(
          ['第 1 张：a', '第 2 张：b', '第 3 张：c', '第 4 张：d']);
      expect(s, contains('第 1 张'));
      expect(s, contains('第 2 张'));
      expect(s, isNot(contains('第 3 张')));
      expect(s, contains('还有 2 条'));
    });

    test('超长原因被截断，不会把 Toast 撑爆', () {
      final long = '第 1 张：${'很长的原因' * 20}';
      final s = AppState.summarizeFailures([long]);
      expect(s.length, lessThan(80));
      expect(s, endsWith('…'));
    });

    test('原因里的换行被压成空格（Toast 不换行）', () {
      final s = AppState.summarizeFailures(['第 2 张：第一行\n第二行']);
      expect(s.contains('\n'), isFalse);
    });
  });
}
