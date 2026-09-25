import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 本地解析引擎 —— **整个「不依赖服务器」方案的地基**。
///
/// 思路和服务端 `03-后端服务/src/browser.js` 完全一样：
/// 不去逆向任何签名算法，而是让平台自己的 JS 在真实浏览器环境里跑一遍，
/// 我们只在旁边**拦截它自己发出的接口响应**。
///
/// 区别只有一个：浏览器从服务器搬到了手机里。好处是手机的真实 IP 风控概率低、
/// WebView 自带 Cookie jar 不用维护、零服务器成本。
///
/// 两种提取方式：
///   1. [collect]   拦截页面发出的 JSON 接口响应（适合有详情接口的平台）
///   2. [evaluate]  在页面里执行一段 JS 取回结果（适合数据在 DOM 里的场景）
class LocalEngine {
  LocalEngine._();
  static final LocalEngine instance = LocalEngine._();

  WebViewController? _controller;
  Completer<void>? _ready;

  final List<InterceptHit> _hits = [];

  /// 每次解析自增，用来丢弃「上一次解析」的残留命中
  int _epoch = 0;

  bool get isReady => _controller != null;

  /// 公开的初始化入口。
  ///
  /// 【关键】WebView 必须**挂到 widget 树里**才会真正工作 ——
  /// 只创建 controller 而不渲染 [LocalEngineHost]，页面根本不会加载
  /// （实测：未挂载时 document.title 是空字符串，挂了才拿到正常内容）。
  /// 所以 App 启动时要把 [LocalEngineHost] 放进界面树。
  Future<WebViewController> ensure() => _ensure();

  /// 预热：App 一启动就把 WebView 的渲染进程拉起来。
  ///
  /// 冷启动一次要 3–4 秒（起进程、初始化网络栈、加载渲染器）。
  /// 如果等用户点「开始解析」才做，这几秒就白算在解析时间里了。
  /// 这里提前加载一个空白页，把这份开销挪到用户还在粘贴链接的时候。
  Future<void> warmUp() async {
    try {
      final c = await _ensure();
      await c.loadRequest(Uri.parse('about:blank'));
    } catch (_) {
      // 预热失败不影响正常解析
    }
  }

  /* ------------------------------------------------------------------ */
  /* 初始化                                                              */
  /* ------------------------------------------------------------------ */

  Future<WebViewController> _ensure() async {
    if (_controller != null) return _controller!;
    if (_ready != null) {
      await _ready!.future;
      return _controller!;
    }

    final done = Completer<void>();
    _ready = done;

    final c = WebViewController()
      // 必须用真实桌面 Chrome 的 UA ——
      // 手机 UA 会把抖音重定向到 m.douyin.com，那套站不发详情接口。
      // 服务端方案踩过「浏览器版本过低」的坑，这里也别用 WebView 默认 UA。
      ..setUserAgent(_desktopChromeUa())
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));

    await c.addJavaScriptChannel('FsBridge', onMessageReceived: _onBridge);

    await c.setNavigationDelegate(NavigationDelegate(
      // 【必须拦自定义 scheme】平台的页面会尝试用 snssdk1128:// 之类的方式
      // 拉起自家 App。WebView 处理不了这种 scheme，整个页面会变成
      // 「Webpage not available」，JS 一行都不执行 —— 表现就是解析恒超时。
      // 实测：抖音 /video/ 页面会这样，/note/ 页面不会。
      onNavigationRequest: (req) {
        final u = req.url;
        if (u.startsWith('http://') ||
            u.startsWith('https://') ||
            u.startsWith('about:') ||
            u.startsWith('data:')) {
          return NavigationDecision.navigate;
        }
        debugPrint('[LocalEngine] 已拦截自定义 scheme: '
            '${u.length > 60 ? u.substring(0, 60) : u}');
        return NavigationDecision.prevent;
      },
      // 钩子必须「每个新文档都装一次」：导航会换掉 JS 上下文，
      // 初始化时装的那份会随旧文档一起消失。这一步漏掉的话表现是
      // 「有时抓得到有时抓不到」，最难排查。
      onPageStarted: (_) => _installHook(),
      onPageFinished: (_) => _installHook(),
      onWebResourceError: (e) {
        debugPrint('[LocalEngine] 资源错误: ${e.description}');
      },
    ));

    _controller = c;
    done.complete();
    return c;
  }

  /// 【必须用桌面 Chrome 的 UA，不能用手机 UA】
  ///
  /// 这是个反直觉但很关键的坑，实测确认：
  /// 给手机 UA 时，抖音会把 www.douyin.com **重定向到 m.douyin.com**，
  /// 而手机站是另一套架构 —— 它**不发** `/aweme/v1/web/aweme/detail/`，
  /// 只发 `seo/entity/related`、`web/api/v2/image/related` 这些，
  /// 详情数据拿不到，解析必然超时。
  ///
  /// 服务端方案用的是桌面 UA，所以能看到 www 站的 detail 接口。
  /// 这里保持一致，两边行为才能对齐。反正我们不需要渲染，桌面版页面照样跑。
  static String _desktopChromeUa() {
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  }

  /// 装钩子。脚本自带 `__fsHooked` 幂等判断，重复调用安全且开销极小。
  ///
  /// 【必须在同一次调用里带上 epoch】导航会换掉 JS 上下文，
  /// 在 `loadRequest` 之前设的 `window.__fsEpoch` 到新文档里就没了。
  /// 钩子推上来的消息会带 `epoch: 0`，而 Dart 端按当前 epoch 过滤 ——
  /// 结果就是**钩子装上了、页面也发了请求，但一条都收不到**。
  /// 这个 bug 的迷惑性在于所有中间状态看起来都正常。
  Future<void> _installHook() async {
    try {
      await _controller?.runJavaScript('window.__fsEpoch = $_epoch;$_hookScript');
    } catch (_) {
      // 页面还在切文档时 runJavaScript 可能失败，下一轮再装
    }
  }

  /// 装「特征伪装」脚本。必须在页面自己的 JS 之前跑，所以和钩子一起、
  /// 在每个新文档起来时立刻装。
  ///
  /// 【为什么要做这件事】实测确认：页面能加载（71 万字节 HTML）、
  /// 钩子也装上了，但页面自己的 JS **就是不执行**（一个 XHR 都不发、
  /// 懒加载图片一张不加载）。逐个排除了版本旧、没挂载、视口小、scheme 漏拦，
  /// 剩下的最大嫌疑就是**平台识别出了 WebView 并给了降级页面**。
  ///
  /// WebView 与桌面 Chrome 的特征差异主要在：`window.chrome` 对象、
  /// plugins/mimeTypes 列表、`navigator.userAgentData`、屏幕与窗口尺寸。
  /// 这里把这些补齐成「桌面 Windows Chrome」的样子，和 UA 保持一致。
  Future<void> _installStealth() async {
    try {
      await _controller?.runJavaScript(_stealthScript);
    } catch (_) {}
  }

  /// 加载后密集补装几次（钩子 + 伪装）。
  ///
  /// 页面常常会 302 一跳（比如 www → 带参数的地址），一跳就是新文档，
  /// 之前装的脚本全没了。等 300ms 的轮询周期太慢 —— 页面的接口请求
  /// 往往在新文档起来后几百毫秒内就发出去了，晚一步就抓不到。
  Future<void> _installHookBurst() async {
    for (var i = 0; i < 5; i++) {
      await _installStealth();
      await _installHook();
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  void _onBridge(JavaScriptMessage msg) {
    try {
      final map = jsonDecode(msg.message) as Map<String, dynamic>;
      final epoch = (map['epoch'] as num?)?.toInt() ?? 0;
      if (epoch != _epoch) return; // 上一次解析的残留，丢掉
      _hits.add(InterceptHit(
        url: (map['url'] ?? '') as String,
        json: map['json'],
        epoch: epoch,
      ));
    } catch (e) {
      debugPrint('[LocalEngine] 桥消息解析失败: $e');
    }
  }

  /* ------------------------------------------------------------------ */
  /* 方式一：拦截接口响应                                                */
  /* ------------------------------------------------------------------ */

  Future<List<InterceptHit>> collect(
    String pageUrl, {
    required List<RegExp> match,
    bool Function(List<InterceptHit> hits)? stopWhen,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final c = await _ensure();
    _epoch++;
    _hits.clear();

    await c
        .runJavaScript('window.__fsEpoch = $_epoch; window.__fsHits = []; window.__fsUrls = [];')
        .catchError((_) {});
    await c.loadRequest(Uri.parse(pageUrl));
    unawaited(_installHookBurst());

    // 【为什么要主动拉，而不是等桥推送】
    // 抖音的作品详情响应很大（几十上百 KB）。JavaScriptChannel 的消息有大小上限，
    // 超了以后 postMessage 会抛异常，而钩子里是 try/catch 吞掉的 ——
    // 表现是「请求明明发出去了、页面里也有数据，但 Dart 这边一条都收不到」。
    // 改成先从页面里读「命中列表」（只有 URL，很小），按需把某一条的 JSON 拉回来。
    final pulled = <int, InterceptHit>{};

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 300));
      await _installStealth();
      await _installHook();
      await _pullHits(c, match, pulled);

      final hits = pulled.values.toList();
      if (hits.isNotEmpty && (stopWhen == null || stopWhen(hits))) return hits;
    }
    await _pullHits(c, match, pulled);
    return pulled.values.toList();
  }

  /// 把页面里「命中 [match] 且还没拉过」的响应取值回来
  Future<void> _pullHits(
    WebViewController c,
    List<RegExp> match,
    Map<int, InterceptHit> out,
  ) async {
    List<String> urls;
    try {
      final raw = await c.runJavaScriptReturningResult(
          'JSON.stringify((window.__fsHits||[]).map(function(h){return String(h.url)}))');
      final v = _decodeJsResult(raw);
      if (v is! List) return;
      urls = v.map((e) => e.toString()).toList();
    } catch (_) {
      return;
    }

    for (var i = 0; i < urls.length; i++) {
      if (out.containsKey(i)) continue;
      var matched = false;
      for (final re in match) {
        if (re.hasMatch(urls[i])) {
          matched = true;
          break;
        }
      }
      if (!matched) continue;

      dynamic body;
      try {
        final rawJson = await c
            .runJavaScriptReturningResult('JSON.stringify(window.__fsHits[$i].json)');
        body = _decodeJsResult(rawJson);
      } catch (_) {
        body = null; // 体积太大拉不回来时，至少保留 URL
      }
      out[i] = InterceptHit(url: urls[i], json: body, epoch: _epoch);
    }
  }

  /* ------------------------------------------------------------------ */
  /* 方式二：在页面里跑一段 JS                                           */
  /* ------------------------------------------------------------------ */

  /// [script] 建议写成 `(async function(){ ... })()` 这种自执行形式，
  /// 因为 `runJavaScriptReturningResult` 对返回 Promise 的表达式处理不一致。
  /// 页面内的轮询等待就写在脚本里，比在外面写死 sleep 又快又稳。
  Future<dynamic> evaluate(
    String pageUrl,
    String script, {
    Duration settle = const Duration(milliseconds: 800),
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final c = await _ensure();
    _epoch++;
    _hits.clear();

    await c.runJavaScript('window.__fsEpoch = $_epoch;').catchError((_) {});
    await _navigate(c, pageUrl, settle);
    unawaited(_installHookBurst());

    await _installHook();

    try {
      final raw = await c.runJavaScriptReturningResult(script).timeout(timeout);
      return _decodeJsResult(raw);
    } on TimeoutException {
      return null;
    } catch (e) {
      debugPrint('[LocalEngine] evaluate 失败: $e');
      return null;
    }
  }

  /// WebView 的返回值可能是 String / num / Map / List，
  /// 而且字符串**常常被编码了不止一层**。
  ///
  /// 实测：脚本里写 `return JSON.stringify(x)`，Android 的
  /// `evaluateJavascript` 会把结果再包一层引号，拿回来是这样：
  ///   `"{\"images\":[...]}"`
  /// 只解一层得到的是 String，不是 Map —— 上层 `value is Map` 判断全部落空，
  /// 表现是轮询永远等不到结束条件、最后再抛一个「页面没能读到内容」。
  /// 所以这里必须循环解，直到不再是「看起来像 JSON 的字符串」。
  dynamic _decodeJsResult(dynamic raw) {
    dynamic cur = raw;
    for (var i = 0; i < 4; i++) {
      if (cur is! String) return cur;
      final t = cur.trim();
      if (t.isEmpty || t == 'null') return null;
      if (t.startsWith('"') || t.startsWith('{') || t.startsWith('[')) {
        try {
          final decoded = jsonDecode(t);
          if (decoded is String) {
            cur = decoded; // 还套着一层，继续解
            continue;
          }
          return decoded;
        } catch (_) {
          return t;
        }
      }
      return t;
    }
    return cur;
  }

  /// 反复执行 [probeScript] 直到 [isDone] 说可以了，返回最后一次的结果。
  ///
  /// 【为什么轮询要放在 Dart 而不是页面里】
  /// WebView 的 `runJavaScriptReturningResult` 底层是 Android 的
  /// `evaluateJavascript`，它**不会等待 Promise** —— 一个 async IIFE 拿回来的是
  /// `{}` 而不是 resolve 后的值。所以「等图片加载齐」这种等待必须由 Dart 驱动。
  ///
  /// [probeScript] 必须是一个**同步**表达式，返回 JSON 字符串。
  /// 导航到 [pageUrl]，并**确认真的换了文档**才返回。
  ///
  /// 【为什么不能只 `loadRequest` + 固定等待】
  /// `loadRequest` 返回时页面**还没加载完** —— 短链要过 302、目标页也要时间。
  /// 如果这时就去读 DOM，读到的是**上一页的残留数据**。
  ///
  /// 实测踩过：性能基准里连着解析「抖音图文」和「抖音动图」两条链接，
  /// 第二条只用了 914ms 就返回了 **46 张图** —— 那是第一条的数据。
  /// 对用户来说就是「解析这个链接，出来的是上一个的内容」，非常严重。
  ///
  /// 判据：导航前在当前文档打一个标记，新文档里这个标记自然就没了。
  /// 等它消失 = 文档确实被替换了。比猜等待时间可靠得多。
  Future<void> _navigate(WebViewController c, String pageUrl, Duration settle) async {
    try {
      await c.runJavaScript('window.__fsPreNav = 1;');
    } catch (_) {
      // 当前页可能还没就绪，打不上标记也不影响后续（下面会兜底超时）
    }

    await c.loadRequest(Uri.parse(pageUrl));

    // 等标记消失（最多 10 秒，超时也继续 —— 总比卡死好）
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final v = await c.runJavaScriptReturningResult('String(window.__fsPreNav)');
        final s = v.toString().replaceAll('"', '');
        if (s != '1') break; // 新文档了
      } catch (_) {
        break; // 取不到（文档正在切换）也说明已经在换
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }

    // 再给页面一点渲染时间（DOM 就绪但数据还没填进去）
    await Future.delayed(settle);
  }

  Future<dynamic> evaluatePolling(
    String pageUrl,
    String probeScript, {
    required bool Function(dynamic value) isDone,
    Duration settle = const Duration(milliseconds: 900),
    Duration interval = const Duration(milliseconds: 400),
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final c = await _ensure();
    _epoch++;
    _hits.clear();

    await c.runJavaScript('window.__fsEpoch = $_epoch;').catchError((_) {});
    await _navigate(c, pageUrl, settle);
    unawaited(_installHookBurst());

    dynamic last;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      // 【为什么这里不再每轮注入脚本】
      // 轮询用的探针只读 DOM（图片列表、<video> 的 src），**不依赖钩子**。
      // 而每轮注入钩子 + 特征伪装是两大段 JS，一来一回要几百毫秒 ——
      // 名义上 300ms 的轮询间隔会被拖成将近 1 秒，白白拖慢解析。
      // 开头的 _installHookBurst() 已经把钩子装好了（且跨导航重装过），
      // 这里保持不动即可；只有探针取不到值（文档换了）时才补装一次。
      try {
        final raw = await c.runJavaScriptReturningResult(probeScript);
        last = _decodeJsResult(raw);
        if (last != null && isDone(last)) return last;
      } catch (e) {
        debugPrint('[LocalEngine] 轮询失败，补装脚本: $e');
        await _installStealth();
        await _installHook();
      }
      await Future.delayed(interval);
    }
    return last; // 超时就把最后一次的结果交出去，让上层判断够不够用
  }

  /* ------------------------------------------------------------------ */
  /* 页面内注入的钩子                                                    */
  /* ------------------------------------------------------------------ */

  /// 特征伪装：把 WebView 补齐成「桌面 Windows Chrome」。
  ///
  /// 与服务端 `src/adapters/douyin.js` 里那段 UA-CH 对齐是同一个思路 ——
  /// 那边解决的是「UA 说 133、UA-CH 说别的」的矛盾，这边解决的是
  /// 「UA 说桌面 Chrome、但环境里根本没有桌面 Chrome 该有的东西」。
  ///
  /// 每一项都是桌面 Chrome 有、Android WebView 没有的：
  ///   · `window.chrome`（含 runtime / app / csi / loadTimes）
  ///   · `navigator.plugins` 的 5 个 PDF 插件
  ///   · `navigator.userAgentData`（brands / mobile:false / platform:Windows）
  ///   · 桌面尺寸的 screen / outerWidth / innerWidth
  ///
  /// 目标只是**让特性探测通过**，不做任何对抗性的事情，也不改页面数据。
  static const String _stealthScript = r'''
(function () {
  if (window.__fsStealth) return;
  window.__fsStealth = true;

  function def(obj, prop, getter) {
    try { Object.defineProperty(obj, prop, { get: getter, configurable: true }); } catch (e) {}
  }

  // ---- 1. window.chrome：桌面 Chrome 必有 ----
  if (!window.chrome) { try { window.chrome = {}; } catch (e) {} }
  if (window.chrome) {
    if (!window.chrome.runtime) {
      try {
        window.chrome.runtime = {
          OnInstalledReason: { CHROME_UPDATE: 'chrome_update', INSTALL: 'install', SHARED_MODULE_UPDATE: 'shared_module_update', UPDATE: 'update' },
          OnRestartRequiredReason: { APP_UPDATE: 'app_update', OS_UPDATE: 'os_update', PERIODIC: 'periodic' },
          PlatformArch: { ARM: 'arm', ARM64: 'arm64', MIPS: 'mips', MIPS64: 'mips64', X86_32: 'x86-32', X86_64: 'x86-64' },
          PlatformOs: { ANDROID: 'android', CROS: 'cros', LINUX: 'linux', MAC: 'mac', OPENBSD: 'openbsd', WIN: 'win' },
          RequestUpdateCheckStatus: { NO_UPDATE: 'no_update', THROTTLED: 'throttled', UPDATE_AVAILABLE: 'update_available' },
          connect: function () { return { onDisconnect: { addListener: function () {} }, onMessage: { addListener: function () {} }, postMessage: function () {} }; },
          sendMessage: function () {}
        };
      } catch (e) {}
    }
    if (!window.chrome.app) {
      try {
        window.chrome.app = {
          isInstalled: false,
          InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
          RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' },
          getDetails: function () { return null; },
          getIsInstalled: function () { return false; }
        };
      } catch (e) {}
    }
    if (!window.chrome.csi) {
      try {
        window.chrome.csi = function () {
          return { onloadT: Date.now(), startE: Date.now(), pageT: 1000, tran: 15 };
        };
      } catch (e) {}
    }
    if (!window.chrome.loadTimes) {
      try {
        window.chrome.loadTimes = function () {
          return {
            commitLoadTime: Date.now() / 1000,
            connectionInfo: 'http/2',
            finishDocumentLoadTime: Date.now() / 1000,
            finishLoadTime: Date.now() / 1000,
            firstPaintAfterLoadTime: 0,
            firstPaintTime: Date.now() / 1000,
            navigationType: 'Other',
            npnNegotiatedProtocol: 'h2',
            requestTime: Date.now() / 1000,
            startLoadTime: Date.now() / 1000,
            wasAlternateProtocolAvailable: false,
            wasFetchedViaSpdy: true,
            wasNpnNegotiated: true
          };
        };
      } catch (e) {}
    }
  }

  // ---- 2. 自动化特征 ----
  def(navigator, 'webdriver', function () { return undefined; });

  // ---- 3. 语言 ----
  def(navigator, 'languages', function () { return ['zh-CN', 'zh', 'en-US', 'en']; });

  // ---- 4. 插件列表：桌面 Chrome 有 5 个 PDF 插件，WebView 是空的 ----
  try {
    var mk = function (name) {
      var p = { name: name, filename: 'internal-pdf-viewer', description: 'Portable Document Format', length: 2 };
      p.item = function (i) { return null; };
      p.namedItem = function (n) { return null; };
      return p;
    };
    var plugins = [
      mk('PDF Viewer'), mk('Chrome PDF Viewer'), mk('Chromium PDF Viewer'),
      mk('Microsoft Edge PDF Viewer'), mk('WebKit built-in PDF')
    ];
    plugins.item = function (i) { return this[i] || null; };
    plugins.namedItem = function (n) {
      for (var i = 0; i < this.length; i++) { if (this[i].name === n) return this[i]; }
      return null;
    };
    plugins.refresh = function () {};
    def(navigator, 'plugins', function () { return plugins; });
  } catch (e) {}

  // ---- 5. UA-CH：必须和 UA 一致（Windows / 非移动）----
  try {
    var brands = [
      { brand: 'Not_A Brand', version: '8' },
      { brand: 'Chromium', version: '126' },
      { brand: 'Google Chrome', version: '126' }
    ];
    var uaData = {
      brands: brands,
      mobile: false,
      platform: 'Windows',
      getHighEntropyValues: function () {
        return Promise.resolve({
          architecture: 'x86', bitness: '64', brands: brands, mobile: false,
          model: '', platform: 'Windows', platformVersion: '10.0.0',
          uaFullVersion: '126.0.0.0', fullVersionList: brands, wow64: false
        });
      },
      toJSON: function () { return { brands: brands, mobile: false, platform: 'Windows' }; }
    };
    def(navigator, 'userAgentData', function () { return uaData; });
  } catch (e) {}

  // ---- 6. 桌面尺寸：WebView 报的是手机尺寸，和桌面 UA 自相矛盾 ----
  def(window, 'outerWidth', function () { return 1440; });
  def(window, 'outerHeight', function () { return 900; });
  def(screen, 'width', function () { return 1440; });
  def(screen, 'height', function () { return 900; });
  def(screen, 'availWidth', function () { return 1440; });
  def(screen, 'availHeight', function () { return 860; });
  def(screen, 'colorDepth', function () { return 24; });
  def(screen, 'pixelDepth', function () { return 24; });

  // ---- 7. 硬件信息：手机 WebView 常见 4 核 / 4G，桌面普遍更高 ----
  def(navigator, 'hardwareConcurrency', function () { return 8; });
  def(navigator, 'deviceMemory', function () { return 8; });
  def(navigator, 'maxTouchPoints', function () { return 0; });
})();
''';

  /// 同时钩住 fetch 与 XMLHttpRequest。
  ///
  /// 为什么两个都要钩：各平台实现不一样 —— 抖音的详情接口走 XHR，
  /// 而新一代页面越来越多用 fetch。少钩一个就会「有时抓得到有时抓不到」。
  ///
  /// 【为什么还要单独记一份「所有请求 URL」】
  /// 有些数据不在任何 JSON 响应里，也不在页面 HTML 里 —— 比如抖音视频，
  /// 页面里根本没有视频地址（播放器是把流拉进 blob 的）。这种情况只能从
  /// **网络层**捞：把所有请求 URL 记下来，再按 CDN 域名筛。
  static const String _hookScript = r'''
(function () {
  if (window.__fsHooked) return;
  window.__fsHooked = true;
  if (!window.__fsHits) window.__fsHits = [];
  if (!window.__fsUrls) window.__fsUrls = [];

  function noteUrl(u) {
    try {
      u = String(u);
      if (!u || u.indexOf('http') !== 0) return;
      if (window.__fsUrls.length > 400) return;
      if (window.__fsUrls.indexOf(u) === -1) window.__fsUrls.push(u);
    } catch (e) {}
  }

  function push(url, json, status, ct) {
    try {
      window.__fsHits.push({ url: String(url), json: json, status: status || 0, ct: ct || '' });
      if (window.FsBridge && window.FsBridge.postMessage) {
        window.FsBridge.postMessage(JSON.stringify({
          url: String(url),
          json: json,
          epoch: window.__fsEpoch || 0
        }));
      }
    } catch (e) { /* 太大的消息序列化会失败，忽略这一条 —— Dart 那边会主动来拉 */ }
  }

  // ---- fetch ----
  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function (input, init) {
      var url = '';
      try { url = (typeof input === 'string') ? input : (input && input.url) || ''; } catch (e) {}
      noteUrl(url);
      var p = origFetch.apply(this, arguments);
      try {
        p.then(function (res) {
          try {
            var ct = (res.headers && res.headers.get && res.headers.get('content-type')) || '';
            if (ct.indexOf('json') === -1) return;
            res.clone().json().then(function (j) { push(url, j); }).catch(function () {});
          } catch (e) {}
        }).catch(function () {});
      } catch (e) {}
      return p;
    };
  }

  // ---- XMLHttpRequest ----
  var origOpen = XMLHttpRequest.prototype.open;
  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    try { this.__fsUrl = url; noteUrl(url); } catch (e) {}
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    var self = this;
    try {
      // 用 loadend 而不是 load：抖音会并发发好几个详情请求然后取消其中一部分，
      // 被取消的请求不会触发 load —— 换成 load 就会把这些响应整条漏掉。
      // 而且即使拿不到 body，也把 URL / 状态码 / content-type 记下来，
      // 排查时能一眼看出是「没发请求」还是「发了但被取消」。
      self.addEventListener('loadend', function () {
        var ct = '';
        var status = 0;
        try { ct = (self.getResponseHeader && self.getResponseHeader('content-type')) || ''; } catch (e) {}
        try { status = self.status || 0; } catch (e) {}
        var body = null;
        if (ct.indexOf('json') > -1) {
          try { body = JSON.parse(self.responseText); } catch (e) { body = null; }
        }
        push(self.__fsUrl || '', body, status, ct);
      });
    } catch (e) {}
    return origSend.apply(this, arguments);
  };

  // ---- sendBeacon / Image 兜底：有些播放器用这两种方式取分片 ----
  var origBeacon = navigator.sendBeacon;
  if (origBeacon) {
    navigator.sendBeacon = function (u) {
      noteUrl(u);
      return origBeacon.apply(this, arguments);
    };
  }
})();
''';

  /// 临时切换 User-Agent。
  ///
  /// 有些平台手机站和 PC 站是两套完全不同的实现，需要分别试。
  /// 用完记得切回 [desktopChromeUa]，否则会污染后续解析。
  Future<void> setUserAgent(String ua) async {
    try {
      await _controller?.setUserAgent(ua);
    } catch (_) {}
  }

  /// 引擎默认的桌面 Chrome UA
  static String get desktopUa => _desktopChromeUa();

  /// 手机 Chrome UA（部分平台手机站才给数据）
  static const String mobileUa =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  /// 读回页面发出过的所有请求 URL（去重、上限 400 条）。
  ///
  /// 用于那些「数据不在 JSON 里也不在 HTML 里」的场景 —— 抖音视频就是：
  /// 页面 HTML 里没有视频地址，播放器运行时才把流拉进 blob。
  Future<List<String>> capturedUrls() async {
    final v = await evalCurrent('JSON.stringify(window.__fsUrls || [])');
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  /// **在当前页面上求值，不做任何导航。**
  ///
  /// [evaluate] / [evaluatePolling] 都会先 `loadRequest`，那会换掉文档、
  /// 把已经收集到的 `__fsHits` 清空。想读「当前页面已经攒下的东西」必须用这个。
  Future<dynamic> evalCurrent(String script) async {
    final c = _controller;
    if (c == null) return null;
    try {
      final raw = await c.runJavaScriptReturningResult(script);
      return _decodeJsResult(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    _controller = null;
    _ready = null;
    _hits.clear();
  }
}

/// 把隐藏 WebView 挂进界面树的宿主。
///
/// 【两个必须注意的点，都是实测踩出来的】
///
/// 1. **必须挂进 widget 树**。只创建 controller 而不渲染它，页面根本不会加载
///    （document.title 读回来是空字符串）。
///
/// 2. **必须有真实的视口尺寸，不能图省事给 1×1**。
///    这是最隐蔽的一个坑：给 1×1 时，页面**能加载**（HTML 有 72 万字节）、
///    钩子**也装上了**，但——
///      · 懒加载的图片因为「不在视口内」永远不加载（图文作品一张都抠不到）
///      · SPA 因为视口异常没有正常启动，一个 XHR 都不发（视频详情抓不到）
///    表现就是「一切看起来都对，但什么数据都没有」。
///    这里给一个桌面尺寸的视口（和服务端 Playwright 的 1440×900 同理），
///    然后靠「放在最底层 + 上层用不透明背景盖住」来隐藏它。
class LocalEngineHost extends StatefulWidget {
  const LocalEngineHost({super.key});

  /// 视口尺寸。给足高度，让懒加载的图片有机会进入视口。
  static const double viewportWidth = 1000;
  static const double viewportHeight = 1600;

  @override
  State<LocalEngineHost> createState() => _LocalEngineHostState();
}

class _LocalEngineHostState extends State<LocalEngineHost> {
  WebViewController? _c;

  @override
  void initState() {
    super.initState();
    LocalEngine.instance.ensure().then((c) {
      if (!mounted) return;
      setState(() => _c = c);
      // 拿到 controller 立刻预热，把冷启动开销从「第一次解析」挪到「App 刚打开」
      LocalEngine.instance.warmUp();
    }).catchError((Object e) {
      // 单元测试环境里没有 WebView 平台实现，构造 controller 会断言失败 ——
      // 这是预期的，静默跳过即可，不用刷一行吓人的报错。
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    return IgnorePointer(
      // 【必须用 OverflowBox】只写 SizedBox(1000×1600) 是**没用的**：
      // Flutter 会把子组件约束在父容器（手机屏幕）尺寸内，SizedBox 被钳成了
      // 屏幕大小，WebView 的视口还是那么小，懒加载的图片照样不加载。
      // 用 OverflowBox 强行突破父约束，WebView 才能拿到我们想要的视口。
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: LocalEngineHost.viewportWidth,
        maxWidth: LocalEngineHost.viewportWidth,
        minHeight: LocalEngineHost.viewportHeight,
        maxHeight: LocalEngineHost.viewportHeight,
        child: SizedBox(
          width: LocalEngineHost.viewportWidth,
          height: LocalEngineHost.viewportHeight,
          child: WebViewWidget(controller: c),
        ),
      ),
    );
  }
}

/// 一次被拦截到的响应
class InterceptHit {
  final String url;
  final dynamic json;
  final int epoch;

  const InterceptHit({required this.url, this.json, this.epoch = 0});

  /// 按路径取值，例如 `['aweme_detail', 'desc']`
  dynamic dig(List<String> path) {
    dynamic cur = json;
    for (final k in path) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return null;
      }
    }
    return cur;
  }
}
