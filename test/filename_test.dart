// 保存到相册时的文件名清理规则。
//
// 【为什么单独测这个】文件名看起来是琐事，但这里踩过一个会让数据真的丢掉的坑：
// 图文作品的每张图叫 `标题_3`（见 AppState.saveAllImages），而清理逻辑原本是
// 「超过 60 字符就从尾部砍断」—— 标题一长，`_3` 就被砍掉，9 张图变成同一个名字，
// 后存的把先存的覆盖掉。用户看到「保存成功」，相册里却只剩 1 张。
//
// 这类问题功能测试发现不了（每次都返回 saved=true），只能靠对文件名的断言。

import 'package:flutter_test/flutter_test.dart';

import 'package:flashsave/services/download_service.dart';

void main() {
  final svc = DownloadService.instance;

  group('基本清理', () {
    test('普通标题原样保留', () {
      expect(svc.safeFileName('熊去香港玩啦'), '熊去香港玩啦');
    });

    test('非法字符替换成下划线', () {
      expect(svc.safeFileName('a/b:c*d?e"f<g>h|i'), 'a_b_c_d_e_f_g_h_i');
      expect(svc.safeFileName('换行\n和\t制表'), '换行_和_制表');
    });

    test('去掉已知扩展名', () {
      expect(svc.safeFileName('视频.mp4'), '视频');
      expect(svc.safeFileName('图片.JPG'), '图片');
      expect(svc.safeFileName('图.png'), '图');
      expect(svc.safeFileName('图.webp'), '图');
      expect(svc.safeFileName('动图.gif'), '动图');
    });

    test('空文件名有兜底（带时间戳，不会撞名）', () {
      final a = svc.safeFileName('');
      expect(a.startsWith('flashsave_'), isTrue);
    });
  });

  group('长度截断', () {
    test('短于 60 不截断', () {
      final n = 'a' * 59;
      expect(svc.safeFileName(n), n);
    });

    test('刚好 60 不截断', () {
      final n = 'a' * 60;
      expect(svc.safeFileName(n), n);
    });

    test('超过 60 截断到 60', () {
      final out = svc.safeFileName('a' * 100);
      expect(out.length, lessThanOrEqualTo(60));
    });
  });

  group('截断时必须保住尾部序号（图文的 _1 _2 …）', () {
    test('长标题 + _3 → 序号还在，且长度不超 60', () {
      final long = '${'很长的标题' * 20}_3'; // 远超 60
      final out = svc.safeFileName(long);
      expect(out.endsWith('_3'), isTrue,
          reason: '序号被截掉了 —— 多张图会变成同一个名字互相覆盖');
      expect(out.length, lessThanOrEqualTo(60));
    });

    test('不同序号截断后仍然不同（不会撞名）', () {
      final long = '很长的标题' * 20;
      final names = {
        for (var i = 1; i <= 9; i++) svc.safeFileName('${long}_$i'),
      };
      expect(names.length, 9, reason: '9 张图必须得到 9 个不同的文件名');
    });

    test('两位数序号也能保住', () {
      final long = '很长的标题' * 20;
      final out = svc.safeFileName('${long}_46');
      expect(out.endsWith('_46'), isTrue);
    });

    test('没有序号的超长标题：正常截断（不加多余省略号）', () {
      final out = svc.safeFileName('很长的标题' * 30);
      expect(out.length, 60);
      expect(out.contains('…'), isFalse);
    });
  });
}
