import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 错误日志 —— 把崩溃和异常写进手机本地的一个文件。
///
/// 【为什么需要它】
/// App 完全跑在用户手机上，我们这边**看不到任何东西**。
/// 用户在微信上发一句「闪退」，我们没有任何线索，既复现不了也定位不了。
/// 有了这个，让用户打开「我的 → 错误日志」截个图，就知道是哪一步炸的。
///
/// 【为什么不接第三方崩溃平台】
/// 这个 App 的卖点就是**不联网、不上传**。为了排查问题把用户的
/// 设备信息和调用栈传到别人的服务器上，跟产品承诺自相矛盾。
/// 写本地文件、用户主动截图，是这里最合适的做法。
///
/// 【只记最近 N 条】日志无限增长会占空间，也会让截图变得不现实。
class CrashLog {
  CrashLog._();

  /// 最多保留多少条
  static const int maxEntries = 40;

  /// 单条最长字符数（超长截断，避免一条就把文件撑爆）
  static const int _maxLen = 1200;

  static File? _file;
  static bool _installed = false;

  /// 装钩子。在 runApp 之前调用一次即可。
  static void install() {
    if (_installed) return;
    _installed = true;

    // ---- Flutter 层的异常（build 报错、setState 后异常等）----
    final prev = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      unawaited(record(
        '界面异常',
        details.exceptionAsString(),
        details.stack,
      ));
      // 保留默认行为：debug 下还是要打红屏，不能因为我们记日志就吞掉
      prev?.call(details);
    };

    // ---- 引擎层的异步异常（Future 里没 catch 的）----
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(record('运行时异常', '$error', stack));
      return true; // 已处理，别让 App 直接挂掉
    };
  }

  static Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/error.log');
    if (!await f.exists()) {
      await f.create(recursive: true);
    }
    _file = f;
    return f;
  }

  /// 记一条
  static Future<void> record(
    String kind,
    String message,
    StackTrace? stack, {
    String where = '',
  }) async {
    try {
      final f = await _ensureFile();

      final now = DateTime.now();
      final ts = '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
          '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';

      // 只留我们自己的栈帧，系统那几十行对定位没帮助
      final trace = (stack?.toString() ?? '')
          .split('\n')
          .where((l) => !l.contains('dart:async') && !l.contains('dart:isolate'))
          .take(8)
          .join('\n');

      var body = '[$ts] $kind${where.isEmpty ? '' : ' @ $where'}\n$message';
      if (trace.isNotEmpty) body += '\n$trace';
      if (body.length > _maxLen) body = '${body.substring(0, _maxLen)}…(截断)';

      // 追加
      await f.writeAsString('$body\n${'-' * 48}\n', mode: FileMode.append);

      await _trim(f);
    } catch (_) {
      // 记日志本身失败就算了 —— 绝对不能因为记日志再抛一次异常
    }
  }

  /// 只保留最近 maxEntries 条
  static Future<void> _trim(File f) async {
    final text = await f.readAsString();
    const sep = '------------------------------------------------';
    final blocks = text.split(sep).where((b) => b.trim().isNotEmpty).toList();
    if (blocks.length <= maxEntries) return;
    final keep = blocks.sublist(blocks.length - maxEntries);
    await f.writeAsString(keep.map((b) => '$b$sep\n').join());
  }

  /// 读出来给用户看（顺便让用户截图）
  static Future<String> read() async {
    try {
      final f = await _ensureFile();
      final t = await f.readAsString();
      return t.trim().isEmpty ? '' : t.trim();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _ensureFile();
      await f.writeAsString('');
    } catch (_) {}
  }

  static Future<bool> hasAny() async => (await read()).isNotEmpty;

  static String _pad(int n) => n < 10 ? '0$n' : '$n';
}

/// 「错误日志」页 —— 给用户看，也方便他截图发给我们。
class CrashLogPage extends StatefulWidget {
  const CrashLogPage({super.key});

  @override
  State<CrashLogPage> createState() => _CrashLogPageState();
}

class _CrashLogPageState extends State<CrashLogPage> {
  String _text = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await CrashLog.read();
    if (mounted) {
      setState(() {
        _text = t;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('错误日志', style: TextStyle(fontSize: 17)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          if (_text.isNotEmpty)
            TextButton(
              onPressed: () async {
                await CrashLog.clear();
                await _load();
              },
              child: const Text('清空'),
            ),
        ],
      ),
      backgroundColor: const Color(0xFFF7F8FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _text.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 42, color: Color(0xFF3BC26C)),
                      SizedBox(height: 12),
                      Text('没有错误记录',
                          style: TextStyle(
                              fontSize: 14, color: Color(0xFF8A9099))),
                      SizedBox(height: 6),
                      Text('一切正常',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFFB4B9C2))),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9E6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF5E3B3)),
                      ),
                      child: const Text(
                        '这些内容只存在你的手机里，不会上传。\n'
                        '如果 App 出问题，把这一页截图发给我们就能定位。',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF8A6D1F), height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE8EBF2)),
                      ),
                      child: SelectableText(
                        _text,
                        style: const TextStyle(
                            fontSize: 11,
                            height: 1.55,
                            fontFamily: 'monospace',
                            color: Color(0xFF3D4450)),
                      ),
                    ),
                  ],
                ),
    );
  }
}
