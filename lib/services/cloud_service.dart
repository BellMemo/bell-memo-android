import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:markdown_quill/markdown_quill.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:dio/dio.dart';
import '../memo/memo.dart';

class CloudService {
  static final CloudService _instance = CloudService._internal();
  factory CloudService() => _instance;
  CloudService._internal();

  webdav.Client? _client;
  String? _effectiveUrl;
  String _memoRoot = '/BellMemo';

  bool get isConnected => _client != null;
  String? get effectiveUrl => _effectiveUrl;
  String get memoRoot => _memoRoot;

  /// 设置云端备份根目录（WebDAV 路径），例如 `/BellMemo` 或 `/local/BellMemo`
  void setMemoRoot(String path) {
    final p = _normalizeWebdavPath(path);
    _memoRoot = p.isEmpty ? '/BellMemo' : p;
  }

  // 初始化连接
  Future<void> connect(String serverUrl, String username, String password) async {
    final input = serverUrl.trim();

    // 兼容：用户可能填的是 WebUI 地址（/），也可能填的是 WebDAV 地址（通常 /dav/）
    // 我们按候选顺序尝试，连接成功后把最终可用的 URL 记下来。
    final candidates = _buildCandidateUrls(input);
    Object? lastError;

    for (final url in candidates) {
      _client = webdav.newClient(
        url,
        user: username,
        password: password,
        debug: false,
      );

      try {
        await _client!.readDir('/'); // PROPFIND root
        _effectiveUrl = url;
        return;
      } catch (e) {
        lastError = e;
        _client = null;
      }
    }

    final hint = _hintForConnectError(lastError, input);
    throw Exception('连接失败: $lastError$hint');
  }

  void disconnect() {
    _client = null;
    _effectiveUrl = null;
  }

  // 列出文件
  Future<List<webdav.File>> listFiles(String path) async {
    if (_client == null) throw Exception('未连接到网盘');
    try {
      // 确保路径以 / 结尾，除了根目录
      String searchPath = path;
      if (searchPath != '/' && !searchPath.endsWith('/')) {
        searchPath = '$searchPath/';
      }
      return await _client!.readDir(searchPath);
    } catch (e) {
      throw Exception('获取文件列表失败: $e');
    }
  }

  // 读取文本文件内容 (如 .md)
  Future<String> readTextFile(String path) async {
    if (_client == null) throw Exception('未连接到网盘');
    try {
      // 使用 read 方法获取字节流
      final List<int> bytes = await _client!.read(path);
      return utf8.decode(bytes);
    } catch (e) {
      throw Exception('读取文件失败: $e');
    }
  }

  // 下载文件到本地
  Future<String> downloadFile(String remotePath, String localPath) async {
    if (_client == null) throw Exception('未连接到网盘');
    try {
      final List<int> bytes = await _client!.read(remotePath);
      final file = File(localPath);
      await file.writeAsBytes(bytes);
      return localPath;
    } catch (e) {
      throw Exception('下载失败: $e');
    }
  }
  
  // 上传文件
  Future<void> uploadFile(String localPath, String remotePath) async {
     if (_client == null) throw Exception('未连接到网盘');
     try {
       final file = File(localPath);
       final bytes = await file.readAsBytes();
       await _client!.write(remotePath, bytes);
     } catch (e) {
       throw Exception('上传失败: $e');
     }
  }

  // 这里的 sync 是简单的单向覆盖：Local -> Cloud
  Future<void> syncMemoToCloud(Memo memo) async {
    if (_client == null) return; // 未连接则忽略

    try {
      final root = _memoRoot;
      // 1) 确保目录存在（可能是多级目录），并且真的“可访问”
      try {
        await _ensureDirExists(root);
      } catch (e) {
        print(
            'Sync failed for ${memo.title}: invalid cloud root "$root": ${_formatWebdavError(e)}');
        return;
      }

      // 2. 生成 Markdown 内容
      final mdContent = _generateMarkdown(memo);
      final bytes = utf8.encode(mdContent);

      // 3. 生成文件名: 2023-10-01_标题.md
      // 为了避免文件名非法字符，简单处理一下标题
      final safeTitle = memo.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final dateStr = memo.createdAt.toIso8601String().split('T')[0];
      // 使用 ID 后缀防止重名
      final fileName = '${dateStr}_${safeTitle}_${memo.id.substring(0, 4)}.md';
      final remotePath = '${root.endsWith('/') ? root.substring(0, root.length - 1) : root}/$fileName';

      // 4. 上传
      await _client!.write(remotePath, bytes);
      print('Synced memo: ${memo.title}');
    } catch (e) {
      print('Sync failed for ${memo.title}: ${_formatWebdavError(e)}');
      // 不抛出异常，以免中断批量同步
    }
  }

  String _generateMarkdown(Memo memo) {
    String contentMd = memo.content;
    
    // 如果是 JSON 格式（Quill Delta），转换为 Markdown
    if (memo.content.trim().startsWith('[') || memo.content.trim().startsWith('{')) {
      try {
        final json = jsonDecode(memo.content);
        if (json is List) {
          final delta = Delta.fromJson(json);
          // 使用 markdown_quill 转换
          final deltaToMd = DeltaToMarkdown();
          contentMd = deltaToMd.convert(delta);
        }
      } catch (e) {
        // 解析失败，回退到原文
        print('Markdown conversion failed: $e');
      }
    }

    return '''
---
uuid: "${memo.id}"
title: "${memo.title}"
created_at: ${memo.createdAt.toIso8601String()}
updated_at: ${memo.updatedAt.toIso8601String()}
---

# ${memo.title}

$contentMd
''';
  }

  // 创建文件夹
  Future<void> createDir(String path) async {
    if (_client == null) throw Exception('未连接到网盘');
    try {
      await _client!.mkdirAll(_normalizeWebdavPath(path));
    } catch (e) {
      throw Exception('创建文件夹失败: ${_formatWebdavError(e)}');
    }
  }

  List<String> _buildCandidateUrls(String input) {
    String normalize(String s) => s.trim();

    // 已经是 /dav 或 /dav/ 结尾：优先按原样尝试
    final list = <String>[];
    final raw = normalize(input);
    if (raw.isNotEmpty) list.add(raw);

    // 如果用户没写 /dav，则尝试追加 /dav（Alist 默认 WebDAV）
    final hasDav = raw.contains('/dav');
    if (!hasDav) {
      if (raw.endsWith('/')) {
        list.add('${raw}dav');
      } else {
        list.add('$raw/dav');
      }
    }

    // 去重（保持顺序）
    final seen = <String>{};
    final out = <String>[];
    for (final u in list) {
      if (seen.add(u)) out.add(u);
    }
    return out;
  }

  String _hintForConnectError(Object? err, String inputUrl) {
    final s = err?.toString() ?? '';

    // 404 Not Found：最常见是 WebDAV 未开启 / 反代未转发 / URL 不是 WebDAV 地址
    if (s.contains('Not Found') || s.contains('404')) {
      return '\n'
          '提示：服务器返回 404(Not Found)。这通常表示你填的不是 WebDAV 地址。\n'
          '请在浏览器访问：${_suggestDavUrl(inputUrl)} ，若仍是 404，去 Alist 后台确认已开启 WebDAV，或检查反向代理是否转发了 /dav 路径。';
    }

    // 401/403：账号权限问题
    if (s.contains('401') || s.contains('Unauthorized') || s.contains('403')) {
      return '\n提示：看起来是权限/账号问题，请确认账号密码正确，且 Alist WebDAV 已允许该用户访问。';
    }

    // 405：方法不允许——通常是 WebDAV 未启用，或反代/WAF/CDN 禁止了 PROPFIND/OPTIONS 等 WebDAV 方法
    if (s.contains('405') || s.contains('Method Not Allowed')) {
      return '\n'
          '提示：服务器返回 405(Method Not Allowed)。这通常表示 WebDAV 没有启用，或中间层（反向代理/WAF/CDN）拦截了 WebDAV 方法（PROPFIND/OPTIONS/MKCOL/PUT/DELETE/MOVE/COPY）。\n'
          '你可以用 curl 验证（需要支持 PROPFIND）：\n'
          '  curl -i -X PROPFIND -u <user>:<pass> "${_suggestDavUrl(inputUrl)}" -H "Depth: 1"\n'
          '正常应返回 207 Multi-Status；如果依然 405，请去 Alist 后台开启 WebDAV，或检查反代是否允许这些方法透传。';
    }

    return '';
  }

  String _suggestDavUrl(String input) {
    final raw = input.trim();
    if (raw.endsWith('/dav') || raw.endsWith('/dav/')) return raw;
    if (raw.endsWith('/')) return '${raw}dav/';
    return '$raw/dav/';
  }

  String _normalizeWebdavPath(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    var p = trimmed;
    // 只保留 path 部分（用户可能误填完整 URL）
    if (p.startsWith('http://') || p.startsWith('https://')) {
      try {
        final u = Uri.parse(p);
        p = u.path;
      } catch (_) {}
    }
    if (!p.startsWith('/')) p = '/$p';
    // 去掉多余的尾部空格，保留尾部 / 由调用者决定
    while (p.contains('//')) {
      p = p.replaceAll('//', '/');
    }
    // 不允许根目录为空
    if (p == '/') return '/';
    // 去掉末尾 '/'
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  String _formatWebdavError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      final msg = e.response?.statusMessage;
      final uri = e.requestOptions.uri.toString();
      final method = e.requestOptions.method;
      return 'DioException(${e.type}) code=$code msg=$msg method=$method uri=$uri error=${e.error}';
    }
    return e.toString();
  }

  Future<void> _ensureDirExists(String root) async {
    if (_client == null) throw Exception('not connected');
    final dir = _normalizeWebdavPath(root);
    final dirWithSlash = (dir == '/') ? '/' : '$dir/';

    // 先尝试读取目录（最可靠）
    try {
      await _client!.readDir(dirWithSlash);
      return;
    } catch (_) {
      // ignore and try create
    }

    // 尝试创建（注意：部分服务返回 405 并不代表已存在）
    await _client!.mkdirAll(dirWithSlash);

    // 再次读取确认
    await _client!.readDir(dirWithSlash);
  }
}
