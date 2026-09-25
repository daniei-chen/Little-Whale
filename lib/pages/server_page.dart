import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../models/parse_result.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/primitives.dart';

/// 解析服务地址配置
///
/// APP 与小程序最大的不同：小程序只能填死一个后台配置的域名，
/// APP 可以让用户自己填任意地址 —— 自建服务、局域网调试、换服务器都不用重新发版。
class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  late final TextEditingController _controller;
  String _status = '';
  bool _testing = false;
  bool _ok = false;
  Map<String, dynamic>? _health;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: AppState.instance.settings.apiBase);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() {
        _status = '请先填写地址';
        _ok = false;
      });
      return;
    }

    setState(() {
      _testing = true;
      _status = '';
      _health = null;
    });

    try {
      final h = await ApiClient(baseUrl: url).health();
      if (!mounted) return;
      final adapters = <String>[];
      if (h['adapters'] is Map) {
        (h['adapters'] as Map).forEach((k, v) {
          if (v is Map && v['name'] != null) adapters.add('${v['name']}');
        });
      }
      setState(() {
        _testing = false;
        _ok = true;
        _health = h;
        _status = '连接成功 · 可用平台：${adapters.isEmpty ? "未知" : adapters.join(" / ")}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _ok = false;
        _status = e is ParseFailure ? e.message : '连接失败：$e';
      });
    }
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    await AppState.instance.updateSettings(AppState.instance.settings.copyWith(apiBase: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('已保存'),
        duration: Duration(milliseconds: 1500),
        margin: EdgeInsets.fromLTRB(16, 0, 16, 24),
      ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('解析服务'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SoftCard(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('服务地址', style: AppText.cardTitle),
                const SizedBox(height: 10),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: AppText.body,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'https://api.你的域名.com',
                    hintStyle: AppText.hint,
                    filled: true,
                    fillColor: const Color(0xFFFAFBFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFDFE4EF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFDFE4EF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFB9C7FF), width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: _testing ? '测试中…' : '测试连接',
                        busy: _testing,
                        showArrow: false,
                        height: 42,
                        onTap: _test,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Pressable(
                        onTap: _save,
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F9FF),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: const Color(0xFFE2E7F8)),
                          ),
                          child: const Center(
                            child: Text('保存',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5269CF),
                                    height: 1.1)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _ok ? AppColors.greenSoft : AppColors.redSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _ok ? const Color(0xFFD8F0E6) : const Color(0xFFF5DDE0)),
                    ),
                    child: Text(
                      _status,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: _ok ? const Color(0xFF12734F) : const Color(0xFFC04A56),
                      ),
                    ),
                  ),
                ],
                if (_health != null && _health!['mediaProxy'] is Map) ...[
                  const SizedBox(height: 11),
                  _healthRow('媒体代理对外地址',
                      '${(_health!['mediaProxy'] as Map)['publicBase'] ?? '-'}'),
                  _healthRow('下载链接签名',
                      (_health!['mediaProxy'] as Map)['signatureRequired'] == true ? '强制' : '关闭'),
                  _healthRow('密钥固定',
                      (_health!['mediaProxy'] as Map)['secretStable'] == true ? '是' : '否（重启后旧链接会失效）'),
                ],
                if (_health != null && _health!['browser'] is Map)
                  _healthRow(
                    '浏览器解析',
                    (_health!['browser'] as Map)['playwrightFound'] == true
                        ? ((_health!['browser'] as Map)['chromiumFound'] == true ? '就绪' : '缺 Chromium')
                        : '不可用',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('怎么填', style: AppText.cardTitle),
                const SizedBox(height: 8),
                ...const [
                  '· 自建服务：填你部署好的域名，例如 https://api.example.com',
                  '· 本机调试：Android 模拟器访问电脑用 http://10.0.2.2:8787',
                  '· 真机调试：填电脑在局域网里的 IP，例如 http://192.168.1.5:8787',
                  '· 线上必须是 HTTPS，否则 Android 会拦截明文请求',
                ].map((t) => Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(t,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.text2, height: 1.7)),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthRow(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(k, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.text2, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}
