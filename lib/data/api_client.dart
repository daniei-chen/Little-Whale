import 'package:dio/dio.dart';

import '../models/parse_result.dart';

/// 后端解析服务客户端
///
/// 契约来自 `03-后端服务`：
///   POST {base}/parse   body { text }        → { code: 0, data: {...} }
///   GET  {base}/health                       → { code: 0, data: {...} }
///
/// 关键：后端会用合理的 HTTP 状态码（400/422/502…），业务结果一律看 **body.code**。
/// 所以不能只看 statusCode —— 这一点和小程序端的约定是一样的。
class ApiClient {
  ApiClient({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: _normalize(baseUrl),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 15),
          headers: {'Accept': 'application/json'},
          // 后端对 4xx/5xx 也返回有意义的 JSON，交给业务层判断
          validateStatus: (s) => s != null && s < 600,
        ));

  final Dio _dio;

  static String _normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  String get baseUrl => _dio.options.baseUrl;

  /// 解析一条分享文案
  Future<ParseResult> parse(String text) async {
    if (_dio.options.baseUrl.isEmpty) {
      throw const ParseFailure('NO_SERVER', '还没有配置解析服务地址，去「我的 → 解析服务」填一下');
    }

    Response<dynamic> res;
    try {
      res = await _dio.post('/parse', data: {'text': text});
    } on DioException catch (e) {
      throw ParseFailure('NETWORK', _networkMessage(e));
    }

    final body = res.data;
    if (body is! Map) {
      throw const ParseFailure('BAD_RESPONSE', '解析服务返回了无法识别的数据');
    }

    final code = body['code'];
    if (code == 0 && body['data'] is Map) {
      return ParseResult.fromJson(Map<String, dynamic>.from(body['data'] as Map));
    }

    final msg = (body['message'] ?? '').toString().trim();
    throw ParseFailure(
      (code ?? 'PARSE_FAIL').toString(),
      msg.isNotEmpty ? msg : '解析失败（HTTP ${res.statusCode}）',
    );
  }

  /// 健康检查：用于「我的」页展示服务状态
  Future<Map<String, dynamic>> health() async {
    if (_dio.options.baseUrl.isEmpty) {
      throw const ParseFailure('NO_SERVER', '未配置服务地址');
    }
    try {
      final res = await _dio.get('/health');
      final body = res.data;
      if (body is Map && body['data'] is Map) {
        return Map<String, dynamic>.from(body['data'] as Map);
      }
      throw const ParseFailure('BAD_RESPONSE', '健康检查返回异常');
    } on DioException catch (e) {
      throw ParseFailure('NETWORK', _networkMessage(e));
    }
  }

  String _networkMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return '连接解析服务超时，检查下网络或服务地址';
      case DioExceptionType.receiveTimeout:
        return '解析服务响应太慢，稍后再试';
      case DioExceptionType.connectionError:
        return '连不上解析服务，确认地址填对了、服务是启动的';
      case DioExceptionType.badCertificate:
        return 'HTTPS 证书校验失败';
      default:
        return '网络异常：${e.message ?? '未知错误'}';
    }
  }
}
