import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:markdown_quill/markdown_quill.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import '../memo/memo.dart';

class CloudService {
  static final CloudService _instance = CloudService._internal();
  factory CloudService() => _instance;
  CloudService._internal();

  webdav.Client? _client;

  bool get isConnected => _client != null;

  // 初始化连接
  Future<void> connect(String serverUrl, String username, String password) async {
    // Alist 的 WebDAV 通常在 /dav 下
    if (!serverUrl.endsWith('/dav') && !serverUrl.endsWith('/dav/')) {
      if (serverUrl.endsWith('/')) {
        serverUrl = '${serverUrl}dav';
      } else {
        serverUrl = '$serverUrl/dav';
      }
    }
    
    _client = webdav.newClient(
      serverUrl,
      user: username,
      password: password,
      debug: false,
    );

    // 测试连接，读取根目录
    try {
      await _client!.readDir('/');
    } catch (e) {
      _client = null;
      throw Exception('连接失败: $e');
    }
  }

  void disconnect() {
    _client = null;
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
      // 1. 确保 BellMemo 目录存在
      try {
        await _client!.mkdir('/BellMemo');
      } catch (_) {
        // 忽略已存在的错误
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
      final remotePath = '/BellMemo/$fileName';

      // 4. 上传
      await _client!.write(remotePath, bytes);
      print('Synced memo: ${memo.title}');
    } catch (e) {
      print('Sync failed for ${memo.title}: $e');
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
      await _client!.mkdir(path);
    } catch (e) {
      throw Exception('创建文件夹失败: $e');
    }
  }
}
